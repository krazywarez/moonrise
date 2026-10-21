import assert from "node:assert/strict";
import { test } from "node:test";
import { digestPayload, dueOffsets, localDate, pickHeadlines, type Article } from "../src/news.ts";

test("digest is due for the UTC offsets whose local time is in the 09:00 hour", () => {
  for (let minute = 0; minute < 1440; minute += 5) {
    const now = new Date(Date.UTC(2026, 9, 18, 0, minute));
    const ranges = dueOffsets(now);
    for (let offset = -840; offset <= 840; offset++) {
      const local = (((minute + offset) % 1440) + 1440) % 1440;
      const due = ranges.some(([lo, hi]) => offset >= lo && offset < hi);
      assert.equal(due, local >= 540 && local < 600, `${now.toISOString()} ${offset}`);
    }
  }
  assert.deepEqual(dueOffsets(new Date("2026-10-18T14:00:00Z")), [[-300, -240], [1140, 841]]); // 09:00 CDT
  assert.deepEqual(dueOffsets(new Date("2026-10-17T23:30:00Z")), [[-840, -810], [570, 630]]); // 09:00 ACST, next day
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
