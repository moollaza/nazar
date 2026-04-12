---
title: "In-App Feedback Form"
type: feat
status: draft
date: 2026-04-11
issue: ZPR-24
origin: docs/brainstorms/2026-04-11-feedback-form-requirements.md
---

# In-App Feedback Form — Implementation Plan

## Overview

Replace the raw GitHub Issue URL shortcut with a native in-app feedback form. The form collects feedback type, title, and description, then opens the browser with a well-structured pre-filled GitHub Issue. No backend required.

## Implementation

### Step 1: Create `Views/FeedbackView.swift`

New SwiftUI view presented as a modal sheet.

**Structure:**

```
FeedbackView
├── FeedbackType enum: .bug, .featureRequest, .other
├── @State feedbackType: FeedbackType = .bug
├── @State title: String = ""
├── @State description: String = ""
├── Computed: appVersion (from Bundle.main)
├── Computed: macOSVersion (from ProcessInfo)
├── @Environment(\.dismiss) var dismiss
└── submitFeedback() — builds URL and opens browser
```

**UI layout (top to bottom):**
1. Header: "Send Feedback" title
2. Picker (segmented): Bug Report | Feature Request | Other
3. TextField: "Title" (single line, required)
4. TextEditor: "Description" (multi-line, ~4-6 lines height)
5. System info display: read-only HStack showing app version and macOS version in caption style
6. Button bar: Cancel (left) | Submit (right, borderedProminent, disabled when title is empty)

**Submit action:**
- Build title string: `[Bug] user title` / `[Feature] user title` / `[Feedback] user title`
- Build body markdown:
  ```
  **Type:** Bug Report
  **App Version:** 1.0
  **macOS:** 15.4.0

  ## Description
  User's description text here
  ```
- Percent-encode title and body for URL query parameters
- Construct URL: `https://github.com/moollaza/status-monitor/issues/new?title=<encoded>&body=<encoded>`
- Open via `NSWorkspace.shared.open(url)`
- Dismiss sheet

**Frame:** `.frame(width: 420)` to match popover width. Let height be automatic.

### Step 2: Update `StatusMonitorApp.swift`

**Changes to `AppDelegate`:**

1. Add a state property to trigger the feedback sheet:
   ```swift
   var showFeedbackForm = false
   ```

2. Replace `sendFeedback()` body — instead of directly opening a URL, set `showFeedbackForm = true` and present a new `NSWindow` containing `FeedbackView`. Use `NSHostingController` to wrap the SwiftUI view in a window (same pattern as how the popover hosts `DashboardView`).

   Approach: Create a standalone `NSWindow` with `NSHostingController(rootView: FeedbackView(...))`. This avoids fighting with the popover lifecycle or Settings scene. The window is modal (`runModal` or `.beginSheet`), centered, non-resizable, and titled "Send Feedback".

   Alternative (simpler): Post a `Notification` that the SwiftUI `App` struct observes, toggling a sheet on the Settings scene. But this requires Settings window to be open, which is not guaranteed. Standalone window is more reliable.

3. Clean up: Remove the old URL-construction code from `sendFeedback()`.

**Standalone window approach (recommended):**
```swift
@objc private func sendFeedback() {
    let feedbackView = FeedbackView()
    let controller = NSHostingController(rootView: feedbackView)
    let window = NSWindow(contentViewController: controller)
    window.title = "Send Feedback"
    window.styleMask = [.titled, .closable]
    window.setContentSize(controller.sizeThatFits(in: NSSize(width: 420, height: 600)))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

The `FeedbackView` handles its own dismissal by closing its parent window via `NSApp.keyWindow?.close()` or `@Environment(\.dismiss)`.

### Step 3 (optional, v1.x): Add feedback button to SettingsView

Add a "Send Feedback" link or button to the footer bar of `SettingsView`, next to the service count. This presents `FeedbackView` as a `.sheet`. Lower priority than the right-click menu entry point.

## Files Changed

| File | Change |
|------|--------|
| `Views/FeedbackView.swift` | **New.** Feedback form view with type picker, title, description, system info, submit/cancel. |
| `StatusMonitorApp.swift` | Update `sendFeedback()` to present `FeedbackView` in a standalone window instead of opening raw URL. |

## Acceptance Criteria

1. Right-clicking menu bar icon and selecting "Send Feedback..." opens a native feedback form window.
2. Form has a segmented picker for Bug Report / Feature Request / Other.
3. Title field is required; Submit button is disabled when title is empty.
4. App version and macOS version are displayed and included in the submitted issue.
5. Clicking Submit opens the default browser with a pre-filled GitHub Issue containing the type tag in the title, and a structured body with type, versions, and description.
6. Clicking Cancel closes the form with no side effects.
7. Form window is non-resizable, centered, and feels native to macOS.

## Risks & Mitigations

- **URL length limit:** GitHub Issue URLs are capped around 8000 characters. Long descriptions could be truncated. Mitigation: this is rare for feedback forms; can add a character warning in v1.x (R9).
- **Window lifecycle:** Standalone `NSWindow` needs to be retained. Mitigation: store a reference on `AppDelegate` and nil it on close, or let the window controller manage its own lifecycle.
