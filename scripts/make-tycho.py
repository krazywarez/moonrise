#!/usr/bin/env python3
"""Builds SkyRenderer/Resources/tycho2.bin: Tycho-2 stars from V 6 to 9 that are not in the Bright Star Catalogue.

Input is a VizieR TAP CSV of I/259/tyc2 (ESA; Høg et al. 2000), queried with
    SELECT RAmdeg, DEmdeg, pmRA, pmDE, BTmag, VTmag, HIP FROM "I/259/tyc2" WHERE VTmag < 9.6
V = VT − 0.090 (BT − VT) and B − V = 0.850 (BT − VT) (ESA 1997, Hipparcos and Tycho Catalogues, vol. 1, 1.3).
Stars without a mean position are left out, as are those brighter than V 6 (the Bright Star Catalogue is
complete there) and any within 30″ of a BSC5 star whose V is within 0.7.

Record, 14 bytes, little-endian, sorted by V: RA as UInt32 (360° = 2^32), Dec as Int32 (90° = 2^31 − 1),
V as UInt8 ((V + 2) × 20), B − V as Int8 (× 50), pmRA (× cos dec) and pmDec as Int16 in mas/yr. J2000.

    scripts/make-tycho.py tyc2.csv
"""
import csv
import json
import math
import struct
import sys
from pathlib import Path

RES = Path(__file__).resolve().parent.parent / "Packages/MoonriseKit/Sources/SkyRenderer/Resources"

bright = json.load(open(RES / "bsc5.json"))
cells = {}
for hr, ra, dec, v, *_ in bright:
    cells.setdefault((int(dec), int(ra)), []).append((ra, dec, v))


def in_bsc(ra, dec, v):
    for d in (-1, 0, 1):
        for r in (-1, 0, 1):
            for bra, bdec, bv in cells.get((int(dec) + d, (int(ra) + r) % 360), []):
                dra = (ra - bra + 180) % 360 - 180
                sep = math.hypot(dra * math.cos(math.radians(dec)), dec - bdec) * 3600
                if sep < 30 and abs(v - bv) < 0.7:
                    return True
    return False


rows = []
for r in csv.DictReader(open(sys.argv[1])):
    if not r["RAmdeg"] or not r["VTmag"]:
        continue
    vt, ra, dec = float(r["VTmag"]), float(r["RAmdeg"]), float(r["DEmdeg"])
    bt = float(r["BTmag"]) if r["BTmag"] else None
    v = vt - 0.090 * (bt - vt) if bt is not None else vt
    bv = 0.850 * (bt - vt) if bt is not None else 0.6
    if v < 6 or v > 9 or in_bsc(ra, dec, v):
        continue
    pmra = float(r["pmRA"]) if r["pmRA"] else 0
    pmde = float(r["pmDE"]) if r["pmDE"] else 0
    rows.append((v, ra, dec, bv, pmra, pmde))

rows.sort()
clamp = lambda x, lo, hi: max(lo, min(hi, x))
with open(RES / "tycho2.bin", "wb") as f:
    for v, ra, dec, bv, pmra, pmde in rows:
        f.write(struct.pack("<IiBbhh",
                            int(ra / 360 * 2**32) % 2**32, int(dec / 90 * (2**31 - 1)),
                            clamp(round((v + 2) * 20), 0, 255), clamp(round(bv * 50), -128, 127),
                            clamp(round(pmra), -32768, 32767), clamp(round(pmde), -32768, 32767)))
print(len(rows), "stars,", len(rows) * 14, "bytes")
