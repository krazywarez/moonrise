import assert from "node:assert/strict";
import { test } from "node:test";
import { activityPush, focusEvery, focusPick, focusPollDue, inFocus, needsChannel, sinceNet } from "../src/activity.ts";

const now = new Date("2026-10-20T12:00:00Z");
const unix = (iso: string) => Date.parse(iso) / 1000;

test("focus runs from an hour before NET to 15 minutes after, until an outcome", () => {
  const at = (net: string, status = "Go") => inFocus({ net, status }, now);
  assert.equal(at("2026-10-20T13:00:00Z"), true);
  assert.equal(at("2026-10-20T13:00:01Z"), false);
  assert.equal(at("2026-10-20T11:45:00Z", "In Flight"), true);
  assert.equal(at("2026-10-20T11:44:59Z"), false);
  assert.equal(at("2026-10-20T11:50:00Z", "Success"), false);
  assert.equal(sinceNet(now), "2026-10-20T11:45:00.000Z");
});

test("overlapping launches take turns, one request per 5-minute tick", () => {
  const ids = ["a", "b"];
  assert.equal(focusPick(ids, new Date("2026-10-20T12:00:00Z")), "a");
  assert.equal(focusPick(ids, new Date("2026-10-20T12:05:00Z")), "b");
  assert.equal(focusPick(ids, new Date("2026-10-20T12:10:00Z")), "a");
  assert.equal(focusPick(["a"], new Date("2026-10-20T12:05:00Z")), "a");
  assert.deepEqual([0, 2, 4, 6].map((m) => focusPick(ids, new Date(Date.UTC(2026, 9, 20, 12, m)), 2)), ["a", "b", "a", "b"]);
});

test("the launch in focus is polled every 5 minutes anonymously and every even minute with a key", () => {
  for (const keyed of [false, true]) {
    const polled: number[] = [];
    for (let m = 0; m < 60; m++) {
      const at = new Date(Date.UTC(2026, 9, 20, 12, m));
      const five = m % 5 === 0 && focusPollDue(5, at, keyed);
      const two = m % 2 === 0 && focusPollDue(2, at, keyed);
      assert.ok(!(five && two), `both crons poll at minute ${m}`);
      if (five || two) polled.push(m);
    }
    const every = focusEvery(keyed);
    assert.deepEqual(polled, Array.from({ length: 60 / every }, (_, i) => i * every));
  }
});

test("a launch needs a channel within 24 hours of NET until it has an outcome", () => {
  assert.equal(needsChannel({ net: "2026-10-21T12:00:00Z", status: "Go" }, now), true);
  assert.equal(needsChannel({ net: "2026-10-21T12:00:01Z", status: "Go" }, now), false);
  assert.equal(needsChannel({ net: "2026-10-20T11:50:00Z", status: "In Flight" }, now), true);
  assert.equal(needsChannel({ net: "2026-10-20T11:40:00Z", status: "Go" }, now), false);
  assert.equal(needsChannel({ net: "2026-10-20T13:00:00Z", status: "Success" }, now), false);
});

test("no push without a change of status or NET", () => {
  assert.equal(activityPush({ net: "2026-10-20T13:00:00Z", status: "Go" }, { net: "2026-10-20T13:00:00Z", status: "Go" }, now), null);
});

test("a status change is an update at priority 10, with content-state dates in seconds since 2001", () => {
  const p = activityPush({ net: "2026-10-20T13:00:00Z", status: "Go" }, { net: "2026-10-20T13:00:00Z", status: "Hold" }, now)!;
  assert.equal(p.priority, 10);
  assert.equal(p.end, false);
  assert.deepEqual(p.payload, {
    aps: {
      timestamp: unix("2026-10-20T12:00:00Z"),
      event: "update",
      "content-state": { net: unix("2026-10-20T13:00:00Z") - 978_307_200, status: "Hold" },
      "stale-date": unix("2026-10-20T14:00:00Z"),
    },
  });
});

test("a NET change alone goes at priority 5", () => {
  const p = activityPush({ net: "2026-10-20T13:00:00Z", status: "Go" }, { net: "2026-10-20T13:10:00Z", status: "Go" }, now)!;
  assert.equal(p.priority, 5);
  assert.equal((p.payload.aps["content-state"] as { net: number }).net, unix("2026-10-20T13:10:00Z") - 978_307_200);
});

test("an outcome ends the activity and dismisses it 15 minutes later", () => {
  for (const status of ["Success", "Failure", "Partial Failure"]) {
    const p = activityPush({ net: "2026-10-20T11:50:00Z", status: "In Flight" }, { net: "2026-10-20T11:50:00Z", status }, now)!;
    assert.equal(p.end, true);
    assert.equal(p.priority, 10);
    assert.equal(p.payload.aps.event, "end");
    assert.equal(p.payload.aps["dismissal-date"], unix("2026-10-20T12:15:00Z"));
    assert.equal(p.payload.aps["stale-date"], undefined);
  }
});
