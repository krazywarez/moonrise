// Creates, lists and deletes APNs broadcast channels from a computer, over Node's HTTP/2 client.
// create and delete print SQL for the launch_channels pool, to pipe into `wrangler d1 execute`.
//
//   APNS_KEY_PATH=AuthKey_644XS4F2RG.p8 node scripts/channels.ts list sandbox
//   APNS_KEY_PATH=... node scripts/channels.ts create production 5 > pool.sql
//   APNS_KEY_PATH=... node scripts/channels.ts delete sandbox <channel id>... > deleted.sql

import { readFileSync } from "node:fs";
import { connect } from "node:http2";
import { createChannel, deleteChannel, listChannels, type ApnsConfig } from "../src/apns.ts";

/** Enough of fetch() for the channel calls in apns.ts, over HTTP/2. */
const h2fetch = ((input: string, init: RequestInit = {}) =>
  new Promise<Response>((resolve, reject) => {
    const url = new URL(input);
    const session = connect(url.origin);
    session.on("error", reject);
    const req = session.request({ ":method": init.method ?? "GET", ":path": url.pathname, ...(init.headers as Record<string, string>) });
    let status = 0;
    const headers = new Headers();
    let body = "";
    req.on("response", (h) => {
      status = Number(h[":status"]);
      for (const [k, v] of Object.entries(h)) if (!k.startsWith(":") && v !== undefined) headers.set(k, String(v));
    });
    req.setEncoding("utf8");
    req.on("data", (chunk: string) => (body += chunk));
    req.on("end", () => {
      session.close();
      resolve(new Response(body || null, { status, headers }));
    });
    req.on("error", reject);
    req.end(init.body as string | undefined);
  })) as typeof fetch;

const [command, environment, ...rest] = process.argv.slice(2);
if (!["create", "list", "delete"].includes(command) || !["sandbox", "production"].includes(environment) || !process.env.APNS_KEY_PATH) {
  console.error("usage: APNS_KEY_PATH=<.p8> node scripts/channels.ts create|list|delete sandbox|production [count | channel id...]");
  process.exit(2);
}
const config: ApnsConfig = {
  keyId: process.env.APNS_KEY_ID ?? "644XS4F2RG",
  teamId: process.env.APNS_TEAM_ID ?? "ZCNAX3VL9D",
  privateKey: readFileSync(process.env.APNS_KEY_PATH, "utf8"),
  topic: process.env.APNS_TOPIC ?? "sh.krz.moonrise",
};
const sandbox = environment === "sandbox";
const base64 = /^[A-Za-z0-9+/=]+$/;

if (command === "list") {
  const r = await listChannels(config, sandbox, h2fetch);
  if (r.status !== 200) fail(r.status, r.reason);
  for (const id of r.channels) console.log(id);
} else if (command === "create") {
  const created = new Date().toISOString();
  for (let i = 0; i < Number(rest[0] ?? 1); i++) {
    const r = await createChannel(config, sandbox, h2fetch);
    if (!r.channelId || !base64.test(r.channelId)) fail(r.status, r.reason);
    console.log(`INSERT INTO launch_channels (channel_id, environment, created_at) VALUES ('${r.channelId}', '${environment}', '${created}');`);
  }
} else {
  for (const id of rest) {
    if (!base64.test(id)) fail(0, `not a channel id: ${id}`);
    const r = await deleteChannel(config, id, sandbox, h2fetch);
    if (r.status !== 204 && r.status !== 404) fail(r.status, r.reason);
    console.log(`DELETE FROM launch_channels WHERE channel_id = '${id}';`);
  }
}

function fail(status: number, reason: string | null): never {
  console.error("apns", status, reason);
  process.exit(1);
}
