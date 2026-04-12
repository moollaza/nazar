---
title: "feat: UX polish and catalog finalization"
type: feat
status: active
date: 2026-04-12
origin: docs/brainstorms/2026-04-12-ux-overhaul-requirements.md
---

# UX Polish and Catalog Finalization

## Overview

Complete the remaining UX overhaul items (4 not done, 7 partial) and finalize the 1,683-service catalog. Most of the UX overhaul from the origin requirements doc is already implemented. This plan targets the gap between current state and "feels like a polished native macOS app."

## Implementation Units

### Unit 1: Popover arrow removal + keyboard shortcut

**Goal:** Remove the NSPopover arrow and add Cmd+R refresh shortcut.

**Files:**
- `StatusMonitorApp.swift:46-54` — popover setup
- `StatusMonitorApp.swift:56-59` — event monitors

**Approach:**
1. After `popover.behavior = .transient` (line 48), add: `popover.hasFullSizeContent = true`
2. If `hasFullSizeContent` doesn't hide the arrow on macOS 14.6, use `popover.setValue(true, forKeyPath: "shouldHideAnchor")` (private but widely used)
3. Add local event monitor for Cmd+R:
```swift
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "r" {
        self?.statusManager.pollAll()
        return nil // consume the event
    }
    return event
}
```

**Verification:** Popover appears without arrow. Cmd+R triggers refresh when popover is focused.

**Patterns to follow:** Existing event monitor pattern at `StatusMonitorApp.swift:57`

---

### Unit 2: Header button hover and press states

**Goal:** Every interactive element in the dashboard header has visible hover and press feedback.

**Files:**
- `Views/DashboardView.swift:86-142` — header buttons (issues filter, sort picker, refresh, settings gear)

**Approach:**
Extract a reusable `HeaderButton` view that wraps each button with hover+press states:

```swift
struct HeaderButton: View {
    let icon: String
    let isActive: Bool
    var activeColor: Color = .orange
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
```

Replace the 4 header buttons (issues filter, refresh, settings gear) with `HeaderButton`. The sort picker is a SwiftUI `Picker` which already has native hover — leave it.

**Verification:** Hovering over filter, refresh, and settings buttons shows a subtle rounded background highlight. Mouse-down shows pressed state.

**Patterns to follow:** `ProviderRowView` hover pattern at `DashboardView.swift:286-345`

---

### Unit 3: Tooltip update on every poll

**Goal:** Menu bar tooltip always reflects current status, not just when worst-status changes.

**Files:**
- `StatusMonitorApp.swift:72-75` — onWorstStatusChanged callback
- `Services/StatusManager.swift` — poll cycle completion

**Approach:**
Add a second callback `onPollCycleComplete` that fires after every `pollAll()` finishes. Call `updateTooltip()` from it. This way the tooltip updates even when status doesn't change (e.g., count of degraded services changes but worst-status stays the same).

In `StatusManager`:
```swift
var onPollCycleComplete: (() -> Void)?
```
Call it at the end of `pollAll()`.

In `AppDelegate.applicationDidFinishLaunching`:
```swift
statusManager.onPollCycleComplete = { [weak self] in
    self?.updateTooltip()
}
```

**Verification:** Tooltip updates after each poll cycle, not just on worst-status changes.

---

### Unit 4: Notification toggle in Preferences

**Goal:** Replace placeholder text with a real notification enable/disable toggle.

**Files:**
- `Views/SettingsView.swift:378-406` — PreferencesSettingsView
- `Services/NotificationService.swift` — notification delivery

**Approach:**
Add `@AppStorage("notificationsEnabled") private var notificationsEnabled = true` in PreferencesSettingsView. Replace the placeholder text with a Toggle. In NotificationService, check this preference before delivering notifications.

```swift
Section("Notifications") {
    Toggle("Send notifications on status changes", isOn: $notificationsEnabled)
    Text("You'll be notified when a service status changes.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Verification:** Toggle appears in Preferences. When off, no notifications fire on status changes.

---

### Unit 5: Recommended services in Catalog

**Goal:** First-time users see popular services pre-suggested at the top of the catalog.

**Files:**
- `Views/SettingsView.swift:262-373` — CatalogSettingsView

**Approach:**
Add a "Popular" section at the top of the catalog list (before category groups) showing ~10 high-profile services: GitHub, Cloudflare, Vercel, OpenAI, Anthropic, Stripe, AWS (if added), Discord, Notion, Figma. These are shown with checkboxes like other catalog entries. No special "pre-checked" behavior — just prominent placement.

```swift
// At the top of the List, before ForEach(filteredEntries)
if searchText.isEmpty {
    Section("Popular") {
        ForEach(popularEntries) { entry in
            // Same toggle row as category entries
        }
    }
}
```

`popularEntries` is a computed property that filters `catalog.entries` by a hardcoded list of IDs.

**Verification:** "Popular" section appears at top of catalog when search is empty. Entries can be toggled on/off.

---

### Unit 6: Website catalog count update

**Goal:** Marketing site reflects the actual catalog size.

**Files:**
- `website/index.html` — catalog count mentions

**Approach:**
Find and replace the old count with "1,600+" (round down for safety since catalog may grow/shrink). Update any "N services" text in the hero, features section, and catalog preview.

**Verification:** Website shows updated count. Redeploy via `wrangler pages deploy website/`.

---

### Unit 7: Auto-categorize uncategorized services

**Goal:** Reduce "Uncategorized" from 1,325 to under 200.

**Files:**
- `Resources/catalog.json`
- `scripts/auto-categorize.py`

**Approach:**
The keyword-based auto-categorizer only catches ~15%. Use a two-pass approach:
1. **Web search pass:** For the top 200 uncategorized services (by component count, as a proxy for size/importance), search "what does [service name] do" and assign a category.
2. **Bulk LLM pass:** Feed remaining names to Claude in batches of 50, asking for category assignment from the existing category list. Write results back to catalog.json.

This is a data task, not a code task. Run it as a script that outputs updated catalog.json.

**Verification:** `Uncategorized` count drops below 200. Run `python3 scripts/audit-catalog.py` to verify all entries still pass.

---

## Dependency Order

```
Unit 1 (popover arrow + Cmd+R) — no deps
Unit 2 (hover states) — no deps
Unit 3 (tooltip) — no deps
Unit 4 (notification toggle) — no deps
Unit 5 (recommended) — no deps
Unit 6 (website) — no deps
Unit 7 (categorize) — no deps
```

All units are independent — can be parallelized.

## Acceptance Criteria

- [ ] Popover has no arrow
- [ ] Cmd+R refreshes all services when popover is focused
- [ ] All header buttons (filter, refresh, settings) show hover highlight
- [ ] Menu bar tooltip updates after every poll, not just worst-status changes
- [ ] Notification toggle in Preferences enables/disables status change notifications
- [ ] "Popular" section appears at top of Catalog tab with ~10 well-known services
- [ ] Website shows "1,600+ services" catalog count
- [ ] Uncategorized services reduced to <200
- [ ] All existing functionality still works (no regressions)

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-12-ux-overhaul-requirements.md](docs/brainstorms/2026-04-12-ux-overhaul-requirements.md) — key decisions: popover=dashboard only, Settings=separate window, uniform drill-down, no sheets from popover
- Existing hover pattern: `Views/DashboardView.swift:286-345`
- Popover setup: `StatusMonitorApp.swift:46-54`
- Event monitor pattern: `StatusMonitorApp.swift:56-59`
- Catalog view: `Views/SettingsView.swift:262-373`
