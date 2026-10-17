import assert from "node:assert/strict";
import { test } from "node:test";
import { normalize } from "../src/ll2.ts";

// Trimmed from /2.3.0/launches/upcoming/?mode=normal on 2026-10-17.
const raw = {
  id: "3b430f81-0ff1-4d85-8a1a-cef0de326198",
  name: "Falcon 9 Block 5 | Bandwagon 5 (Dedicated Mid-Inclination Rideshare)",
  net: "2026-10-19T10:30:00Z",
  window_start: "2026-10-19T10:30:00Z",
  window_end: "2026-10-19T11:30:00Z",
  last_updated: "2026-10-17T20:00:00Z",
  status: { id: 1, name: "Go for Launch", abbrev: "Go" },
  launch_service_provider: { name: "SpaceX", abbrev: "SpX" },
  rocket: { configuration: { name: "Falcon 9", full_name: "Falcon 9 Block 5" } },
  mission: { name: "Bandwagon 5", type: "Dedicated Rideshare", description: " Rideshare. ", orbit: { abbrev: "LEO" } },
  pad: { name: "Space Launch Complex 40", latitude: "28.56194122", longitude: "-80.57735736", location: { name: "Cape Canaveral SFS, FL, USA" } },
};

test("normalizes a launch", () => {
  const l = normalize(raw);
  assert.equal(l.rocket, "Falcon 9 Block 5");
  assert.equal(l.status, "Go");
  assert.equal(l.orbit, "LEO");
  assert.equal(l.missionDescription, "Rideshare.");
  assert.equal(l.padLatitude, 28.56194122);
});

test("tolerates a missing mission", () => {
  const l = normalize({ ...raw, mission: null });
  assert.equal(l.mission, null);
  assert.equal(l.orbit, null);
});
