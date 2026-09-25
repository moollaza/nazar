#!/usr/bin/env python3
"""Audit catalog.json — verify every service endpoint still works.

Run: python3 scripts/audit-catalog.py [--workers N] [--json PATH] [--quiet]
Exit code: 0 if all pass, 1 if any fail.

Entries are checked concurrently, and every failure is retried serially before
being reported. A parallel sweep across ~1,900 third-party hosts always turns
up hosts that simply throttled us; the retry pass is what separates "this
service is gone" from "we asked too fast".
"""

import argparse
import json
import pathlib
import ssl
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

CATALOG = "Resources/catalog.json"
VERSION_CONFIG = "Config/Version.xcconfig"


def app_version(default="1.0"):
    """Read MARKETING_VERSION, the same value the app stamps into its User-Agent."""
    try:
        for line in pathlib.Path(VERSION_CONFIG).read_text().splitlines():
            if line.strip().startswith("MARKETING_VERSION"):
                return line.split("=", 1)[1].split("//")[0].strip()
    except OSError:
        pass
    return default


# Identical to the app's User-Agent (Services/StatusManager.swift). The audit
# only predicts what the app will see if it asks the way the app asks.
HEADERS = {"User-Agent": f"Nazar/{app_version()} (+https://usenazar.com)"}


def endpoint(entry):
    base = entry["base_url"].rstrip("/")
    return {
        "statuspage": base + "/api/v2/summary.json",
        "betterstack": base + "/index.json",
        "instatus": base + "/summary.json",
        "datadog": base + "/config.json",
    }.get(entry["type"], base)


def check(entry, ctx, timeout=20):
    """Return (ok, detail): a status string when ok, otherwise a reason."""
    try:
        resp = urllib.request.urlopen(
            urllib.request.Request(endpoint(entry), headers=HEADERS), timeout=timeout, context=ctx
        )
        data = resp.read()

        # RSS/Atom entries serve a feed, not JSON.
        if entry["type"] == "rss":
            head = data[:400].lstrip()
            if head.startswith(b"<?xml") or b"<rss" in head or b"<feed" in head:
                return True, "feed"
            return False, "Response is not an RSS/Atom feed"

        j = json.loads(data)

        if entry["type"] == "statuspage":
            # Reject two lookalikes: pages that nest `status` inside `page`
            # (Instatus and similar), and unclaimed pages returning nulls.
            if not isinstance(j.get("page"), dict) or not isinstance(j.get("status"), dict):
                return False, "Missing or null page/status in JSON"
            return True, f"indicator={j.get('status', {}).get('indicator', '?')}"

        if entry["type"] == "instatus":
            # Instatus nests `status` inside `page`, unlike Atlassian.
            page = j.get("page")
            if not isinstance(page, dict) or not isinstance(page.get("status"), str):
                return False, "Missing page.status in Instatus JSON"
            return True, f"status={page['status']}"

        if entry["type"] == "datadog":
            # Datadog pages carry no page-level rollup — `components` is the
            # status signal, and its absence means this is not a Datadog page.
            if not isinstance(j.get("components"), list):
                return False, "Missing components array in Datadog config.json"
            statuses = {c.get("status") for c in j["components"]}
            return True, f"components={len(j['components'])} statuses={','.join(sorted(s for s in statuses if s))}"

        if entry["type"] == "betterstack":
            if "data" not in j or "attributes" not in j.get("data", {}):
                return False, "Missing data.attributes in JSON:API document"
            return True, f"aggregate_state={j['data']['attributes'].get('aggregate_state', '?')}"

        return False, f"Unknown entry type: {entry['type']}"

    except json.JSONDecodeError:
        return False, "Response is not JSON (likely HTML)"
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001 — any transport failure is a failure
        return False, str(e)[:80]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=12, help="concurrent requests (default 12)")
    ap.add_argument("--json", dest="json_out", help="write failures to this path as JSON")
    ap.add_argument("--quiet", action="store_true", help="print only failures and the summary")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)

    ctx = ssl.create_default_context()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda e: (e, *check(e, ctx)), catalog))

    if not args.quiet:
        for entry, ok, detail in results:
            if ok:
                print(f"OK    {entry['name']:30s}  {detail}")

    suspects = [entry for entry, ok, _ in results if not ok]

    failed = []
    if suspects:
        print(f"\nRetrying {len(suspects)} failures serially...", flush=True)
        for entry in suspects:
            time.sleep(0.4)
            ok, detail = check(entry, ctx, timeout=30)
            if ok:
                print(f"OK    {entry['name']:30s}  {detail} (recovered on retry)")
            else:
                print(f"FAIL  {entry['name']:30s}  {detail}")
                failed.append((entry, detail))

    passed = len(catalog) - len(failed)
    print(f"\n{'=' * 60}")
    print(f"PASSED: {passed}/{len(catalog)}")

    if args.json_out:
        with open(args.json_out, "w") as f:
            json.dump(
                [
                    {
                        "id": e["id"],
                        "name": e["name"],
                        "base_url": e["base_url"],
                        "type": e["type"],
                        "reason": reason,
                    }
                    for e, reason in failed
                ],
                f,
                indent=1,
            )

    if failed:
        print(f"FAILED: {len(failed)}")
        for entry, reason in failed:
            print(f"  - {entry['name']}: {reason}")
        sys.exit(1)

    print("All services verified.")
    sys.exit(0)


if __name__ == "__main__":
    main()
