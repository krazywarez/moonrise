import assert from "node:assert/strict";
import { test } from "node:test";
import { ccor2Frames, reduceCycle, reduceEnlil } from "../src/sun.ts";

test("Enlil: hourly means from the start time, CME hours flagged", () => {
  const rows = [
    { time_tag: "2026-10-22T00:10:00", earth_particles_per_cm3: 4, v_r: 400, cloud: null },
    { time_tag: "2026-10-22T00:50:00", earth_particles_per_cm3: 6, v_r: 420, cloud: null },
    { time_tag: "2026-10-22T01:10:00", earth_particles_per_cm3: 20, v_r: 700, cloud: 1 },
    { time_tag: "2026-10-21T22:00:00", earth_particles_per_cm3: 5, v_r: 380, cloud: null },
  ];
  assert.deepEqual(reduceEnlil(rows, new Date("2026-10-22T00:00:00Z")), [
    { t: "2026-10-22T00:00:00.000Z", speed: 410, density: 5, cloud: false },
    { t: "2026-10-22T01:00:00.000Z", speed: 700, density: 20, cloud: true },
  ]);
});

test("CCOR-2: the last frame of each hour in the last day", () => {
  const listing = ["20261021_0300", "20261022_0315", "20261022_0330", "20261022_0400", "20261021_0245"]
    .map((s) => `<a href="${s}_ccor2_1024by960.jpg">x</a>`).join("") + `<a href="latest.jpg">l</a>`;
  const frames = ccor2Frames(listing, new Date("2026-10-22T04:10:00Z"));
  assert.deepEqual(frames.map((f) => f.t), ["2026-10-22T03:30:00.000Z", "2026-10-22T04:00:00.000Z"]);
  assert.equal(frames[0].url, "https://services.swpc.noaa.gov/images/animations/ccor2/20261022_0330_ccor2_1024by960.jpg");
});

test("Cycle 25 from December 2019, missing values as null", () => {
  const c = reduceCycle(
    [{ "time-tag": "2019-11", ssn: 1, smoothed_ssn: 2 }, { "time-tag": "2019-12", ssn: 1.5, smoothed_ssn: 1.8 }, { "time-tag": "2026-09", ssn: 60.3, smoothed_ssn: -1 }],
    [{ "time-tag": "2026-10", predicted_ssn: 90, high_ssn: 100, low_ssn: 80 }],
  );
  assert.deepEqual(c.observed, [{ month: "2019-12", ssn: 1.5, smoothed: 1.8 }, { month: "2026-09", ssn: 60.3, smoothed: null }]);
  assert.deepEqual(c.predicted, [{ month: "2026-10", ssn: 90, high: 100, low: 80 }]);
});
