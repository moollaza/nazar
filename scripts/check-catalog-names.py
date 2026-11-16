#!/usr/bin/env python3
"""Flag catalog names that look like status page titles, not product names.

Discovery copies a page's <title> or Statuspage `page.name`, so names arrive as
"Cohere Status Page", "Server Status | Nexcess" or "Braze, Inc.". The app shows
the name in the menu bar panel and builds the fallback icon's initials from it.

Usage:
  python3 scripts/check-catalog-names.py          # exit 1 if any name is flagged
  python3 scripts/check-catalog-names.py --json   # machine-readable list
"""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Resources" / "catalog.json"

# Real product names that a rule would otherwise flag.
ALLOWED = {
    "Atlassian Statuspage",  # the product is called Statuspage
    "Statusbrew",
    "StatusCake",
    "Incident IQ",
}

RULES = [
    ("separator", re.compile(r"\s[-–—|:·•]\s|^\s|\s$|\s{2}")),
    ("status-page words", re.compile(
        r"\b(status(es)?|statuspage|page|operational|updates|incidents?|uptime)\b"
        r"|[a-z]status\b|^status\b",
        re.I,
    )),
    ("legal suffix", re.compile(
        r",?\s+(inc|llc|ltd|limited|gmbh|corp|corporation|plc|pty|s\.?a|ag|bv|oy|ab|as)\.?$",
        re.I,
    )),
    ("generic suffix", re.compile(
        r"\s(system|system health|prod|production|external|public|customer facing|site)$"
        r"|^[\w.&'-]+ services?$",
        re.I,
    )),
]


def problems(name):
    if name in ALLOWED:
        return []
    return [label for label, rx in RULES if rx.search(name)]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true", help="print flagged entries as JSON")
    parser.add_argument("--catalog", type=Path, default=CATALOG, help="catalog file to check")
    args = parser.parse_args()

    entries = json.loads(args.catalog.read_text())
    counts = Counter(e["name"].casefold() for e in entries)
    flagged = [
        {"id": e["id"], "name": e["name"], "problems": p}
        for e in entries
        if (p := problems(e["name"]) + (["duplicate name"] if counts[e["name"].casefold()] > 1 else []))
    ]

    if args.json:
        print(json.dumps(flagged, indent=2))
    elif flagged:
        print(f"{len(flagged)} catalog names look like page titles, not product names:")
        for f in flagged:
            print(f"  {f['id']}: {f['name']!r} ({', '.join(f['problems'])})")
        print("Use the product name. If the name is correct, add it to ALLOWED in this script.")
    else:
        print(f"All {len(entries)} catalog names pass.")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
