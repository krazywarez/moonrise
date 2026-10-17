import assert from "node:assert/strict";
import { test } from "node:test";
import { importKey, providerToken } from "../src/apns.ts";

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

test("provider token is a valid ES256 JWT signed by the .p8 key", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der)).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;

  const jwt = await providerToken("ABC123DEFG", "TEAM123456", await importKey(pem), 1_792_202_400);
  const [h, c, s] = jwt.split(".");

  assert.deepEqual(JSON.parse(new TextDecoder().decode(b64urlDecode(h))), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(new TextDecoder().decode(b64urlDecode(c))), { iss: "TEAM123456", iat: 1_792_202_400 });

  const sig = b64urlDecode(s);
  assert.equal(sig.length, 64);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, sig, new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok);
});
