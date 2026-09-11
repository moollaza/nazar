#!/usr/bin/env python3
"""Fail when a stated "N+ services" figure drifts from the catalog size.

Reads the real count from Resources/catalog.json, finds every "N+" figure of
1,000 or more in the website, README, and OG image script, and fails if any
figure exceeds the real count or trails it by more than MAX_LAG. Also checks
the no-JS category count fallback in website/index.html.

--fix rewrites every figure to the real count rounded down to the nearest 100
and sets the category fallback. Run `npm run build:og` afterwards.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "catalog.json"
INDEX = ROOT / "website" / "index.html"
SOURCES = [
    ROOT / "README.md",
    ROOT / "website" / "scripts" / "generate-og-image.mjs",
    *sorted((ROOT / "website").glob("*.html")),
]
MAX_LAG = 200
ROUND_TO = 100
FIX_HINT = "run: python3 scripts/check-service-count.py --fix && npm run build:og"

# "1,800+" or "1800+". Four or more digits skips version floors like "macOS 14+".
FIGURE = re.compile(r"(?<![\d,])(\d{1,3}(?:,\d{3})+|\d{4,})\+")
CATEGORY_FALLBACK = re.compile(r'(<span id="catalog-cat-count">)(\d+)(</span>)')


def fix(real: int, categories: int) -> int:
    figure = f"{real // ROUND_TO * ROUND_TO:,}+"
    for path in SOURCES:
        text = path.read_text()
        new = FIGURE.sub(figure, text)
        if path == INDEX:
            new = CATEGORY_FALLBACK.sub(rf"\g<1>{categories}\g<3>", new)
        if new != text:
            path.write_text(new)
            print(f"updated {path.relative_to(ROOT)}")
    print(f"Figures set to {figure}, category fallback to {categories}. Now run: npm run build:og")
    return 0


def check(real: int, categories: int) -> int:
    found = 0
    errors = []
    for path in SOURCES:
        rel = path.relative_to(ROOT)
        for lineno, line in enumerate(path.read_text().splitlines(), start=1):
            for match in FIGURE.finditer(line):
                found += 1
                stated = int(match.group(1).replace(",", ""))
                where = f"{rel}:{lineno}: {match.group(0)}"
                if stated > real:
                    errors.append(f"{where} overstates the catalog ({real})")
                elif real - stated > MAX_LAG:
                    errors.append(f"{where} is {real - stated} below the catalog ({real}); max lag is {MAX_LAG}")

    if found == 0:
        errors.append("no N+ service figures found; update FIGURE or SOURCES in this script")

    fallback = CATEGORY_FALLBACK.search(INDEX.read_text())
    if not fallback:
        errors.append("website/index.html: #catalog-cat-count fallback not found")
    elif int(fallback.group(2)) != categories:
        errors.append(f"website/index.html: #catalog-cat-count fallback is {fallback.group(2)}, catalog has {categories} categories")

    for error in errors:
        print(f"::error::{error}")
    if errors:
        print(f"To fix, {FIX_HINT}")
        return 1
    print(f"OK: {found} figures within {MAX_LAG} of {real}, {categories} categories")
    return 0


def main() -> int:
    catalog = json.loads(CATALOG.read_text())
    real = len(catalog)
    categories = len({entry["category"] for entry in catalog})
    print(f"Resources/catalog.json: {real} services, {categories} categories")
    if sys.argv[1:] == ["--fix"]:
        return fix(real, categories)
    if sys.argv[1:]:
        print("usage: check-service-count.py [--fix]", file=sys.stderr)
        return 2
    return check(real, categories)


if __name__ == "__main__":
    sys.exit(main())
