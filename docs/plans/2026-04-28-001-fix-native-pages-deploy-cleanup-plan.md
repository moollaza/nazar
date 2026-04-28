---
title: fix: Clean up native Pages deployment
type: fix
status: active
date: 2026-04-28
---

# fix: Clean up native Pages deployment

## Overview

Cloudflare Pages is now connected to GitHub natively, so the repo should stop running the legacy GitHub Actions Wrangler deployment. The cleanup removes duplicate deployment ownership while preserving the website catalog freshness guard that used to be handled during the deploy action.

## Problem Frame

The latest website deployment did not reflect the most recent logo work because the legacy `.github/workflows/deploy-website.yml` run timed out after five minutes. Native Cloudflare Pages Git integration now owns deployments for `main`, so keeping a second Wrangler deploy workflow creates duplicate deployment paths, stale-status confusion, and unnecessary Cloudflare secrets in GitHub Actions.

## Requirements Trace

- R1. Native Cloudflare Pages Git integration should be the only automatic website deployment path.
- R2. The public website should still serve committed assets from `website/`.
- R3. The website catalog must not silently drift from `Resources/catalog.json`.
- R4. The repo should document the current deployment model clearly enough to avoid reintroducing the old action.

## Scope Boundaries

- Do not change the website design, logo assets, or Cloudflare dashboard settings from code.
- Do not modify app release workflows.
- Do not require a build step in Cloudflare Pages while `website/catalog.json` is committed and guarded by CI.

## Context & Research

### Relevant Code and Patterns

- `.github/workflows/deploy-website.yml` deploys with `wrangler pages deploy website --project-name=usenazar --branch=main` and currently times out.
- `.github/workflows/visual.yml` already runs on website and catalog changes, and verifies `Resources/catalog.json` matches `website/catalog.json`.
- `website/index.html` fetches `catalog.json` from the deployed `website/` directory.
- `README.md` currently states the static website lives in `website/` and is deployed to Cloudflare Pages.

### Institutional Learnings

- Existing plans reference manual `wrangler pages deploy website/`; this plan supersedes that for the current native Pages setup.

### External References

- Cloudflare Pages Git integration docs: Git integration automatically builds and deploys when pushing to the connected GitHub repository.
- Cloudflare Pages build configuration docs: no framework is required, and build settings define the build command and output directory. For this repo, a build command is unnecessary because the static output is committed under `website/`.

## Key Technical Decisions

- Remove the GitHub Actions deploy workflow: Native Pages owns deployment now, and the old Wrangler action has already produced stale deployment confusion.
- Keep `website/catalog.json` committed: This preserves a no-build static site and lets Cloudflare deploy `website/` directly.
- Rely on visual CI for catalog freshness: `.github/workflows/visual.yml` already fails when `Resources/catalog.json` and `website/catalog.json` differ.
- Update README deployment wording: The deployment model should be explicit in the repo.

## Open Questions

### Resolved During Planning

- Is a Cloudflare Pages build step required? No. With `website/catalog.json` committed and CI checking it against `Resources/catalog.json`, native Pages can deploy the static `website/` output without a copy step.

### Deferred to Implementation

- Exact Cloudflare dashboard labels: Cloudflare may label the setting as build directory, output directory, or root/output fields depending on UI flow. Verification remains dashboard-side.

## Implementation Units

- [x] **Unit 1: Remove legacy deploy workflow**

**Goal:** Stop GitHub Actions from deploying the website through Wrangler.

**Requirements:** R1

**Dependencies:** Native Cloudflare Pages Git integration has been connected by the user.

**Files:**
- Delete: `.github/workflows/deploy-website.yml`

**Approach:**
- Remove the whole workflow rather than disabling branches or leaving dead secrets references.

**Patterns to follow:**
- Keep `.github/workflows/visual.yml` intact as the website quality gate.

**Test scenarios:**
- GitHub Actions should no longer show a `Deploy Website to Cloudflare Pages` workflow from this branch after the deletion lands.
- Website visual CI should still run for website/catalog changes.

**Verification:**
- The workflow file is gone and no remaining workflow invokes `wrangler pages deploy`.

- [x] **Unit 2: Document native Pages deployment**

**Goal:** Make the current deployment model clear for future maintainers.

**Requirements:** R1, R2, R3, R4

**Dependencies:** Unit 1

**Files:**
- Modify: `README.md`

**Approach:**
- Update the tech stack/deployment note to say the static website is deployed by Cloudflare Pages Git integration from `website/`.
- Mention that `website/catalog.json` is committed and checked against `Resources/catalog.json` by website visual CI, so no Pages build command is required.

**Patterns to follow:**
- Keep README wording concise and factual.

**Test scenarios:**
- Documentation should not refer readers to the old Wrangler deploy action.
- Documentation should explain why catalog freshness is still protected without a build step.

**Verification:**
- README matches the native Pages setup and references the existing CI guard.

## System-Wide Impact

- **Interaction graph:** GitHub push to `main` now triggers Cloudflare Pages directly, while GitHub Actions remains responsible for visual checks only.
- **Error propagation:** Deploy failures should appear in Cloudflare Pages deployment status instead of the removed GitHub Actions deploy workflow.
- **State lifecycle risks:** The main risk is Cloudflare dashboard misconfiguration outside the repo; document expected static output location.
- **API surface parity:** No app API or website runtime behavior changes.
- **Integration coverage:** Visual CI continues covering website render and catalog freshness.

## Risks & Dependencies

- Cloudflare Pages must be configured to deploy `website/` as the static output. If configured with repo root as output, the site may serve the wrong files.
- If future work stops committing `website/catalog.json`, Cloudflare Pages would need a build command to copy `Resources/catalog.json` into `website/`.

## Documentation / Operational Notes

- After this lands, confirm the next Cloudflare Pages deployment for `main` points at the merge commit and `usenazar.com` serves the new logo.
- The old GitHub Actions Cloudflare secrets can be removed later after native Pages has deployed successfully.

## Sources & References

- Cloudflare Pages Git integration: https://developers.cloudflare.com/pages/get-started/git-integration/
- Cloudflare Pages build configuration: https://developers.cloudflare.com/pages/configuration/build-configuration/
- Related workflow: `.github/workflows/visual.yml`
