// App Attest (developer.apple.com, "Validating apps that connect to your server"): attestation of a new key, then an
// assertion with each device registration. WebCrypto only; minimal CBOR and DER readers for the shapes Apple sends.

/** Apple App Attestation Root CA, from https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem. */
export const APPLE_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const NONCE_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = "appattest\0\0\0\0\0\0\0";
const AAGUID_DEVELOPMENT = "appattestdevelop";

export class AttestError extends Error {}

const fail = (m: string): never => {
  throw new AttestError(m);
};

const encoder = new TextEncoder();
const sha256 = async (...parts: Uint8Array[]) => new Uint8Array(await crypto.subtle.digest("SHA-256", concat(...parts)));

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let i = 0;
  for (const p of parts) {
    out.set(p, i);
    i += p.length;
  }
  return out;
}

const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((x, i) => x === b[i]);
export const fromBase64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
export const toBase64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));

// MARK: CBOR (major types 0–5 with definite lengths, which is all App Attest uses)

export function cbor(bytes: Uint8Array): unknown {
  return new CborReader(bytes).item();
}

class CborReader {
  private i = 0;
  private readonly bytes: Uint8Array;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  item(): unknown {
    const head = this.take(1)[0], major = head >> 5, n = this.length(head & 31);
    switch (major) {
      case 0: return n;
      case 1: return -1 - n;
      case 2: return this.take(n);
      case 3: return new TextDecoder().decode(this.take(n));
      case 4: return Array.from({ length: n }, () => this.item());
      case 5: return this.map(n);
      default: return fail("cbor type");
    }
  }

  private length(info: number): number {
    if (info < 24) return info;
    const n = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : fail("cbor length");
    return this.take(n).reduce((v, byte) => v * 256 + byte, 0);
  }

  private map(n: number): Map<unknown, unknown> {
    const m = new Map<unknown, unknown>();
    for (let k = 0; k < n; k++) m.set(this.item(), this.item());
    return m;
  }

  /** The next `n` bytes; failing rather than reading past the end. */
  private take(n: number): Uint8Array {
    if (this.i + n > this.bytes.length) fail("cbor truncated");
    const v = this.bytes.slice(this.i, this.i + n);
    this.i += n;
    return v;
  }
}

// MARK: DER

interface Der { tag: number; start: number; header: number; length: number; bytes: Uint8Array }

function der(bytes: Uint8Array, at = 0): Der {
  const tag = bytes[at];
  let length = bytes[at + 1], header = 2;
  if (length & 0x80) {
    const n = length & 0x7f;
    length = 0;
    for (let k = 0; k < n; k++) length = length * 256 + bytes[at + 2 + k];
    header += n;
  }
  if (at + header + length > bytes.length) fail("der truncated");
  return { tag, start: at, header, length, bytes };
}

const content = (d: Der) => d.bytes.slice(d.start + d.header, d.start + d.header + d.length);
const whole = (d: Der) => d.bytes.slice(d.start, d.start + d.header + d.length);

function children(d: Der): Der[] {
  const out: Der[] = [];
  let at = d.start + d.header;
  while (at < d.start + d.header + d.length) {
    const c = der(d.bytes, at);
    out.push(c);
    at = c.start + c.header + c.length;
  }
  return out;
}

function oid(b: Uint8Array): string {
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let v = 0;
  for (const x of b.slice(1)) {
    v = v * 128 + (x & 0x7f);
    if (!(x & 0x80)) { parts.push(v); v = 0; }
  }
  return parts.join(".");
}

function time(d: Der): number {
  const s = new TextDecoder().decode(content(d));
  const full = d.tag === 0x17 ? (Number(s.slice(0, 2)) < 50 ? "20" : "19") + s : s; // UTCTime or GeneralizedTime
  return Date.UTC(+full.slice(0, 4), +full.slice(4, 6) - 1, +full.slice(6, 8), +full.slice(8, 10), +full.slice(10, 12), +full.slice(12, 14));
}

interface Certificate {
  tbs: Uint8Array;
  signatureHash: "SHA-256" | "SHA-384";
  signature: Uint8Array;
  spki: Uint8Array;
  curve: "P-256" | "P-384";
  /** EC point, uncompressed. */
  point: Uint8Array;
  notBefore: number;
  notAfter: number;
  extensions: Map<string, Uint8Array>;
}

const CURVES: Record<string, "P-256" | "P-384"> = { "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384" };
const HASHES: Record<string, "SHA-256" | "SHA-384"> = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" };

export function certificate(bytes: Uint8Array): Certificate {
  const [tbs, alg, sig] = children(der(bytes));
  const fields = children(tbs);
  const f = fields[0].tag === 0xa0 ? fields.slice(1) : fields; // skip [0] version
  const [, , , validity, , spki] = f;
  const [notBefore, notAfter] = children(validity).map(time);
  const [spkiAlg, key] = children(spki);
  const curve = CURVES[oid(content(children(spkiAlg)[1]))] ?? fail("curve");
  const extensions = new Map<string, Uint8Array>();
  const ext = f.find((x) => x.tag === 0xa3);
  if (ext) {
    for (const e of children(children(ext)[0])) {
      const parts = children(e);
      extensions.set(oid(content(parts[0])), content(parts[parts.length - 1]));
    }
  }
  return {
    tbs: whole(tbs),
    signatureHash: HASHES[oid(content(children(alg)[0]))] ?? fail("signature algorithm"),
    signature: content(sig).slice(1), // drop the BIT STRING's unused-bits byte
    spki: whole(spki),
    curve,
    point: content(key).slice(1),
    notBefore,
    notAfter,
    extensions,
  };
}

const pem = (s: string) => fromBase64(s.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""));

/** DER ECDSA-Sig-Value to the r||s WebCrypto expects. */
export function rawSignature(sig: Uint8Array, size: number): Uint8Array {
  const [r, s] = children(der(sig)).map(content);
  const fit = (x: Uint8Array) => {
    const t = x.slice(Math.max(0, x.length - size));
    return concat(new Uint8Array(size - t.length), t);
  };
  return concat(fit(r), fit(s));
}

async function verifies(issuer: { spki: Uint8Array; curve: "P-256" | "P-384" }, hash: "SHA-256" | "SHA-384", signature: Uint8Array, data: Uint8Array): Promise<boolean> {
  const key = await crypto.subtle.importKey("spki", issuer.spki, { name: "ECDSA", namedCurve: issuer.curve }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSignature(signature, issuer.curve === "P-256" ? 32 : 48), data);
}

// MARK: attestation and assertion

interface AuthData { rpIdHash: Uint8Array; counter: number; aaguid: string; credentialId: Uint8Array }

function authData(b: Uint8Array, attested: boolean): AuthData {
  if (b.length < 37) fail("authData");
  const counter = new DataView(b.buffer, b.byteOffset + 33, 4).getUint32(0);
  if (!attested) return { rpIdHash: b.slice(0, 32), counter, aaguid: "", credentialId: new Uint8Array() };
  if (b.length < 55) fail("authData");
  const n = new DataView(b.buffer, b.byteOffset + 53, 2).getUint16(0);
  return { rpIdHash: b.slice(0, 32), counter, aaguid: new TextDecoder().decode(b.slice(37, 53)), credentialId: b.slice(55, 55 + n) };
}

export interface AttestedKey {
  /** SubjectPublicKeyInfo of the key, for assertions. */
  spki: Uint8Array;
  environment: "sandbox" | "production";
}

/**
 * Checks an attestation object for `keyId` (base64), made with clientDataHash = SHA-256(`challenge`). `appId` is
 * "TEAMID.bundle.id". `root` is Apple's root in production; tests pass their own.
 */
export async function verifyAttestation(a: { attestation: Uint8Array; keyId: string; challenge: Uint8Array; appId: string; now: Date; root?: string }): Promise<AttestedKey> {
  const obj = cbor(a.attestation) as Map<string, unknown>;
  if (!(obj instanceof Map) || obj.get("fmt") !== "apple-appattest") fail("format");
  const stmt = obj.get("attStmt") as Map<string, unknown>;
  const x5c = stmt?.get("x5c") as Uint8Array[];
  const raw = obj.get("authData") as Uint8Array;
  if (!Array.isArray(x5c) || x5c.length < 2 || !(raw instanceof Uint8Array)) fail("structure");

  const [leaf, intermediate] = x5c.map(certificate);
  const root = certificate(pem(a.root ?? APPLE_ROOT));
  const t = a.now.getTime();
  for (const c of [leaf, intermediate]) if (t < c.notBefore || t > c.notAfter) fail("certificate dates");
  if (!(await verifies(root, intermediate.signatureHash, intermediate.signature, intermediate.tbs))) fail("intermediate signature");
  if (!(await verifies(intermediate, leaf.signatureHash, leaf.signature, leaf.tbs))) fail("leaf signature");

  const nonce = await sha256(raw, await sha256(a.challenge));
  const ext = leaf.extensions.get(NONCE_OID) ?? fail("nonce extension");
  // SEQUENCE { [1] { OCTET STRING nonce } }
  const inner = content(children(children(der(ext))[0])[0]);
  if (!equal(inner, nonce)) fail("nonce");

  const keyId = fromBase64(a.keyId);
  if (!equal(await sha256(leaf.point), keyId)) fail("key id");
  const auth = authData(raw, true);
  if (!equal(auth.rpIdHash, await sha256(encoder.encode(a.appId)))) fail("app id");
  if (auth.counter !== 0) fail("counter");
  if (auth.aaguid !== AAGUID_PRODUCTION && auth.aaguid !== AAGUID_DEVELOPMENT) fail("aaguid");
  if (!equal(auth.credentialId, keyId)) fail("credential id");
  return { spki: leaf.spki, environment: auth.aaguid === AAGUID_DEVELOPMENT ? "sandbox" : "production" };
}

/** Checks an assertion over `clientData` with an attested key; returns its counter, which must exceed `lastCounter`. */
export async function verifyAssertion(a: { assertion: Uint8Array; clientData: Uint8Array; spki: Uint8Array; appId: string; lastCounter: number }): Promise<number> {
  const obj = cbor(a.assertion) as Map<string, unknown>;
  const signature = obj instanceof Map ? obj.get("signature") : undefined;
  const raw = obj instanceof Map ? obj.get("authenticatorData") : undefined;
  if (!(signature instanceof Uint8Array) || !(raw instanceof Uint8Array)) fail("structure");
  const nonce = await sha256(raw as Uint8Array, await sha256(a.clientData));
  if (!(await verifies({ spki: a.spki, curve: "P-256" }, "SHA-256", signature as Uint8Array, nonce))) fail("signature");
  const auth = authData(raw as Uint8Array, false);
  if (!equal(auth.rpIdHash, await sha256(encoder.encode(a.appId)))) fail("app id");
  if (auth.counter <= a.lastCounter) fail("counter");
  return auth.counter;
}
