#!/usr/bin/env python3
"""Cloud climatology grids for eclipse dates, from MODIS Terra daytime cloud fraction (NASA GIBS).

Terra passes at about 10:30 local time. For each MM-DD given, averages the 1° cloud fraction over days
-6, -3, 0, +3 and +6 around that date for 2015-2024 (50 images), and writes App/Clouds/clouds-MMDD.bin:
360 x 180 bytes, rows from 90° N to 90° S, columns from 180° W to 180° E, each the mean percentage
(0-100) or 255 where no day had data. One request a second.

    scripts/make-clouds.py 08-02 02-06
"""
import datetime
import struct
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

UA = "Moonrise/5.8.2 (sh.krz.moonrise; root@krz.sh)"
LAYER = "MODIS_Terra_Cloud_Fraction_Day"
COLORMAP = "https://gibs.earthdata.nasa.gov/colormaps/v1.3/MODIS_Cloud_Fraction.xml"
WMS = ("https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0"
       "&LAYERS={layer}&CRS=EPSG:4326&BBOX=-90,-180,90,180&WIDTH=360&HEIGHT=180&FORMAT=image/png&TIME={day}")
YEARS = range(2015, 2025)
OFFSETS = (-6, -3, 0, 3, 6)


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=60) as r:
        return r.read()


def palette():
    """RGB to percentage, from the GIBS colour map; no-data entries are left out."""
    out = {}
    for e in ET.fromstring(get(COLORMAP)).iter():
        if e.tag.endswith("ColorMapEntry") and e.get("nodata") != "true":
            out[tuple(int(v) for v in e.get("rgb").split(","))] = int(float(e.get("value")))
    return out


def rgba(png):
    """Pixels of an 8-bit RGBA, non-interlaced PNG, as rows of (r, g, b, a)."""
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    pos, data, width, height = 8, b"", 0, 0
    while pos < len(png):
        length, kind = struct.unpack(">I4s", png[pos:pos + 8])
        body = png[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and color == 6, (depth, color)
        elif kind == b"IDAT":
            data += body
        pos += 12 + length
    raw, stride, rows, prev = zlib.decompress(data), width * 4, [], bytearray(width * 4)
    for y in range(height):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b, c = prev[i], prev[i - 4] if i >= 4 else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * 4:x * 4 + 4]) for x in range(width)])
        prev = line
    return rows


def grid(month_day, colors):
    month, day = (int(v) for v in month_day.split("-"))
    total, count = [0] * 64800, [0] * 64800
    for year in YEARS:
        for offset in OFFSETS:
            d = datetime.date(year, month, day) + datetime.timedelta(days=offset)
            for y, row in enumerate(rgba(get(WMS.format(layer=LAYER, day=d.isoformat())))):
                for x, (r, g, b, a) in enumerate(row):
                    if a and (r, g, b) in colors:
                        total[y * 360 + x] += colors[(r, g, b)]
                        count[y * 360 + x] += 1
            time.sleep(1)
    return bytes(round(t / n) if n else 255 for t, n in zip(total, count))


if __name__ == "__main__":
    colors = palette()
    out = Path(__file__).resolve().parent.parent / "App" / "Clouds"
    out.mkdir(exist_ok=True)
    for md in sys.argv[1:]:
        g = grid(md, colors)
        (out / f"clouds-{md.replace('-', '')}.bin").write_bytes(g)
        print(md, "cells with data:", sum(v != 255 for v in g))
