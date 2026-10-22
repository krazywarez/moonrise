import assert from "node:assert/strict";
import { test } from "node:test";
import { reduce, stormLikely } from "../src/solarwind.ts";

const now = new Date("2026-10-22T06:00:00Z");
const minutes = (n: number, f: (i: number) => object) =>
  Array.from({ length: n }, (_, i) => ({ time_tag: new Date(now.getTime() - (n - i) * 60_000).toISOString().slice(0, 19), active: true, source: "SOLAR1", ...f(i) }));

test("reduces 1-minute rows to 5-minute means from the active spacecraft", () => {
  const mag = [...minutes(60, () => ({ bz_gsm: -4, bt: 6 })), { time_tag: "2026-10-22T05:58:00", active: false, source: "ACE", bz_gsm: 50, bt: 50 }];
  const wind = minutes(60, (i) => ({ proton_speed: 400 + i, proton_density: 5 }));
  const w = reduce(mag, wind, now)!;
  assert.equal(w.source, "SOLAR1");
  assert.equal(w.series.length, 12);
  assert.ok(w.series.every((p) => p.bz === -4 && p.bt === 6 && p.density === 5));
  assert.equal(w.series[0].speed, 402);
});

test("storm likely only after 30 minutes of strong southward field and fast wind", () => {
  const wind = minutes(60, () => ({ proton_speed: 520, proton_density: 8 }));
  assert.equal(stormLikely(reduce(minutes(60, () => ({ bz_gsm: -12, bt: 14 })), wind, now), now), true);
  assert.equal(stormLikely(reduce(minutes(60, () => ({ bz_gsm: -6, bt: 14 })), wind, now), now), false);
  assert.equal(stormLikely(reduce(minutes(60, (i) => ({ bz_gsm: i < 45 ? 5 : -15, bt: 15 })), wind, now), now), false);
  assert.equal(stormLikely(reduce(minutes(60, () => ({ bz_gsm: -12, bt: 14 })), minutes(60, () => ({ proton_speed: 380, proton_density: 8 })), now), now), false);
  assert.equal(stormLikely(null, now), false);
});
