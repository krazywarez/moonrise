#!/usr/bin/env python3
"""Check Library pages: JSON shape, and that every source and image URL resolves.

Usage: scripts/check-library.py [--offline]
"""
import json
import pathlib
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PAGES = pathlib.Path(__file__).resolve().parent.parent / "Packages/MoonriseKit/Sources/Library/Resources/pages"
UA = {"User-Agent": "moonrise-library-check (sh.krz.moonrise)"}


def status(url, image=False):
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method, headers=UA)
            with urllib.request.urlopen(req, timeout=20) as r:
                kind = r.headers.get("content-type", "")
                if image and not kind.startswith("image/"):
                    return f"{r.status} {kind}"
                return r.status
        except Exception as e:
            err = getattr(e, "code", None) or type(e).__name__
    return err


def main():
    offline = "--offline" in sys.argv
    pages, problems = [], []
    for f in sorted(PAGES.glob("*.json")):
        for p in json.loads(f.read_text()):
            pages.append((f.name, p))
    print(f"{len(pages)} pages in {len(list(PAGES.glob('*.json')))} files")
    if offline:
        return 0
    checks = []
    for name, p in pages:
        for s in p.get("sources", []):
            checks.append((p["id"], "source", s["url"], False))
        if p.get("image"):
            checks.append((p["id"], "image", p["image"]["url"], True))
            checks.append((p["id"], "image page", p["image"]["page"], False))
    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(lambda c: (c, status(c[2], c[3])), checks))
    for (pid, kind, url, _), st in results:
        # loc.gov item pages send scripts to a bot check (403); the items exist.
        if st == 403 and kind == "image page" and url.startswith("https://www.loc.gov/item/"):
            continue
        if st != 200:
            problems.append(f"{pid}: {kind} {st} {url}")
    print(f"{len(checks)} URLs checked, {len(problems)} problems")
    for line in problems:
        print("  " + line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
