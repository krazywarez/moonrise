import assert from "node:assert/strict";
import { test } from "node:test";
import { actionableKp, alertBands, bandFor, eventKey, isNight, ovalEdge, visibleFrom } from "../src/aurora.ts";

test("oval edge follows the NOAA chart", () => {
  assert.equal(ovalEdge(0), 66.5);
  assert.ok(Math.abs(ovalEdge(5) - 56.3) < 0.1);
  assert.ok(Math.abs(visibleFrom(5) - 50.3) < 0.1);
});

test("bands", () => {
  assert.equal(bandFor(52.4), 50);
  assert.equal(bandFor(49.9), 45);
  assert.equal(bandFor(-52.4), -55);
});

test("Kp 5 alerts bands reaching 50.3° geomagnetic, both hemispheres", () => {
  assert.deepEqual(alertBands(5, [40, 45, 50, 55, -45, -55]), [50, 55, -55]);
  // Kp 2: visible from 56.4°, which the 55–60° band reaches.
  assert.deepEqual(alertBands(2, [45, 50, 55]), [55]);
});

test("night is 20:00 to 04:00 local", () => {
  const t = new Date("2026-10-18T02:00:00Z"); // 21:00 CDT
  assert.equal(isNight(t, -300), true);
  assert.equal(isNight(new Date("2026-10-17T18:00:00Z"), -300), false); // 13:00 CDT
  assert.equal(isNight(new Date("2026-10-18T08:30:00Z"), -300), true); // 03:30 CDT
});

test("event key splits the UTC day in two", () => {
  assert.equal(eventKey(new Date("2026-10-18T02:00:00Z")), "2026-10-18a");
  assert.equal(eventKey(new Date("2026-10-18T13:00:00Z")), "2026-10-18b");
});

test("actionable Kp takes the forecast for the next 3 hours", () => {
  const now = new Date("2026-10-18T01:00:00Z");
  const f = [
    { start: new Date("2026-10-18T00:00:00Z"), kp: 4 },
    { start: new Date("2026-10-18T03:00:00Z"), kp: 6 },
    { start: new Date("2026-10-18T09:00:00Z"), kp: 8 },
  ];
  assert.equal(actionableKp(2, f, now), 6);
});
