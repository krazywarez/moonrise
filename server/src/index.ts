import { send, type ApnsConfig } from "./apns";
import { actionableKp, alertBands, eventKey, isNight } from "./aurora";
import { fetchUpcoming, type Launch } from "./ll2";
import { fetchSpaceWeather, next24h, type SpaceWeather } from "./swpc";

interface Env {
  DB: D1Database;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY: string;
}

interface DeviceRequest {
  token: string;
  environment: "sandbox" | "production";
  band: number;
  utcOffsetMinutes: number;
  aurora?: boolean;
}

const LAUNCH_CRON = "*/10 * * * *";

const json = (body: unknown, status = 200) => Response.json(body, { status });

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
  if (!row) return json({ spaceWeather: null });
  const w = JSON.parse(row.body) as SpaceWeather;
  w.forecast = w.forecast.map((f) => ({ ...f, start: new Date(f.start) }));
  return json({
    spaceWeather: { kpNow: w.kpNow, observedAt: w.observedAt, kpNext24h: next24h(w, now), fetchedAt: row.fetched_at },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const now = new Date();

    if (request.method === "GET" && url.pathname === "/healthz") {
      const rows = await env.DB.prepare("SELECT feed, fetched_at, ok FROM feed_snapshots").all();
      return json({ ok: true, feeds: rows.results });
    }
    if (request.method === "GET" && url.pathname === "/v1/today") return today(env, now);
    if (request.method === "GET" && url.pathname === "/v1/launches") return launches(env, now);

    if (request.method === "POST" && url.pathname === "/v1/devices") {
      const d = (await request.json().catch(() => ({}))) as Partial<DeviceRequest>;
      if (!validDevice(d)) return json({ error: "invalid device" }, 400);
      await env.DB.prepare(
        `INSERT INTO devices (token, environment, band, utc_offset_minutes, aurora, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (token) DO UPDATE SET environment = ?2, band = ?3, utc_offset_minutes = ?4, aurora = ?5, last_seen = ?6`,
      ).bind(d.token, d.environment, d.band, d.utcOffsetMinutes, d.aurora === false ? 0 : 1, now.toISOString()).run();
      return json({ ok: true });
    }

    const del = url.pathname.match(/^\/v1\/devices\/([0-9a-f]{64,200})$/i);
    if (request.method === "DELETE" && del) {
      await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(del[1]).run();
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  },

  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    const now = new Date(controller.scheduledTime);
    // Launches every 10 minutes: 6 of the 15 anonymous Launch Library 2 requests per hour.
    if (controller.cron === LAUNCH_CRON) ctx.waitUntil(pollLaunches(env, now));
    else ctx.waitUntil(pollSpaceWeather(env, now));
  },
} satisfies ExportedHandler<Env>;

async function launches(env: Env, now: Date): Promise<Response> {
  const since = new Date(now.getTime() - 6 * 3600_000).toISOString();
  const rows = await env.DB.prepare("SELECT * FROM launches WHERE net >= ?1 ORDER BY net LIMIT 20").bind(since).all<Record<string, unknown>>();
  const fetched = await env.DB.prepare("SELECT fetched_at FROM feed_snapshots WHERE feed = 'll2' AND ok = 1").first<{ fetched_at: string }>();
  return json({
    fetchedAt: fetched?.fetched_at ?? null,
    launches: rows.results.map((r) => ({
      id: r.id, name: r.name, net: r.net, windowStart: r.window_start, windowEnd: r.window_end,
      status: r.status, statusName: r.status_name, provider: r.provider, rocket: r.rocket,
      mission: r.mission, missionType: r.mission_type, missionDescription: r.mission_description, orbit: r.orbit,
      pad: r.pad, location: r.location, padLatitude: r.pad_latitude, padLongitude: r.pad_longitude,
    })),
  });
}

async function pollLaunches(env: Env, now: Date): Promise<void> {
  let list: Launch[];
  try {
    list = await fetchUpcoming();
  } catch (e) {
    console.error("ll2", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 0").bind(now.toISOString()).run();
    return;
  }
  const upsert = env.DB.prepare(
    `INSERT INTO launches (id, name, net, window_start, window_end, status, status_name, provider, rocket, mission, mission_type, mission_description, orbit, pad, location, pad_latitude, pad_longitude, last_updated)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
     ON CONFLICT (id) DO UPDATE SET name = ?2, net = ?3, window_start = ?4, window_end = ?5, status = ?6, status_name = ?7, provider = ?8, rocket = ?9,
       mission = ?10, mission_type = ?11, mission_description = ?12, orbit = ?13, pad = ?14, location = ?15, pad_latitude = ?16, pad_longitude = ?17, last_updated = ?18`,
  );
  await env.DB.batch([
    ...list.map((l) => upsert.bind(l.id, l.name, l.net, l.windowStart, l.windowEnd, l.status, l.statusName, l.provider, l.rocket, l.mission, l.missionType, l.missionDescription, l.orbit, l.pad, l.location, l.padLatitude, l.padLongitude, l.lastUpdated)),
    env.DB.prepare("DELETE FROM launches WHERE net < ?1").bind(new Date(now.getTime() - 7 * 86400_000).toISOString()),
    env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2', ?1, 1) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1").bind(now.toISOString()),
  ]);
}

async function pollSpaceWeather(env: Env, now: Date): Promise<void> {
  let w: SpaceWeather;
  try {
    w = await fetchSpaceWeather();
  } catch (e) {
    console.error("swpc", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('swpc', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 0").bind(now.toISOString()).run();
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
