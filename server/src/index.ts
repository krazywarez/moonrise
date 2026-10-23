import { activityPush, startDue, startPayload, type StartLaunch, focusEvery, focusPick, focusPollDue, inFocus, needsChannel, sinceNet, type ActivityState } from "./activity";
import { AttestError, fromBase64, toBase64, verifyAssertion, verifyAttestation, type AttestedKey } from "./appattest";
import { broadcast, createChannel, deleteChannel, retryable, send, sendAll, type ApnsConfig } from "./apns";
import { actionableKp, alertBands, eventKey, isNight } from "./aurora";
import { compose, fetchGroups, fetchSupGP, fitsLaunch, retryDue, retryTick, supgpFile, supgpLaunches, type LaunchElements, type LaunchRef, type Row } from "./celestrak";
import { activeEvent, fetchTrajectory, STEP_MINUTES } from "./live";
import { fetchLaunch, fetchLaunches, PREVIOUS_URL, throttleSeconds, Throttled, UPCOMING_URL, type Launch } from "./ll2";
import { digestPayload, dueOffsets, fetchLatest, localDate, pickHeadlines, type Article } from "./news";
import { fetchSolarWind, STORM_KP, stormLikely, type SolarWind } from "./solarwind";
import { fetchSmallBodies } from "./smallbodies";
import { CALM_MS, stormActive, stormEnd, stormUpdate, type StormPush, type StormState } from "./storm";
import { fetchCcor2, fetchCycle, fetchEnlil } from "./sun";
import { fetchSpaceWeather, next24h, type SpaceWeather } from "./swpc";

interface Env {
  DB: D1Database;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY: string;
  /** Optional Launch Library 2 API key. */
  LL2_API_KEY?: string;
  /** "1": the Worker creates and deletes launch channels itself. Otherwise scripts/channels.ts fills the pool. */
  APNS_MANAGE_CHANNELS?: string;
  /** "require": device registrations without an App Attest assertion are refused. Otherwise only bad ones are. */
  APP_ATTEST?: string;
}

interface DeviceRequest {
  token: string;
  environment: "sandbox" | "production";
  band: number;
  utcOffsetMinutes: number;
  aurora?: boolean;
  news?: boolean;
  /** From POST /v1/challenge; required with an App Attest assertion. */
  challenge?: string;
}

/** Challenges are good for 5 minutes and used once. */
const CHALLENGE_MS = 5 * 60_000;

const NEWS_CRON = "*/10 * * * *";
const SATELLITE_CRON = "7 */2 * * *";
const FOCUS_CRON = "*/2 * * * *";
/** Launches are kept this long after NET, so a launch page and its first pass outlive liftoff. */
const RETENTION_MS = 14 * 86400_000;
/** Devices are dropped after this long without registering; the app registers whenever iOS hands it a token. */
const DEVICE_RETENTION_MS = 180 * 86400_000;
/**
 * Alert pushes per run; the rest go on later runs. The Paid plan allows 10,000 subrequests per invocation; at 6
 * connections open at once, 200 sends take a few seconds of the five-minute run.
 */
export const PUSH_SLICE = 200;
const PUSH_CONCURRENCY = 6;

const json = (body: unknown, status = 200, maxAge?: number) =>
  Response.json(body, { status, headers: maxAge && status === 200 ? { "cache-control": `public, max-age=${maxAge}` } : {} });

const PRIVACY_URL = "https://krz.sh/privacy/moonrise/";

/** Read-only endpoints whose responses are the same for everyone. */
const API = new Set(["/v1/today", "/v1/launches", "/v1/live", "/v1/satellites", "/v1/news", "/v1/sun", "/v1/smallbodies"]);

function api(url: URL, env: Env, now: Date): Promise<Response> {
  switch (url.pathname) {
    case "/v1/today": return today(env, now);
    case "/v1/launches": return launches(env, url, now);
    case "/v1/live": return live(env, url, now);
    case "/v1/news": return news(env);
    case "/v1/sun": return sun(env);
    case "/v1/smallbodies": return smallBodies(env);
    default: return satellites(env);
  }
}

/** Comets near perihelion and bright asteroids, refreshed daily. */
async function smallBodies(env: Env): Promise<Response> {
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'sbdb' AND ok = 1").first<{ fetched_at: string; body: string }>();
  return json({ fetchedAt: row?.fetched_at ?? null, bodies: row ? JSON.parse(row.body) : [] }, 200, MAX_AGE.smallBodies);
}

/** WSA-Enlil at Earth, CCOR-2 frames and solar cycle 25, each with the time it was fetched. */
async function sun(env: Env): Promise<Response> {
  const rows = await env.DB.prepare("SELECT feed, fetched_at, body FROM feed_snapshots WHERE feed IN ('sun:enlil', 'sun:ccor2', 'sun:cycle') AND ok = 1")
    .all<{ feed: string; fetched_at: string; body: string }>();
  const get = (f: string) => rows.results.find((r) => r.feed === f);
  const part = (f: string, key: string) => ({ fetchedAt: get(f)?.fetched_at ?? null, [key]: get(f) ? JSON.parse(get(f)!.body) : null });
  return json({ enlil: part("sun:enlil", "points"), ccor2: part("sun:ccor2", "frames"), cycle: part("sun:cycle", "months") }, 200, MAX_AGE.sun);
}

/** Spaceflight News API articles in its own field names, so clients do not call The Space Devs directly. */
async function news(env: Env): Promise<Response> {
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'news' AND ok = 1").first<{ fetched_at: string; body: string }>();
  return json({ fetchedAt: row?.fetched_at ?? null, results: row ? JSON.parse(row.body) : [] }, 200, MAX_AGE.news);
}

async function satellites(env: Env): Promise<Response> {
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'celestrak' AND ok = 1").first<{ fetched_at: string; body: string }>();
  return json({ fetchedAt: row?.fetched_at ?? null, satellites: row ? JSON.parse(row.body) : [] }, 200, MAX_AGE.satellites);
}

/**
 * Answers from the data centre's cache when it holds a fresh copy, keyed by URL (so ?environment= and ?at= are
 * separate), and stores 200 responses for their max-age. The Cache API does nothing on workers.dev.
 */
async function cached(request: Request, ctx: ExecutionContext | undefined, respond: () => Promise<Response>): Promise<Response> {
  const cache = typeof caches === "undefined" ? undefined : caches.default;
  const hit = await cache?.match(request);
  if (hit) return hit;
  const res = await respond();
  if (cache && res.status === 200 && res.headers.has("cache-control")) {
    const put = cache.put(request, res.clone());
    if (ctx) ctx.waitUntil(put);
    else await put;
  }
  return res;
}

/** How long clients may reuse each GET response, matched to how often its source is polled. */
export const MAX_AGE = { today: 60, launches: 300, satellites: 3600, live: 300, news: 600, sun: 1800, smallBodies: 3600 } as const;

/** An APNs device token: hex, 32 to 100 bytes. */
function validToken(t: unknown): t is string {
  return typeof t === "string" && /^[0-9a-f]{64,200}$/i.test(t);
}

function validEnvironment(e: unknown): e is DeviceRequest["environment"] {
  return e === "sandbox" || e === "production";
}

/** A latitude band: a multiple of 5 degrees. */
function validBand(b: unknown): b is number {
  return Number.isInteger(b) && Math.abs(b as number) <= 90 && (b as number) % 5 === 0;
}

function validUTCOffset(m: unknown): m is number {
  return Number.isInteger(m) && Math.abs(m as number) <= 14 * 60;
}

function validDevice(d: Partial<DeviceRequest>): d is DeviceRequest {
  return validToken(d.token) && validEnvironment(d.environment) && validBand(d.band) && validUTCOffset(d.utcOffsetMinutes);
}

async function today(env: Env, now: Date): Promise<Response> {
  const row = await env.DB.prepare("SELECT fetched_at, body FROM feed_snapshots WHERE feed = 'swpc' AND ok = 1").first<{ fetched_at: string; body: string }>();
  if (!row) return json({ spaceWeather: null }, 200, MAX_AGE.today);
  const w = JSON.parse(row.body) as SpaceWeather;
  w.forecast = w.forecast.map((f) => ({ ...f, start: new Date(f.start) }));
  const wind = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'rtsw' AND ok = 1").first<{ body: string }>();
  const storm = await env.DB.prepare("SELECT channel_id, environment, started_at, sent FROM storm_channels WHERE ended_at IS NULL AND sent IS NOT NULL")
    .all<{ channel_id: string; environment: string; started_at: string; sent: string }>();
  return json({
    spaceWeather: { kpNow: w.kpNow, observedAt: w.observedAt, kpNext24h: next24h(w, now), fetchedAt: row.fetched_at },
    solarWind: wind ? JSON.parse(wind.body) : null,
    // The storm Live Activity's channel for each APNs environment and the state last broadcast on it.
    storm: storm.results.length ? {
      startedAt: storm.results[0].started_at,
      channels: Object.fromEntries(storm.results.map((c) => [c.environment, c.channel_id])),
      state: JSON.parse(storm.results[0].sent),
    } : null,
  }, 200, MAX_AGE.today);
}

export default {
  async fetch(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const now = new Date();
    if (request.method === "GET" && API.has(url.pathname)) return cached(request, ctx, () => api(url, env, now));

    if (request.method === "GET" && url.pathname === "/healthz") return health(env);
    // The policy lives on krz.sh; older builds link here.
    if (request.method === "GET" && url.pathname === "/privacy") return Response.redirect(PRIVACY_URL, 301);

    if (request.method === "POST" && url.pathname === "/v1/challenge") return issueChallenge(env, now);

    if (request.method === "POST" && url.pathname === "/v1/attest") return attest(request, env, now);

    if (request.method === "POST" && url.pathname === "/v1/devices") return registerDevice(request, env, now);

    const test = url.pathname.match(/^\/v1\/devices\/([0-9a-f]{64,200})\/test$/i);
    if (request.method === "POST" && test) return sendTest(env, test[1].toLowerCase(), now);

    if (request.method === "POST" && url.pathname === "/v1/launch-starts") return registerLaunchStarts(request, env, now);
    const delStarts = url.pathname.match(/^\/v1\/launch-starts\/([0-9a-f]{64,200})$/i);
    if (request.method === "DELETE" && delStarts) return deleteRow(env, "DELETE FROM launch_starts WHERE token = ?1", delStarts[1].toLowerCase());

    const del = url.pathname.match(/^\/v1\/devices\/([0-9a-f]{64,200})$/i);
    if (request.method === "DELETE" && del) return deleteRow(env, "DELETE FROM devices WHERE token = ?1", del[1]);

    return json({ error: "not found" }, 404);
  },

  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    const now = new Date(controller.scheduledTime);
    if (controller.cron === NEWS_CRON) {
      ctx.waitUntil((now.getUTCMinutes() === 0 ? pollNews(env, now) : Promise.resolve()).then(() => sendNewsDigests(env, now)));
      if (now.getUTCHours() === 0 && now.getUTCMinutes() === 0) ctx.waitUntil(prune(env, now));
    } else if (controller.cron === SATELLITE_CRON) ctx.waitUntil(pollSatellites(env, now));
    else if (controller.cron === FOCUS_CRON) ctx.waitUntil(focusTick(env, now));
    else ctx.waitUntil(Promise.all([pollSpaceWeather(env, now), launchTick(env, now), retrySatellites(env, now), pollSun(env, now)]));
  },
} satisfies ExportedHandler<Env>;

async function health(env: Env): Promise<Response> {
  const rows = await env.DB.prepare("SELECT feed, fetched_at, ok FROM feed_snapshots").all();
  return json({ ok: true, feeds: rows.results });
}

async function issueChallenge(env: Env, now: Date): Promise<Response> {
  const challenge = toBase64(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.prepare("INSERT INTO attest_challenges (challenge, expires_at) VALUES (?1, ?2)").bind(challenge, new Date(now.getTime() + CHALLENGE_MS).toISOString()).run();
  return json({ challenge });
}

async function registerDevice(request: Request, env: Env, now: Date): Promise<Response> {
  const body = new Uint8Array(await request.arrayBuffer());
  let d: Partial<DeviceRequest>;
  try {
    d = JSON.parse(new TextDecoder().decode(body));
  } catch {
    d = {};
  }
  if (!validDevice(d)) return json({ error: "invalid device" }, 400);
  const refused = await checkAssertion(env, request, body, d.challenge, now);
  if (refused) return refused;
  await env.DB.prepare(
    `INSERT INTO devices (token, environment, band, utc_offset_minutes, aurora, news, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
     ON CONFLICT (token) DO UPDATE SET environment = ?2, band = ?3, utc_offset_minutes = ?4, aurora = ?5, news = ?6, last_seen = ?7`,
  ).bind(d.token.toLowerCase(), d.environment, d.band, d.utcOffsetMinutes, d.aurora === false ? 0 : 1, d.news === true ? 1 : 0, now.toISOString()).run();
  return json({ ok: true });
}

async function deleteRow(env: Env, sql: string, token: string): Promise<Response> {
  await env.DB.prepare(sql).bind(token).run();
  return json({ ok: true });
}

const apnsConfig = (env: Env): ApnsConfig => ({ keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC });

/** A Live Activity push to a channel, kept by APNs for 8 hours. */
function broadcastPush(config: ApnsConfig, c: { channel_id: string; environment: string }, push: { payload: unknown; priority: 5 | 10 }, now: Date) {
  return broadcast(config, c.channel_id, push.payload, {
    sandbox: c.environment === "sandbox",
    priority: push.priority,
    expiration: Math.floor(now.getTime() / 1000) + 8 * 3600,
  });
}

/** Deletes the channels in `table` whose stored end message has expired. */
async function deleteEndedChannels(env: Env, config: ApnsConfig, table: "launch_channels" | "storm_channels", now: Date): Promise<void> {
  const done = await env.DB.prepare(`SELECT channel_id, environment FROM ${table} WHERE ended_at < ?1`)
    .bind(new Date(now.getTime() - 8 * 3600_000).toISOString()).all<{ channel_id: string; environment: string }>();
  const label = table === "storm_channels" ? "apns storm channel delete" : "apns channel delete";
  for (const c of done.results) {
    const r = await deleteChannel(config, c.channel_id, c.environment === "sandbox");
    if (r.status === 204 || r.status === 404) await env.DB.prepare(`DELETE FROM ${table} WHERE channel_id = ?1`).bind(c.channel_id).run();
    else console.error(label, r.status, r.reason);
  }
}

/** A channel per environment for each launch that needs one: from the pool, or created when channels are managed here. */
async function assignLaunchChannels(env: Env, config: ApnsConfig, manage: boolean, near: Near[], now: Date): Promise<void> {
  const assigned = await env.DB.prepare("SELECT launch_id, environment FROM launch_channels WHERE launch_id IS NOT NULL").all<{ launch_id: string; environment: string }>();
  const has = new Set(assigned.results.map((c) => `${c.launch_id}:${c.environment}`));
  for (const l of near.filter((l) => needsChannel(l, now))) {
    for (const environment of ["sandbox", "production"]) {
      if (!has.has(`${l.id}:${environment}`)) await assignLaunchChannel(env, manage ? config : null, l, environment, now);
    }
  }
}

/** Takes a pooled channel for a launch in one environment, or creates one when `creator` may. */
async function assignLaunchChannel(env: Env, creator: ApnsConfig | null, l: Near, environment: string, now: Date): Promise<void> {
  const pooled = await env.DB.prepare(
    `UPDATE launch_channels SET launch_id = ?1, net = ?2, status = ?3
     WHERE channel_id = (SELECT channel_id FROM launch_channels WHERE launch_id IS NULL AND environment = ?4 ORDER BY created_at LIMIT 1)`,
  ).bind(l.id, l.net, l.status, environment).run();
  if (pooled.meta.changes) return;
  if (!creator) {
    console.error("launch channel pool empty", environment);
    return;
  }
  const c = await createChannel(creator, environment === "sandbox");
  if (!c.channelId) {
    console.error("apns channel", c.status, c.reason);
    return;
  }
  await env.DB.prepare("INSERT INTO launch_channels (channel_id, environment, launch_id, net, status, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)")
    .bind(c.channelId, environment, l.id, l.net, l.status, now.toISOString()).run();
}

/** An open storm channel and what it last broadcast. */
interface StormChannelRow {
  channel_id: string;
  environment: string;
  active_at: string;
  sent: string | null;
  sent_at: string | null;
}

/** One new storm channel per environment, recorded as open. */
async function openStormChannels(env: Env, config: ApnsConfig, iso: string): Promise<StormChannelRow[]> {
  const open: StormChannelRow[] = [];
  for (const environment of ["sandbox", "production"]) {
    const c = await createChannel(config, environment === "sandbox");
    if (!c.channelId) {
      console.error("apns storm channel", c.status, c.reason);
      continue;
    }
    await env.DB.prepare("INSERT INTO storm_channels (channel_id, environment, started_at, active_at) VALUES (?1, ?2, ?3, ?3)").bind(c.channelId, environment, iso).run();
    open.push({ channel_id: c.channelId, environment, active_at: iso, sent: null, sent_at: null });
  }
  return open;
}

/** Pushes the storm's change to one open channel, ending it once the storm has been calm long enough. */
async function updateStormChannel(env: Env, config: ApnsConfig, c: StormChannelRow, state: StormState, now: Date): Promise<void> {
  const iso = now.toISOString();
  const active = stormActive(state);
  const end = !active && now.getTime() - Date.parse(c.active_at) >= CALM_MS;
  const push: StormPush | null = end ? stormEnd(state, now)
    : stormUpdate(c.sent && c.sent_at ? { state: JSON.parse(c.sent), at: new Date(c.sent_at) } : null, state, now);
  if (active) await env.DB.prepare("UPDATE storm_channels SET active_at = ?2 WHERE channel_id = ?1").bind(c.channel_id, iso).run();
  if (!push) return;
  const r = await broadcastPush(config, c, push, now)
    .catch((e) => ({ status: 0, reason: String(e) }));
  if (r.status !== 200) {
    console.error("apns storm broadcast", r.status, r.reason);
    return;
  }
  await env.DB.prepare("UPDATE storm_channels SET sent = ?2, sent_at = ?3, ended_at = ?4 WHERE channel_id = ?1")
    .bind(c.channel_id, JSON.stringify(state), iso, end ? iso : null).run();
}

const appId = (env: Env) => `${env.APNS_TEAM_ID}.${env.APNS_TOPIC}`;

/** Deletes a challenge and says whether it was there and unexpired. */
async function useChallenge(env: Env, challenge: string | undefined, now: Date): Promise<boolean> {
  if (typeof challenge !== "string") return false;
  const row = await env.DB.prepare("DELETE FROM attest_challenges WHERE challenge = ?1 RETURNING expires_at").bind(challenge).first<{ expires_at: string }>();
  return !!row && row.expires_at > now.toISOString();
}

/** POST /v1/attest {keyId, attestation, challenge}: stores a key Apple attests belongs to this app. */
async function attest(request: Request, env: Env, now: Date): Promise<Response> {
  const a = (await request.json().catch(() => ({}))) as { keyId?: unknown; attestation?: unknown; challenge?: string };
  if (typeof a.keyId !== "string" || typeof a.attestation !== "string" || a.attestation.length > 20_000) return json({ error: "invalid attestation" }, 400);
  if (!(await useChallenge(env, a.challenge, now))) return json({ error: "unknown or expired challenge" }, 401);
  let key: AttestedKey;
  try {
    key = await verifyAttestation({ attestation: fromBase64(a.attestation), keyId: a.keyId, challenge: fromBase64(a.challenge!), appId: appId(env), now });
  } catch (e) {
    // Malformed input surfaces as DOMException (base64, WebCrypto) or RangeError (truncated data) as well as AttestError.
    return json({ error: `attestation: ${e instanceof AttestError ? e.message : "malformed"}` }, 401);
  }
  await env.DB.prepare("INSERT OR IGNORE INTO app_keys (key_id, spki, environment, counter, created_at, last_used) VALUES (?1, ?2, ?3, 0, ?4, ?4)")
    .bind(a.keyId, toBase64(key.spki), key.environment, now.toISOString()).run();
  return json({ ok: true });
}

/**
 * A refusal, or null to go ahead: the request's App Attest assertion (header x-app-attest-assertion, by key
 * x-app-attest-key) must sign the exact body, which carries a fresh challenge. Without one, refused only when
 * APP_ATTEST is "require".
 */
async function checkAssertion(env: Env, request: Request, body: Uint8Array, challenge: string | undefined, now: Date): Promise<Response | null> {
  const keyId = request.headers.get("x-app-attest-key"), assertion = request.headers.get("x-app-attest-assertion");
  if (!keyId || !assertion) return env.APP_ATTEST === "require" ? json({ error: "app attest required" }, 401) : null;
  const key = await env.DB.prepare("SELECT spki, counter FROM app_keys WHERE key_id = ?1").bind(keyId).first<{ spki: string; counter: number }>();
  if (!key) return json({ error: "unknown key" }, 401);
  if (!(await useChallenge(env, challenge, now))) return json({ error: "unknown or expired challenge" }, 401);
  let counter: number;
  try {
    counter = await verifyAssertion({ assertion: fromBase64(assertion), clientData: body, spki: fromBase64(key.spki), appId: appId(env), lastCounter: key.counter });
  } catch (e) {
    return json({ error: `assertion: ${e instanceof AttestError ? e.message : "malformed"}` }, 401);
  }
  // The counter only rises, so a replayed or concurrent assertion with the same counter loses here.
  const updated = await env.DB.prepare("UPDATE app_keys SET counter = ?2, last_used = ?3 WHERE key_id = ?1 AND counter < ?2").bind(keyId, counter, now.toISOString()).run();
  return updated.meta.changes ? null : json({ error: "assertion: counter" }, 401);
}

/** One test push to a registered device, at most once per 10 minutes per device. */
async function sendTest(env: Env, token: string, now: Date): Promise<Response> {
  const device = await env.DB.prepare("SELECT environment FROM devices WHERE token = ?1").bind(token).first<{ environment: string }>();
  if (!device) return json({ error: "not registered" }, 404);
  const window = `${token}:${now.toISOString().slice(0, 15)}`; // 10-minute bucket
  const claimed = await env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES ('test', 0, ?1, ?2)")
    .bind(window, now.toISOString()).run();
  if (!claimed.meta.changes) return json({ error: "try again in a few minutes" }, 429);
  const config = apnsConfig(env);
  const payload = { aps: { alert: { title: "Moonrise test alert", body: "Alerts reach this device." }, sound: "default" } };
  const r = await send(config, token, payload, device.environment === "sandbox");
  if (r.status === 410) await env.DB.prepare("DELETE FROM devices WHERE token = ?1").bind(token).run();
  return json({ apnsStatus: r.status, reason: r.reason }, r.status === 200 ? 200 : 502);
}

/**
 * The live event at `?at=` (default now) and its geocentric ecliptic trajectory up to then:
 * points are [unix seconds, x, y, z] km. The cached trajectory is refreshed from Horizons at most
 * every 10 minutes while the event runs, and no sooner than 10 minutes after a failed attempt.
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
  // One Horizons request per event per 10 minutes, across requests and isolates and after failures
  // (JPL's fair use policy: no simultaneous requests, back off on errors). The request that claims the
  // attempt row makes it.
  const claimed = covered < wanted && stale && (await env.DB.prepare(
    "INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES (?1, ?2, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?2 WHERE fetched_at < ?3",
  ).bind(`${key}:attempt`, now.toISOString(), new Date(now.getTime() - 10 * 60_000).toISOString()).run()).meta.changes === 1;
  if (claimed) {
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

/** `?environment=sandbox` gives Debug builds the channels of the APNs sandbox. */
async function launches(env: Env, url: URL, now: Date): Promise<Response> {
  const since = new Date(now.getTime() - 6 * 3600_000).toISOString();
  const [rows, recent, fetched, els, ch] = await env.DB.batch<Record<string, unknown>>([
    env.DB.prepare("SELECT * FROM launches WHERE net >= ?1 ORDER BY net LIMIT 20").bind(since),
    env.DB.prepare("SELECT * FROM launches WHERE net < ?1 AND net >= ?2 ORDER BY net DESC LIMIT 20").bind(since, new Date(now.getTime() - RETENTION_MS).toISOString()),
    env.DB.prepare("SELECT fetched_at FROM feed_snapshots WHERE feed = 'll2' AND ok = 1"),
    env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'launch-elements' AND ok = 1"),
    env.DB.prepare("SELECT launch_id, channel_id FROM launch_channels WHERE environment = ?1 AND launch_id IS NOT NULL AND ended_at IS NULL")
      .bind(url.searchParams.get("environment") === "sandbox" ? "sandbox" : "production"),
  ]);
  const elements: Record<string, LaunchElements> = els.results.length ? JSON.parse(String(els.results[0].body)) : {};
  const channels = Object.fromEntries(ch.results.map((c) => [c.launch_id, c.channel_id]));
  const shape = (r: Record<string, unknown>) => ({
    id: r.id, name: r.name, net: r.net, windowStart: r.window_start, windowEnd: r.window_end,
    status: r.status, statusName: r.status_name, provider: r.provider, rocket: r.rocket,
    mission: r.mission, missionType: r.mission_type, missionDescription: r.mission_description, orbit: r.orbit,
    pad: r.pad, location: r.location, padLatitude: r.pad_latitude, padLongitude: r.pad_longitude,
    elements: elements[String(r.id)]?.elements ?? [], elementsSource: elements[String(r.id)]?.source ?? null,
    channelId: channels[String(r.id)] ?? null,
  });
  return json({
    fetchedAt: fetched.results[0]?.fetched_at ?? null,
    launches: rows.results.map(shape),
    recent: recent.results.map(shape),
  }, 200, MAX_AGE.launches);
}

type Near = ActivityState & { id: string };

const nearLaunches = async (env: Env, now: Date): Promise<Near[]> =>
  (await env.DB.prepare("SELECT id, net, status FROM launches WHERE net >= ?1 ORDER BY net").bind(sinceNet(now)).all<Near>()).results;

/**
 * Launch Library 2: the launch in focus (T−60 to T+15) on its own, with the list paused; otherwise the upcoming list
 * every 10 minutes and previous launches hourly. Anonymous (15 requests per hour), the launch in focus every 5 minutes:
 * at most 12 + 1 requests in any hour. With a key (45 per hour), every 2 minutes with focusTick: at most 30 + 1.
 */
async function launchTick(env: Env, now: Date): Promise<void> {
  const near = await nearLaunches(env, now);
  const throttled = await ll2Throttled(env, now);
  const focus = near.filter((l) => inFocus(l, now)).map((l) => l.id);
  const keyed = Boolean(env.LL2_API_KEY);
  const pollFocus = !throttled && focus.length > 0 && focusPollDue(5, now, keyed);
  const pollList = !throttled && !focus.length && now.getUTCMinutes() % 10 === 0;
  if (pollFocus) await pollLaunch(env, focusPick(focus, now, focusEvery(keyed)), now);
  else if (pollList) await pollLaunches(env, now);
  // Channels are handed out with the launch's current state, so a poll means reading it again.
  if (env.APNS_KEY) await launchChannels(env, pollFocus || pollList ? await nearLaunches(env, now) : near, now);
  if (env.APNS_KEY) await startLaunches(env, now);
}

const RULE = (v: unknown) => Array.isArray(v) && v.length <= 20 && v.every((x) => typeof x === "string" && x.length > 0 && x.length <= 100);

/**
 * POST /v1/launch-starts {token, environment, rockets, providers, challenge?}: the rockets and providers whose launches
 * start a countdown on this install. Signed with App Attest like /v1/devices. No rules removes the token.
 */
async function registerLaunchStarts(request: Request, env: Env, now: Date): Promise<Response> {
  const body = new Uint8Array(await request.arrayBuffer());
  let d: { token?: unknown; environment?: unknown; rockets?: unknown; providers?: unknown; challenge?: string };
  try {
    d = JSON.parse(new TextDecoder().decode(body));
  } catch {
    d = {};
  }
  if (!validToken(d.token) || !validEnvironment(d.environment) || !RULE(d.rockets) || !RULE(d.providers)) {
    return json({ error: "invalid registration" }, 400);
  }
  const refused = await checkAssertion(env, request, body, d.challenge, now);
  if (refused) return refused;
  const rockets = d.rockets as string[], providers = d.providers as string[];
  if (!rockets.length && !providers.length) {
    await env.DB.prepare("DELETE FROM launch_starts WHERE token = ?1").bind(d.token.toLowerCase()).run();
  } else {
    await env.DB.prepare(
      `INSERT INTO launch_starts (token, environment, rockets, providers, last_seen) VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT (token) DO UPDATE SET environment = ?2, rockets = ?3, providers = ?4, last_seen = ?5`,
    ).bind(d.token.toLowerCase(), d.environment, JSON.stringify(rockets), JSON.stringify(providers), now.toISOString()).run();
  }
  return json({ ok: true });
}

/**
 * Push-to-start for followed launches: an hour before NET, each install following the launch's rocket or provider
 * gets the countdown, subscribed to the launch's broadcast channel. Once per install, launch and NET date, so a
 * launch moved to another day starts again.
 */
async function startLaunches(env: Env, now: Date): Promise<void> {
  const due = (await env.DB.prepare(
    "SELECT id, name, net, status, rocket, provider, mission, location FROM launches WHERE net > ?1 AND net <= ?2",
  // A minute either side: LL2 writes "…:00Z" and toISOString "…:00.000Z", which compare unequal as text. startDue decides.
  ).bind(new Date(now.getTime() - 60_000).toISOString(), new Date(now.getTime() + 61 * 60_000).toISOString()).all<StartLaunch>()).results.filter((l) => startDue(l, now));
  if (!due.length) return;
  const config = apnsConfig(env);
  for (const l of due) {
    const channels = Object.fromEntries((await env.DB.prepare("SELECT environment, channel_id FROM launch_channels WHERE launch_id = ?1 AND ended_at IS NULL")
      .bind(l.id).all<{ environment: string; channel_id: string }>()).results.map((c) => [c.environment, c.channel_id]));
    const event = `${l.id}:${l.net.slice(0, 10)}`;
    const installs = (await env.DB.prepare(
      `SELECT token, environment FROM launch_starts s
       WHERE (EXISTS (SELECT 1 FROM json_each(s.rockets) WHERE value = ?1) OR EXISTS (SELECT 1 FROM json_each(s.providers) WHERE value = ?2))
       AND NOT EXISTS (SELECT 1 FROM alerts_sent a WHERE a.kind = 'start' AND a.band = 0 AND a.event = s.token || ':' || ?3)
       LIMIT ?4`,
    ).bind(l.rocket, l.provider, event, PUSH_SLICE).all<{ token: string; environment: string }>()).results;
    if (!installs.length) continue;
    const results = await sendAll(config, installs.map((i) => ({
      token: i.token, payload: startPayload(l, channels[i.environment] ?? null, now), sandbox: i.environment === "sandbox", type: "liveactivity" as const,
    })), PUSH_CONCURRENCY);
    const writes: D1PreparedStatement[] = [];
    installs.forEach((i, k) => {
      const { status, reason } = results[k];
      if (status !== 200) console.error("apns start", status, reason);
      if (status === 410) writes.push(env.DB.prepare("DELETE FROM launch_starts WHERE token = ?1").bind(i.token));
      else if (!retryable(status)) writes.push(env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES ('start', 0, ?1, ?2)").bind(`${i.token}:${event}`, now.toISOString()));
    });
    if (writes.length) await env.DB.batch(writes);
  }
}

/** With an LL2 key: the launch in focus on the even minutes the 5-minute cron does not run on, and its broadcasts. */
async function focusTick(env: Env, now: Date): Promise<void> {
  if (!focusPollDue(2, now, Boolean(env.LL2_API_KEY)) || await ll2Throttled(env, now)) return;
  const focus = (await nearLaunches(env, now)).filter((l) => inFocus(l, now)).map((l) => l.id);
  if (!focus.length) return;
  await pollLaunch(env, focusPick(focus, now, focusEvery(true)), now);
  if (env.APNS_KEY) await broadcastChanges(env, now);
}

/** Whether LL2 said to wait (HTTP 429) and the wait has not passed. */
async function ll2Throttled(env: Env, now: Date): Promise<boolean> {
  const row = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'll2:throttled'").first<{ body: string }>();
  return row !== null && Date.parse(row.body) > now.getTime();
}

/** After a 429, no LL2 requests until /api-throttle/ says the limit has reset (15 minutes if it cannot say). */
async function ll2Throttle(env: Env, now: Date): Promise<void> {
  const seconds = await throttleSeconds(env.LL2_API_KEY).catch(() => 0) || 15 * 60;
  await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('ll2:throttled', ?1, 0, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, body = ?2")
    .bind(now.toISOString(), new Date(now.getTime() + seconds * 1000).toISOString()).run();
}

async function pollLaunch(env: Env, id: string, now: Date): Promise<void> {
  try {
    await env.DB.batch(upsertLaunches(env, [await fetchLaunch(id, env.LL2_API_KEY)]));
  } catch (e) {
    console.error("ll2 launch", String(e));
    if (e instanceof Throttled) await ll2Throttle(env, now);
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
  }
}

// Failures are recorded under "<feed>:error" so the last good snapshot and its time survive.
async function pollLaunches(env: Env, now: Date): Promise<void> {
  let list: Launch[];
  try {
    list = await fetchLaunches(UPCOMING_URL, env.LL2_API_KEY);
  } catch (e) {
    console.error("ll2", String(e));
    if (e instanceof Throttled) await ll2Throttle(env, now);
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    return;
  }
  // Previous launches on the first run of each hour: designators and outcomes arrive after a launch leaves the upcoming list.
  if (now.getUTCMinutes() < 10) {
    try {
      list = [...list, ...(await fetchLaunches(PREVIOUS_URL, env.LL2_API_KEY))];
    } catch (e) {
      console.error("ll2 previous", String(e));
      if (e instanceof Throttled) await ll2Throttle(env, now);
    }
  }
  await env.DB.batch([
    ...upsertLaunches(env, list),
    env.DB.prepare("DELETE FROM launches WHERE net < ?1").bind(new Date(now.getTime() - RETENTION_MS).toISOString()),
    env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('ll2', ?1, 1) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1").bind(now.toISOString()),
  ]);
}

function upsertLaunches(env: Env, list: Launch[]): D1PreparedStatement[] {
  const upsert = env.DB.prepare(
    `INSERT INTO launches (id, name, net, window_start, window_end, status, status_name, provider, rocket, mission, mission_type, mission_description, orbit, pad, location, pad_latitude, pad_longitude, last_updated, launch_designator)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
     ON CONFLICT (id) DO UPDATE SET name = ?2, net = ?3, window_start = ?4, window_end = ?5, status = ?6, status_name = ?7, provider = ?8, rocket = ?9,
       mission = ?10, mission_type = ?11, mission_description = ?12, orbit = ?13, pad = ?14, location = ?15, pad_latitude = ?16, pad_longitude = ?17, last_updated = ?18,
       launch_designator = COALESCE(?19, launch_designator)
     WHERE (name, net, window_start, window_end, status, status_name, provider, rocket, mission, mission_type, mission_description, orbit, pad, location, pad_latitude, pad_longitude, last_updated, launch_designator)
       IS NOT (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, COALESCE(?19, launch_designator))`,
  );
  return list.map((l) => upsert.bind(l.id, l.name, l.net, l.windowStart, l.windowEnd, l.status, l.statusName, l.provider, l.rocket, l.mission, l.missionType, l.missionDescription, l.orbit, l.pad, l.location, l.padLatitude, l.padLongitude, l.lastUpdated, l.designator));
}

/**
 * Broadcast channels for launch Live Activities: hands one per APNs environment to each launch within 24 hours
 * (from the pool, or created here with APNS_MANAGE_CHANNELS), broadcasts each change of status or NET, and
 * retires a channel once its launch is over. Nothing about who follows a launch reaches the server.
 */
async function launchChannels(env: Env, near: Near[], now: Date): Promise<void> {
  const config = apnsConfig(env);
  const manage = env.APNS_MANAGE_CHANNELS === "1";
  const iso = now.toISOString();

  await assignLaunchChannels(env, config, manage, near, now);

  await broadcastChanges(env, now);

  // A day past NET without an outcome, or gone from the table: ended without a push, as activities last 8 hours at most.
  await env.DB.prepare("UPDATE launch_channels SET ended_at = ?1 WHERE launch_id IS NOT NULL AND ended_at IS NULL AND launch_id NOT IN (SELECT id FROM launches WHERE net >= ?2)")
    .bind(iso, new Date(now.getTime() - 86400_000).toISOString()).run();
  if (!manage) return;
  // Deleted once the stored end message has expired.
  await deleteEndedChannels(env, config, "launch_channels", now);
}

/** Each change of status or NET since the last broadcast on a channel. */
async function broadcastChanges(env: Env, now: Date): Promise<void> {
  const config = apnsConfig(env);
  const changed = await env.DB.prepare(
    `SELECT c.channel_id, c.environment, c.net AS sent_net, c.status AS sent_status, l.net, l.status
     FROM launch_channels c JOIN launches l ON l.id = c.launch_id WHERE c.ended_at IS NULL AND (c.net != l.net OR c.status != l.status)`,
  ).all<{ channel_id: string; environment: string; sent_net: string; sent_status: string; net: string; status: string }>();
  for (const c of changed.results) {
    const push = activityPush({ net: c.sent_net, status: c.sent_status }, c, now)!;
    // APNs keeps the latest message for devices that are offline, for at most 8 hours.
    const r = await broadcastPush(config, c, push, now)
      .catch((e) => ({ status: 0, reason: String(e) }));
    if (r.status !== 200) {
      console.error("apns broadcast", r.status, r.reason);
      continue;
    }
    await env.DB.prepare("UPDATE launch_channels SET net = ?2, status = ?3, ended_at = ?4 WHERE channel_id = ?1").bind(c.channel_id, c.net, c.status, push.end ? now.toISOString() : null).run();
  }
}

/** One more try at a failed 2-hourly CelesTrak poll, from the 5-minute cron. */
async function retrySatellites(env: Env, now: Date): Promise<void> {
  if (!retryTick(now)) return;
  const rows = await env.DB.prepare("SELECT feed, fetched_at FROM feed_snapshots WHERE feed IN ('celestrak', 'celestrak:error')").all<{ feed: string; fetched_at: string }>();
  const at = Object.fromEntries(rows.results.map((r) => [r.feed, r.fetched_at]));
  if (retryDue(now, at.celestrak ?? null, at["celestrak:error"] ?? null)) await pollSatellites(env, now);
}

async function pollSatellites(env: Env, now: Date): Promise<void> {
  let groups: { visual: Row[]; recent: Row[] };
  // A visual group downloaded earlier in this 2-hourly update, kept when last-30-days failed.
  const kept = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'celestrak:visual' AND fetched_at > ?1")
    .bind(new Date(now.getTime() - 60 * 60_000).toISOString()).first<{ body: string }>();
  try {
    groups = await fetchGroups(kept ? JSON.parse(kept.body) : undefined);
  } catch (e) {
    console.error("celestrak", String(e));
    const visual = (e as { visual?: Row[] }).visual;
    await env.DB.batch([
      env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('celestrak:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()),
      ...(visual && !kept ? [env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('celestrak:visual', ?1, 1, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, body = ?2").bind(now.toISOString(), JSON.stringify(visual))] : []),
    ]);
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
  const wind = await pollSolarWind(env, now);
  await sendAuroraAlerts(env, w, wind, now);
  await stormChannels(env, {
    kp: w.kpNow, expectedKp: actionableKp(w.kpNow, w.forecast, now), early: stormLikely(wind, now),
    bz: wind?.series.findLast((p) => p.bz !== null)?.bz ?? null, speed: wind?.series.findLast((p) => p.speed !== null)?.speed ?? null,
  }, now);
}

/**
 * Broadcast channels for the storm Live Activity: a pair (sandbox, production) opens when a storm starts, carries
 * its updates, and closes with an end message after 3 calm hours. Channels are deleted once that message expires.
 */
async function stormChannels(env: Env, state: StormState, now: Date): Promise<void> {
  if (!env.APNS_KEY) return;
  const config = apnsConfig(env);
  const iso = now.toISOString();
  const active = stormActive(state);
  let open = (await env.DB.prepare("SELECT channel_id, environment, active_at, sent, sent_at FROM storm_channels WHERE ended_at IS NULL")
    .all<StormChannelRow>()).results;
  if (!open.length && active && env.APNS_MANAGE_CHANNELS === "1") open = await openStormChannels(env, config, iso);
  for (const c of open) await updateStormChannel(env, config, c, state, now);
  if (env.APNS_MANAGE_CHANNELS !== "1") return;
  await deleteEndedChannels(env, config, "storm_channels", now);
}

/** RTSW, reduced; the last good copy is kept on failure, and null is returned so no alert rests on old wind. */
async function pollSolarWind(env: Env, now: Date): Promise<SolarWind | null> {
  try {
    const wind = await fetchSolarWind(now);
    if (!wind) return null;
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('rtsw', ?1, 1, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1, body = ?2")
      .bind(now.toISOString(), JSON.stringify(wind)).run();
    return wind;
  } catch (e) {
    console.error("rtsw", String(e));
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok) VALUES ('rtsw:error', ?1, 0) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1").bind(now.toISOString()).run();
    return null;
  }
}

/**
 * Hourly at minute 20: WSA-Enlil (runs every few hours) and the CCOR-2 listing; solar cycle numbers once a day
 * (monthly data), or whenever none are stored. Each kept until a fetch succeeds.
 */
async function pollSun(env: Env, now: Date): Promise<void> {
  if (now.getUTCMinutes() !== 20) return;
  const save = env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES (?1, ?2, 1, ?3) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?2, ok = 1, body = ?3");
  const jobs: [string, () => Promise<unknown>][] = [["sun:enlil", () => fetchEnlil(now)], ["sun:ccor2", () => fetchCcor2(now)]];
  const cycle = await env.DB.prepare("SELECT 1 FROM feed_snapshots WHERE feed = 'sun:cycle' AND ok = 1").first();
  if (now.getUTCHours() === 0 || !cycle) jobs.push(["sun:cycle", () => fetchCycle()]);
  const sbdb = await env.DB.prepare("SELECT 1 FROM feed_snapshots WHERE feed = 'sbdb' AND ok = 1").first();
  if (now.getUTCHours() === 3 || !sbdb) jobs.push(["sbdb", () => fetchSmallBodies(now)]);
  for (const [feed, job] of jobs) {
    try {
      await save.bind(feed, now.toISOString(), JSON.stringify(await job())).run();
    } catch (e) {
      console.error(feed, String(e));
    }
  }
}

async function sendAuroraAlerts(env: Env, w: SpaceWeather, wind: SolarWind | null, now: Date): Promise<void> {
  const forecastKp = actionableKp(w.kpNow, w.forecast, now);
  const early = stormLikely(wind, now) && forecastKp < STORM_KP;
  const kp = early ? STORM_KP : forecastKp;
  const bandRows = await env.DB.prepare("SELECT DISTINCT band FROM devices WHERE aurora = 1").all<{ band: number }>();
  const bands = alertBands(kp, bandRows.results.map((r) => r.band));
  if (!bands.length || !env.APNS_KEY) return;

  const event = eventKey(now);
  const devices = await env.DB.prepare(
    `SELECT token, environment, band, utc_offset_minutes FROM devices d WHERE d.aurora = 1 AND d.band IN (SELECT value FROM json_each(?1))
     AND NOT EXISTS (SELECT 1 FROM alerts_sent a WHERE a.kind = 'aurora' AND a.band = d.band AND a.event = d.token || ':' || ?2)`,
  ).bind(JSON.stringify(bands), event).all<{ token: string; environment: string; band: number; utc_offset_minutes: number }>();
  const due = devices.results.filter((d) => isNight(now, d.utc_offset_minutes)).map((d) => ({ ...d, event: `${d.token}:${event}` }));
  await sendAlerts(env, "aurora", due, now, (d) => ({
    aps: { alert: { title: "Aurora possible tonight", body: early
      ? `The solar wind has turned strongly south; aurora often follows within the hour. Look toward the ${d.band >= 0 ? "north" : "south"} after dark.`
      : `Kp ${kp.toFixed(1)}. Look toward the ${d.band >= 0 ? "north" : "south"} after dark.` }, sound: "default" },
  }));
}

/** Spaceflight News API hourly, as The Space Devs asked; the last good copy is kept on failure. */
async function pollNews(env: Env, now: Date): Promise<void> {
  try {
    const articles = await fetchLatest();
    await env.DB.prepare("INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('news', ?1, 1, ?2) ON CONFLICT (feed) DO UPDATE SET fetched_at = ?1, ok = 1, body = ?2")
      .bind(now.toISOString(), JSON.stringify(articles)).run();
  } catch (e) {
    console.error("snapi", String(e));
  }
}

/** The daily news digest, sent in the 09:00 local hour to devices that opted in, once per local day. */
async function sendNewsDigests(env: Env, now: Date): Promise<void> {
  if (!env.APNS_KEY) return;
  const [first, second] = dueOffsets(now);
  const rows = await env.DB.prepare(
    `SELECT token, environment, utc_offset_minutes FROM devices d WHERE d.news = 1
     AND (d.utc_offset_minutes >= ?1 AND d.utc_offset_minutes < ?2 OR d.utc_offset_minutes >= ?3 AND d.utc_offset_minutes < ?4)
     AND NOT EXISTS (SELECT 1 FROM alerts_sent a WHERE a.kind = 'news' AND a.band = 0 AND a.event = d.token || ':' || date(?5, d.utc_offset_minutes || ' minutes'))`,
  ).bind(...first, ...second, now.toISOString()).all<{ token: string; environment: string; utc_offset_minutes: number }>();
  const due = rows.results.map((d) => ({ ...d, band: 0, event: `${d.token}:${localDate(now, d.utc_offset_minutes)}` }));
  if (!due.length) return;

  const row = await env.DB.prepare("SELECT body FROM feed_snapshots WHERE feed = 'news' AND ok = 1").first<{ body: string }>();
  const headlines = pickHeadlines(row ? JSON.parse(row.body) as Article[] : [], now);
  if (!headlines.length) return;
  const payload = digestPayload(headlines);

  await sendAlerts(env, "news", due, now, () => payload);
}

interface Recipient {
  token: string;
  environment: string;
  band: number;
  /** The alerts_sent key for this device. */
  event: string;
}

/**
 * Sends to the first PUSH_SLICE recipients, then in one batch records every send APNs answered for good in
 * alerts_sent and drops devices it reports gone (410). Retryable failures are not recorded, so a later run tries again.
 */
async function sendAlerts(env: Env, kind: string, recipients: Recipient[], now: Date, payload: (r: Recipient) => unknown): Promise<void> {
  const config = apnsConfig(env);
  const slice = recipients.slice(0, PUSH_SLICE);
  const results = await sendAll(config, slice.map((r) => ({ token: r.token, payload: payload(r), sandbox: r.environment === "sandbox" })), PUSH_CONCURRENCY);
  const sent = env.DB.prepare("INSERT OR IGNORE INTO alerts_sent (kind, band, event, sent_at) VALUES (?1, ?2, ?3, ?4)");
  const gone = env.DB.prepare("DELETE FROM devices WHERE token = ?1");
  const writes: D1PreparedStatement[] = [];
  slice.forEach((r, i) => {
    const { status, reason } = results[i];
    if (status !== 200) console.error("apns", status, reason);
    if (status === 410) writes.push(gone.bind(r.token));
    else if (!retryable(status)) writes.push(sent.bind(kind, r.band, r.event, now.toISOString()));
  });
  if (writes.length) await env.DB.batch(writes);
}

/** Daily: alert keys older than 3 days (the longest is a local day) and devices not registered in DEVICE_RETENTION_MS. */
async function prune(env: Env, now: Date): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM attest_challenges WHERE expires_at < ?1").bind(now.toISOString()),
    env.DB.prepare("DELETE FROM app_keys WHERE last_used < ?1").bind(new Date(now.getTime() - DEVICE_RETENTION_MS).toISOString()),
    env.DB.prepare("DELETE FROM alerts_sent WHERE sent_at < ?1").bind(new Date(now.getTime() - 3 * 86400_000).toISOString()),
    env.DB.prepare("DELETE FROM devices WHERE last_seen < ?1").bind(new Date(now.getTime() - DEVICE_RETENTION_MS).toISOString()),
    env.DB.prepare("DELETE FROM launch_starts WHERE last_seen < ?1").bind(new Date(now.getTime() - DEVICE_RETENTION_MS).toISOString()),
  ]);
}
