import assert from "node:assert/strict";
import { test } from "node:test";
import { broadcast, createChannel, deleteChannel, listChannels, retryable, send, sendAll, type ApnsConfig } from "../src/apns.ts";

async function config(): Promise<ApnsConfig> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  return { keyId: "ABC123DEFG", teamId: "TEAM123456", privateKey: pem, topic: "sh.krz.moonrise" };
}

interface Seen {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string | undefined;
}

function recorder(response: () => Response): { seen: Seen[]; fetcher: typeof fetch } {
  const seen: Seen[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    seen.push({ url, method: init.method ?? "GET", headers: init.headers as Record<string, string>, body: init.body as string | undefined });
    return response();
  }) as typeof fetch;
  return { seen, fetcher };
}

test("alert pushes keep their headers", async () => {
  const { seen, fetcher } = recorder(() => new Response(null, { status: 200, headers: { "apns-id": "x" } }));
  const real = globalThis.fetch;
  globalThis.fetch = fetcher;
  try {
    const r = await send(await config(), "ab".repeat(32), { aps: { alert: "hi" } }, true);
    assert.equal(r.apnsId, "x");
  } finally {
    globalThis.fetch = real;
  }
  assert.equal(seen[0].url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  assert.equal(seen[0].headers["apns-push-type"], "alert");
  assert.equal(seen[0].headers["apns-topic"], "sh.krz.moonrise");
});

test("broadcast goes to the standard host with the channel, Live Activity type, priority and expiration", async () => {
  const { seen, fetcher } = recorder(() => new Response(null, { status: 200, headers: { "apns-request-id": "r" } }));
  const real = globalThis.fetch;
  globalThis.fetch = fetcher;
  try {
    const r = await broadcast(await config(), "dHN0LXNyY2gtY2hubA==", { aps: { event: "update" } }, { sandbox: false, priority: 5, expiration: 1_792_230_000 });
    assert.deepEqual(r, { status: 200, apnsId: "r", reason: null });
  } finally {
    globalThis.fetch = real;
  }
  const s = seen[0];
  assert.equal(s.url, "https://api.push.apple.com/4/broadcasts/apps/sh.krz.moonrise");
  assert.equal(s.method, "POST");
  assert.equal(s.headers["apns-channel-id"], "dHN0LXNyY2gtY2hubA==");
  assert.equal(s.headers["apns-push-type"], "liveactivity");
  assert.equal(s.headers["apns-priority"], "5");
  assert.equal(s.headers["apns-expiration"], "1792230000");
  assert.match(s.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(JSON.parse(s.body!), { aps: { event: "update" } });
});

test("channels are created with most-recent-message storage on the management host", async () => {
  const { seen, fetcher } = recorder(() => new Response(null, { status: 201, headers: { "apns-channel-id": "Y2hhbm5lbA==", "apns-request-id": "r" } }));
  const r = await createChannel(await config(), true, fetcher);
  assert.equal(r.channelId, "Y2hhbm5lbA==");
  assert.equal(r.status, 201);
  assert.equal(seen[0].url, "https://api-manage-broadcast.sandbox.push.apple.com:2195/1/apps/sh.krz.moonrise/channels");
  assert.equal(seen[0].method, "POST");
  assert.deepEqual(JSON.parse(seen[0].body!), { "message-storage-policy": 1, "push-type": "LiveActivity" });
});

test("channels are listed and deleted on the production management port", async () => {
  const list = recorder(() => Response.json({ channels: ["YQ==", "Yg=="] }, { headers: { "apns-request-id": "r" } }));
  const r = await listChannels(await config(), false, list.fetcher);
  assert.deepEqual(r.channels, ["YQ==", "Yg=="]);
  assert.equal(list.seen[0].url, "https://api-manage-broadcast.push.apple.com:2196/1/apps/sh.krz.moonrise/all-channels");

  const del = recorder(() => new Response(null, { status: 204 }));
  const d = await deleteChannel(await config(), "YQ==", false, del.fetcher);
  assert.equal(d.status, 204);
  assert.equal(del.seen[0].method, "DELETE");
  assert.equal(del.seen[0].headers["apns-channel-id"], "YQ==");
  assert.equal(del.seen[0].url, "https://api-manage-broadcast.push.apple.com:2196/1/apps/sh.krz.moonrise/channels");
});

test("errors report APNs' reason", async () => {
  const { fetcher } = recorder(() => Response.json({ reason: "InvalidProviderToken" }, { status: 403 }));
  const r = await listChannels(await config(), true, fetcher);
  assert.equal(r.status, 403);
  assert.equal(r.reason, "InvalidProviderToken");
  assert.deepEqual(r.channels, []);
});

test("concurrent sends share one provider token", async () => {
  const { seen, fetcher } = recorder(() => new Response(null, { status: 200 }));
  const real = globalThis.fetch;
  globalThis.fetch = fetcher;
  try {
    const c = { ...(await config()), keyId: "SHARED0001" };
    await Promise.all(Array.from({ length: 6 }, (_, i) => send(c, i.toString(16).padStart(64, "0"), {}, false)));
  } finally {
    globalThis.fetch = real;
  }
  assert.equal(new Set(seen.map((s) => s.headers.authorization)).size, 1);
});

test("sendAll keeps order, bounds concurrency and turns network errors into status 0", async () => {
  let inFlight = 0;
  let max = 0;
  const real = globalThis.fetch;
  globalThis.fetch = (async (url: string) => {
    inFlight++;
    max = Math.max(max, inFlight);
    await new Promise((r) => setTimeout(r, 2));
    inFlight--;
    if (url.endsWith("1".padStart(64, "0"))) throw new Error("network");
    return new Response(null, { status: url.includes("sandbox") ? 410 : 200 });
  }) as typeof fetch;
  let results;
  try {
    const c = await config();
    results = await sendAll(c, Array.from({ length: 10 }, (_, i) => ({ token: i.toString(16).padStart(64, "0"), payload: {}, sandbox: i === 2 })), 3);
  } finally {
    globalThis.fetch = real;
  }
  assert.equal(max, 3);
  assert.deepEqual(results.map((r) => r.status), [200, 0, 410, 200, 200, 200, 200, 200, 200, 200]);
});

test("only network errors, 429 and 5xx are worth retrying", () => {
  assert.deepEqual([0, 200, 400, 403, 410, 429, 500, 503].map(retryable), [true, false, false, false, false, true, true, true]);
});
