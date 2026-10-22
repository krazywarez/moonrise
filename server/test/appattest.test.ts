import assert from "node:assert/strict";
import { createHash, createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { AttestError, cbor, fromBase64, verifyAssertion, verifyAttestation } from "../src/appattest.ts";

const fx = JSON.parse(readFileSync(new URL("./fixtures/attest.json", import.meta.url), "utf8"));
const now = new Date("2027-01-01T00:00:00Z");
const base = { attestation: fromBase64(fx.attestation), keyId: fx.keyId, challenge: fromBase64(fx.challenge), appId: fx.appId, now, root: fx.root };
const sha = (...b: Buffer[]) => createHash("sha256").update(Buffer.concat(b)).digest();

/** CBOR {"signature": sig, "authenticatorData": authData}, signed with the fixture's leaf key. */
function assertion(clientData: string, counter: number, appId = fx.appId): Uint8Array {
  const c = Buffer.alloc(4);
  c.writeUInt32BE(counter);
  const authData = Buffer.concat([sha(Buffer.from(appId)), Buffer.from([0x40]), c]);
  const signature = sign("sha256", sha(authData, sha(Buffer.from(clientData))), createPrivateKey(fx.leafKey));
  const text = (s: string) => Buffer.concat([Buffer.from([0x60 | s.length]), Buffer.from(s)]);
  const bytes = (b: Buffer) => Buffer.concat([Buffer.from([0x58, b.length]), b]);
  return Buffer.concat([Buffer.from([0xa2]), text("signature"), bytes(signature), text("authenticatorData"), bytes(authData)]);
}

test("CBOR maps, arrays, byte and text strings decode", () => {
  const m = cbor(Uint8Array.from([0xa2, 0x61, 0x61, 0x82, 0x01, 0x20, 0x61, 0x62, 0x42, 0xca, 0xfe])) as Map<string, unknown>;
  assert.deepEqual(m.get("a"), [1, -1]);
  assert.deepEqual(m.get("b"), Uint8Array.from([0xca, 0xfe]));
});

test("an attestation under its root verifies as a development key", async () => {
  const k = await verifyAttestation(base);
  assert.equal(k.environment, "sandbox");
  assert.ok(k.spki.length > 60);
});

test("attestations fail on another challenge, app, key, root or date", async () => {
  const rejects = (over: Partial<typeof base>, message: string) =>
    assert.rejects(verifyAttestation({ ...base, ...over }), (e) => e instanceof AttestError && e.message === message);
  await rejects({ challenge: new Uint8Array(32) }, "nonce");
  await rejects({ appId: "ZCNAX3VL9D.sh.krz.other" }, "app id");
  await rejects({ keyId: btoa("x".repeat(32)) }, "key id");
  await rejects({ root: undefined }, "intermediate signature");
  await rejects({ now: new Date("2200-01-01T00:00:00Z") }, "certificate dates");
});

test("assertions verify over the request body and need a rising counter", async () => {
  const { spki } = await verifyAttestation(base);
  const body = '{"token":"ab","challenge":"x"}';
  assert.equal(await verifyAssertion({ assertion: assertion(body, 3), clientData: new TextEncoder().encode(body), spki, appId: fx.appId, lastCounter: 2 }), 3);
  await assert.rejects(verifyAssertion({ assertion: assertion(body, 2), clientData: new TextEncoder().encode(body), spki, appId: fx.appId, lastCounter: 2 }), /counter/);
  await assert.rejects(verifyAssertion({ assertion: assertion(body, 3), clientData: new TextEncoder().encode(body + " "), spki, appId: fx.appId, lastCounter: 0 }), /signature/);
  await assert.rejects(verifyAssertion({ assertion: assertion(body, 3, "X.y"), clientData: new TextEncoder().encode(body), spki, appId: fx.appId, lastCounter: 0 }), /app id/);
});
