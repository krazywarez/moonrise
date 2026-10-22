import assert from "node:assert/strict";
import { test } from "node:test";
import { contentState, stormActive, stormEnd, stormUpdate, type StormState } from "../src/storm.ts";

const now = new Date("2026-10-20T22:00:00Z");
const unix = (iso: string) => Date.parse(iso) / 1000;
const quiet: StormState = { kp: 3, expectedKp: 3.7, early: false, bz: -2, speed: 380 };
const g1: StormState = { kp: 5.3, expectedKp: 5.7, early: false, bz: -12.4, speed: 610 };
const at = (min: number) => new Date(now.getTime() + min * 60_000);

test("a storm is Kp 5 now or expected within 3 hours, or a strongly southward wind", () => {
  assert.equal(stormActive(quiet), false);
  assert.equal(stormActive({ ...quiet, expectedKp: 5 }), true);
  assert.equal(stormActive({ ...quiet, early: true }), true);
});

test("the content state uses Swift's reference date and leaves out missing wind", () => {
  assert.deepEqual(contentState(g1, now), { kp: 5.3, expectedKp: 5.7, early: false, updated: unix("2026-10-20T22:00:00Z") - 978_307_200, bz: -12.4, speed: 610 });
  assert.deepEqual(Object.keys(contentState({ ...g1, bz: null, speed: null }, now)), ["kp", "expectedKp", "early", "updated"]);
});

test("the first update and any rise in G level go at priority 10, with a 45-minute stale date", () => {
  const first = stormUpdate(null, g1, now)!;
  assert.equal(first.priority, 10);
  assert.equal(first.payload.aps.event, "update");
  assert.equal(first.payload.aps["stale-date"], unix("2026-10-20T22:45:00Z"));
  assert.equal(stormUpdate({ state: g1, at: now }, { ...g1, kp: 6.3 }, at(5))!.priority, 10);
  assert.equal(stormUpdate({ state: quiet, at: now }, { ...quiet, early: true }, at(5))!.priority, 10);
});

test("a fall in G level goes at priority 5; small changes wait for the 30-minute refresh", () => {
  assert.equal(stormUpdate({ state: g1, at: now }, { ...g1, kp: 4.7 }, at(5))!.priority, 5);
  assert.equal(stormUpdate({ state: g1, at: now }, { ...g1, kp: 5.7, bz: -4 }, at(29)), null);
  assert.equal(stormUpdate({ state: g1, at: now }, { ...g1, kp: 5.7, bz: -4 }, at(30))!.priority, 5);
});

test("the end stays on the Lock Screen for an hour", () => {
  const end = stormEnd(quiet, now);
  assert.equal(end.payload.aps.event, "end");
  assert.equal(end.payload.aps["dismissal-date"], unix("2026-10-20T23:00:00Z"));
});
