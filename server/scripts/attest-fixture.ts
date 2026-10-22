// Writes test/fixtures/attest.json: an App Attest attestation built like Apple's (P-384 root and intermediate, P-256
// leaf with the nonce extension) under a throwaway root, for test/appattest.test.ts. Needs openssl.
//   node scripts/attest-fixture.ts
import { execFileSync } from "node:child_process";
import { createHash, createPublicKey, randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const APP_ID = "ZCNAX3VL9D.sh.krz.moonrise";
const dir = mkdtempSync(join(tmpdir(), "attest-"));
const f = (n: string) => join(dir, n);
const ssl = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "inherit"] });
const sha = (...b: Buffer[]) => createHash("sha256").update(Buffer.concat(b)).digest();

ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key");
ssl("req", "-x509", "-new", "-key", "root.key", "-subj", "/CN=Test Root", "-days", "36500", "-sha384", "-addext", "basicConstraints=critical,CA:true", "-out", "root.pem");
ssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "ca.key");
ssl("req", "-new", "-key", "ca.key", "-subj", "/CN=Test CA", "-out", "ca.csr");
writeFileSync(f("ca.ext"), "basicConstraints=critical,CA:true\n");
ssl("x509", "-req", "-in", "ca.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-days", "36500", "-sha384", "-extfile", "ca.ext", "-out", "ca.pem");

ssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
ssl("pkcs8", "-topk8", "-nocrypt", "-in", "leaf.key", "-out", "leaf.p8");
const jwk = createPublicKey(readFileSync(f("leaf.key"))).export({ format: "jwk" });
const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]);
const keyId = sha(point);

const counter = Buffer.alloc(4);
const len = Buffer.alloc(2);
len.writeUInt16BE(32);
const authData = Buffer.concat([sha(Buffer.from(APP_ID)), Buffer.from([0x40]), counter, Buffer.from("appattestdevelop"), len, keyId]);
const challenge = randomBytes(32);
const nonce = sha(authData, sha(challenge));

ssl("req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr");
writeFileSync(f("leaf.ext"), `1.2.840.113635.100.8.2=DER:3024a1220420${nonce.toString("hex")}\n`);
ssl("x509", "-req", "-in", "leaf.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-days", "36500", "-sha256", "-extfile", "leaf.ext", "-out", "leaf.pem");
const der = (n: string) => ssl("x509", "-in", n, "-outform", "DER");

// CBOR: {"fmt": "apple-appattest", "attStmt": {"x5c": [leaf, ca], "receipt": h''}, "authData": authData}
const head = (major: number, n: number) => n < 24 ? Buffer.from([major << 5 | n]) : n < 256 ? Buffer.from([major << 5 | 24, n]) : Buffer.from([major << 5 | 25, n >> 8, n & 255]);
const bytes = (b: Buffer) => Buffer.concat([head(2, b.length), b]);
const text = (s: string) => Buffer.concat([head(3, Buffer.byteLength(s)), Buffer.from(s)]);
const attestation = Buffer.concat([
  head(5, 3),
  text("fmt"), text("apple-appattest"),
  text("attStmt"), head(5, 2), text("x5c"), head(4, 2), bytes(der("leaf.pem")), bytes(der("ca.pem")), text("receipt"), bytes(Buffer.alloc(0)),
  text("authData"), bytes(authData),
]);

writeFileSync(new URL("../test/fixtures/attest.json", import.meta.url), JSON.stringify({
  appId: APP_ID,
  root: readFileSync(f("root.pem"), "utf8"),
  attestation: attestation.toString("base64"),
  keyId: keyId.toString("base64"),
  challenge: challenge.toString("base64"),
  leafKey: readFileSync(f("leaf.p8"), "utf8"),
}, null, 2) + "\n");
