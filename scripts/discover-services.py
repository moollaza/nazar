#!/usr/bin/env python3
"""Discover and verify status pages for candidate services.

Given a list of candidate services (name + domain), tries common status page URL
patterns, verifies JSON API works, detects platform, and outputs catalog entries.

Run: python3 scripts/discover-services.py
     python3 scripts/discover-services.py --candidates candidates.json
     python3 scripts/discover-services.py --url "https://status.example.com" --name "Example"

Exit code: 0 if any discovered, 1 if none.
"""

import json
import sys
import urllib.request
import urllib.error
import ssl
import argparse
import time

URL_PATTERNS = [
    "https://status.{domain}",
    "https://{slug}status.com",
    "https://www.{slug}status.com",
    "https://status.{domain}.com",
    "https://status.{domain}.io",
    "https://{slug}.statuspage.io",
    "https://{slug}.status.atlassian.com",
]

HEADERS = {"User-Agent": "StatusMonitor-Discovery/1.0"}


def try_url(url, ctx):
    """Try fetching summary.json from a URL. Returns (json_data, platform) or (None, None)."""
    api_url = url.rstrip("/") + "/api/v2/summary.json"
    try:
        req = urllib.request.Request(api_url, headers=HEADERS)
        resp = urllib.request.urlopen(req, timeout=15, context=ctx)
        data = resp.read()
        j = json.loads(data)

        if "page" not in j or "status" not in j:
            return None, None

        # Detect platform
        has_incidents = bool(j.get("incidents"))
        has_scheduled = bool(j.get("scheduled_maintenances"))
        platform = "atlassian" if (has_incidents or has_scheduled) else "incident.io"

        return j, platform
    except (json.JSONDecodeError, urllib.error.HTTPError, urllib.error.URLError, Exception):
        return None, None


def discover_service(name, domain=None, slug=None, ctx=None):
    """Try to find a working status page for a service."""
    if domain is None:
        domain = name.lower().replace(" ", "").replace(".", "")
    if slug is None:
        slug = domain

    # Generate candidate URLs
    candidates = []
    for pattern in URL_PATTERNS:
        try:
            url = pattern.format(domain=domain, slug=slug)
            candidates.append(url)
        except KeyError:
            continue

    for url in candidates:
        j, platform = try_url(url, ctx)
        if j is not None:
            page_name = j.get("page", {}).get("name", name)
            indicator = j.get("status", {}).get("indicator", "?")
            component_count = len(j.get("components", []))
            return {
                "url": url,
                "platform": platform,
                "page_name": page_name,
                "indicator": indicator,
                "component_count": component_count,
            }

    return None


def verify_url(url, ctx):
    """Verify a specific URL works as a status page."""
    j, platform = try_url(url, ctx)
    if j is not None:
        return {
            "url": url,
            "platform": platform,
            "page_name": j.get("page", {}).get("name", ""),
            "indicator": j.get("status", {}).get("indicator", "?"),
            "component_count": len(j.get("components", [])),
        }
    return None


def make_catalog_entry(name, result, category="Uncategorized"):
    """Create a catalog.json entry from discovery result."""
    slug = name.lower().replace(" ", "-").replace(".", "-").replace("/", "-")
    # Clean up consecutive hyphens
    while "--" in slug:
        slug = slug.replace("--", "-")
    slug = slug.strip("-")

    return {
        "id": slug,
        "name": name,
        "base_url": result["url"],
        "type": "statuspage",
        "category": category,
        "platform": result["platform"],
    }


def main():
    parser = argparse.ArgumentParser(description="Discover and verify status pages")
    parser.add_argument("--candidates", help="JSON file with candidate services")
    parser.add_argument("--url", help="Verify a specific status page URL")
    parser.add_argument("--name", help="Service name (used with --url)")
    parser.add_argument("--output", help="Output file for discovered entries (JSON)")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between requests (seconds)")
    args = parser.parse_args()

    ctx = ssl.create_default_context()
    discovered = []
    failed = []

    if args.url:
        # Single URL verification mode
        name = args.name or "Unknown"
        print(f"Verifying: {args.url}")
        result = verify_url(args.url, ctx)
        if result:
            entry = make_catalog_entry(name, result)
            print(f"OK    {name:30s}  platform={result['platform']}  indicator={result['indicator']}  components={result['component_count']}")
            print(f"\nCatalog entry:")
            print(json.dumps(entry, indent=2))
            discovered.append(entry)
        else:
            print(f"FAIL  {name:30s}  No valid status page at {args.url}")
            failed.append(name)

    elif args.candidates:
        # Batch discovery from candidates file
        # Format: [{"name": "Service", "domain": "service.com", "category": "Cat"}, ...]
        with open(args.candidates) as f:
            candidates = json.load(f)

        print(f"Discovering status pages for {len(candidates)} candidates...\n")

        for i, cand in enumerate(candidates):
            name = cand["name"]
            domain = cand.get("domain")
            slug = cand.get("slug")
            category = cand.get("category", "Uncategorized")

            # Also try direct URL if provided
            if "url" in cand:
                result = verify_url(cand["url"], ctx)
            else:
                result = discover_service(name, domain=domain, slug=slug, ctx=ctx)

            if result:
                entry = make_catalog_entry(name, result, category)
                discovered.append(entry)
                print(f"OK    {name:30s}  {result['url']:50s}  {result['platform']:12s}  indicator={result['indicator']}  components={result['component_count']}")
            else:
                failed.append(name)
                print(f"FAIL  {name:30s}  No status page found")

            if i < len(candidates) - 1:
                time.sleep(args.delay)

    else:
        # Default: discover from built-in candidate list
        print("No candidates provided. Use --candidates FILE or --url URL")
        print("\nExample candidates.json:")
        print(json.dumps([
            {"name": "Stripe", "domain": "stripe.com", "category": "Payments"},
            {"name": "AWS", "domain": "aws.amazon.com", "slug": "aws", "category": "Cloud & Hosting"},
            {"name": "Shopify", "domain": "shopify.com", "category": "E-commerce"},
        ], indent=2))
        sys.exit(1)

    # Summary
    print(f"\n{'=' * 80}")
    print(f"DISCOVERED: {len(discovered)}/{len(discovered) + len(failed)}")
    if failed:
        print(f"FAILED: {len(failed)}")
        for name in failed:
            print(f"  - {name}")

    # Write output
    if args.output and discovered:
        with open(args.output, "w") as f:
            json.dumps(discovered, f, indent=2)
        print(f"\nEntries written to {args.output}")

    # Also print discovered entries for easy copy-paste
    if discovered:
        print(f"\n--- Catalog entries (copy to catalog.json) ---")
        for entry in discovered:
            print(json.dumps(entry))

    sys.exit(0 if discovered else 1)


if __name__ == "__main__":
    main()
