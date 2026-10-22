import assert from "node:assert/strict";
import { test } from "node:test";
import { parse } from "../src/smallbodies.ts";

test("SBDB rows to SmallBody, without rows lacking a brightness", () => {
  const comets = parse([["   24P/Schaumasse", "0.7079", "1.185", "11.50", "78.29", "58.48", "2461049.06", "14.6", "8."], ["C/2026 X1", "1.0", "0.5", "40", "10", "20", "2461100", null, null]], "comet");
  assert.deepEqual(comets, [{ name: "24P/Schaumasse", e: 0.7079, q: 1.185, i: 11.5, node: 78.29, peri: 58.48, tp: 2461049.06, brightness: { comet: { m1: 14.6, k1: 8 } } }]);
  const asteroids = parse([["     1 Ceres (A801 AA)", "0.0797", "2.545", "10.59", "80.25", "73.29", "2461599.84", "3.34", null]], "asteroid");
  assert.deepEqual(asteroids[0].brightness, { asteroid: { h: 3.34, g: 0.15 } });
  assert.equal(asteroids[0].name, "1 Ceres (A801 AA)");
});
