#!/usr/bin/env python3
"""Audit catalog.json — verify every service URL returns valid JSON.

Run: python3 scripts/audit-catalog.py
Exit code: 0 if all pass, 1 if any fail.
"""

import json
import sys
import urllib.request
import urllib.error
import ssl

def main():
    with open("Resources/catalog.json") as f:
        catalog = json.load(f)

    ctx = ssl.create_default_context()
    passed = 0
    failed = []

    for entry in catalog:
        name = entry["name"]
        base_url = entry["base_url"].rstrip("/")

        if entry["type"] == "statuspage":
            url = f"{base_url}/api/v2/summary.json"
        elif entry["type"] == "betterstack":
            url = f"{base_url}/index.json"
        else:
            url = base_url

        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Nazar-Audit/1.0"})
            resp = urllib.request.urlopen(req, timeout=15, context=ctx)
            data = resp.read()

            # RSS/Atom entries serve a feed, not JSON.
            if entry["type"] == "rss":
                head = data[:400].lstrip()
                if head.startswith(b"<?xml") or b"<rss" in head or b"<feed" in head:
                    passed += 1
                    print(f"OK    {name:30s}  feed")
                else:
                    failed.append((name, "Response is not an RSS/Atom feed"))
                    print(f"FAIL  {name:30s}  NOT A FEED")
                continue

            # Must be valid JSON
            j = json.loads(data)

            # Must have expected top-level keys
            if entry["type"] == "statuspage":
                # Reject two lookalikes: pages that nest `status` inside `page`
                # (Instatus and similar), and unclaimed pages that return nulls.
                if not isinstance(j.get("page"), dict) or not isinstance(j.get("status"), dict):
                    failed.append((name, "Missing or null page/status in JSON"))
                    print(f"FAIL  {name:30s}  Missing expected JSON structure")
                    continue
            elif entry["type"] == "betterstack":
                if "data" not in j or "attributes" not in j.get("data", {}):
                    failed.append((name, "Missing data.attributes in JSON:API document"))
                    print(f"FAIL  {name:30s}  Missing expected JSON structure")
                    continue

            passed += 1
            if entry["type"] == "betterstack":
                state = j.get("data", {}).get("attributes", {}).get("aggregate_state", "?")
                print(f"OK    {name:30s}  aggregate_state={state}")
            else:
                indicator = j.get("status", {}).get("indicator", "?")
                print(f"OK    {name:30s}  indicator={indicator}")

        except json.JSONDecodeError:
            failed.append((name, "Response is not JSON (likely HTML)"))
            print(f"FAIL  {name:30s}  NOT JSON")
        except urllib.error.HTTPError as e:
            failed.append((name, f"HTTP {e.code}"))
            print(f"FAIL  {name:30s}  HTTP {e.code}")
        except Exception as e:
            failed.append((name, str(e)[:80]))
            print(f"FAIL  {name:30s}  {str(e)[:80]}")

    print(f"\n{'=' * 60}")
    print(f"PASSED: {passed}/{len(catalog)}")
    if failed:
        print(f"FAILED: {len(failed)}")
        for name, reason in failed:
            print(f"  - {name}: {reason}")
        sys.exit(1)
    else:
        print("All services verified.")
        sys.exit(0)

if __name__ == "__main__":
    main()
