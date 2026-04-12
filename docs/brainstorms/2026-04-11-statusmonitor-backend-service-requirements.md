---
date: 2026-04-11
topic: statusmonitor-backend-service
---

# StatusMonitor Backend Service

## Problem Frame

StatusMonitor's v1 architecture has each Mac app client independently polling every status page it monitors. This works for individual users with 5-20 services, but creates problems at scale: thousands of users independently polling the same 100+ status pages is wasteful for both clients and status page providers. A centralized backend that polls once and serves all clients eliminates this redundancy, enables push-based ingestion (email subscriptions), and makes the service catalog dynamically updatable without app releases.

This is a **v2 feature**. The v1 Mac app ships with direct client-side polling and a bundled catalog. The backend is additive — the app must continue working standalone when the backend is unreachable.

## How It Works

The backend aggregates status data from all catalog services and serves it as a single CDN-cached JSON endpoint. Each Mac app client makes one GET request to fetch all statuses, then filters locally to display only the services the user monitors. The server has zero knowledge of which services any user cares about.

```
Status Pages (1000+)          StatusMonitor Backend            Mac Apps
                                                          
GitHub      ──┐               ┌──────────────────┐       ┌── User A
OpenAI      ──┤  Tier 1-3     │ CF Workers + R2   │  1 GET├── User B
Anthropic   ──┼──────────────►│                   │◄──────├── User C
Cloudflare  ──┤  (poll/email) │ CDN-cached JSON   │       ├── ...
Asana       ──┘               └──────────────────┘       └── User N
                                                          
                                User-added custom URLs:
                                polled directly by client (never touches backend)
```

**Without backend:** N users x M services = N*M polls/minute to status pages
**With backend:** M polls/minute (server) + N reads/minute (CDN-cached) = M+N total

## Requirements

### Backend Service

- B1. Aggregate status data for all catalog services using a tiered ingestion strategy (see Ingestion Tiers below).
- B2. Serve a single JSON endpoint (`/v1/statuses.json`) that returns the current status of every catalog service. Response is the complete set — no filtering, no per-user customization.
- B3. CDN-cache the response with a 30-60 second TTL. Clients receive the cached version. The server writes a fresh snapshot to R2 on each poll cycle.
- B4. Run on Cloudflare Workers + R2. Must stay within free tier at launch (<100k requests/day, <10M R2 reads/month). Serve via Workers (not R2 directly) so Cloudflare CDN absorbs client reads.
- B5. Support a dynamic catalog: adding a new service to the backend's catalog does not require a Mac app update. The app fetches the latest catalog from the backend (with bundled catalog as offline fallback).
- B6. No user accounts, no authentication, no per-user state. The API is public and read-only. Privacy by design: the server cannot know which services any individual user monitors.

### Ingestion Tiers

Status data is collected using the best available source per service, in priority order:

- B7. **Tier 1 — JSON API polling.** For Atlassian Statuspage and incident.io services. Fetch `/api/v2/summary.json`. Use HTTP conditional GET (ETag/If-Modified-Since) to minimize bandwidth. This covers ~70% of catalog services.
- B8. **Tier 2 — RSS/Atom feed polling.** For services without a JSON API but with an RSS feed (e.g., Shopify, Stripe). Parse feed items and derive status via keyword heuristics (same approach as the Mac app's existing RSS parser).
- B9. **Tier 3 — Email subscriptions (push).** Subscribe the backend's email inbox to status page email alerts. Receive via Cloudflare Email Workers. Parse incoming emails to extract status changes. This provides near-instant detection (~seconds vs ~minutes for polling). Deploy for high-value services first (GitHub, Cloudflare, AWS, etc.), expand over time.
- B10. Webhooks are theoretically ideal but practically unavailable — most status pages only offer webhooks to page owners, not public subscribers. Do not invest in webhook infrastructure unless a significant number of providers start offering public subscriber webhooks.

### Mac App Integration (v2 changes)

- B11. The Mac app fetches from the backend by default: one GET to `/v1/statuses.json` per poll interval. This replaces individual per-service polling for catalog services.
- B12. If the backend is unreachable (network error, timeout), the app falls back to direct client-side polling (existing v1 behavior). The user does not notice the difference.
- B13. User-added custom providers (URLs not in the catalog) are always polled directly by the client. They never touch the backend.
- B14. The app fetches the latest catalog from the backend (`/v1/catalog.json`) on launch or periodically. The bundled `catalog.json` is the offline fallback.
- B15. The backend endpoint URL is configurable (for self-hosting scenarios) but defaults to StatusMonitor's hosted service.

### Catalog Growth

- B16. Start with ~100 curated services at v1 launch (bundled in the app).
- B17. Grow to 500+ via the backend, using programmatic discovery: probe common URL patterns (`status.{domain}`, `{company}status.com`) across top SaaS companies for Statuspage/incident.io API responses.
- B18. Long-term (1000+): accept community contributions to the catalog via GitHub PRs or an open submission process. The catalog is open-source data.
- B19. Research automated discovery: scan Atlassian Statuspage directory, G2/Crunchbase SaaS lists, and existing aggregators (StatusGator claims 4,500+) to identify the full landscape of monitorable status pages.

## Success Criteria

- A v2 user with 20 monitored catalog services makes 1 HTTP request per poll interval instead of 20.
- Status changes for Tier 3 (email) services are reflected within 30 seconds. Tier 1-2 (polling) services within 2 minutes.
- The backend runs within Cloudflare's free tier at launch and up to ~1,000 daily active users.
- The Mac app works identically whether the backend is available or not.
- No per-user data is collected, stored, or inferable from server logs.

## Scope Boundaries

- No user accounts, authentication, or per-user subscriptions.
- No per-user push notifications (APNs). The client polls the broadcast endpoint.
- No Server-Sent Events (SSE) or WebSocket connections in v2. Simple GET is sufficient. SSE is a potential v2.1+ enhancement.
- No HTML scraping of custom status pages. If a service has no API and no RSS, it's not in the catalog.
- No client telemetry or analytics. The server does not track usage.
- Self-hosting is a nice-to-have, not a v2 requirement (but the architecture naturally supports it since it's just Workers + R2).

## Key Decisions

- **Broadcast, not per-user:** The server returns all statuses to all clients. This is simpler, more cacheable, and maximally private. The client filters locally. The tradeoff is bandwidth (sending statuses for services the user doesn't monitor), but at 100-500 services the payload is <100KB — trivial.
- **v2, not v1:** The Mac app ships first with direct polling. The backend is additive. This lets us launch faster and validates the product before investing in infrastructure.
- **Cloudflare Workers + R2:** Serverless, free tier viable, Email Workers enable Tier 3 push ingestion, CDN-cached reads scale to thousands of users at near-zero cost.
- **Tiered ingestion, not all-push:** Email-as-push is powerful but operationally complex (subscription management, email parsing). Start with JSON API + RSS polling (simple, reliable, ~90% coverage). Layer email on top for high-value services.
- **Client polls custom providers directly:** The backend only monitors catalog services. User-added URLs stay client-side. This keeps the backend simple and avoids processing arbitrary user-supplied URLs (security + abuse concern).
- **Privacy by design:** No accounts, no per-user state, no tracking. The API is public. A user's monitoring list exists only on their Mac.

## Dependencies / Assumptions

- Cloudflare Workers free tier (100k requests/day) is sufficient for launch.
- Cloudflare R2 free tier (10M reads/month, 1M writes/month) is sufficient when serving via Workers with CDN caching.
- Cloudflare Email Workers can receive and parse status page emails at the scale needed (~100-500 email subscriptions).
- Status page email subscriptions are stable and don't require periodic re-subscription.
- The `/v1/statuses.json` payload stays under 500KB even at 1,000+ services (estimated ~100-200 bytes per service = ~200KB for 1,000 services).

## Outstanding Questions

### Resolve Before Planning
- None — all product decisions are resolved.

### Deferred to Planning
- [Affects B9][Needs research] Can Atlassian Statuspage email subscriptions be automated via API, or must each be manually subscribed via the web form?
- [Affects B17][Needs research] What is the most efficient method for programmatic discovery of Statuspage-hosted services? Is there a public directory or API?
- [Affects B4][Technical] Cloudflare Workers cron triggers have a minimum interval. Confirm whether 1-minute cron is available on the free tier or requires paid ($5/month Workers plan).
- [Affects B3][Technical] What is the optimal R2 write strategy? Write on every poll cycle (once per minute = 1,440 writes/day) or only on change (fewer writes but requires diff logic)?
- [Affects B5][Technical] Schema design for `/v1/statuses.json` and `/v1/catalog.json` — what fields does the Mac app need?
- [Affects B9][Technical] Email parsing strategy: regex/template per provider, or LLM-based extraction for flexibility?
- [Affects B19][Needs research] How many unique services are realistically monitorable via Statuspage/incident.io/RSS? Is 5,000 achievable?

## Cost Model

| Scale | Daily active users | CDN reads/month | R2 writes/month | Workers req/day | Estimated cost |
|-------|-------------------|----------------|-----------------|-----------------|---------------|
| Launch | <100 | <5M | ~43k | <10k | **Free** |
| Growth | 1,000 | ~50M | ~43k | ~50k | **Free** (CDN absorbs reads) |
| Scale | 10,000 | ~500M | ~43k | ~500k | **$5-20/mo** (Workers paid plan) |
| Large | 100,000 | ~5B | ~43k | ~5M | **$50-100/mo** (R2 reads + Workers) |

Note: R2 writes are constant regardless of user count (server polls once, writes once). Only reads scale with users, and CDN caching absorbs most of them.

## Roadmap

- **v1:** Mac app only. Direct client-side polling. Bundled catalog (~100 services).
- **v2.0:** Backend launches. Tier 1+2 ingestion (JSON API + RSS polling). Broadcast endpoint. Dynamic catalog. Mac app uses backend with direct-polling fallback.
- **v2.1:** Tier 3 ingestion (email subscriptions) for top 20-30 high-value services. Catalog grows to 500+.
- **v2.x:** Community-contributed catalog. Automated discovery pipeline. 1,000+ services.
- **v3 (speculative):** SSE for real-time push to clients. Mobile app. Historical status data.

## Next Steps

→ `/ce:plan` for structured implementation planning (when ready to build v2)
→ v1 Mac app work proceeds independently per existing plan
