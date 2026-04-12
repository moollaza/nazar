#!/usr/bin/env python3
"""Merge URLs from aggregator sources, deduplicate against existing catalog,
and verify new candidates have working /api/v2/summary.json endpoints.

Run: python3 scripts/merge-and-verify.py [--limit N] [--delay S]
"""

import json
import sys
import urllib.request
import urllib.error
import ssl
import time
import argparse
from pathlib import Path

HEADERS = {"User-Agent": "StatusMonitor-Discovery/1.0"}


def load_existing_catalog():
    with open("Resources/catalog.json") as f:
        catalog = json.load(f)
    urls = {e["base_url"].rstrip("/").lower() for e in catalog}
    names = {e["name"].lower() for e in catalog}
    return catalog, urls, names


def load_source(path):
    if not Path(path).exists():
        return []
    with open(path) as f:
        return json.load(f)


def normalize_url(url):
    return url.rstrip("/").lower()


def verify_url(url, ctx, timeout=12):
    api_url = url.rstrip("/") + "/api/v2/summary.json"
    try:
        req = urllib.request.Request(api_url, headers=HEADERS)
        resp = urllib.request.urlopen(req, timeout=timeout, context=ctx)
        data = resp.read()
        j = json.loads(data)
        if "page" not in j or "status" not in j:
            return None
        has_incidents = bool(j.get("incidents"))
        has_scheduled = bool(j.get("scheduled_maintenances"))
        platform = "atlassian" if (has_incidents or has_scheduled) else "incident.io"
        return {
            "page_name": j.get("page", {}).get("name", ""),
            "indicator": j.get("status", {}).get("indicator", "?"),
            "components": len(j.get("components", [])),
            "platform": platform,
        }
    except Exception:
        return None


def make_id(name):
    slug = name.lower().strip()
    for ch in [".", "/", "(", ")", "&", "'", ","]:
        slug = slug.replace(ch, "")
    slug = slug.replace(" ", "-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="Max candidates to verify (0=all)")
    parser.add_argument("--delay", type=float, default=0.3, help="Delay between requests")
    parser.add_argument("--output", default="scripts/new-verified.json", help="Output file")
    args = parser.parse_args()

    ctx = ssl.create_default_context()
    catalog, existing_urls, existing_names = load_existing_catalog()

    # Load all sources
    sources = {}
    for name, path in [
        ("awesome-status", "scripts/awesome-status-urls.json"),
        ("statusphere", "scripts/statusphere-urls.json"),
    ]:
        data = load_source(path)
        sources[name] = data
        print(f"Loaded {len(data)} URLs from {name}")

    # Merge and deduplicate
    seen_urls = set()
    candidates = []
    for source_name, entries in sources.items():
        for entry in entries:
            url = normalize_url(entry["url"])
            if url in seen_urls or url in existing_urls:
                continue
            seen_urls.add(url)
            candidates.append({"name": entry["name"], "url": entry["url"], "source": source_name})

    print(f"\nTotal unique candidates (after dedup): {len(candidates)}")
    print(f"Already in catalog: {len(existing_urls)}")

    if args.limit > 0:
        candidates = candidates[:args.limit]
        print(f"Limited to first {args.limit}")

    # Verify
    verified = []
    failed = 0
    print(f"\nVerifying {len(candidates)} candidates...\n")

    for i, cand in enumerate(candidates):
        result = verify_url(cand["url"], ctx)
        if result:
            entry = {
                "id": make_id(result["page_name"] or cand["name"]),
                "name": result["page_name"] or cand["name"],
                "base_url": cand["url"].rstrip("/"),
                "type": "statuspage",
                "category": "Uncategorized",
                "platform": result["platform"],
            }
            verified.append(entry)
            if (i + 1) % 50 == 0 or len(verified) % 25 == 0:
                print(f"  [{i+1}/{len(candidates)}] OK: {entry['name']:30s} components={result['components']}")
        else:
            failed += 1

        if i < len(candidates) - 1:
            time.sleep(args.delay)

        # Progress every 100
        if (i + 1) % 100 == 0:
            print(f"  Progress: {i+1}/{len(candidates)} checked, {len(verified)} verified, {failed} failed")

    # Deduplicate verified by id
    seen_ids = {e["id"] for e in catalog}
    unique_verified = []
    for v in verified:
        if v["id"] not in seen_ids:
            seen_ids.add(v["id"])
            unique_verified.append(v)

    print(f"\n{'=' * 70}")
    print(f"VERIFIED: {len(unique_verified)} new services")
    print(f"FAILED: {failed}")
    print(f"ALREADY IN CATALOG: {len(verified) - len(unique_verified)} (by ID)")

    if unique_verified:
        with open(args.output, "w") as f:
            json.dump(unique_verified, f, indent=2, ensure_ascii=False)
        print(f"\nNew entries written to {args.output}")
        print(f"Run 'python3 scripts/audit-catalog.py' after merging to verify all entries.")

    # Platform breakdown
    plats = {}
    for v in unique_verified:
        plats[v["platform"]] = plats.get(v["platform"], 0) + 1
    if plats:
        print(f"\nPlatform breakdown:")
        for k, v in sorted(plats.items(), key=lambda x: -x[1]):
            print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
