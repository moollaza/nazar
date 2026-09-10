---
title: "feat: Add Fathom website events"
type: feat
status: completed
date: 2026-04-28
origin: docs/brainstorms/2026-04-11-statusmonitor-ux-polish-requirements.md
---

# feat: Add Fathom website events

## Overview

Add Fathom Analytics to the Nazar marketing website using public site ID `BEFUXWLN`, then track meaningful aggregate conversion and engagement events on the static page. The change is limited to `website/index.html` plus website visual/test coverage where needed.

## Problem Frame

The UX polish requirements call for Fathom Analytics on the marketing website as a privacy-friendly way to understand website usage (see origin: `docs/brainstorms/2026-04-11-statusmonitor-ux-polish-requirements.md`). The current website has no analytics script and still contains copy that says "no analytics" in app privacy claims, which becomes ambiguous once website-level Fathom analytics is added.

## Requirements Trace

- R1. Add the Fathom embed script to the marketing website using site ID `BEFUXWLN`.
- R2. Track meaningful website events with the current `fathom.trackEvent` API, not deprecated `trackGoal`.
- R3. Use privacy-preserving event names only; never send search text, service names, user IDs, or other visitor-specific data.
- R4. Preserve the macOS app privacy claim by making copy clear that the app has no telemetry, while the website uses aggregate Fathom analytics.
- R5. Keep the site static HTML with no new build dependency.

## Scope Boundaries

- No native macOS app analytics or TelemetryDeck work.
- No Fathom account/API configuration beyond the supplied public site ID.
- No event values or revenue tracking.
- No custom Fathom proxy domain.
- No React/Vite/Svelte package integration; this is a static HTML page.

## Context & Research

### Relevant Code and Patterns

- `website/index.html` is the single-page static marketing site and already contains small inline scripts for theme switching and catalog browsing.
- `website/tests/website.visual.spec.js` is the Playwright/Argos coverage for homepage rendering, catalog empty state, and catalog service links.
- `package.json` exposes `npm run test:visual` for website visual checks.
- `.github/workflows/deploy-website.yml` deploys `website/` to Cloudflare Pages at `https://usenazar.com/`.
- Project-hub Fathom standard recommends hardcoding public site IDs in the HTML shell, dot-separated `page.element.action` event names, `trackEvent`, and domain restriction for local/preview protection.

### Institutional Learnings

- No `docs/solutions/` directory exists in this repository, so there are no local institutional solution notes to apply.

### External References

- Fathom event docs confirm `trackGoal` is deprecated for new events, `trackEvent` is current, and event code should run after the Fathom script.
- Fathom static/React integration docs confirm a plain script tag is appropriate for static sites without client-side routing.

## Key Technical Decisions

- Hardcode `BEFUXWLN` in `website/index.html`: Fathom site IDs are public and this repo has a single production website.
- Load the CDN script near the end of `<body>` before local event code: this matches Fathom's ordering guidance and avoids blocking first paint.
- Add `data-included-domains="usenazar.com,www.usenazar.com"`: prevents local/preview traffic from being reported while still letting the page render normally in tests.
- Use `data-fathom-event` attributes plus one delegated click listener for static links/buttons: keeps event wiring visible in HTML and avoids repeated inline handler code.
- Add small imperative hooks only for dynamic catalog controls: category chips and service result links are created at runtime, so their generic events need to be set when elements are built or handled by existing listeners.
- Use generic event names for catalog interactions: track that a search/category/service click happened without sending search queries, category names, or service names.

## Open Questions

### Resolved During Planning

- Which source requirement governs analytics? The older website v1 requirements excluded analytics, but the later UX polish R13 plus the current user request explicitly add Fathom. Treat R13/current request as the active scope.
- Should this use `fathom-client`? No. The website is static HTML without SPA routing or bundling; the CDN script is the simpler local pattern.

### Deferred to Implementation

- Exact event placement: The implementer should wire events in the least noisy way after re-reading the latest `website/index.html`, because the file changed recently on `main`.

## Implementation Units

- [x] **Unit 1: Embed Fathom and static click events**

**Goal:** Load Fathom on the production website and track static navigation, CTA, GitHub, footer, and theme interactions.

**Requirements:** R1, R2, R3, R5

**Dependencies:** None

**Files:**
- Modify: `website/index.html`
- Test: `website/tests/website.visual.spec.js`

**Approach:**
- Add the Fathom script with `data-site="BEFUXWLN"` and production-domain restriction.
- Add a guarded local helper that no-ops when `window.fathom.trackEvent` is unavailable.
- Add `data-fathom-event` attributes for static links/buttons and a delegated listener that calls the helper.
- Track theme changes from the existing theme toggle click handler.

**Patterns to follow:**
- Existing inline script style in `website/index.html`.
- Project-hub event naming convention: lowercase dot-separated `page.element.action`, underscores for multi-word segments.

**Test scenarios:**
- Page renders when Fathom is unavailable or blocked.
- Static CTA links still open their existing destinations.
- Theme toggle still changes local theme state.

**Verification:**
- `website/index.html` contains the Fathom script and only generic event names.
- Visual homepage test expectations remain valid or are intentionally updated for privacy copy.

- [x] **Unit 2: Track dynamic catalog and FAQ events**

**Goal:** Track meaningful interactions produced by existing JavaScript without leaking visitor-entered text or service identity.

**Requirements:** R2, R3, R5

**Dependencies:** Unit 1

**Files:**
- Modify: `website/index.html`
- Test: `website/tests/website.visual.spec.js`

**Approach:**
- Track catalog category selection, first non-empty search interaction, show-more clicks, request-service links, and status-page clicks with generic event names.
- Track FAQ opens using a single event per open interaction, without encoding question text in the event name.
- Keep the catalog filtering behavior unchanged.

**Patterns to follow:**
- Existing catalog script state variables and event listeners in `website/index.html`.
- Fathom docs: custom events use one required event name and optional `_value`; no values are needed here.

**Test scenarios:**
- Catalog search empty state still renders.
- Catalog service result still opens the service status page.
- No event sends search query, service name, category name, or FAQ text.

**Verification:**
- Existing Playwright website tests pass.
- Manual code inspection shows dynamic events are generic and guarded.

- [x] **Unit 3: Align privacy copy and verification**

**Goal:** Keep public copy accurate after adding website analytics while preserving the app's privacy positioning.

**Requirements:** R4

**Dependencies:** Unit 1

**Files:**
- Modify: `website/index.html`
- Test: `website/tests/website.visual.spec.js`

**Approach:**
- Update only the website copy that says "no analytics" in a way that could now describe the website itself.
- Keep app-specific claims focused on no app telemetry, no account, no proxy server, and local provider data.
- Update visual test text expectations only if changed copy breaks them.

**Patterns to follow:**
- Existing concise website copy style.
- Current visual test assertion for the hero privacy line.

**Test scenarios:**
- Hero privacy line remains visible.
- FAQ privacy answer remains accurate for the macOS app.

**Verification:**
- Website visual tests pass.
- No native app files are changed.

## System-Wide Impact

- **Interaction graph:** Browser click/input/toggle event listeners only. No app callbacks, persistence, backend, or worker behavior changes.
- **Error propagation:** Fathom failures must be swallowed by the helper so analytics cannot break navigation or catalog browsing.
- **State lifecycle risks:** No persistent state beyond the existing theme `localStorage`; analytics adds no local storage of its own code.
- **API surface parity:** Not applicable; this is a static website script integration.
- **Integration coverage:** Playwright website tests cover the page and catalog behavior through the real browser chain.

## Risks & Dependencies

- External CDN requests can be blocked by privacy tools; event helper must tolerate missing Fathom.
- Over-specific event names could accidentally encode user intent; keep dynamic events generic.
- Copy changes can break visual/text tests; update only the required assertions.

## Documentation / Operational Notes

- Post-deploy validation should use the Fathom dashboard for `usenazar.com` and verify pageviews plus selected events appear after production deploy.
- No README or app documentation changes are required.

## Sources & References

- Origin document: [docs/brainstorms/2026-04-11-statusmonitor-ux-polish-requirements.md](../brainstorms/2026-04-11-statusmonitor-ux-polish-requirements.md)
- Superseded website v1 context: [docs/brainstorms/2026-04-09-statusmonitor-website-requirements.md](../brainstorms/2026-04-09-statusmonitor-website-requirements.md)
- Related code: `website/index.html`
- Related tests: `website/tests/website.visual.spec.js`
- External docs: `https://fathomanalytics.mintlify.dev/docs/events/overview`
- External docs: `https://usefathom.com/docs/integrations/react`
