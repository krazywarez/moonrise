import assert from "node:assert/strict";
import { test } from "node:test";
import { decode, next24h } from "../src/swpc.ts";

// Shapes copied from the live SWPC feeds on 2026-10-17.
const now = [
  { time_tag: "2026-10-17T23:32:00", kp_index: 0, estimated_kp: 0.33, kp: "0P" },
  { time_tag: "2026-10-17T23:33:00", kp_index: 0, estimated_kp: 0.67, kp: "1M" },
];
const forecast = [
  { time_tag: "2026-10-17T18:00:00", kp: 2.33, observed: "observed", noaa_scale: null },
  { time_tag: "2026-10-18T00:00:00", kp: 3.67, observed: "predicted", noaa_scale: null },
  { time_tag: "2026-10-18T09:00:00", kp: 5.33, observed: "predicted", noaa_scale: "G1" },
  { time_tag: "2026-10-19T21:00:00", kp: 7.0, observed: "predicted", noaa_scale: "G3" },
];

test("decodes latest Kp and forecast", () => {
  const w = decode(now, forecast);
  assert.equal(w.kpNow, 0.67);
  assert.equal(w.observedAt, "2026-10-17T23:33:00.000Z");
  assert.equal(w.forecast.length, 4);
  assert.equal(w.forecast[0].predicted, false);
});

test("next 24 h maximum ignores observed and later rows", () => {
  const w = decode(now, forecast);
  assert.equal(next24h(w, new Date("2026-10-17T23:34:00Z")), 5.33);
});
