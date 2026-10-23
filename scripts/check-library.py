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
BLOCKS_SCRIPTS = ("https://www.loc.gov/item/", "https://www.jpl.nasa.gov/news/press_kits/", "https://rocketlabcorp.com/", "https://www.blueorigin.com/", "https://blueorigin.com/")
# Launch Library 2 allows 15 anonymous requests an hour; its pages are not checked here.
SKIP = ("https://ll.thespacedevs.com/",)


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


def load_pages():
    """(file name, page) for every Library page, files in name order."""
    return [(f.name, p) for f in sorted(PAGES.glob("*.json")) for p in json.loads(f.read_text())]


def url_checks(pages):
    """(page id, what, URL, must be an image) for each source and image a page cites."""
    checks = []
    for _, p in pages:
        for s in p.get("sources", []):
            if not s["url"].startswith(SKIP):
                checks.append((p["id"], "source", s["url"], False))
        if p.get("image"):
            checks.append((p["id"], "image", p["image"]["url"], True))
            checks.append((p["id"], "image page", p["image"]["page"], False))
    return checks


def problem(check, st):
    """The report line for a failed check, or None when it passed."""
    pid, kind, url, _ = check
    # Sites that refuse scripts (403/429) but load in a browser.
    if st in (403, 429) and any(url.startswith(p) for p in BLOCKS_SCRIPTS):
        return None
    return None if st == 200 else f"{pid}: {kind} {st} {url}"


def main():
    pages = load_pages()
    print(f"{len(pages)} pages in {len(list(PAGES.glob('*.json')))} files")
    if "--offline" in sys.argv:
        return 0
    checks = url_checks(pages)
    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(lambda c: (c, status(c[2], c[3])), checks))
    problems = [line for line in (problem(c, st) for c, st in results) if line]
    print(f"{len(checks)} URLs checked, {len(problems)} problems")
    for line in problems:
        print("  " + line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
