---
title: "Mute/Ignore Per Service"
type: feat
status: planned
date: 2026-04-11
origin: docs/brainstorms/2026-04-11-mute-service-requirements.md
linear: ZPR-28
---

# Mute/Ignore Per Service — Implementation Plan

## Overview

Add per-service mute toggle so users can exclude individual services from the menu bar worst-status indicator and notifications while keeping them visible and polled in the dashboard. Primary interaction via context menu on service rows; secondary toggle in Settings.

## Problem Statement / Motivation

Services like Cloudflare report frequent regional issues that are irrelevant to most users. These inflate the worst-status indicator and trigger unnecessary notifications, causing alert fatigue. Users need a way to say "I want to see this, but don't bother me about it."

## Design Decisions (resolved)

1. **Optional Codable field.** `isMuted` is `var isMuted: Bool` with a default of `false`, decoded via `decodeIfPresent` (or using a default value in a custom init). Existing UserDefaults data without the key decodes without error.
2. **Filter in recalcWorstStatus, not in snapshots.** Muted providers still have snapshots. The filter is applied only at the worst-status aggregation point and at the notification trigger point.
3. **previousStatuses updated even when muted.** Prevents notification burst on unmute.
4. **Context menu uses `.contextMenu {}` modifier.** Standard SwiftUI, no NSMenu bridging needed.
5. **Dimmed row: opacity 0.5 + speaker.slash.fill icon.** Minimal visual change, no layout shift.

## Implementation

### Step 1: Add `isMuted` to Provider model

**File: `Models/Models.swift`**

Add `var isMuted: Bool` to the `Provider` struct. Update both initializers to default it to `false`.

```swift
struct Provider: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String
    var type: ProviderType
    var pollIntervalSeconds: Int
    var isEnabled: Bool
    var catalogEntryId: String?
    var isMuted: Bool  // NEW

    init(name: String, baseURL: String, type: ProviderType = .statuspage,
         pollIntervalSeconds: Int = 60, isEnabled: Bool = true,
         catalogEntryId: String? = nil, isMuted: Bool = false) {
        // ... existing fields ...
        self.isMuted = isMuted
    }

    init(from entry: CatalogEntry) {
        self.init(name: entry.name, baseURL: entry.baseURL, type: entry.type, catalogEntryId: entry.id)
        // isMuted defaults to false via the primary init
    }
}
```

For backwards compatibility, add a custom `init(from decoder:)` that uses `decodeIfPresent` for `isMuted`:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    baseURL = try container.decode(String.self, forKey: .baseURL)
    type = try container.decode(ProviderType.self, forKey: .type)
    pollIntervalSeconds = try container.decode(Int.self, forKey: .pollIntervalSeconds)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    catalogEntryId = try container.decodeIfPresent(String.self, forKey: .catalogEntryId)
    isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
}
```

Add `isMuted` to `CodingKeys` enum.

### Step 2: Add `toggleMute` to StatusManager

**File: `Services/StatusManager.swift`**

Add a method to toggle mute state and recalculate:

```swift
func toggleMute(for provider: Provider) {
    guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
    providers[idx].isMuted.toggle()
    saveProviders()
    recalcWorstStatus()
}
```

### Step 3: Exclude muted services from `recalcWorstStatus()`

**File: `Services/StatusManager.swift`**

Update `recalcWorstStatus()` to filter out muted providers:

```swift
private func recalcWorstStatus() {
    let mutedIds = Set(providers.filter(\.isMuted).map(\.id))
    let newStatus = snapshots
        .filter { $0.error == nil && !mutedIds.contains($0.id) }
        .map(\.overallStatus)
        .max() ?? .operational
    if newStatus != worstStatus {
        worstStatus = newStatus
        onWorstStatusChanged?(newStatus)
    }
}
```

### Step 4: Skip notifications for muted services

**File: `Services/StatusManager.swift`**

In `applySnapshot(_:for:)`, guard the notification call:

```swift
private func applySnapshot(_ snapshot: ProviderSnapshot, for provider: Provider) {
    let previousStatus = previousStatuses[provider.id]

    if let idx = snapshots.firstIndex(where: { $0.id == provider.id }) {
        snapshots[idx] = snapshot
    } else {
        snapshots.append(snapshot)
    }

    // Notify on status change — skip if muted
    if !provider.isMuted, let prev = previousStatus, prev != snapshot.overallStatus {
        NotificationService.shared.notify(
            provider: provider.name,
            from: prev,
            to: snapshot.overallStatus,
            incident: snapshot.activeIncidents.first?.name
        )
    }

    // Always update previousStatuses (even when muted) to prevent burst on unmute
    previousStatuses[provider.id] = snapshot.overallStatus
    recalcWorstStatus()
}
```

### Step 5: Add context menu to ProviderRowView

**File: `Views/DashboardView.swift`**

Add `isMuted` and `onToggleMute` parameters to `ProviderRowView`. Apply `.contextMenu` to the row's top-level VStack. Apply opacity when muted.

```swift
struct ProviderRowView: View {
    let snapshot: ProviderSnapshot
    var catalogId: String? = nil
    var statusPageURL: URL? = nil
    var isMuted: Bool = false          // NEW
    let isExpanded: Bool
    let onTap: () -> Void
    var onToggleMute: (() -> Void)?    // NEW

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // ... existing icon stack ...

                // Mute indicator icon (NEW)
                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(snapshot.name)
                    .font(.system(.body, weight: .medium))

                // ... rest of row ...
            }
            // ... expanded detail ...
        }
        .opacity(isMuted ? 0.5 : 1.0)
        .contextMenu {
            Button {
                onToggleMute?()
            } label: {
                Label(
                    isMuted ? "Unmute Service" : "Mute Service",
                    systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
        }
        // ... existing modifiers ...
    }
}
```

Update the `ForEach` in `DashboardView` to pass the new parameters:

```swift
ForEach(sortedSnapshots) { snapshot in
    let provider = manager.providers.first(where: { $0.id == snapshot.id })
    ProviderRowView(
        snapshot: snapshot,
        catalogId: provider?.catalogEntryId,
        statusPageURL: provider.flatMap { URL(string: $0.baseURL) },
        isMuted: provider?.isMuted ?? false,
        isExpanded: expandedProvider == snapshot.id,
        onTap: { /* existing */ },
        onToggleMute: {
            if let p = provider { manager.toggleMute(for: p) }
        }
    )
}
```

### Step 6: Add mute toggle in SettingsView

**File: `Views/SettingsView.swift`**

Add a mute/unmute button in each provider row, between the poll interval menu and the remove button:

```swift
// Mute toggle
Button {
    manager.toggleMute(for: provider)
} label: {
    Image(systemName: provider.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        .foregroundStyle(provider.isMuted ? .orange : .secondary)
        .font(.system(size: 14))
}
.buttonStyle(.plain)
.help(provider.isMuted ? "Unmute service" : "Mute service")
```

## Files Changed

| File | Change |
|------|--------|
| `Models/Models.swift` | Add `isMuted` property to `Provider`, add to `CodingKeys`, add custom `init(from:)` for backwards compat |
| `Services/StatusManager.swift` | Add `toggleMute(for:)`, filter muted in `recalcWorstStatus()`, skip notifications for muted in `applySnapshot` |
| `Views/DashboardView.swift` | Pass `isMuted`/`onToggleMute` to `ProviderRowView`, add `.contextMenu`, add mute icon, add opacity |
| `Views/SettingsView.swift` | Add mute/unmute button in provider row |

**No new files.** All changes are modifications to existing files.

## Acceptance Criteria

- [ ] Adding `isMuted` field does not break decoding of existing UserDefaults data (backwards compat)
- [ ] Muted service is still polled on its normal interval
- [ ] Muted service still appears in dashboard with correct real-time status
- [ ] Muted service row is dimmed (opacity 0.5) with a `speaker.slash.fill` icon
- [ ] Muted service is excluded from `worstStatus` calculation — menu bar icon reflects unmuted services only
- [ ] Muted service does not trigger notifications on status change
- [ ] Unmuting a service does not trigger a retroactive notification for its current status
- [ ] Right-click on service row shows "Mute Service" / "Unmute Service" context menu item
- [ ] Mute/unmute toggle available in Settings per-provider
- [ ] Mute state persists across app restarts
- [ ] Muting/unmuting immediately recalculates worst status

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Existing UserDefaults data missing `isMuted` key | Certain (first upgrade) | None | `decodeIfPresent` with `?? false` default handles this |
| User confusion about muted vs disabled | Low | Low | Visual indicator (dimmed + icon) makes state obvious; tooltip on context menu clarifies |
| Notification burst on unmute | Medium | Low | `previousStatuses` updated even when muted — no stale state to compare against |

## Estimated Scope

**Small.** Four files modified, no new files, no new dependencies. Core logic change is two filter conditions and one new Bool property.
