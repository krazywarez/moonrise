// Spike: does a deployed Worker reach APNs channel management, on port 2195 (sandbox) and 2196 (production)?
// Any APNs response with an apns-request-id answers yes.

import { listChannels } from "../../../server/src/apns";

interface Env {
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "GET" || url.pathname !== "/probe") return new Response("not found", { status: 404 });
    if (!env.APNS_KEY) return new Response("APNS_KEY not set", { status: 500 });

    const sandbox = url.searchParams.get("env") !== "production";
    let body = "";
    const capture = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const res = await fetch(input, init);
      body = await res.clone().text();
      return res;
    }) as typeof fetch;
    try {
      const r = await listChannels({ keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_KEY, topic: env.APNS_TOPIC }, sandbox, capture);
      return Response.json({ sandbox, status: r.status, requestId: r.apnsId, body });
    } catch (e) {
      return Response.json({ sandbox, error: String(e) }, { status: 502 });
    }
  },
} satisfies ExportedHandler<Env>;
