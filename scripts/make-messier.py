#!/usr/bin/env python3
"""Builds SkyRenderer/Resources/messier.json from OpenNGC (CC BY-SA 4.0), pinned to v20260501.

Usage: make-messier.py

Rows with a Messier number in NGC.csv and addendum.csv (M40, M45). Coordinates are J2000 degrees,
axes arcminutes, position angle degrees east of north; magnitude is V, else B. Each object carries the
id of its Library page (link.messier in pages/deep-sky-*.json).

M102: OpenNGC lists it as a duplicate observation of M101 (addendum type "Dup"), so it is left out
and the file has 109 objects. The Library page for M102 keeps its own account (probably NGC 5866).
"""
import csv
import io
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Packages/MoonriseKit/Sources/SkyRenderer/Resources"
PAGES = ROOT / "Packages/MoonriseKit/Sources/Library/Resources/pages"
VERSION = "v20260501"
BASE = f"https://raw.githubusercontent.com/mattiaverga/OpenNGC/{VERSION}/database_files"


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8")


def sexagesimal(s, hours):
    sign = -1 if s.startswith("-") else 1
    d, m, sec = (float(x) for x in s.lstrip("+-").split(":"))
    v = sign * (d + m / 60 + sec / 3600)
    return v * 15 if hours else v


def number(s):
    return float(s) if s.strip() else None


def main():
    pages = {}
    for f in sorted(PAGES.glob("deep-sky-*.json")):
        for p in json.loads(f.read_text()):
            pages[p["link"]["messier"]] = p["id"]

    out = {}
    for name in ("NGC.csv", "addendum.csv"):
        for row in csv.DictReader(io.StringIO(fetch(f"{BASE}/{name}")), delimiter=";"):
            if not row["M"] or row["Type"] == "Dup":
                continue
            m = int(row["M"])
            assert m not in out, m
            o = {
                "messier": m,
                "type": row["Type"],
                "ra": round(sexagesimal(row["RA"], True), 5),
                "dec": round(sexagesimal(row["Dec"], False), 5),
                "magnitude": number(row["V-Mag"]) if row["V-Mag"].strip() else number(row["B-Mag"]),
                "majorAxis": number(row["MajAx"]),
                "minorAxis": number(row["MinAx"]),
                "positionAngle": number(row["PosAng"]),
                "page": pages[m],
            }
            out[m] = {k: v for k, v in o.items() if v is not None}

    assert sorted(out) == [m for m in range(1, 111) if m != 102], sorted(set(range(1, 111)) - set(out))
    (RES / "messier.json").write_text(json.dumps([out[m] for m in sorted(out)], ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
