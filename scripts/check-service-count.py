#!/usr/bin/env python3
"""Fail when a stated "N+ services" figure drifts from the catalog size.

Reads the real count from Resources/catalog.json, finds every "N+" figure of
1,000 or more in the website, README, and OG image script, and fails if any
figure exceeds the real count or trails it by more than MAX_LAG.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "catalog.json"
SOURCES = [
    ROOT / "README.md",
    ROOT / "website" / "scripts" / "generate-og-image.mjs",
    *sorted((ROOT / "website").glob("*.html")),
]
MAX_LAG = 200

# "1,800+" or "1800+". Four or more digits skips version floors like "macOS 14+".
FIGURE = re.compile(r"(?<![\d,])(\d{1,3}(?:,\d{3})+|\d{4,})\+")


def main() -> int:
    real = len(json.loads(CATALOG.read_text()))
    print(f"Resources/catalog.json: {real} services")

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

    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"OK: {found} figures within {MAX_LAG} of {real}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
