#!/usr/bin/env python3
"""Adds active missions to SkyRenderer/Resources/spacecraft.json from JPL Horizons.

Heliocentric positions in AU on J2000 ecliptic axes every 10 days (2 for Parker Solar Probe, whose orbit takes 88),
from launch to five years from now or the end of Horizons' data (its predicted trajectory after the last tracking). Entries are replaced by Horizons ID; the others in
the file are kept. One request at a time, two seconds apart (JPL's SSD API fair use).

    scripts/make-spacecraft.py
"""
import datetime
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

FILE = Path(__file__).resolve().parent.parent / "Packages/MoonriseKit/Sources/SkyRenderer/Resources/spacecraft.json"
UA = "Moonrise/5.3.0 (sh.krz.moonrise; root@krz.sh)"
MISSIONS = [
    (-61, "Juno", "2011-08-05", "10d"),
    (-96, "Parker Solar Probe", "2018-08-12", "2d"),
    (-49, "Lucy", "2021-10-16", "10d"),
    (-28, "JUICE", "2023-04-14", "10d"),
    (-255, "Psyche", "2023-10-13", "10d"),
    (-159, "Europa Clipper", "2024-10-14", "10d"),
]
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


def horizons(command, start, stop, step):
    q = urllib.parse.urlencode({
        "format": "json", "COMMAND": f"'{command}'", "EPHEM_TYPE": "'VECTORS'", "CENTER": "'500@10'",
        "REF_PLANE": "'ECLIPTIC'", "START_TIME": f"'{start}'", "STOP_TIME": f"'{stop}'", "STEP_SIZE": f"'{step}'",
        "VEC_TABLE": "'1'", "OUT_UNITS": "'AU-D'", "CSV_FORMAT": "'YES'", "OBJ_DATA": "'NO'",
    })
    with urllib.request.urlopen(urllib.request.Request(f"https://ssd.jpl.nasa.gov/api/horizons.api?{q}", headers={"User-Agent": UA}), timeout=120) as r:
        return json.load(r)["result"]


def limit(result, which):
    m = re.search(which + r" A\.D\. (\d{4})-([A-Z]{3})-(\d{2}) (\d{2}):(\d{2})", result)
    if not m:
        return None
    return datetime.datetime(int(m[1]), MONTHS.index(m[2]) + 1, int(m[3]), int(m[4]), int(m[5]))


def points(command, launch, step):
    start = datetime.datetime.fromisoformat(launch) + datetime.timedelta(days=1)
    stop = datetime.datetime.now() + datetime.timedelta(days=5 * 365)
    for _ in range(4):
        result = horizons(command, start.strftime("%Y-%m-%d %H:%M"), stop.strftime("%Y-%m-%d %H:%M"), step)
        time.sleep(2)
        first, last = limit(result, "prior to"), limit(result, "after")
        if first and first > start:
            start = first + datetime.timedelta(minutes=1)
            continue
        if last and last < stop:
            stop = last - datetime.timedelta(minutes=1)
            continue
        rows = result[result.index("$$SOE") + 5:result.index("$$EOE")].strip().splitlines()
        out = []
        for line in rows:
            f = [s.strip() for s in line.split(",")]
            jd, x, y, z = float(f[0]), float(f[2]), float(f[3]), float(f[4])
            out.append([round(jd - 2440587.5, 1), round(x, 4), round(y, 4), round(z, 4)])
        return out
    raise RuntimeError(f"no data for {command}")


crafts = json.loads(FILE.read_text())
for hid, name, launch, step in MISSIONS:
    p = points(hid, launch, step)
    crafts = [c for c in crafts if c["id"] != hid] + [{"id": hid, "name": name, "launch": launch, "points": p}]
    print(name, len(p), "points", p[0][0], "to", p[-1][0])
FILE.write_text(json.dumps(crafts, separators=(",", ":")))
