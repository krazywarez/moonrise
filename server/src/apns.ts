// APNs provider-token auth and sending, using only Web APIs (Workers, Node).

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  /** Contents of the .p8 key file (PKCS#8 PEM). */
  privateKey: string;
  /** App bundle ID. */
  topic: string;
}

export interface ApnsResult {
  status: number;
  apnsId: string | null;
  reason: string | null;
}

const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export async function importKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** ES256 provider token. WebCrypto returns the raw r||s signature JWS expects. */
export async function providerToken(keyId: string, teamId: string, key: CryptoKey, issuedAt = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: teamId, iat: issuedAt })));
  const input = `${header}.${claims}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
  return `${input}.${base64url(new Uint8Array(sig))}`;
}

/**
 * Apple accepts a token for up to 60 minutes and rejects refreshes more often than every 20. The promise is
 * cached, so concurrent sends share one token.
 */
let cached: { token: Promise<string>; issuedAt: number; keyId: string } | null = null;

function token(config: ApnsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.keyId === config.keyId && now - cached.issuedAt < 50 * 60) return cached.token;
  const t = importKey(config.privateKey).then((key) => providerToken(config.keyId, config.teamId, key, now));
  cached = { token: t, issuedAt: now, keyId: config.keyId };
  t.catch(() => {
    if (cached?.token === t) cached = null;
  });
  return t;
}

/** An alert to a device token, or with `liveactivity` a Live Activity push (push-to-start) to an ActivityKit token. */
export async function send(config: ApnsConfig, deviceToken: string, payload: unknown, sandbox: boolean, type: "alert" | "liveactivity" = "alert"): Promise<ApnsResult> {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await token(config)}`,
      "apns-topic": type === "alert" ? config.topic : `${config.topic}.push-type.liveactivity`,
      "apns-push-type": type,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return result(res, "apns-id");
}

/** `send` to each device, at most `concurrency` at a time. Results are in input order; a network error is status 0. */
export async function sendAll(config: ApnsConfig, sends: { token: string; payload: unknown; sandbox: boolean; type?: "alert" | "liveactivity" }[], concurrency: number): Promise<ApnsResult[]> {
  const out: ApnsResult[] = new Array(sends.length);
  let next = 0;
  const worker = async () => {
    while (next < sends.length) {
      const i = next++;
      out[i] = await send(config, sends[i].token, sends[i].payload, sends[i].sandbox, sends[i].type).catch((e) => ({ status: 0, apnsId: null, reason: String(e) }));
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, sends.length) }, worker));
  return out;
}

/** Failures that may pass: network errors, 429 and 5xx. Other statuses are final for that device. */
export const retryable = (status: number) => status === 0 || status === 429 || status >= 500;

async function result(res: Response, idHeader: string): Promise<ApnsResult> {
  let reason: string | null = null;
  if (!res.ok) {
    const text = await res.text();
    try {
      reason = (JSON.parse(text) as { reason?: string }).reason ?? text;
    } catch {
      reason = text;
    }
  }
  return { status: res.status, apnsId: res.headers.get(idHeader), reason };
}

/** How a broadcast is delivered. `expiration` is in Unix seconds. */
export interface BroadcastOptions {
  sandbox: boolean;
  priority: 5 | 10;
  expiration: number;
}

/** A Live Activity update to every device listening on a broadcast channel. */
export async function broadcast(config: ApnsConfig, channelId: string, payload: unknown, { sandbox, priority, expiration }: BroadcastOptions): Promise<ApnsResult> {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/4/broadcasts/apps/${config.topic}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await token(config)}`,
      "apns-channel-id": channelId,
      "apns-push-type": "liveactivity",
      "apns-priority": String(priority),
      "apns-expiration": String(expiration),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return result(res, "apns-request-id");
}

// Channel management runs on its own host and ports. `fetcher` lets a Node script supply HTTP/2.

const manageBase = (sandbox: boolean) =>
  sandbox ? "https://api-manage-broadcast.sandbox.push.apple.com:2195" : "https://api-manage-broadcast.push.apple.com:2196";

/** A channel that keeps its most recent message (up to 8 hours) for devices that were offline. */
export async function createChannel(config: ApnsConfig, sandbox: boolean, fetcher: typeof fetch = fetch): Promise<ApnsResult & { channelId: string | null }> {
  const res = await fetcher(`${manageBase(sandbox)}/1/apps/${config.topic}/channels`, {
    method: "POST",
    headers: { authorization: `bearer ${await token(config)}`, "content-type": "application/json" },
    body: JSON.stringify({ "message-storage-policy": 1, "push-type": "LiveActivity" }),
  });
  return { ...(await result(res, "apns-request-id")), channelId: res.ok ? res.headers.get("apns-channel-id") : null };
}

export async function deleteChannel(config: ApnsConfig, channelId: string, sandbox: boolean, fetcher: typeof fetch = fetch): Promise<ApnsResult> {
  const res = await fetcher(`${manageBase(sandbox)}/1/apps/${config.topic}/channels`, {
    method: "DELETE",
    headers: { authorization: `bearer ${await token(config)}`, "apns-channel-id": channelId },
  });
  return result(res, "apns-request-id");
}

export async function listChannels(config: ApnsConfig, sandbox: boolean, fetcher: typeof fetch = fetch): Promise<ApnsResult & { channels: string[] }> {
  const res = await fetcher(`${manageBase(sandbox)}/1/apps/${config.topic}/all-channels`, {
    method: "GET",
    headers: { authorization: `bearer ${await token(config)}` },
  });
  if (!res.ok) return { ...(await result(res, "apns-request-id")), channels: [] };
  const body = (await res.json()) as { channels?: string[] };
  return { status: res.status, apnsId: res.headers.get("apns-request-id"), reason: null, channels: body.channels ?? [] };
}
