// Spike: does a deployed Worker reach APNs over HTTP/2? APNs rejects HTTP/1.1,
// so any APNs response with an apns-id answers yes.

import { send } from "./apns";

interface Env {
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY: string;
  SPIKE_SECRET: string;
}

interface PushRequest {
  token: string;
  sandbox?: boolean;
  title?: string;
  body?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/probe") return probe();
    if (request.method !== "POST" || url.pathname !== "/push") return new Response("not found", { status: 404 });
    if (request.headers.get("authorization") !== `Bearer ${env.SPIKE_SECRET}`) return new Response("unauthorized", { status: 401 });

    const req = (await request.json()) as PushRequest;
    if (!/^[0-9a-f]{64,200}$/i.test(req.token ?? "")) return new Response("bad token", { status: 400 });

    const result = await send(
      { keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC },
      req.token,
      { aps: { alert: { title: req.title ?? "Moonrise", body: req.body ?? "Push from a Cloudflare Worker" } } },
      req.sandbox ?? true,
    );
    return Response.json(result, { status: result.status === 200 ? 200 : 502 });
  },
} satisfies ExportedHandler<Env>;

/** Sends with a throwaway key and token. Needs no Apple credentials: an APNs JSON
 *  error (e.g. 403 InvalidProviderToken) still proves the HTTP/2 connection worked. */
async function probe(): Promise<Response> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
  try {
    const result = await send(
      { keyId: "PROBE00000", teamId: "PROBE00000", privateKey: pem, topic: "org.example.probe" },
      "0".repeat(64),
      { aps: { alert: "probe" } },
      true,
    );
    return Response.json({ http2: result.apnsId !== null || result.reason !== null, ...result });
  } catch (e) {
    return Response.json({ http2: false, error: String(e) }, { status: 502 });
  }
}
