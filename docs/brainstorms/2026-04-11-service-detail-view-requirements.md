---
date: 2026-04-11
topic: service-detail-view
linear: ZPR-25
---

# Service Detail View

## Problem Frame

Clicking a service row in the dashboard expands it inline, showing components and active incidents. This works for services with a handful of components (GitHub has ~10, Vercel has ~8). But Cloudflare has 200+ components — mostly regional PoPs like "Johannesburg, ZA - JNB" — and the inline expand becomes a wall of text that pushes the entire dashboard off-screen. Even with the "Show issues only" collapse, users who want to browse components or search for a specific region cannot do so effectively. The current design does not scale.

## Requirements

### R1. Drill-down navigation within the popover

Clicking a service row replaces the dashboard content with a detail view for that service. This is an in-popover push navigation — not a sheet, not a modal, not a new window. The popover frame stays the same (420x520). A back button in the detail view's header returns to the dashboard. The transition should feel native: a horizontal slide or crossfade, whichever is cheaper to implement.

### R2. Component search/filter by name

The detail view includes a search field that filters the component list by name. Uses `localizedCaseInsensitiveContains`. Useful for finding a specific Cloudflare PoP (e.g., typing "JNB" to find Johannesburg) or a specific AWS region. The search field appears only when the service has 10+ components.

### R3. Status filter (All / Issues Only)

A segmented control or toggle to filter components by status: "All" shows every component, "Issues Only" shows only non-operational components. Default depends on context:
- If the service has active issues, default to "Issues Only" so degraded components are immediately visible.
- If the service is fully operational, default to "All" so the view is not empty.

### R4. Service header with overall status

The detail view header shows: service icon (via existing ServiceIconView), service name, overall status indicator (colored dot + label), and last-updated timestamp. This replaces the dashboard header while the detail view is active.

### R5. Active incidents with description text

Active incidents are shown below the header (above the component list) with the incident name, impact severity icon, status, and the full latest update body text. Currently `IncidentSnapshot.latestUpdate` is truncated to 3 lines in the inline expand — the detail view should show the full text.

### R6. View Status Page link

A "View Status Page" button that opens the provider's status page URL in the default browser via `NSWorkspace.shared.open()`. Same behavior as the current inline expand link. Placed in the header area or as a footer action.

### R7. Inline expand preserved for small services

Services with fewer than 10 components continue to use the current inline expand behavior. The detail view is only used for services with 10+ components. The threshold should be a constant, not hardcoded in multiple places.

### R8. Back button returns to dashboard

A back button (chevron.left + "Back" or just "Services") in the detail view header. Clicking it returns to the dashboard list, restoring the previous scroll position if feasible. The transition should match the forward navigation (reverse slide or crossfade).

## Design Sketch

```
┌──────────────────────────────────────────┐
│  ‹ Services     Cloudflare     [↗ Page]  │
│  ● Partial Outage · Updated 2m ago       │
├──────────────────────────────────────────┤
│  ▲ Active Incidents                      │
│  ⚠ Cloudflare Dashboard degraded         │
│    We are investigating reports of...    │
│    (full update text, not truncated)     │
├──────────────────────────────────────────┤
│  🔍 Filter components...    [All|Issues] │
├──────────────────────────────────────────┤
│  ● Amsterdam, NL - AMS       Operational │
│  ● Atlanta, GA - ATL         Operational │
│  ◉ Johannesburg, ZA - JNB   Degraded    │
│  ● London, GB - LHR         Operational │
│  ...                                     │
│  (scrollable, 200+ rows)                │
└──────────────────────────────────────────┘
```

## Success Criteria

- A user monitoring Cloudflare can search for "JNB" and see only the Johannesburg PoP.
- Navigating into and out of the detail view is instant (no perceptible delay).
- Services with <10 components still expand inline as before.
- The popover does not resize or jump when navigating between views.
- Active incident descriptions are shown in full, not truncated.

## Scope Boundaries

- No per-component notifications or watches (v2).
- No persistent component favorites or pinning (v2).
- No grouping components by region/category (requires upstream data not always available).
- No custom component ordering — display in API response order.
- The detail view is read-only. No actions beyond "View Status Page" and "Back".

## Key Decisions

- **In-popover navigation, not sheet/modal:** Sheets in a popover are awkward on macOS — the popover can resize, the sheet doesn't get the popover's visual treatment, and it adds a layer of modality that makes a simple drill-down feel heavy. Replacing content in-place is the standard pattern for menu bar app popovers (1Password, iStat Menus, etc.).
- **Threshold of 10 components:** Below 10, inline expand is perfectly usable and faster (no navigation). Above 10, search and filtering become valuable. 10 is a pragmatic cutoff — most services have either <10 or 50+ components.
- **Default status filter is context-dependent:** "Issues Only" when issues exist avoids burying the signal in 200 operational rows. "All" when everything is fine avoids an empty view.

## Dependencies / Assumptions

- `ProviderSnapshot` already contains `components: [ComponentSnapshot]` and `activeIncidents: [IncidentSnapshot]` — no model changes needed.
- `ServiceIconView` and "View Status Page" link already exist and can be reused.
- The popover's fixed 420x520 frame is sufficient for the detail view layout.

## Outstanding Questions

### Resolve Before Planning
- None — all decisions resolved.

### Deferred to Implementation
- [Technical] SwiftUI animation for in-popover navigation: `.transition(.move(edge: .trailing))` with a conditional `if/else` on navigation state, or a custom `NavigationStack`-like pattern? NavigationStack in a popover has known quirks on macOS.
- [Technical] Restoring scroll position on back navigation: may require storing the ScrollView offset, or may "just work" if the dashboard view is preserved in memory behind the detail view.

## Next Steps

→ `docs/plans/2026-04-11-002-feat-service-detail-view-plan.md` for implementation plan
