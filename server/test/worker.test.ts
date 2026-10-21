import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { registerHooks } from "node:module";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import { afterEach, test } from "node:test";

// src/index.ts imports without extensions, which wrangler's bundler resolves.
registerHooks({
  resolve(specifier, context, next) {
    try {
      return next(specifier, context);
    } catch (e) {
      if (specifier.startsWith(".")) return next(`${specifier}.ts`, context);
      throw e;
    }
  },
});
const { default: worker } = await import("../src/index.ts");

const FIVE = "*/5 * * * *";
const TWO = "*/2 * * * *";
const NEWS = "*/10 * * * *";
const SATELLITES = "7 */2 * * *";

interface Call {
  sql: string;
  params: SQLInputValue[];
}

/** D1 over node:sqlite with the migrations applied. Each call is one D1 round trip; a batch is one call. */
function database() {
  const db = new DatabaseSync(":memory:");
  const dir = new URL("../migrations/", import.meta.url);
  for (const f of readdirSync(dir).sort()) db.exec(readFileSync(new URL(f, dir), "utf8"));
  const calls: Call[] = [];
  const statement = (sql: string, params: SQLInputValue[] = []) => ({
    sql,
    params,
    bind: (...p: SQLInputValue[]) => statement(sql, p),
    exec() {
      const results = db.prepare(sql).all(...params);
      return { results, success: true, meta: { changes: (db.prepare("SELECT changes() AS n").get() as { n: number }).n } };
    },
    async all() {
      calls.push({ sql, params });
      return this.exec();
    },
    async first() {
      calls.push({ sql, params });
      return this.exec().results[0] ?? null;
    },
    async run() {
      calls.push({ sql, params });
      return this.exec();
    },
  });
  const DB = {
    prepare: (sql: string) => statement(sql),
    async batch(statements: ReturnType<typeof statement>[]) {
      calls.push({ sql: "batch", params: [] });
      db.exec("BEGIN");
      try {
        const out = statements.map((s) => s.exec());
        db.exec("COMMIT");
        return out;
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
    },
  };
  return { db, DB, calls };
}

async function apnsKey(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
}

async function setup(vars: Record<string, string> = {}) {
  const { db, DB, calls } = database();
  const env = { DB, APNS_KEY_ID: "KEY1234567", APNS_TEAM_ID: "TEAM123456", APNS_TOPIC: "sh.krz.moonrise", APNS_KEY: await apnsKey(), ...vars };
  return { db, env, calls };
}

const real = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = real;
});

type Handler = (url: URL, init: RequestInit) => Response | Promise<Response>;

/** Answers by host; anything else gets 503. Returns the hosts requested, in order. */
function network(handlers: Record<string, Handler>): string[] {
  const hosts: string[] = [];
  globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
    const url = new URL(String(input));
    hosts.push(url.hostname);
    const h = handlers[url.hostname];
    return h ? h(url, init) : new Response("unavailable", { status: 503 });
  }) as typeof fetch;
  return hosts;
}

/** APNs alert sends: status by device token (default 200); `fail` throws, as fetch does past the subrequest limit. */
function apns(status: Record<string, number> = {}) {
  const state = { sent: [] as string[], broadcasts: 0, inFlight: 0, maxInFlight: 0, fail: (_n: number) => false };
  const handler: Handler = async (url) => {
    if (url.pathname.startsWith("/4/broadcasts/")) {
      state.broadcasts++;
      return new Response(null, { status: 200 });
    }
    if (state.fail(state.sent.length)) throw new Error("Too many subrequests.");
    const token = url.pathname.split("/").at(-1)!;
    state.sent.push(token);
    state.inFlight++;
    state.maxInFlight = Math.max(state.maxInFlight, state.inFlight);
    await new Promise((r) => setTimeout(r, 2));
    state.inFlight--;
    const s = status[token] ?? 200;
    return new Response(s === 200 ? null : JSON.stringify({ reason: "x" }), { status: s });
  };
  return { state, handlers: { "api.push.apple.com": handler, "api.sandbox.push.apple.com": handler } };
}

function swpc(kp: number): Record<string, Handler> {
  return {
    "services.swpc.noaa.gov": (url) =>
      Response.json(url.pathname.includes("planetary_k_index_1m") ? [{ time_tag: "2026-10-20T22:00:00", estimated_kp: kp }] : []),
  };
}

async function run(env: object, cron: string, iso: string): Promise<void> {
  const pending: Promise<unknown>[] = [];
  await worker.scheduled({ cron, scheduledTime: Date.parse(iso) } as never, env as never, { waitUntil: (p: Promise<unknown>) => pending.push(p) } as never);
  await Promise.all(pending);
}

const token = (i: number) => i.toString(16).padStart(64, "0");

function device(db: DatabaseSync, i: number, d: { band?: number; offset?: number; aurora?: number; news?: number; lastSeen?: string } = {}) {
  db.prepare("INSERT INTO devices (token, environment, band, utc_offset_minutes, aurora, news, last_seen) VALUES (?, 'production', ?, ?, ?, ?, ?)")
    .run(token(i), d.band ?? 55, d.offset ?? 0, d.aurora ?? 1, d.news ?? 0, d.lastSeen ?? "2026-10-20T00:00:00.000Z");
}

const count = (db: DatabaseSync, sql: string) => (db.prepare(sql).get() as { n: number }).n;

test("a failed CelesTrak poll is tried once more 33 minutes later, from the 5-minute cron", async () => {
  const { db, env } = await setup({ APNS_KEY: "" });
  let status = 522;
  const hosts = network({ "celestrak.org": () => new Response("[]", { status }) });
  const requests = async (cron: string, iso: string) => {
    const before = hosts.filter((h) => h === "celestrak.org").length;
    await run(env, cron, iso);
    return hosts.filter((h) => h === "celestrak.org").length - before;
  };
  assert.equal(await requests(SATELLITES, "2026-10-21T02:07:00Z"), 1);
  assert.equal(await requests(FIVE, "2026-10-21T02:35:00Z"), 0);
  assert.equal(await requests(FIVE, "2026-10-21T02:40:00Z"), 1);
  assert.equal(await requests(FIVE, "2026-10-21T02:45:00Z"), 0);
  assert.equal(await requests(FIVE, "2026-10-21T03:40:00Z"), 0);
  assert.equal(await requests(FIVE, "2026-10-21T04:40:00Z"), 0);

  assert.equal(await requests(SATELLITES, "2026-10-21T06:07:00Z"), 1);
  status = 200;
  assert.equal(await requests(FIVE, "2026-10-21T06:40:00Z"), 2);
  assert.equal(count(db, "SELECT count(*) AS n FROM feed_snapshots WHERE feed = 'celestrak' AND ok = 1 AND fetched_at = '2026-10-21T06:40:00.000Z'"), 1);
  assert.equal(await requests(SATELLITES, "2026-10-21T08:07:00Z"), 2);
  assert.equal(await requests(FIVE, "2026-10-21T08:40:00Z"), 0);
});

test("aurora alerts go out in bounded slices and are recorded per device once answered", async () => {
  const { db, env, calls } = await setup();
  for (let i = 0; i < 30; i++) device(db, i);
  device(db, 30, { offset: 720 }); // 10:05 local: not night
  const push = apns({ [token(3)]: 503, [token(4)]: 410, [token(5)]: 400 });
  const hosts = network({ ...swpc(6), ...push.handlers });

  await run(env, FIVE, "2026-10-20T22:05:00Z");
  assert.equal(push.state.sent.length, 20);
  assert.ok(push.state.maxInFlight <= 6, `max in flight ${push.state.maxInFlight}`);
  assert.ok(hosts.length + calls.length <= 50, `${hosts.length} fetches + ${calls.length} D1 calls`);
  assert.equal(count(db, "SELECT count(*) AS n FROM alerts_sent WHERE kind = 'aurora'"), 18);
  assert.equal(count(db, `SELECT count(*) AS n FROM devices WHERE token = '${token(4)}'`), 0);

  push.state.sent = [];
  await run(env, FIVE, "2026-10-20T22:10:00Z");
  assert.deepEqual(push.state.sent.sort(), [3, ...Array.from({ length: 10 }, (_, i) => 20 + i)].map(token).sort());

  push.state.sent = [];
  await run(env, FIVE, "2026-10-20T22:15:00Z");
  assert.deepEqual(push.state.sent, [token(3)]);
});

test("an aurora run cut short leaves the remaining devices for the next run", async () => {
  const { db, env } = await setup();
  for (let i = 0; i < 5; i++) device(db, i);
  const push = apns();
  push.state.fail = (n) => n >= 2;
  network({ ...swpc(6), ...push.handlers });

  await run(env, FIVE, "2026-10-20T22:05:00Z");
  assert.equal(count(db, "SELECT count(*) AS n FROM alerts_sent WHERE kind = 'aurora'"), 2);

  push.state.fail = () => false;
  const first = push.state.sent;
  push.state.sent = [];
  await run(env, FIVE, "2026-10-20T22:10:00Z");
  assert.equal(push.state.sent.length, 3);
  assert.ok(push.state.sent.every((t) => !first.includes(t)));
});

test("news digests go out in slices during the local 09:00 hour, once per local day", async () => {
  const { db, env, calls } = await setup();
  for (let i = 0; i < 25; i++) device(db, i, { offset: -300, aurora: 0, news: 1 });
  device(db, 25, { offset: 330, aurora: 0, news: 1 });
  const push = apns();
  const articles = [{ id: 1, title: "t1", news_site: "ESA", published_at: "2026-10-20T13:00:00Z" }];
  const hosts = network({ ...push.handlers, "api.spaceflightnewsapi.net": () => Response.json({ results: articles }) });
  const snapi = () => hosts.filter((h) => h === "api.spaceflightnewsapi.net").length;

  await run(env, NEWS, "2026-10-20T14:00:00Z");
  assert.equal(push.state.sent.length, 20);
  await run(env, NEWS, "2026-10-20T14:10:00Z");
  assert.equal(push.state.sent.length, 25);
  assert.equal(new Set(push.state.sent).size, 25);
  await run(env, NEWS, "2026-10-20T14:20:00Z");
  assert.equal(push.state.sent.length, 25);
  assert.equal(snapi(), 2);
  assert.equal(count(db, "SELECT count(*) AS n FROM alerts_sent WHERE kind = 'news' AND event LIKE '%:2026-10-20'"), 25);

  const q = calls.find((c) => c.sql.includes("news = 1"))!;
  const plan = db.prepare(`EXPLAIN QUERY PLAN ${q.sql}`).all(...q.params).map((r) => String(r.detail)).join("\n");
  assert.match(plan, /SEARCH d USING INDEX devices_news \(news=\? AND utc_offset_minutes>\? AND utc_offset_minutes<\?\)/);
});

test("a daily prune removes alert keys older than 3 days and devices not seen in 180 days", async () => {
  const { db, env } = await setup({ APNS_KEY: "" });
  const sent = db.prepare("INSERT INTO alerts_sent (kind, band, event, sent_at) VALUES (?, 0, ?, ?)");
  for (const kind of ["aurora", "news", "test"]) {
    sent.run(kind, "old", "2026-10-17T23:59:00.000Z");
    sent.run(kind, "new", "2026-10-18T00:01:00.000Z");
  }
  device(db, 1, { lastSeen: "2026-04-23T23:59:00.000Z" });
  device(db, 2, { lastSeen: "2026-04-24T00:01:00.000Z" });
  network({});

  await run(env, NEWS, "2026-10-20T23:50:00Z");
  assert.equal(count(db, "SELECT count(*) AS n FROM alerts_sent"), 6);
  await run(env, NEWS, "2026-10-21T00:00:00Z");
  assert.deepEqual(db.prepare("SELECT DISTINCT event FROM alerts_sent").all().map((r) => r.event), ["new"]);
  assert.deepEqual(db.prepare("SELECT token FROM devices").all().map((r) => r.token), [token(2)]);
});

test("GET /v1/launches reads everything in one D1 batch", async () => {
  const { db, env, calls } = await setup();
  const launch = db.prepare(
    "INSERT INTO launches (id, name, net, status, status_name, provider, rocket, pad, location, last_updated) VALUES (?, ?, ?, 'Go', 'Go for Launch', 'SpaceX', 'Falcon 9', 'SLC-40', 'Cape', '2026-10-01T00:00:00Z')",
  );
  const day = (n: number) => new Date(Date.now() + n * 86400_000).toISOString();
  launch.run("up", "Upcoming", day(1));
  launch.run("past", "Past", day(-2));
  db.exec(`INSERT INTO feed_snapshots (feed, fetched_at, ok, body) VALUES ('ll2', '2026-10-20T11:50:00.000Z', 1, NULL),
    ('launch-elements', '2026-10-20T10:07:00.000Z', 1, '{"up":{"source":"supgp","elements":[{"OBJECT_NAME":"x"}]}}');
    INSERT INTO launch_channels (channel_id, environment, launch_id, net, status, created_at) VALUES ('ch1', 'production', 'up', 'x', 'Go', 'x')`);

  const res = await worker.fetch(new Request("https://moonrise.test/v1/launches"), env as never);
  assert.deepEqual(calls.map((c) => c.sql), ["batch"]);
  const body = await res.json();
  assert.equal(res.headers.get("cache-control"), "public, max-age=300");
  assert.equal(body.fetchedAt, "2026-10-20T11:50:00.000Z");
  assert.deepEqual(body.launches.map((l: { id: string }) => l.id), ["up"]);
  assert.deepEqual(body.recent.map((l: { id: string }) => l.id), ["past"]);
  assert.equal(body.launches[0].channelId, "ch1");
  assert.equal(body.launches[0].elementsSource, "supgp");
  assert.deepEqual(body.launches[0].elements, [{ OBJECT_NAME: "x" }]);
  assert.equal(body.recent[0].elementsSource, null);

  const sandbox = await (await worker.fetch(new Request("https://moonrise.test/v1/launches?environment=sandbox"), env as never)).json();
  assert.equal(sandbox.launches[0].channelId, null);
});

const ID = "3b430f81-0ff1-4d85-8a1a-cef0de326198";
const raw = (net: string, status: string, designator: string | null = null) => ({
  id: ID, name: "Falcon 9 Block 5 | Bandwagon 5", net, window_start: net, window_end: net, last_updated: "2026-10-17T20:00:00Z", launch_designator: designator,
  status: { name: status, abbrev: status }, launch_service_provider: { name: "SpaceX" }, rocket: { configuration: { name: "Falcon 9", full_name: "Falcon 9 Block 5" } },
  mission: { name: "Bandwagon 5", type: "Dedicated Rideshare", description: "Rideshare.", orbit: { abbrev: "LEO" } },
  pad: { name: "Space Launch Complex 40", latitude: "28.56", longitude: "-80.57", location: { name: "Cape Canaveral SFS, FL, USA" } },
});

for (const keyed of [true, false]) {
  test(`the launch in focus is polled every ${keyed ? 2 : 5} minutes ${keyed ? "with" : "without"} an LL2 key`, async () => {
    const { db, env, calls } = await setup(keyed ? { LL2_API_KEY: "k" } : {});
    const net = "2026-10-20T12:30:00Z";
    db.prepare("INSERT INTO launches (id, name, net, status, status_name, provider, rocket, pad, location, last_updated) VALUES (?, 'x', ?, 'Go', 'Go', 'SpaceX', 'Falcon 9', 'SLC-40', 'Cape', 'x')").run(ID, net);
    for (const e of ["sandbox", "production"])
      db.prepare("INSERT INTO launch_channels (channel_id, environment, launch_id, net, status, created_at) VALUES (?, ?, ?, ?, 'Go', 'x')").run(`ch-${e}`, e, ID, net);
    let status = "Go";
    const auth: (string | undefined)[] = [];
    const push = apns();
    const hosts = network({
      ...swpc(0),
      ...push.handlers,
      "ll.thespacedevs.com": (url, init) => {
        auth.push((init.headers as Record<string, string>).authorization);
        return Response.json(url.pathname.endsWith(`/launches/${ID}/`) ? raw(net, status) : { results: [] });
      },
    });

    for (let m = 0; m < 60; m++) {
      const iso = new Date(Date.parse("2026-10-20T11:30:00Z") + m * 60_000).toISOString();
      if (m === 12) status = "Hold";
      const before = calls.length;
      if (m % 2 === 0) await run(env, TWO, iso);
      if (!keyed) assert.equal(calls.length, before, "the 2-minute cron does nothing without a key");
      if (m % 5 === 0) await run(env, FIVE, iso);
      if (m === 12) assert.equal(push.state.broadcasts, keyed ? 2 : 0);
    }
    assert.equal(hosts.filter((h) => h === "ll.thespacedevs.com").length, keyed ? 30 : 12);
    assert.ok(auth.every((a) => a === (keyed ? "Token k" : undefined)));
    assert.equal(push.state.broadcasts, 2);
  });
}

test("a list poll leaves unchanged launches alone; a tick without a poll runs the near query once", async () => {
  const { db, env, calls } = await setup();
  db.exec(`CREATE TEMP TABLE writes (id TEXT);
    CREATE TEMP TRIGGER launch_update AFTER UPDATE ON launches BEGIN INSERT INTO writes VALUES (NEW.id); END`);
  let launch = raw("2026-10-25T12:00:00Z", "Go");
  network({ "ll.thespacedevs.com": () => Response.json({ results: [launch] }) });
  const near = () => calls.filter((c) => /^SELECT id, net, status FROM launches WHERE net >= /.test(c.sql)).length;

  await run(env, FIVE, "2026-10-20T10:10:00Z");
  const polled = near();
  await run(env, FIVE, "2026-10-20T10:15:00Z");
  assert.equal(near() - polled, 1);
  await run(env, FIVE, "2026-10-20T10:20:00Z");
  assert.equal(count(db, "SELECT count(*) AS n FROM writes"), 0);

  launch = raw("2026-10-25T12:00:00Z", "TBC");
  await run(env, FIVE, "2026-10-20T10:30:00Z");
  launch = raw("2026-10-25T12:00:00Z", "TBC", "2026-232");
  await run(env, FIVE, "2026-10-20T10:40:00Z");
  launch = raw("2026-10-25T12:00:00Z", "TBC");
  await run(env, FIVE, "2026-10-20T10:50:00Z");
  assert.equal(count(db, "SELECT count(*) AS n FROM writes"), 2);
  assert.deepEqual({ ...db.prepare("SELECT status, launch_designator FROM launches").get() }, { status: "TBC", launch_designator: "2026-232" });
});
