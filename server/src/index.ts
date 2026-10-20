import { send, type ApnsConfig } from "./apns";
import { actionableKp, alertBands, eventKey, isNight } from "./aurora";
import { compose, fetchGroups, fetchSupGP, fitsLaunch, supgpFile, supgpLaunches, type LaunchElements, type LaunchRef, type Row } from "./celestrak";
import { activeEvent, fetchTrajectory, STEP_MINUTES } from "./live";
import { fetchLaunches, PREVIOUS_URL, UPCOMING_URL, type Launch } from "./ll2";
import { digestDue, digestPayload, fetchLatest, localDate, pickHeadlines } from "./news";
import { PRIVACY_HTML } from "./privacy";
import { fetchSpaceWeather, next24h, type SpaceWeather } from "./swpc";

interface Env {
  DB: D1Database;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY: string;
  /** Optional Launch Library 2 API key. */
  LL2_API_KEY?: string;
}

interface DeviceRequest {
  token: string;
  environment: "sandbox" | "production";
  band: number;
  utcOffsetMinutes: number;
  aurora?: boolean;
  news?: boolean;
}

const LAUNCH_CRON = "*/10 * * * *";
const SATELLITE_CRON = "7 */2 * * *";
/** Launches are kept this long after NET, so a launch page and its first pass outlive liftoff. */
const RETENTION_MS = 14 * 86400_000;

const json = (body: unknown, status = 200, maxAge?: number) =>
  Response.json(body, { status, headers: maxAge && status === 200 ? { "cache-control": `public, max-age=${maxAge}` } : {} });

/** How long clients may reuse each GET response, matched to how often its source is polled. */
export const MAX_AGE = { today: 60, launches: 300, satellites: 3600, live: 300 } as const;

function validDevice(d: Partial<DeviceRequest>): d is DeviceRequest {
  return (
    typeof d.token === "string" && /^[0-9a-f]{64,200}$/i.test(d.token) &&
    (d.environment === "sandbox" || d.environment === "production") &&
    Number.isInteger(d.band) && Math.abs(d.band!) <= 90 && d.band! % 5 === 0 &&
    Number.isInteger(d.utcOffsetMinutes) && Math.abs(d.utcOffsetMinutes!) <= 14 * 60
  );
}

async function today(env: Env, now: Date): Promise<Response> {
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'swpc' AND ok = 1").first<{ fetched_at: string; body: string }>();
  if (!row) return json({ spaceWeather: null }, 200, MAX_AGE.today);
  const w = JSON.parse(row.body) as SpaceWeather;
  w.forecast = w.forecast.map((f) => ({ ...f, start: new Date(f.start) }));
  return json({
    spaceWeather: { kpNow: w.kpNow, observedAt: w.observedAt, kpNext24h: next24h(w, now), fetchedAt: row.fetched_at },
  }, 200, MAX_AGE.today);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const now = new Date();

    if (request.method === "GET" && url.pathname === "/healthz") {
      const rows = await env.DB.prepare("SELECT feed, fetched_at, ok FROM feed_snapshots").all();
      return json({ ok: true, feeds: rows.results });
    }
    if (request.method === "GET" && url.pathname === "/privacy")
      return new Response(PRIVACY_HTML, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } });
    if (request.method === "GET" && url.pathname === "/v1/today") return today(env, now);
    if (request.method === "GET" && url.pathname === "/v1/launches") return launches(env, now);
    if (request.method === "GET" && url.pathname === "/v1/live") return live(env, url, now);
    if (request.method === "GET" && url.pathname === "/v1/satellites") {
      const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'celestrak' AND ok = 1").first<{ fetched_at: string; body: string }>();
      return json({ fetchedAt: row?.fetched_at ?? null, satellites: row ? JSON.parse(row.body) : [] }, 200, MAX_AGE.satellites);
    }

    if (request.method === "POST" && url.pathname === "/v1/devices") {
      const d = (await request.json().catch(() => ({}))) as Partial<DeviceRequest>;
      if (!validDevice(d)) return json({ error: "invalid device" }, 400);
      await env.DB.prepare(
        `INSERT INTO devices (token, environment, band, utc_offset_minutes, aurora, news, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT (token) DO UPDATE SET environment = ?2, band = ?3, utc_offset_minutes = ?4, aurora = ?5, news = ?6, last_seen = ?7`,
      ).bind(d.token.toLowerCase(), d.environment, d.band, d.utcOffsetMinutes, d.aurora === false ? 0 : 1, d.news === true ? 1 : 0, now.toISOString()).run();
      return json({ ok: true });
    }

    const test = url.pathname.match(/^\/v1\/devices\/([0-9a-f]{64,200})\/test$/i);
    if (request.method === "POST" && test) return sendTest(env, test[1].toLowerCase(), now);

    const del = url.pathname.match(/^\/v1\/devices\/([0-9a-f]{64,200})$/i);
    if (request.method === "DELETE" && del) {
      await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(del[1]).run();
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  },

  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    const now = new Date(controller.scheduledTime);
    // Upcoming launches every 10 minutes and previous launches hourly: 7 of the 15 anonymous Launch Library 2 requests per hour.
    if (controller.cron === LAUNCH_CRON) ctx.waitUntil(Promise.all([pollLaunches(env, now), sendNewsDigests(env, now)]));
    else if (controller.cron === SATELLITE_CRON) ctx.waitUntil(pollSatellites(env, now));
    else ctx.waitUntil(pollSpaceWeather(env, now));
  },
} satisfies ExportedHandler<Env>;

/** One test push to a registered device, at most once per 10 minutes per device. */
async function sendTest(env: Env, token: string, now: Date): Promise<Response> {
  const device = await env.DB.prepare("SELECT environment FROM devices WHERE token = ?1").bind(token).first<{ environment: string }>();
  if (!device) return json({ error: "not registered" }, 404);
  const window = `${token}:${now.toISOString().slice(0, 15)}`; // 10-minute bucket
  const claimed = await env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES ('test', 0, ?1, ?2)")
    .bind(window, now.toISOString()).run();
  if (!claimed.meta.changes) return json({ error: "try again in a few minutes" }, 429);
  const config: ApnsConfig = { keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC };
  const payload = { aps: { alert: { title: "Moonrise test alert", body: "Alerts reach this device." }, sound: "default" } };
  const r = await send(config, token, payload, device.environment === "sandbox");
  if (r.status === 410) await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(token).run();
  return json({ apnsStatus: r.status, reason: r.reason }, r.status === 200 ? 200 : 502);
}

/**
 * The live event at `?at=` (default now) and its geocentric ecliptic trajectory up to then:
 * points are [unix seconds, x, y, z] km. The cached trajectory is refreshed from Horizons at most
 * every 10 minutes while the event runs.
 */
async function live(env: Env, url: URL, now: Date): Promise<Response> {
  const atParam = url.searchParams.get("at");
  const at = atParam ? new Date(atParam) : now;
  if (Number.isNaN(at.getTime())) return json({ error: "invalid at" }, 400);
  const event = activeEvent(at);
  if (!event) return json({ event: null }, 200, MAX_AGE.live);

  const key = `live:${event.id}`;
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = ?1 AND ok = 1").bind(key).first<{ fetched_at: string; body: string }>();
  let points: number[][] = row ? JSON.parse(row.body) : [];
  const covered = (points.at(-1)?.[0] ?? 0) * 1000;
  const wanted = Math.min(now.getTime(), Date.parse(event.end)) - 2 * STEP_MINUTES * 60_000;
  const stale = !row || points.length === 0 || now.getTime() - Date.parse(row.fetched_at) > 10 * 60_000;
  if (covered < wanted && stale) {
    try {
      const fresh = await fetchTrajectory(event, now);
      if (fresh.length === 0) throw new Error("no Horizons data");
      points = fresh;
      await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES (?1, ?2, 1, ?3) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?2, ok = 1, body = ?3")
        .bind(key, now.toISOString(), JSON.stringify(points)).run();
    } catch (e) {
      console.error("horizons", String(e));
    }
  }
  return json({ event, at: at.toISOString(), points: points.filter((p) => p[0] * 1000 <= at.getTime()) }, 200, MAX_AGE.live);
}

async function launches(env: Env, now: Date): Promise<Response> {
  const since = new Date(now.getTime() - 6 * 3600_000).toISOString();
  const rows = await env.DB.prepare("SELECT * FROM launches WHERE net >= ?1 ORDER BY net LIMIT 20").bind(since).all<Record<string, unknown>>();
  const recent = await env.DB.prepare("SELECT * FROM launches WHERE net < ?1 AND net >= ?2 ORDER BY net DESC LIMIT 20")
    .bind(since, new Date(now.getTime() - RETENTION_MS).toISOString()).all<Record<string, unknown>>();
  const fetched = await env.DB.prepare("SELECT fetched_at FROM feed_snapshots WHERE feed = 'll2' AND ok = 1").first<{ fetched_at: string }>();
  const els = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'launch-elements' AND ok = 1").first<{ body: string }>();
  const elements: Record<string, LaunchElements> = els ? JSON.parse(els.body) : {};
  const shape = (r: Record<string, unknown>) => ({
    id: r.id, name: r.name, net: r.net, windowStart: r.window_start, windowEnd: r.window_end,
    status: r.status, statusName: r.status_name, provider: r.provider, rocket: r.rocket,
    mission: r.mission, missionType: r.mission_type, missionDescription: r.mission_description, orbit: r.orbit,
    pad: r.pad, location: r.location, padLatitude: r.pad_latitude, padLongitude: r.pad_longitude,
    elements: elements[String(r.id)]?.elements ?? [], elementsSource: elements[String(r.id)]?.source ?? null,
  });
  return json({
    fetchedAt: fetched?.fetched_at ?? null,
    launches: rows.results.map(shape),
    recent: recent.results.map(shape),
  }, 200, MAX_AGE.launches);
}

// Failures are recorded under "<feed>:error" so the last good snapshot and its time survive.
async function pollLaunches(env: Env, now: Date): Promise<void> {
  let list: Launch[];
  try {
    list = await fetchLaunches(UPCOMING_URL, env.LL2_API_KEY);
  } catch (e) {
    console.error("ll2", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    return;
  }
  // Previous launches on the first run of each hour: designators and outcomes arrive after a launch leaves the upcoming list.
  if (now.getUTCMinutes() < 10) {
    try {
      list = [...list, ...(await fetchLaunches(PREVIOUS_URL, env.LL2_API_KEY))];
    } catch (e) {
      console.error("ll2 previous", String(e));
    }
  }
  const upsert = env.DB.prepare(
    `INSERT INTO launches (id, name, net, window_start, window_end, status, status_name, provider, rocket, mission, mission_type, mission_description, orbit, pad, location, pad_latitude, pad_longitude, last_updated, launch_designator)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
     ON CONFLICT (id) DO UPDATE SET name = ?2, net = ?3, window_start = ?4, window_end = ?5, status = ?6, status_name = ?7, provider = ?8, rocket = ?9,
       mission = ?10, mission_type = ?11, mission_description = ?12, orbit = ?13, pad = ?14, location = ?15, pad_latitude = ?16, pad_longitude = ?17, last_updated = ?18,
       launch_designator = COALESCE(?19, launch_designator)`,
  );
  await env.DB.batch([
    ...list.map((l) => upsert.bind(l.id, l.name, l.net, l.windowStart, l.windowEnd, l.status, l.statusName, l.provider, l.rocket, l.mission, l.missionType, l.missionDescription, l.orbit, l.pad, l.location, l.padLatitude, l.padLongitude, l.lastUpdated, l.designator)),
    env.DB.prepare("DELETE FROM launches WHERE net < ?1").bind(new Date(now.getTime() - RETENTION_MS).toISOString()),
    env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2', ?1, 1) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1").bind(now.toISOString()),
  ]);
}

async function pollSatellites(env: Env, now: Date): Promise<void> {
  let groups: { visual: Row[]; recent: Row[] };
  try {
    groups = await fetchGroups();
  } catch (e) {
    console.error("celestrak", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('celestrak:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    return;
  }
  const launches = await env.DB.prepare("SELECT id, mission, provider, net, launch_designator AS designator FROM launches WHERE net >= ?1")
    .bind(new Date(now.getTime() - RETENTION_MS).toISOString()).all<LaunchRef>();
  const supgp = await pollSupGP(env, launches.results, now);
  const fitting = Object.fromEntries(launches.results.map((l) => [l.id, fitsLaunch(supgp[l.id] ?? [], l.net, now)]));
  const out = compose(groups.visual, groups.recent, launches.results, fitting, now);
  const save = env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES (?1, ?2, 1, ?3) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?2, ok = 1, body = ?3");
  await env.DB.batch([
    save.bind("celestrak", now.toISOString(), JSON.stringify(out.satellites)),
    save.bind("launch-elements", now.toISOString(), JSON.stringify(out.launches)),
  ]);
}

/**
 * SupGP sets by launch id, fetched after the GP groups and kept in their own snapshot: on any failure no more
 * requests are made and the last good sets are used, so the GP data is never lost to a SupGP problem.
 */
async function pollSupGP(env: Env, launches: LaunchRef[], now: Date): Promise<Record<string, Row[]>> {
  const sets: Record<string, Row[]> = {};
  try {
    for (const l of supgpLaunches(launches, now)) sets[l.id] = await fetchSupGP(supgpFile(l.mission)!);
  } catch (e) {
    console.error("supgp", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('supgp:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    const last = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'supgp' AND ok = 1").first<{ body: string }>();
    return last ? JSON.parse(last.body) : {};
  }
  await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('supgp', ?1, 1, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1, body = ?2")
    .bind(now.toISOString(), JSON.stringify(sets)).run();
  return sets;
}

async function pollSpaceWeather(env: Env, now: Date): Promise<void> {
  let w: SpaceWeather;
  try {
    w = await fetchSpaceWeather();
  } catch (e) {
    console.error("swpc", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('swpc:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    return;
  }
  await env.DB.prepare(
    "INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('swpc', ?1, 1, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1, body = ?2",
  ).bind(now.toISOString(), JSON.stringify(w)).run();
  await sendAuroraAlerts(env, w, now);
}

async function sendAuroraAlerts(env: Env, w: SpaceWeather, now: Date): Promise<void> {
  const kp = actionableKp(w.kpNow, w.forecast, now);
  const bandRows = await env.DB.prepare("SELECT DISTINCT band FROM devices WHERE aurora = 1").all<{ band: number }>();
  const bands = alertBands(kp, bandRows.results.map((r) => r.band));
  if (!bands.length || !env.APNS_KEY) return;

  const config: ApnsConfig = { keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC };
  const event = eventKey(now);
  for (const band of bands) {
    const claimed = await env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES ('aurora', ?1, ?2, ?3)")
      .bind(band, event, now.toISOString()).run();
    if (!claimed.meta.changes) continue;

    const devices = await env.DB.prepare("SELECT token, environment, utc_offset_minutes FROM devices WHERE aurora = 1 AND band = ?1")
      .bind(band).all<{ token: string; environment: string; utc_offset_minutes: number }>();
    for (const d of devices.results) {
      if (!isNight(now, d.utc_offset_minutes)) continue;
      const payload = { aps: { alert: { title: "Aurora possible tonight", body: `Kp ${kp.toFixed(1)}. Look toward the ${band >= 0 ? "north" : "south"} after dark.` }, sound: "default" } };
      const r = await send(config, d.token, payload, d.environment === "sandbox");
      if (r.status === 410) await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(d.token).run();
      else if (r.status !== 200) console.error("apns", r.status, r.reason);
    }
  }
}

/** The daily news digest, sent at 09:00 local time to devices that opted in, once per local day. */
async function sendNewsDigests(env: Env, now: Date): Promise<void> {
  if (!env.APNS_KEY) return;
  const rows = await env.DB.prepare("SELECT token, environment, utc_offset_minutes FROM devices WHERE news = 1")
    .all<{ token: string; environment: string; utc_offset_minutes: number }>();
  const due = rows.results.filter((d) => digestDue(now, d.utc_offset_minutes));
  if (!due.length) return;

  let payload;
  try {
    const headlines = pickHeadlines(await fetchLatest(), now);
    if (!headlines.length) return;
    payload = digestPayload(headlines);
  } catch (e) {
    console.error("snapi", String(e));
    return;
  }

  const config: ApnsConfig = { keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC };
  for (const d of due) {
    const claimed = await env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES ('news', 0, ?1, ?2)")
      .bind(`${d.token}:${localDate(now, d.utc_offset_minutes)}`, now.toISOString()).run();
    if (!claimed.meta.changes) continue;
    const r = await send(config, d.token, payload, d.environment === "sandbox");
    if (r.status === 410) await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(d.token).run();
    else if (r.status !== 200) console.error("apns", r.status, r.reason);
  }
  await env.DB.prepare("DELETE FROM alerts_sent WHERE kind = 'news' AND sent_at < ?1").bind(new Date(now.getTime() - 3 * 86400_000).toISOString()).run();
}
