---
date: 2026-04-11
topic: in-app-feedback-form
issue: ZPR-24
---

# In-App Feedback Form

## Problem Frame

"Send Feedback" in the right-click context menu currently opens a raw GitHub Issue URL with minimal pre-filled content. The user has no control over the issue title, no way to categorize feedback (bug vs feature request), and the experience is jarring — jumping from a native app to a browser with a URL-encoded template. An in-app form lets users compose structured feedback before it opens the browser, resulting in higher-quality reports and a more polished feel.

## Requirements

### Must Have

- R1. **Modal sheet triggered from right-click menu.** Clicking "Send Feedback..." in the context menu presents a native SwiftUI sheet (modal). The sheet appears over the popover or as a standalone window if the popover is closed.
- R2. **Feedback type picker.** Segmented control or Picker with three options: Bug Report, Feature Request, Other. Defaults to "Bug Report".
- R3. **Title field.** Single-line TextField for a short summary. Required — submit button disabled when empty.
- R4. **Description field.** Multi-line TextEditor for details. Optional but encouraged. Placeholder text hints at what to include (e.g. "Steps to reproduce..." for bugs, "Describe your idea..." for features).
- R5. **Auto-populated system info.** App version (`CFBundleShortVersionString`) and macOS version (`ProcessInfo.processInfo.operatingSystemVersionString`) are collected automatically. Displayed as read-only text at the bottom of the form so the user knows what's being sent.
- R6. **Submit action opens browser with pre-filled GitHub Issue.** Constructs a GitHub Issue URL with query parameters: `title` (prefixed with feedback type tag, e.g. `[Bug] Title`), `body` (structured markdown with type, description, app version, macOS version). Opens in default browser via `NSWorkspace.shared.open()`. Dismisses the sheet after opening.
- R7. **Cancel button.** Dismisses the sheet without action. No confirmation needed (form content is ephemeral).

### Nice to Have (v1.x)

- R8. **Settings access point.** A "Send Feedback" button or link in SettingsView footer, presenting the same sheet. Low priority — the right-click menu is the primary entry point.
- R9. **Character limit indicator.** GitHub URL length is limited (~8000 chars). Show a subtle warning if the body approaches this limit. Not blocking — users rarely hit this.

### Out of Scope (v2)

- Backend submission (CF Worker + GitHub API) — eliminates the browser hop but requires infrastructure.
- Screenshot/attachment support — GitHub Issue URLs can't carry attachments.
- Saved drafts — unnecessary complexity for a simple feedback form.

## Technical Approach

- New file `Views/FeedbackView.swift` containing a `FeedbackView` SwiftUI view.
- Use `@State` for form fields (type, title, description). No persistence needed.
- `@Environment(\.dismiss)` to close the sheet.
- URL construction reuses the pattern from the current `sendFeedback()` in `StatusMonitorApp.swift`, but with user-provided title and structured body.
- The sheet is presented from `AppDelegate` using a new `@Published` or callback pattern. Since `AppDelegate` is not a SwiftUI view, the simplest approach is a shared `@State` bool on the app struct or a notification-based trigger.
- GitHub Issue URL format: `https://github.com/moollaza/status-monitor/issues/new?title=<encoded>&body=<encoded>&labels=<type>`

## Success Criteria

- User can open feedback form from right-click menu, fill in type/title/description, and submit to get a pre-filled GitHub Issue in their browser.
- Cancel dismisses cleanly with no side effects.
- App version and macOS version appear in the submitted issue body without user effort.
- Form is simple, native-feeling, and takes under 30 seconds to fill out.
