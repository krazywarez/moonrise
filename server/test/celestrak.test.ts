import assert from "node:assert/strict";
import { test } from "node:test";
import { byDesignator, compose, fitsLaunch, parseSupGP, pick, starlinkTrains, supgpFile, supgpLaunches } from "../src/celestrak.ts";

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

test("one Starlink train per low recent launch, median satellite", () => {
  const sat = (id: string, n: number, mm: number) => ({
    OBJECT_NAME: `STARLINK-${n}`, OBJECT_ID: id, NORAD_CAT_ID: n, EPOCH: "2026-10-18T00:00:00", MEAN_MOTION: mm,
    ECCENTRICITY: 0.0001, INCLINATION: 53, RA_OF_ASC_NODE: 10, ARG_OF_PERICENTER: 90, MEAN_ANOMALY: 0, BSTAR: 0.001,
  });
  const trains = starlinkTrains(byDesignator([
    sat("2026-232A", 1, 15.9), sat("2026-232B", 2, 16.0), sat("2026-232C", 3, 15.95),
    sat("2026-180A", 4, 15.06), sat("2026-180B", 5, 15.07),
    { ...sat("2026-232D", 6, 16.1), OBJECT_NAME: "FALCON 9 R/B" },
  ]));
  assert.equal(trains.length, 1);
  assert.equal(trains[0].OBJECT_NAME, "Starlink train (2026-232)");
  assert.equal(trains[0].NORAD_CAT_ID, 3);
});

// sup-gp.php?FILE=starlink-g15-15&FORMAT=JSON on 2026-10-19 (trimmed). Its OBJECT_ID is a guess:
// 2026-235 went to USSF-481 on 2026-10-16.
const SUPGP = `[{"OBJECT_NAME":"STARLINK-G15-15 STACK","OBJECT_ID":"2026-235A","EPOCH":"2026-10-21T00:11:38.559984","MEAN_MOTION":16.05876681,"ECCENTRICITY":0.0009517,"INCLINATION":70.007,"RA_OF_ASC_NODE":92.2113,"ARG_OF_PERICENTER":261.8925,"MEAN_ANOMALY":112.7386,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"C","NORAD_CAT_ID":72000,"ELEMENT_SET_NO":0,"REV_AT_EPOCH":1,"BSTAR":0.00011238,"MEAN_MOTION_DOT":0.00082246,"MEAN_MOTION_DDOT":0,"RMS":"0.096","DATA_SOURCE":"SpaceX-SV"},
{"OBJECT_NAME":"STARLINK-G15-15 SINGLE","OBJECT_ID":"2026-235B","EPOCH":"2026-10-21T00:11:38.559984","MEAN_MOTION":16.05877557,"ECCENTRICITY":0.0009499,"INCLINATION":70.0069,"RA_OF_ASC_NODE":92.2113,"ARG_OF_PERICENTER":263.1103,"MEAN_ANOMALY":111.5203,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"C","NORAD_CAT_ID":72001,"ELEMENT_SET_NO":0,"REV_AT_EPOCH":1,"BSTAR":0.0016439,"MEAN_MOTION_DOT":0.012324,"MEAN_MOTION_DDOT":0,"RMS":"0.110","DATA_SOURCE":"SpaceX-SV"}]`;

test("maps Starlink mission names to SupGP files", () => {
  assert.equal(supgpFile("Starlink Group 15-15"), "starlink-g15-15");
  assert.equal(supgpFile("Starlink Group 6-100"), "starlink-g6-100");
  assert.equal(supgpFile("Transporter 18 (Dedicated SSO Rideshare)"), null);
  assert.equal(supgpFile(null), null);
});

test("SupGP misses and malformed rows are no data", () => {
  assert.equal(parseSupGP(SUPGP).length, 2);
  // An unknown FILE comes back as HTTP 200 with plain text.
  assert.deepEqual(parseSupGP("Invalid query: \"starlink-g99-99\" not found."), []);
  assert.deepEqual(parseSupGP("{}"), []);
  assert.deepEqual(parseSupGP("[{"), []);
  const rows = JSON.parse(SUPGP);
  delete rows[1].BSTAR;
  assert.equal(parseSupGP(JSON.stringify(rows)).length, 1);
  assert.deepEqual(parseSupGP(JSON.stringify([{ ...rows[0], MEAN_MOTION: "16" }])), []);
});

test("SupGP sets must fit the launch time", () => {
  const rows = parseSupGP(SUPGP);
  const before = new Date("2026-10-19T12:00:00Z");
  // LL2 NET for Group 15-15: deployment 1 h 57 min later.
  assert.equal(fitsLaunch(rows, "2026-10-20T22:14:00Z", before).length, 2);
  // Slipped a day: the file is for the old time.
  assert.equal(fitsLaunch(rows, "2026-10-21T23:10:00Z", before).length, 0);
  // Epoch four hours after a liftoff still to come: not this opportunity.
  assert.equal(fitsLaunch(rows, "2026-10-20T20:00:00Z", before).length, 0);
  // After liftoff, later post-deployment sets are fine.
  assert.equal(fitsLaunch(rows, "2026-10-20T20:00:00Z", new Date("2026-10-21T06:00:00Z")).length, 2);
});

const launch = (id: string, mission: string | null, net: string, designator: string | null = null, provider = "SpaceX") => ({ id, mission, provider, net, designator });

test("SupGP is fetched for at most four nearby Starlink launches, nearest first", () => {
  const now = new Date("2026-10-19T12:00:00Z");
  const picked = supgpLaunches([
    launch("far", "Starlink Group 1-1", "2026-10-22T12:00:00Z"),
    launch("old", "Starlink Group 1-2", "2026-10-15T12:00:00Z"),
    launch("a", "Starlink Group 1-3", "2026-10-19T14:00:00Z"),
    launch("b", "Starlink Group 1-4", "2026-10-18T12:00:00Z"),
    launch("c", "Starlink Group 1-5", "2026-10-20T12:00:00Z"),
    launch("d", "Starlink Group 1-6", "2026-10-17T00:00:00Z"),
    launch("e", "Starlink Group 1-7", "2026-10-16T13:00:00Z"),
    launch("ussf", "USSF-481", "2026-10-19T13:00:00Z"),
    launch("other", "Starlink Group 1-8", "2026-10-19T13:00:00Z", null, "Rocket Lab"),
  ], now);
  assert.deepEqual(picked.map((l) => l.id), ["a", "b", "c", "d"]);
});

const gp = (id: string, name: string, n: number, epoch = "2026-10-18T00:00:00", mm = 15.9) => ({
  OBJECT_NAME: name, OBJECT_ID: id, NORAD_CAT_ID: n, EPOCH: epoch, MEAN_MOTION: mm,
  ECCENTRICITY: 0.0001, INCLINATION: 53, RA_OF_ASC_NODE: 10, ARG_OF_PERICENTER: 90, MEAN_ANOMALY: 0, BSTAR: 0.001,
});

test("labels trains with the mission and keeps SupGP apart from a designator it guessed", () => {
  const recent = [
    gp("2026-232A", "STARLINK-1", 1), gp("2026-232B", "STARLINK-2", 2), gp("2026-232C", "STARLINK-3", 3),
    gp("2026-235A", "USA 600", 10), gp("2026-235B", "FALCON 9 R/B", 11),
  ];
  const launches = [
    launch("g1525", "Starlink Group 15-25", "2026-10-13T00:28:11Z", "2026-232"),
    launch("ussf", "USSF-481", "2026-10-16T00:01:05Z", "2026-235"),
    launch("g1515", "Starlink Group 15-15", "2026-10-20T23:10:00Z"),
  ];
  const out = compose([gp("1998-067A", "ISS (ZARYA)", 25544)], recent, launches, { g1515: parseSupGP(SUPGP) }, new Date("2026-10-21T06:00:00Z"));
  assert.deepEqual(out.satellites.map((s) => s.OBJECT_NAME), ["ISS (ZARYA)", "Starlink train (Group 15-25)", "Starlink train (Group 15-15)"]);
  assert.deepEqual(out.launches.g1525.elements.map((e) => e.OBJECT_NAME), ["Starlink train (Group 15-25)"]);
  assert.equal(out.launches.g1525.source, "gp");
  assert.deepEqual(out.launches.ussf.elements.map((e) => e.OBJECT_NAME), ["FALCON 9 R/B", "USA 600"]);
  assert.equal(out.launches.g1515.source, "supgp");
  assert.equal(out.launches.g1515.elements[0].NORAD_CAT_ID, 72001);
  // Before its predicted deployment a train is on the launch only: the satellite list is propagated from now.
  const early = compose([], recent, launches, { g1515: parseSupGP(SUPGP) }, new Date("2026-10-19T12:00:00Z"));
  assert.deepEqual(early.satellites.map((s) => s.OBJECT_NAME), ["Starlink train (Group 15-25)"]);
  assert.equal(early.launches.g1515.source, "supgp");
});

test("the newer of GP and SupGP wins for a launch", () => {
  const launches = [launch("g1525", "Starlink Group 15-25", "2026-10-13T00:28:11Z", "2026-232")];
  const recent = [gp("2026-232A", "STARLINK-1", 1, "2026-10-18T00:00:00")];
  const older = [gp("2026-999A", "STARLINK-G15-25 STACK", 72000, "2026-10-13T01:30:00")];
  const newer = [gp("2026-999A", "STARLINK-G15-25 STACK", 72000, "2026-10-18T06:00:00")];
  assert.equal(compose([], recent, launches, { g1525: older }, new Date("2026-10-19T12:00:00Z")).launches.g1525.source, "gp");
  const out = compose([], recent, launches, { g1525: newer }, new Date("2026-10-19T12:00:00Z"));
  assert.equal(out.launches.g1525.source, "supgp");
  assert.equal(out.satellites.length, 1);
});

test("other launches list rocket bodies first, skip debris and stop at eight", () => {
  const recent = [
    ...Array.from({ length: 12 }, (_, i) => gp(`2026-227${String.fromCharCode(65 + i)}`, `SAT ${i}`, 100 + i)),
    gp("2026-227M", "FALCON 9 R/B", 200), gp("2026-227N", "FALCON 9 DEB", 201),
  ];
  const out = compose([], recent, [launch("t18", "Transporter 18", "2026-10-01T18:32:00Z", "2026-227")], {}, new Date("2026-10-19T12:00:00Z"));
  const names = out.launches.t18.elements.map((e) => e.OBJECT_NAME);
  assert.equal(names.length, 8);
  assert.equal(names[0], "FALCON 9 R/B");
  assert.ok(!names.includes("FALCON 9 DEB"));
});
