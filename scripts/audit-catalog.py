#!/usr/bin/env python3
"""Audit catalog.json — verify every service endpoint still works.

Run: python3 scripts/audit-catalog.py [--workers N] [--json PATH] [--quiet]
Exit code: 0 if all pass, 1 if any fail.

Entries are checked concurrently, and every failure is retried serially with
escalating backoff before being reported. A parallel sweep across ~1,900
third-party hosts always turns up hosts that simply throttled us; the retry
pass is what separates "this service is gone" from "we asked too fast" — and
it only does that if it actually waits. Retrying a rate-limited host the
instant the burst ends just re-reads the same 403.

Failures are classified, because they call for different responses:

    gone        404/410/DNS — the page is not there any more. Actionable.
    malformed   200 with the wrong shape — migrated platform, or a dead
                page still serving something. Actionable.
    blocked     401/403/429 — a WAF or challenge. The service may be
                perfectly healthy; we just cannot read it from here.
    unreachable TLS failures, timeouts, 5xx — transient or infrastructural.

Only `gone` and `malformed` are confident findings, and only they set a
non-zero exit code (`--fail-on any` overrides that). A `blocked` result from
CI in particular is as likely to be the GitHub Actions egress range being
scored as hostile as it is to be a real catalog problem: `jane`, `veeps` and
`site-availability` all 403 on the runner and answer 200 from elsewhere.
Blocked and unreachable entries are still printed and still written to
`--json`, so nothing is hidden — they just do not open an issue every Monday.
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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import nazar_ua  # noqa: E402 — needs the sys.path line above

CATALOG = "Resources/catalog.json"

# Identical to the app's User-Agent (Services/StatusManager.swift). The audit
# only predicts what the app will see if it asks the way the app asks.
HEADERS = nazar_ua.HEADERS

# Failure kinds, ordered most to least actionable. See the module docstring.
KIND_GONE = "gone"
KIND_MALFORMED = "malformed"
KIND_BLOCKED = "blocked"
KIND_UNREACHABLE = "unreachable"

KIND_ORDER = [KIND_GONE, KIND_MALFORMED, KIND_BLOCKED, KIND_UNREACHABLE]

# Only these two say something about the catalog. A blocked or unreachable
# entry says something about the network between us and a third party, which
# is not a catalog defect and must not file a weekly issue about one.
CONFIDENT_KINDS = {KIND_GONE, KIND_MALFORMED}

KIND_LABEL = {
    KIND_GONE: "Gone (404/410/DNS) — the status page is no longer there",
    KIND_MALFORMED: "Wrong shape (200, unexpected payload) — likely migrated platform",
    KIND_BLOCKED: "Blocked (401/403/429) — could not read it; the service may be fine",
    KIND_UNREACHABLE: "Unreachable (TLS/timeout/5xx) — transient or infrastructural",
}

# Serial retry schedule, in seconds, applied between whole retry rounds. A
# rate-limited host needs seconds, not milliseconds, to forget about us.
RETRY_DELAYS = (3, 8, 20)


def endpoint(entry):
    base = entry["base_url"].rstrip("/")
    return {
        "statuspage": base + "/api/v2/summary.json",
        "betterstack": base + "/index.json",
        "instatus": base + "/summary.json",
        "datadog": base + "/config.json",
    }.get(entry["type"], base)


def classify_transport_error(exc):
    """Map a transport exception onto a failure kind."""
    text = str(exc).lower()
    if "name or service not known" in text or "nodename nor servname" in text or "getaddrinfo" in text:
        return KIND_GONE
    return KIND_UNREACHABLE


def check(entry, ctx, timeout=20):
    """Return (ok, detail, kind).

    On success `detail` is a status string and `kind` is None. On failure
    `detail` is a human reason and `kind` is one of the KIND_* constants.
    """
    try:
        resp = urllib.request.urlopen(
            urllib.request.Request(endpoint(entry), headers=HEADERS), timeout=timeout, context=ctx
        )
        data = resp.read()

        # RSS/Atom entries serve a feed, not JSON.
        if entry["type"] == "rss":
            head = data[:400].lstrip()
            if head.startswith(b"<?xml") or b"<rss" in head or b"<feed" in head:
                return True, "feed", None
            return False, "Response is not an RSS/Atom feed", KIND_MALFORMED

        j = json.loads(data)

        if entry["type"] == "statuspage":
            # Reject two lookalikes: pages that nest `status` inside `page`
            # (Instatus and similar), and unclaimed pages returning nulls.
            if not isinstance(j.get("page"), dict) or not isinstance(j.get("status"), dict):
                return False, "Missing or null page/status in JSON", KIND_MALFORMED
            return True, f"indicator={j.get('status', {}).get('indicator', '?')}", None

        if entry["type"] == "instatus":
            # Instatus nests `status` inside `page`, unlike Atlassian.
            page = j.get("page")
            if not isinstance(page, dict) or not isinstance(page.get("status"), str):
                return False, "Missing page.status in Instatus JSON", KIND_MALFORMED
            return True, f"status={page['status']}", None

        if entry["type"] == "datadog":
            # Datadog pages carry no page-level rollup — `components` is the
            # status signal, and its absence means this is not a Datadog page.
            if not isinstance(j.get("components"), list):
                return False, "Missing components array in Datadog config.json", KIND_MALFORMED
            statuses = {c.get("status") for c in j["components"]}
            detail = f"components={len(j['components'])} statuses={','.join(sorted(x for x in statuses if x))}"
            return True, detail, None

        if entry["type"] == "betterstack":
            if "data" not in j or "attributes" not in j.get("data", {}):
                return False, "Missing data.attributes in JSON:API document", KIND_MALFORMED
            return True, f"aggregate_state={j['data']['attributes'].get('aggregate_state', '?')}", None

        return False, f"Unknown entry type: {entry['type']}", KIND_MALFORMED

    except json.JSONDecodeError:
        return False, "Response is not JSON (likely HTML)", KIND_MALFORMED
    except urllib.error.HTTPError as e:
        if e.code in (401, 403, 429, 451):
            return False, f"HTTP {e.code}", KIND_BLOCKED
        if e.code in (404, 410):
            return False, f"HTTP {e.code}", KIND_GONE
        return False, f"HTTP {e.code}", KIND_UNREACHABLE
    except urllib.error.URLError as e:
        return False, str(e.reason)[:80], classify_transport_error(e.reason)
    except Exception as e:  # noqa: BLE001 — any transport failure is a failure
        return False, str(e)[:80], classify_transport_error(e)


def retry_serially(suspects, ctx, rounds, quiet=False):
    """Re-check failures one at a time, waiting between rounds.

    Returns [(entry, reason, kind)] for the ones still failing. The waiting is
    the point: the parallel sweep is what rate-limits us, so retrying without
    a pause measures our own burst rather than the service.
    """
    pending = list(suspects)
    last = {}
    # A handful of failures can afford a second between requests; a few hundred
    # cannot, or the audit outruns its CI timeout.
    pacing = 1.0 if len(pending) <= 50 else 0.2

    for attempt, delay in enumerate(rounds, start=1):
        if not pending:
            break
        print(f"\nRetry {attempt}/{len(rounds)} — waiting {delay}s, then {len(pending)} serially...", flush=True)
        time.sleep(delay)
        still = []
        for entry in pending:
            ok, detail, kind = check(entry, ctx, timeout=30)
            if ok:
                if not quiet:
                    print(f"OK    {entry['name']:30s}  {detail} (recovered on retry {attempt})")
            else:
                last[entry["id"]] = (detail, kind)
                still.append(entry)
            time.sleep(pacing)
        pending = still

    return [(entry, *last[entry["id"]]) for entry in pending]


def main():
    ap = argparse.ArgumentParser()
    # Twelve workers across ~1,900 third-party hosts is a lot of simultaneous
    # load for hosts sharing a WAF; six still finishes well inside CI's budget.
    ap.add_argument("--workers", type=int, default=6, help="concurrent requests (default 6)")
    ap.add_argument("--retries", type=int, default=len(RETRY_DELAYS),
                    help=f"serial retry rounds for failures (default {len(RETRY_DELAYS)})")
    ap.add_argument("--json", dest="json_out", help="write failures to this path as JSON")
    ap.add_argument("--fail-on", choices=("confident", "any"), default="confident",
                    help="exit non-zero on confident findings only (default) or on any failure")
    ap.add_argument("--quiet", action="store_true", help="print only failures and the summary")
    args = ap.parse_args()

    with open(CATALOG) as f:
        catalog = json.load(f)

    ctx = ssl.create_default_context()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda e: (e, *check(e, ctx)), catalog))

    if not args.quiet:
        for entry, ok, detail, _kind in results:
            if ok:
                print(f"OK    {entry['name']:30s}  {detail}")

    suspects = [entry for entry, ok, _, _ in results if not ok]

    rounds = RETRY_DELAYS[: max(args.retries, 0)]
    failed = retry_serially(suspects, ctx, rounds, quiet=args.quiet) if suspects else []

    by_kind = {kind: [] for kind in KIND_ORDER}
    for entry, reason, kind in failed:
        by_kind.setdefault(kind or KIND_UNREACHABLE, []).append((entry, reason))

    confident = [f for f in failed if (f[2] or KIND_UNREACHABLE) in CONFIDENT_KINDS]

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
                        "kind": kind or KIND_UNREACHABLE,
                    }
                    for e, reason, kind in failed
                ],
                f,
                indent=1,
            )

    if failed:
        print(f"FAILED: {len(failed)} ({len(confident)} confident)")
        for kind in KIND_ORDER:
            group = by_kind.get(kind) or []
            if not group:
                continue
            print(f"\n{KIND_LABEL[kind]}")
            for entry, reason in group:
                print(f"  - {entry['name']}: {reason}")
        if by_kind.get(KIND_BLOCKED):
            print(
                "\nNote: a 401/403 seen only from CI is as likely to be the GitHub Actions\n"
                "egress range hitting a shared WAF as it is a real catalog problem. Re-check\n"
                "those from another network before touching the entry."
            )
        if args.fail_on == "any" or confident:
            sys.exit(1)
        print("\nNo confident findings — nothing here is a catalog defect. Exiting 0.")
        sys.exit(0)

    print("All services verified.")
    sys.exit(0)


if __name__ == "__main__":
    main()
