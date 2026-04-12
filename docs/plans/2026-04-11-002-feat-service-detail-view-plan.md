---
title: "Service Detail View"
type: feat
status: draft
date: 2026-04-11
origin: docs/brainstorms/2026-04-11-service-detail-view-requirements.md
linear: ZPR-25
---

# Service Detail View — Implementation Plan

## Overview

Add a drill-down detail view for services with many components (10+). Clicking a large service replaces the dashboard content with a searchable, filterable component list. Services with <10 components keep the current inline expand. No model changes needed — this is purely a view-layer feature.

## Problem Statement / Motivation

Cloudflare has 200+ components (regional PoPs). The inline expand creates an unusable wall of text that pushes the dashboard off-screen. Users cannot find a specific region or quickly identify which components are degraded. (see origin: `docs/brainstorms/2026-04-11-service-detail-view-requirements.md`)

## Design Decisions (resolved)

1. **In-popover content replacement, not sheet/modal.** Standard pattern for menu bar app popovers. Avoids sheet-in-popover quirks.
2. **Threshold constant: 10 components.** Below 10, inline expand is fine. Above 10, search/filter adds value. Defined once as a constant.
3. **Status filter defaults to "Issues Only" when issues exist, "All" otherwise.** Prevents empty view when healthy; surfaces signal when degraded.
4. **No NavigationStack.** NavigationStack in macOS popovers has known sizing/animation quirks. Use a simple `@State` enum for navigation state with conditional view rendering and `.transition()`.
5. **Full incident text.** Detail view shows `IncidentSnapshot.latestUpdate` without `.lineLimit()`. The inline expand keeps its 3-line limit.

## Implementation

### Step 1: Add navigation state to DashboardView

**File: `Views/DashboardView.swift`**

Add a `@State` property to track which service detail is being viewed:

```swift
@State private var selectedSnapshot: ProviderSnapshot? = nil
```

When `selectedSnapshot` is non-nil, the detail view replaces the dashboard content. When nil, the dashboard is shown.

Modify the `body` to conditionally render:

```swift
if let selected = selectedSnapshot {
    ServiceDetailView(
        snapshot: selected,
        catalogId: manager.providers.first(where: { $0.id == selected.id })?.catalogEntryId,
        statusPageURL: manager.providers.first(where: { $0.id == selected.id }).flatMap { URL(string: $0.baseURL) },
        onBack: { selectedSnapshot = nil }
    )
    .transition(.move(edge: .trailing))
} else {
    // existing dashboard content (header, search, list, footer)
    .transition(.move(edge: .leading))
}
```

### Step 2: Define component count threshold

**File: `Views/DashboardView.swift`**

Add a private constant at the top of the file or in an extension:

```swift
private let detailViewComponentThreshold = 10
```

### Step 3: Update ProviderRowView tap behavior

**File: `Views/DashboardView.swift`**

Change the `onTap` closure passed to `ProviderRowView` to check the component count:

```swift
ProviderRowView(
    snapshot: snapshot,
    catalogId: provider?.catalogEntryId,
    statusPageURL: provider.flatMap { URL(string: $0.baseURL) },
    isExpanded: expandedProvider == snapshot.id,
    onTap: {
        if snapshot.components.count >= detailViewComponentThreshold {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSnapshot = snapshot
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedProvider = expandedProvider == snapshot.id ? nil : snapshot.id
            }
        }
    }
)
```

### Step 4: Create ServiceDetailView

**New file: `Views/ServiceDetailView.swift`**

```
Layout:
┌──────────────────────────────────────────┐
│  ‹ Services     [ServiceName]   [↗ Page] │  ← header
│  ● Status Label · Updated Xm ago        │
├──────────────────────────────────────────┤
│  ⚠ Incident Name                        │  ← incidents section
│    Full update body text...              │     (only if activeIncidents non-empty)
├──────────────────────────────────────────┤
│  🔍 Filter components...  [All|Issues]  │  ← search + filter bar
├──────────────────────────────────────────┤
│  Component list (ScrollView)             │  ← scrollable component list
│  ...                                     │
└──────────────────────────────────────────┘
```

**Props:**
- `snapshot: ProviderSnapshot`
- `catalogId: String?` (for ServiceIconView)
- `statusPageURL: URL?`
- `onBack: () -> Void`

**Internal state:**
- `@State private var searchText: String = ""`
- `@State private var statusFilter: StatusFilter = .auto` (computed default based on snapshot)

**StatusFilter enum:**
```swift
enum StatusFilter: String, CaseIterable {
    case all = "All"
    case issuesOnly = "Issues Only"
}
```

**Computed properties:**
- `filteredComponents` — filter by searchText, then by statusFilter
- `defaultFilter` — `.issuesOnly` if any component is non-operational, `.all` otherwise

**View structure:**

1. **Header** — Back button (`chevron.left` + "Services"), service icon, service name, status page link button. Below: status dot + label + relative timestamp.
2. **Incidents section** — Shown only when `snapshot.activeIncidents` is non-empty. Each incident: impact icon, name, status, full `latestUpdate` text (no line limit).
3. **Search + filter bar** — Search field (same style as dashboard filter) + segmented control for StatusFilter. Search field only appears if component count >= 10 (which it always will in this view, but keeps the threshold logic centralized).
4. **Component list** — `ScrollView` + `LazyVStack` for performance with 200+ rows. Each row: colored status dot, component name, status label. Same layout as current inline expand but in a lazy scrollable list.

**Key implementation notes:**
- Use `LazyVStack` (not `VStack`) for the component list. 200+ rows must be lazily rendered.
- The search field should debounce or filter synchronously — with 200 items, synchronous `filter` is fast enough (no need for async search).
- `.onAppear` sets `statusFilter` to `defaultFilter` based on snapshot state.

### Step 5: Add ServiceDetailView.swift to Xcode project

**File: `StatusMonitor.xcodeproj/project.pbxproj`**

Add the new file to the project's Sources build phase. This can be done via Xcode or by manually editing pbxproj (prefer Xcode).

### Step 6: Live snapshot updates in detail view

The detail view receives a `ProviderSnapshot` by value. To reflect live polling updates while the detail view is open, the `selectedSnapshot` binding in DashboardView should be updated when `manager.snapshots` changes:

```swift
.onChange(of: manager.snapshots) { _, newSnapshots in
    if let selected = selectedSnapshot,
       let updated = newSnapshots.first(where: { $0.id == selected.id }) {
        selectedSnapshot = updated
    }
}
```

This ensures the detail view reflects the latest poll without the user having to navigate back and forth.

## Files Changed

| File | Change |
|------|--------|
| `Views/ServiceDetailView.swift` | **New.** Detail view with header, incidents, search, filter, component list. |
| `Views/DashboardView.swift` | Add `selectedSnapshot` state, conditional rendering, threshold constant, `.onChange` for live updates, updated `onTap` logic. |
| `StatusMonitor.xcodeproj/project.pbxproj` | Add ServiceDetailView.swift to build sources. |

## Files NOT Changed

| File | Reason |
|------|--------|
| `Models/Models.swift` | No model changes. `ProviderSnapshot`, `ComponentSnapshot`, `IncidentSnapshot` already have all needed fields. |
| `Services/StatusManager.swift` | No service-layer changes. Polling and snapshot management are unaffected. |
| `Views/ProviderRowView` (in DashboardView.swift) | The row itself is unchanged. Only the `onTap` closure logic changes in the parent. |

## Acceptance Criteria

- [ ] Clicking a service with 10+ components opens the detail view (replaces dashboard content)
- [ ] Clicking a service with <10 components still uses inline expand
- [ ] Back button returns to dashboard
- [ ] Component search filters by name (case-insensitive)
- [ ] Status filter toggles between All and Issues Only
- [ ] Status filter defaults to "Issues Only" when any component is non-operational
- [ ] Status filter defaults to "All" when all components are operational
- [ ] Active incidents show full description text (not truncated)
- [ ] "View Status Page" link opens browser
- [ ] Service icon and overall status shown in detail header
- [ ] Component list performs well with 200+ components (lazy rendering)
- [ ] Detail view updates live when polling refreshes the snapshot
- [ ] Popover does not resize during navigation transitions
- [ ] Navigation transition animates smoothly (slide or crossfade)

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SwiftUI transition animation quirks in popover | Medium | Low | Keep transitions simple; fall back to no animation if buggy |
| LazyVStack scroll performance with 200+ rows | Low | Medium | Each row is lightweight (dot + text + text); SwiftUI handles this well |
| NavigationStack temptation | N/A | N/A | Decision already made to avoid it; use simple conditional rendering |
| Snapshot value type becomes stale | Low | Low | `.onChange` handler keeps it in sync with manager |

## Sources & References

- **Origin:** [docs/brainstorms/2026-04-11-service-detail-view-requirements.md](../brainstorms/2026-04-11-service-detail-view-requirements.md)
- **Linear:** [ZPR-25](https://linear.app/moollapps/issue/ZPR-25/service-detail-view-replace-inline-expand-for-large-services)
- **Existing patterns:** DashboardView's conditional rendering for onboarding/empty/loading/list states; ProviderRowView's inline expand
