import assert from "node:assert/strict";
import { test } from "node:test";
import { digestDue, digestPayload, localDate, pickHeadlines, type Article } from "../src/news.ts";

test("digest is due in the first 10 minutes of 09:00 local", () => {
  const at = (iso: string) => new Date(iso);
  assert.equal(digestDue(at("2026-10-18T14:00:00Z"), -300), true); // 09:00 CDT
  assert.equal(digestDue(at("2026-10-18T14:09:59Z"), -300), true);
  assert.equal(digestDue(at("2026-10-18T14:10:00Z"), -300), false);
  assert.equal(digestDue(at("2026-10-17T23:30:00Z"), 570), true); // 09:00 ACST, next day
});

test("local date follows the offset", () => {
  assert.equal(localDate(new Date("2026-10-17T23:30:00Z"), 570), "2026-10-18");
  assert.equal(localDate(new Date("2026-10-18T02:00:00Z"), -300), "2026-10-17");
});

test("picks three recent headlines from different sites, skipping APOD", () => {
  const now = new Date("2026-10-18T16:00:00Z");
  const a = (id: number, site: string, hoursAgo: number, title = `t${id}`): Article =>
    ({ id, title, news_site: site, published_at: new Date(now.getTime() - hoursAgo * 3600_000).toISOString() });
  const picked = pickHeadlines([
    a(1, "NASA", 1, "APOD: 2026 October 18"),
    a(2, "SpaceNews", 2),
    a(3, "SpaceNews", 1.5),
    a(4, "ESA", 5),
    a(5, "NASA", 30),
    a(6, "Spaceflight Now", 20),
    a(7, "NASASpaceflight", 23),
  ], now);
  assert.deepEqual(picked.map((p) => p.id), [3, 4, 6]);
  assert.match(digestPayload(picked).aps.alert.body, /^t3 \(SpaceNews\)\nt4 \(ESA\)\nt6 \(Spaceflight Now\)$/);
});
