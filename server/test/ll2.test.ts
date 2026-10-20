import assert from "node:assert/strict";
import { test } from "node:test";
import { normalize, PREVIOUS_URL } from "../src/ll2.ts";

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

// Trimmed from /2.3.0/launches/previous/?mode=normal on 2026-10-19.
const launched = {
  id: "97c6f5e1-299e-4652-b72d-9618ac047076",
  name: "Falcon 9 Block 5 | Starlink Group 15-25",
  net: "2026-10-13T00:28:11Z",
  window_start: "2026-10-12T23:00:00Z",
  window_end: "2026-10-13T03:00:00Z",
  last_updated: "2026-10-13T10:10:50Z",
  launch_designator: "2026-232",
  status: { name: "Launch Successful", abbrev: "Success" },
  launch_service_provider: { name: "SpaceX" },
  rocket: { configuration: { name: "Falcon 9", full_name: "Falcon 9 Block 5" } },
  mission: { name: "Starlink Group 15-25", type: "Communications", orbit: { abbrev: "LEO" } },
  pad: { name: "Space Launch Complex 4E", latitude: 34.632, longitude: -120.611, location: { name: "Vandenberg SFB, CA, USA" } },
};

test("keeps the international designator once launched", () => {
  assert.equal(normalize(launched).designator, "2026-232");
  assert.equal(normalize(raw).designator, null);
});

test("previous launches are fetched ten at a time", () => {
  assert.match(PREVIOUS_URL, /\/launches\/previous\/\?limit=10&mode=normal$/);
});
