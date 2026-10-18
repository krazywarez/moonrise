import assert from "node:assert/strict";
import { test } from "node:test";
import { activeEvent, ephemerisLimit, parseVectors } from "../src/live.ts";

test("finds the event covering a time", () => {
  assert.equal(activeEvent(new Date("2022-11-21T12:00:00Z"))?.id, "artemis-1");
  assert.equal(activeEvent(new Date("2022-12-12T00:00:00Z")), undefined);
  assert.equal(activeEvent(new Date("2026-10-18T00:00:00Z")), undefined);
});

test("parses a Horizons CSV vector table", () => {
  // Excerpt of a Horizons VECTORS result for Artemis I, 2022-11-20, VEC_TABLE 1.
  const result = `header\n$$SOE\n2459903.500000000, A.D. 2022-Nov-20 00:00:00.0000, -3.304975631098540E+05, -1.579881350142587E+05,  1.186979134120867E+04,\n2459903.750000000, A.D. 2022-Nov-20 06:00:00.0000, -3.342673908331381E+05, -1.637787996887478E+05,  1.148822953490770E+04,\n$$EOE\nfooter`;
  const rows = parseVectors(result);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], [1668902400, -330497.563109854, -157988.1350142587, 11869.79134120867]);
  assert.equal(rows[1][0] - rows[0][0], 6 * 3600);
});

test("reads the start of Horizons data from its error", () => {
  const msg = 'No ephemeris for target "Artemis 1 (spacecraft)" prior to A.D. 2022-NOV-16 08:46:00.3328 TDB';
  assert.equal(ephemerisLimit(msg, "prior to")?.toISOString(), "2022-11-16T08:46:00.000Z");
  assert.equal(ephemerisLimit(msg, "after"), undefined);
  const end = 'No ephemeris for target "Artemis 1 (spacecraft)" after A.D. 2022-DEC-11 17:21:01.8003 TDB';
  assert.equal(ephemerisLimit(end, "after")?.toISOString(), "2022-12-11T17:21:00.000Z");
  assert.equal(ephemerisLimit("$$SOE ... $$EOE", "prior to"), undefined);
});
