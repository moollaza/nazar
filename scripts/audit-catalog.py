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
        else:
            url = base_url

        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Nazar-Audit/1.0"})
            resp = urllib.request.urlopen(req, timeout=15, context=ctx)
            data = resp.read()

            # Must be valid JSON
            j = json.loads(data)

            # Must have expected top-level keys
            if entry["type"] == "statuspage":
                if "page" not in j or "status" not in j:
                    failed.append((name, "Missing page/status keys in JSON"))
                    print(f"FAIL  {name:30s}  Missing expected JSON structure")
                    continue

            passed += 1
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
