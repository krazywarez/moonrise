#!/usr/bin/env python3
"""Builds SkyRenderer/Resources/skycultures.json from Stellarium sky cultures (CC BY-SA only).

Usage: make-skycultures.py HIP_TSV

HIP_TSV is VizieR I/239/hip_main with columns HIP, RAICRS, DEICRS, Vmag (Vmag < 7.2):
https://vizier.cds.unistra.fr/viz-bin/asu-tsv?-source=I/239/hip_main&-out=HIP,RAICRS,DEICRS,Vmag&Vmag=%3C7.2&-out.max=unlimited

Stellarium lines use Hipparcos numbers; the app's catalogue is the Bright Star Catalogue (HR).
Each HIP star is matched to the BSC star within 0.05 degrees. Lines are split where a star has no match
(fainter than the BSC's limit), and segments with fewer than two stars are dropped.
"""
import json
import math
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Packages/MoonriseKit/Sources/SkyRenderer/Resources"
BASE = "https://raw.githubusercontent.com/Stellarium/stellarium-skycultures/master"

# id, display name. All CC BY-SA in their description.md as of 2026-10-18.
CULTURES = [
    ("chinese", "Chinese"),
    ("indian", "Indian (Vedic)"),
    ("mongolian", "Mongolian"),
    ("japanese_moon_stations", "Japanese moon stations"),
    ("hawaiian_starlines", "Hawaiian"),
    ("maori", "Māori"),
    ("tongan", "Tongan"),
    ("boorong", "Boorong (Australia)"),
    ("sami", "Sámi"),
    ("norse", "Norse"),
]


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8")


def license_section(md):
    out, on = [], False
    for line in md.splitlines():
        if line.startswith("#"):
            on = "licen" in line.lower()
            continue
        if on and line.strip():
            out.append(line.strip())
    return " ".join(out)


def load_hip(path):
    """HIP number -> (RA, Dec, Vmag) from the VizieR TSV."""
    hip = {}
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if len(p) == 4 and p[0].strip().isdigit() and p[1].strip() and p[2].strip():
            hip[int(p[0])] = (float(p[1]), float(p[2]), float(p[3] or 99))
    return hip


def hr_matcher(hip, bsc):
    """A function from a HIP number to the BSC (HR) star within 0.05 degrees of it, or None."""
    cells = {}
    for row in bsc:
        cells.setdefault((int(row[2])), []).append(row)

    def hr_for(h):
        if h not in hip:
            return None
        ra, dec, _ = hip[h]
        best = None
        for d in (int(dec) - 1, int(dec), int(dec) + 1):
            for row in cells.get(d, []):
                dra = (row[1] - ra + 180) % 360 - 180
                sep = math.hypot(dra * math.cos(math.radians(dec)), row[2] - dec)
                if sep < 0.05 and (best is None or sep < best[0]):
                    best = (sep, int(row[0]))
        return best[1] if best else None

    return hr_for


def segments(line, hr_for):
    """A Stellarium line as runs of matched HR stars, split at stars without a match."""
    out, current = [], []
    for h in line:
        hr = hr_for(h) if isinstance(h, int) else None
        if hr is None:
            if len(current) > 1:
                out.append(current)
            current = []
        else:
            current.append(hr)
    if len(current) > 1:
        out.append(current)
    return out


def constellation(c, hr_for):
    """One figure for the app, or None when none of its lines survive matching."""
    lines = [s for line in c.get("lines", []) for s in segments(line, hr_for)]
    if not lines:
        return None
    cn = c.get("common_name", {})
    entry = {"name": cn.get("english") or cn.get("native") or c["id"], "lines": lines}
    if cn.get("native") and cn.get("native") != entry["name"]:
        entry["native"] = cn["native"]
    return entry


def culture(cid, name, hr_for):
    index = json.loads(fetch(f"{BASE}/{cid}/index.json"))
    lic = license_section(fetch(f"{BASE}/{cid}/description.md"))
    assert "BY-SA" in lic.replace("-BY SA", "BY-SA").replace("BY SA", "BY-SA"), (cid, lic)
    figures = [f for f in (constellation(c, hr_for) for c in index.get("constellations", [])) if f]
    print(f"{cid}: {len(figures)} of {len(index.get('constellations', []))} figures", file=sys.stderr)
    return {
        "id": cid, "name": name, "region": index.get("region", ""),
        "licence": lic, "source": f"https://github.com/Stellarium/stellarium-skycultures/tree/master/{cid}",
        "constellations": figures,
    }


def main():
    hr_for = hr_matcher(load_hip(sys.argv[1]), json.load(open(RES / "bsc5.json")))
    out = [culture(cid, name, hr_for) for cid, name in CULTURES]
    (RES / "skycultures.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
