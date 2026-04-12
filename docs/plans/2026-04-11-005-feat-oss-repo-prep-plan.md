---
title: "GitHub Repo Prep for Open Source Release"
type: feat
status: draft
date: 2026-04-11
issue: ZPR-29
---

# GitHub Repo Prep for Open Source Release

## Overview

Add standard open-source community files to the StatusMonitor repo before making it public. This is a non-code task: templates, licenses, and documentation only. No app changes.

## Problem Statement / Motivation

StatusMonitor is FOSS (MIT license, free at launch). The repo at `moollaza/status-monitor` needs standard OSS files before going public. Without these, contributors won't know how to contribute, users won't know how to install, and GitHub won't surface issue/PR templates.

## Files to Create

### 1. README.md (repo root)

**Purpose:** First thing visitors see. Communicates what the app does, how to get it, and how to build it.

**Content outline:**

- **App name + tagline:** "StatusMonitor — macOS menu bar app that monitors SaaS service status pages and alerts on outages."
- **Screenshot placeholder:** `![StatusMonitor Screenshot](docs/assets/screenshot.png)` with a TODO comment to replace after UI is finalized.
- **Features list:**
  - Monitor 100+ SaaS services from your menu bar
  - Instant notifications on status changes
  - Built-in catalog with one-click setup (5 services in under 60 seconds)
  - Color-coded menu bar icon (green/yellow/orange/red)
  - Supports Atlassian Statuspage and RSS/Atom feeds
  - Configurable per-service poll intervals
  - Native macOS app (SwiftUI, no Electron)
  - Free and open source (MIT)
- **Install section:**
  - Download the latest `.dmg` from [GitHub Releases](https://github.com/moollaza/status-monitor/releases)
  - Requires macOS 13 (Ventura) or later
- **Development setup:**
  - Prerequisites: Xcode 15+, macOS 13+
  - Clone the repo
  - Open `StatusMonitor.xcodeproj` in Xcode
  - Build and run the `StatusMonitor` scheme
  - CLI build: `xcodebuild -project StatusMonitor.xcodeproj -scheme StatusMonitor -configuration Release build`
- **Tech stack:** Swift 5.9+, SwiftUI, `@Observable`, `URLSession`, sandboxed
- **Contributing:** Link to `CONTRIBUTING.md`
- **License:** MIT — link to `LICENSE`

**Acceptance criteria:**
- [ ] Contains app description, features, install instructions, dev setup, tech stack, contributing link, license link
- [ ] Screenshot placeholder present with TODO note
- [ ] No broken links (relative links to files that will exist)
- [ ] No marketing fluff — factual, concise

---

### 2. LICENSE (repo root)

**Purpose:** MIT license for FOSS distribution.

**Content:** Standard MIT license text with:
- Year: 2026
- Copyright holder: Zaahir Moolla

**Acceptance criteria:**
- [ ] Valid MIT license text
- [ ] Correct year and copyright holder
- [ ] Named `LICENSE` (no extension)

---

### 3. CONTRIBUTING.md (repo root)

**Purpose:** Guide for contributors.

**Content outline:**

- **Welcome message:** Brief, encouraging
- **How to contribute:**
  - Fork the repo, create a branch, submit a PR
  - For bugs: open an issue first using the bug report template
  - For features: open an issue first using the feature request template
- **Development setup:** Link to README dev setup section
- **Code style:**
  - Follow Apple's Swift API Design Guidelines
  - Use `@Observable` (not `ObservableObject`)
  - `StatusManager` is `@MainActor` — all snapshot mutations on main thread
  - New providers: add to catalog via `Resources/catalog.json`
- **PR process:**
  - Fill out the PR template
  - Keep PRs focused — one feature or fix per PR
  - Ensure the app builds with no warnings
  - Test on macOS 13+ if possible
- **Issue reporting:**
  - Use GitHub issue templates
  - Include macOS version and app version
  - Include steps to reproduce for bugs
- **Code of Conduct:** Link to `CODE_OF_CONDUCT.md`

**Acceptance criteria:**
- [ ] Covers fork/branch/PR workflow
- [ ] References Swift API Design Guidelines
- [ ] Lists key project conventions (@Observable, @MainActor)
- [ ] Links to CODE_OF_CONDUCT.md
- [ ] Tone is welcoming but concise

---

### 4. CODE_OF_CONDUCT.md (repo root)

**Purpose:** Contributor Covenant adoption.

**Content:** Contributor Covenant v2.1 (full text). Contact method: GitHub Issues or email (placeholder `conduct@moollapps.com` — confirm with maintainer).

**Acceptance criteria:**
- [ ] Full Contributor Covenant v2.1 text
- [ ] Contact method specified
- [ ] Named `CODE_OF_CONDUCT.md`

---

### 5. .github/ISSUE_TEMPLATE/bug_report.yml

**Purpose:** Structured bug reports using GitHub Issue Forms (YAML, not Markdown).

**Fields:**
- `name`: Bug Report
- `description`: Report a bug in StatusMonitor
- `labels`: ["bug"]
- `body`:
  - **Description** (textarea, required): What happened?
  - **Steps to reproduce** (textarea, required): Numbered steps
  - **Expected behavior** (textarea, required): What should have happened?
  - **App version** (input, required): e.g. "1.0.0"
  - **macOS version** (dropdown, required): Sequoia 15.x, Sonoma 14.x, Ventura 13.x
  - **Screenshots** (textarea, optional): Attach screenshots if helpful
  - **Additional context** (textarea, optional): Logs, affected services, etc.

**Acceptance criteria:**
- [ ] Valid YAML syntax
- [ ] All required fields marked as required
- [ ] macOS version is a dropdown with supported versions
- [ ] Bug label auto-applied
- [ ] File path is `.github/ISSUE_TEMPLATE/bug_report.yml`

---

### 6. .github/ISSUE_TEMPLATE/feature_request.yml

**Purpose:** Structured feature requests using GitHub Issue Forms.

**Fields:**
- `name`: Feature Request
- `description`: Suggest a feature for StatusMonitor
- `labels`: ["enhancement"]
- `body`:
  - **Description** (textarea, required): What feature would you like?
  - **Use case** (textarea, required): Why do you need this? What problem does it solve?
  - **Alternatives considered** (textarea, optional): Other solutions you've considered
  - **Additional context** (textarea, optional): Mockups, examples, references

**Acceptance criteria:**
- [ ] Valid YAML syntax
- [ ] Description and use case are required
- [ ] Enhancement label auto-applied
- [ ] File path is `.github/ISSUE_TEMPLATE/feature_request.yml`

---

### 7. .github/PULL_REQUEST_TEMPLATE.md

**Purpose:** Standardize PR descriptions.

**Content:**

```markdown
## Summary

<!-- What does this PR do? Why? -->

## Changes

- 

## Testing

- [ ] App builds with no warnings
- [ ] Tested on macOS ___

## Screenshots

<!-- If applicable -->

## Checklist

- [ ] PR title is concise and descriptive
- [ ] Changes are focused (one feature or fix)
- [ ] No hardcoded secrets or credentials
```

**Acceptance criteria:**
- [ ] Contains summary, changes, testing, screenshots, and checklist sections
- [ ] Testing checklist includes build check and macOS version
- [ ] File path is `.github/PULL_REQUEST_TEMPLATE.md`

---

### 8. .github/FUNDING.yml

**Purpose:** Enable GitHub Sponsors button on the repo.

**Content:**

```yaml
github: moollaza
```

**Acceptance criteria:**
- [ ] Valid YAML
- [ ] GitHub username is `moollaza`
- [ ] File path is `.github/FUNDING.yml`

---

## File Summary

| File | Type | Purpose |
|------|------|---------|
| `README.md` | Documentation | Repo landing page |
| `LICENSE` | Legal | MIT license |
| `CONTRIBUTING.md` | Documentation | Contributor guide |
| `CODE_OF_CONDUCT.md` | Documentation | Contributor Covenant v2.1 |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Template | Bug report form |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Template | Feature request form |
| `.github/PULL_REQUEST_TEMPLATE.md` | Template | PR description template |
| `.github/FUNDING.yml` | Config | GitHub Sponsors |

**Total files: 8** (all new, no existing files modified)

## Implementation Notes

- All files are standard templates with project-specific values filled in. No code changes.
- Screenshot placeholder in README should be updated after UI work is complete (Phase 5-7 of v1 plan).
- `conduct@moollapps.com` email in CODE_OF_CONDUCT needs confirmation — may use GitHub Issues instead.
- FUNDING.yml uses `moollaza` GitHub username — confirm GitHub Sponsors is enabled.
- These files can be created on any branch and merged independently. No dependencies on app code.

## Scope Boundary

Out of scope for this issue:
- GitHub Actions CI/CD workflows (separate issue)
- Release automation
- CHANGELOG.md (not needed for v1 per requirements)
- Security policy (SECURITY.md — consider for post-v1)

## Estimated Scope

**Small.** All files are standard OSS templates. No code, no tests, no build changes. Can be completed in a single PR.
