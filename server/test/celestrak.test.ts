import assert from "node:assert/strict";
import { test } from "node:test";
import { pick } from "../src/celestrak.ts";

test("keeps only the SGP4 fields", () => {
  // CelesTrak GP JSON for the ISS, 2026-10-18.
  const row = {
    OBJECT_NAME: "ISS (ZARYA)", OBJECT_ID: "1998-067A", EPOCH: "2026-10-18T03:28:15.076416", MEAN_MOTION: 15.48918166,
    ECCENTRICITY: 0.000678, INCLINATION: 51.6328, RA_OF_ASC_NODE: 51.6259, ARG_OF_PERICENTER: 277.7856, MEAN_ANOMALY: 82.2363,
    EPHEMERIS_TYPE: 0, CLASSIFICATION_TYPE: "U", NORAD_CAT_ID: 25544, ELEMENT_SET_NO: 999, REV_AT_EPOCH: 59081, BSTAR: 0.00014456,
    MEAN_MOTION_DOT: 7.503e-05, MEAN_MOTION_DDOT: 0,
  };
  const [o] = pick([row]);
  assert.deepEqual(Object.keys(o).sort(), ["ARG_OF_PERICENTER", "BSTAR", "ECCENTRICITY", "EPOCH", "INCLINATION", "MEAN_ANOMALY", "MEAN_MOTION", "NORAD_CAT_ID", "OBJECT_NAME", "RA_OF_ASC_NODE"]);
  assert.equal(o.NORAD_CAT_ID, 25544);
});
