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

/** Apple accepts a token for up to 60 minutes and rejects refreshes more often than every 20. */
let cached: { token: string; issuedAt: number; keyId: string } | null = null;

async function token(config: ApnsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.keyId === config.keyId && now - cached.issuedAt < 50 * 60) return cached.token;
  const t = await providerToken(config.keyId, config.teamId, await importKey(config.privateKey), now);
  cached = { token: t, issuedAt: now, keyId: config.keyId };
  return t;
}

export async function send(config: ApnsConfig, deviceToken: string, payload: unknown, sandbox: boolean): Promise<ApnsResult> {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await token(config)}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  let reason: string | null = null;
  if (!res.ok) {
    const text = await res.text();
    try {
      reason = (JSON.parse(text) as { reason?: string }).reason ?? text;
    } catch {
      reason = text;
    }
  }
  return { status: res.status, apnsId: res.headers.get("apns-id"), reason };
}
