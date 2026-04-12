---
title: "ZPR-27 — Launch at Login Toggle"
type: feat
status: draft
date: 2026-04-11
issue: ZPR-27
---

# ZPR-27 — Launch at Login Toggle

## Overview

Add a "Launch at Login" toggle to SettingsView using `SMAppService.mainApp` (macOS 13+). Menu bar apps are expected to offer this; without it users must manually add the app to System Settings > Login Items.

## Motivation

StatusMonitor is a menu bar utility — it should be running whenever the Mac is on. Users expect a single toggle to enable this. macOS 13+ provides `SMAppService` which replaces the old helper-app approach with a single API call, no helper bundle required.

## Implementation

### 1. Import ServiceManagement

Add `import ServiceManagement` at the top of `Views/SettingsView.swift`.

### 2. Add computed state for login item status

Inside `SettingsView`, add a computed property that reads `SMAppService.mainApp.status`:

```swift
private var isLaunchAtLoginEnabled: Bool {
    SMAppService.mainApp.status == .enabled
}
```

### 3. Add Toggle to the footer area

In the existing footer `HStack` (line ~106-115), insert a Toggle between the service count text and the "Done" button:

```swift
HStack {
    Text("\(manager.providers.count) services")
        .font(.caption)
        .foregroundStyle(.secondary)
    Spacer()
    Toggle("Launch at Login", isOn: Binding(
        get: { SMAppService.mainApp.status == .enabled },
        set: { newValue in toggleLaunchAtLogin(newValue) }
    ))
    .toggleStyle(.checkbox)
    .controlSize(.small)
    Spacer()
    Button("Done") { dismiss() }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
}
.padding()
```

### 4. Add toggle handler with error handling

Add a private method to SettingsView:

```swift
private func toggleLaunchAtLogin(_ enable: Bool) {
    do {
        if enable {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        // Log error; the toggle will revert on next read since status didn't change
        print("Launch at login failed: \(error.localizedDescription)")
    }
}
```

### 5. Error handling considerations

- `SMAppService.mainApp.register()` throws if the app is not code-signed or sandboxed incorrectly. In debug/unsigned builds, the toggle will fail silently (the status remains `.notRegistered` and the toggle visually reverts on re-render).
- No alert is shown to the user on failure — the toggle simply won't stick. This is acceptable because the failure case only occurs in development builds. In production (signed, notarized), the API works reliably.
- If we want to surface errors later, add a `@State private var launchAtLoginError: String?` and show a small inline warning.

### 6. No entitlement changes needed

`SMAppService.mainApp` works within the existing sandbox entitlements. No new capabilities or entitlements are required. The existing `com.apple.security.network.client` entitlement is unrelated and unaffected.

## Constraints

- **Code signing required**: `SMAppService` only works with a properly code-signed app. In unsigned debug builds, `register()` will throw and the toggle will not persist. This is expected and documented in Apple's API.
- **macOS 13+ only**: The app already targets macOS 14.6+, so this is satisfied.
- **No helper app needed**: Unlike the legacy `SMLoginItemSetEnabled`, `SMAppService.mainApp` manages registration directly.

## Files Changed

| File | Change |
|------|--------|
| `Views/SettingsView.swift` | Add `import ServiceManagement`, toggle in footer, `toggleLaunchAtLogin(_:)` method |

## Acceptance Criteria

1. SettingsView footer shows a "Launch at Login" checkbox toggle
2. Toggling ON calls `SMAppService.mainApp.register()` — app appears in System Settings > Login Items
3. Toggling OFF calls `SMAppService.mainApp.unregister()` — app is removed from Login Items
4. Toggle state reflects actual `SMAppService.mainApp.status` (not a stored boolean)
5. Errors from `register()`/`unregister()` are handled gracefully (no crash, toggle reverts)
6. Works correctly in signed release builds; gracefully degrades in unsigned debug builds
7. No new entitlements or Info.plist changes required

## Estimated Scope

**Small** — single file change, ~20 lines of code.
