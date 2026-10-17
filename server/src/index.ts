import { send, type ApnsConfig } from "./apns";
import { actionableKp, alertBands, eventKey, isNight } from "./aurora";
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

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(pollSpaceWeather(env, new Date()));
  },
} satisfies ExportedHandler<Env>;

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
