#!/usr/bin/env python3
"""Render audit failures as grouped markdown.

Used by `.github/workflows/catalog-audit.yml` for both the job summary and
the `catalog-audit` issue body. Failures are grouped by the kind the audit
assigned them, most actionable first, because a 404 and a WAF challenge call
for completely different responses and a single flat table hides that.

Run: python3 scripts/report-failures.py failures.json [--ids] [--confident-only]
"""

import argparse
import importlib.util
import json
import pathlib

# Reuse the audit's own vocabulary so the report and the audit cannot drift.
# audit-catalog.py has a hyphen in its name, so it needs loading by path.
_AUDIT = pathlib.Path(__file__).resolve().parent / "audit-catalog.py"
_spec = importlib.util.spec_from_file_location("audit_catalog", _AUDIT)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

KIND_ORDER = _mod.KIND_ORDER
KIND_LABEL = _mod.KIND_LABEL
KIND_BLOCKED = _mod.KIND_BLOCKED
KIND_UNREACHABLE = _mod.KIND_UNREACHABLE
CONFIDENT_KINDS = _mod.CONFIDENT_KINDS

CI_403_NOTE = (
    "> A 401/403 seen only from CI is as likely to be the GitHub Actions egress range "
    "hitting a shared WAF as it is a real catalog problem — `jane`, `veeps` and "
    "`site-availability` have all 403'd here while answering 200 from elsewhere. "
    "Re-check these from another network before changing the entry."
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="failures.json written by audit-catalog.py --json")
    ap.add_argument("--ids", action="store_true", help="include the catalog id in the service column")
    ap.add_argument("--confident-only", action="store_true",
                    help="report only gone/malformed entries — the ones that are a catalog defect")
    args = ap.parse_args()

    with open(args.path) as f:
        failures = json.load(f)

    if args.confident_only:
        failures = [e for e in failures if (e.get("kind") or KIND_UNREACHABLE) in CONFIDENT_KINDS]

    grouped = {}
    for entry in failures:
        grouped.setdefault(entry.get("kind") or KIND_UNREACHABLE, []).append(entry)

    for kind in KIND_ORDER + sorted(set(grouped) - set(KIND_ORDER)):
        group = grouped.get(kind)
        if not group:
            continue
        print(f"#### {KIND_LABEL.get(kind, kind)}")
        print()
        print("| Service | Type | Reason | URL |")
        print("|---|---|---|---|")
        for e in group:
            name = f"`{e['id']}` {e['name']}" if args.ids else e["name"]
            print(f"| {name} | {e['type']} | {e['reason']} | {e['base_url']} |")
        print()
        if kind == KIND_BLOCKED:
            print(CI_403_NOTE)
            print()


if __name__ == "__main__":
    main()
