#!/usr/bin/env python3
"""Builds SkyRenderer/Resources/ngc.json from OpenNGC (CC BY-SA 4.0), pinned to v20260501.

Usage: make-ngc.py

NGC and IC objects without a Messier number (those are in messier.json), of the deep-sky types the sky chart
draws, with V or B of 11 or brighter; the magnitude kept is the brighter of the two, since some V values in
OpenNGC are far too faint (NGC 253: V 11.11, B 7.94). Same fields as messier.json, with "designation" ("NGC 7000",
"IC 434") instead of a Messier number and Library page.
"""
import csv
import io
import json
import re

import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location("make_messier", Path(__file__).with_name("make-messier.py"))
messier = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(messier)

TYPES = {"G", "OCl", "GCl", "PN", "Neb", "HII", "RfN", "EmN", "Cl+N", "SNR"}
LIMIT = 11.0


def designation(name):
    m = re.fullmatch(r"(NGC|IC)0*(\d+)(.*)", name)
    return f"{m[1]} {m[2]}{m[3]}" if m else name


def main():
    out = []
    for row in csv.DictReader(io.StringIO(messier.fetch(f"{messier.BASE}/NGC.csv")), delimiter=";"):
        if row["M"] or row["Type"] not in TYPES:
            continue
        mags = [m for m in (messier.number(row["V-Mag"]), messier.number(row["B-Mag"])) if m is not None]
        mag = min(mags) if mags else None
        if mag is None or mag > LIMIT:
            continue
        o = {
            "messier": 0,
            "designation": designation(row["Name"]),
            "type": row["Type"],
            "ra": round(messier.sexagesimal(row["RA"], True), 5),
            "dec": round(messier.sexagesimal(row["Dec"], False), 5),
            "magnitude": mag,
            "majorAxis": messier.number(row["MajAx"]),
            "minorAxis": messier.number(row["MinAx"]),
            "positionAngle": messier.number(row["PosAng"]),
            "page": "",
        }
        out.append({k: v for k, v in o.items() if v is not None})
    out.sort(key=lambda o: o["magnitude"])
    (messier.RES / "ngc.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(len(out), "objects")


if __name__ == "__main__":
    main()
