---
title: "refactor: Switch repository license to Apache-2.0"
type: refactor
status: completed
date: 2026-04-28
---

# refactor: Switch repository license to Apache-2.0

## Overview

Replace Nazar's current Functional Source License 1.1 grant with Apache License 2.0 and update active public-facing copy so the repository, README, website, and agent guidance describe the same open source licensing posture.

This is a documentation and legal-metadata change only. It should not alter app behavior, website layout, release automation, provider catalog data, or runtime code.

## Problem Frame

Nazar currently describes itself as source-available under FSL 1.1, converting to Apache 2.0 on 2028-04-12. The user wants to move away from the BSL/FSL category due to ecosystem controversy and ambiguity around source-available licenses. Apache-2.0 is the least disruptive replacement because it is already the declared future license in `LICENSE`, is OSI-approved, is widely recognized by GitHub/license tooling, and preserves a permissive contribution posture with an explicit patent grant.

## Requirements Trace

- R1. Replace the root `LICENSE` file with the canonical Apache License 2.0 text.
- R2. Update all active user-facing and contributor-facing references from FSL/source-available/conversion language to Apache-2.0/open source language.
- R3. Keep historical planning documents intact unless they are actively used as current project guidance.
- R4. Verify that active surfaces no longer make contradictory FSL claims.
- R5. Run the repo's normal verification before committing, even though the change is mostly documentation.

## Scope Boundaries

- Do not change Swift app behavior, website structure, release automation, catalog data, or tests unless verification exposes a directly related issue.
- Do not rewrite historical plans in `docs/plans/` or requirements in `docs/brainstorms/` unless the implementer finds an active doc that is presented as current guidance.
- Do not add dual licensing, commercial licensing text, CLA/DCO policy, contributor license headers, or a `NOTICE` file in this pass.
- Do not present this plan as legal advice; it is an implementation plan for applying the chosen license text and metadata consistently.

## Context & Research

### Relevant Code and Patterns

- `LICENSE` currently contains `FSL-1.1-Apache-2.0` text and declares Apache 2.0 as the future change license.
- `README.md` has feature and license sections that advertise FSL 1.1 and the 2028 conversion.
- `website/index.html` has active marketing copy, FAQ copy, footer link text, and schema metadata related to the license.
- `AGENTS.md` and `CLAUDE.md` are active project guidance files and currently state FSL 1.1.
- `.github/workflows/ci.yml` defines the normal app build and unit/UI test path for PR confidence.
- `.github/workflows/visual.yml`, `package.json`, `playwright.config.js`, and `website/tests/website.visual.spec.js` define website visual coverage if website copy changes need rendered verification.
- `docs/plans/2026-04-11-005-feat-oss-repo-prep-plan.md` is related prior art, but it is stale/historical and still mentions MIT-era planning assumptions.

### Institutional Learnings

- No `docs/solutions/` directory exists in this repository, so there are no recorded institutional learnings to apply.

### External References

- FSL describes itself as a Fair Source license that converts to Apache 2.0 or MIT after two years and distinguishes itself from Open Source: https://fsl.software/
- OSI's Open Source Definition requires free redistribution and no field-of-endeavor restriction: https://opensource.org/definition/
- OSI lists Apache License 2.0 as an approved license with SPDX ID `Apache-2.0`: https://opensource.org/licenses
- Apache's official guidance says to include a copy of the Apache License, typically in `LICENSE`, and optionally consider a `NOTICE` file: https://www.apache.org/licenses/LICENSE-2.0.html
- ChooseALicense summarizes Apache-2.0 as permissive, allowing commercial use, distribution, modification, patent use, and private use, with copyright/license notice and state-change conditions: https://choosealicense.com/licenses/
- GitHub licensing docs note that recognized licenses are detected from the `LICENSE` file and that unusual/multiple-license complexity can interfere with clear display: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- MPL-2.0 was considered but not chosen for this pass because its file-level copyleft is an additional policy shift beyond the user's goal of avoiding FSL/BSL ambiguity: https://www.mozilla.org/en-US/MPL/2.0/FAQ/

## Key Technical Decisions

- Choose Apache-2.0 as the replacement license: It is already the declared FSL future license, OSI-approved, familiar to GitHub/license tooling, permissive, and includes an explicit patent grant.
- Keep the change repository-wide and simple: Replacing the root `LICENSE` and current copy is sufficient for this pass; per-file headers would add noisy churn and are optional under Apache's own application guidance.
- Do not add a `NOTICE` file initially: Apache says to consider one, but Nazar does not currently have additional required notices or attribution complexity that justify creating one during this narrow switch.
- Update active docs, not historical plans: Current user/contributor-facing files must be consistent, while archived planning documents should remain accurate records of prior decisions unless separately cleaned up.

## Open Questions

### Resolved During Planning

- Replacement license: Use Apache-2.0, inferred from the current FSL future license and the prior recommendation accepted for planning.
- Linear requirement: Ignored for this plan per direct user instruction.
- Historical docs: Leave archived brainstorms/plans unchanged unless they are active guidance.
- Active guidance files: This worktree contains `CLAUDE.md` but not `AGENTS.md`, so implementation updates `CLAUDE.md` only.

### Deferred to Implementation

- Exact website copy: The implementer should keep the current tone and replace only the license claims needed to remove FSL/conversion language.
- License detector behavior: If local or GitHub license detection behaves unexpectedly, simplify `LICENSE` first and avoid adding extra complexity to the license file.

## Implementation Units

- [x] **Unit 1: Replace root license text**

**Goal:** Make the repository's legal grant Apache-2.0 instead of FSL 1.1.

**Requirements:** R1, R4

**Dependencies:** None

**Files:**
- Modify: `LICENSE`
- Test: no dedicated test file; verify with license text comparison and repository license detection where available

**Approach:**
- Replace the current FSL text with the canonical Apache License 2.0 text from the Apache Software Foundation.
- Keep `LICENSE` simple so GitHub Licensee can detect `Apache-2.0`.
- Do not add project-specific commentary, dual-license text, or migration rationale inside `LICENSE`.

**Patterns to follow:**
- Apache Software Foundation "How to apply" guidance for placing the license in a root `LICENSE` file.
- GitHub license detection guidance favoring simple recognized license text.

**Test scenarios:**
- The root `LICENSE` text matches canonical Apache License 2.0 closely enough for standard license tooling.
- No FSL-specific fields remain in `LICENSE`, including `Use Limitation`, `Change Date`, and `Change License`.

**Verification:**
- `LICENSE` clearly identifies Apache License 2.0.
- A search for FSL terms in `LICENSE` returns no matches.

- [x] **Unit 2: Update active repository documentation**

**Goal:** Align active contributor and project guidance with the new Apache-2.0 license.

**Requirements:** R2, R3, R4

**Dependencies:** Unit 1

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Test: no dedicated test file; verify with targeted text search

**Approach:**
- In `README.md`, replace the feature bullet and License section with concise Apache-2.0 language.
- In `CLAUDE.md`, replace "Source-available under FSL 1.1" and the tech-stack license line with Apache-2.0/open source language.
- Preserve all unrelated workflow, build, catalog, and architecture guidance.

**Patterns to follow:**
- Existing README tone: short, factual, no marketing expansion.
- Existing AGENTS/CLAUDE project summary format.

**Test scenarios:**
- README feature list no longer claims source-available/FSL status.
- README License section points to `LICENSE` and names Apache-2.0.
- Existing agent guidance no longer instructs future agents that the project is FSL-licensed.

**Verification:**
- Active docs are internally consistent with `LICENSE`.
- Historical docs remain untouched unless explicitly promoted to active guidance.

- [x] **Unit 3: Update website license copy**

**Goal:** Remove public FSL/conversion claims from the live website source.

**Requirements:** R2, R4

**Dependencies:** Unit 1

**Files:**
- Modify: `website/index.html`
- Test: `website/tests/website.visual.spec.js`

**Approach:**
- Update the "Open and inspectable" feature card to describe the project as open source under Apache-2.0.
- Update the FAQ answer for "Is it really free?" to remove FSL and conversion wording while preserving the no-subscription/no-telemetry message.
- Update footer link text from "FSL 1.1 License" to "Apache-2.0 License".
- Keep schema `license` as the GitHub `LICENSE` URL unless a more specific canonical license URL is preferred during implementation; either is acceptable if public metadata remains accurate.

**Patterns to follow:**
- Existing static HTML + Tailwind CDN site; no build framework.
- Existing FAQ and feature-card copy length and tone.

**Test scenarios:**
- Homepage visible copy no longer contains `FSL`, `Functional Source`, `source-available`, or conversion-date language.
- Footer license link still points to the repository license.
- Website visual test snapshots should not reveal layout regression from copy length changes.

**Verification:**
- Website renders without layout shifts from replacement copy.
- Existing website visual test coverage passes or snapshot updates are intentional and reviewed.

- [x] **Unit 4: Final consistency and commit readiness**

**Goal:** Confirm the license switch is complete and safe to commit.

**Requirements:** R4, R5

**Dependencies:** Units 1-3

**Files:**
- Inspect: `LICENSE`
- Inspect: `README.md`
- Inspect: `AGENTS.md`
- Inspect: `CLAUDE.md`
- Inspect: `website/index.html`
- Inspect: `.github/PULL_REQUEST_TEMPLATE.md`
- Test: `.github/workflows/ci.yml`
- Test: `.github/workflows/visual.yml`

**Approach:**
- Search the active repo surfaces for FSL/source-available/conversion language.
- Decide whether historical mentions in `docs/plans/` should be documented as intentionally unchanged in the final implementation summary.
- Run the repo's normal verification before committing, following the project instruction to lint/test before every commit. For this repo, the plan should expect Xcode build/unit tests and website visual checks where practical.
- If full UI tests or visual uploads are impractical locally, record the limitation and rely on CI for that portion before merge.

**Patterns to follow:**
- `.github/PULL_REQUEST_TEMPLATE.md` testing checklist.
- `CONTRIBUTING.md` expectation that the app builds without warnings and PRs stay focused.

**Test scenarios:**
- Active public copy and active guidance agree on Apache-2.0.
- CI-relevant documentation changes do not break website tests.
- No app source files were changed unintentionally.

**Verification:**
- Search results show no active FSL claims outside intentionally historical docs.
- Build/test/visual verification status is recorded before commit or PR.

## System-Wide Impact

- **Interaction graph:** No runtime callbacks, app services, or website scripts should change. Impact is limited to legal metadata and visible copy.
- **Error propagation:** Not applicable; no runtime error paths are being modified.
- **State lifecycle risks:** Not applicable; no persisted state or catalog data changes.
- **API surface parity:** Not applicable; no app or website API surface changes.
- **Integration coverage:** GitHub license detection and website rendering are the relevant cross-surface checks.

## Risks & Dependencies

- License changes can have legal consequences. The implementation should use canonical Apache-2.0 text and avoid inventing custom terms.
- If third-party dependencies or copied assets have their own attribution requirements, this plan does not audit them; it only changes Nazar's project license.
- Public messaging must avoid claiming source-available/FSL after the switch, especially on the website and README.
- Historical docs may still mention FSL or MIT. That is acceptable if they are clearly archival and not presented as current guidance.

## Documentation / Operational Notes

- The PR description should explicitly state that this is a license and copy alignment change, not an app behavior change.
- If the repository has already been public under FSL, the implementation summary should avoid overclaiming retroactive relicensing effects for copies already received under older terms.
- Release notes are optional; if included, keep them factual: "Switch repository license from FSL 1.1 to Apache-2.0."

## Sources & References

- Related prior plan: `docs/plans/2026-04-11-005-feat-oss-repo-prep-plan.md`
- Active docs: `README.md`, `AGENTS.md`, `CLAUDE.md`, `website/index.html`
- Verification references: `.github/workflows/ci.yml`, `.github/workflows/visual.yml`, `website/tests/website.visual.spec.js`
- FSL: https://fsl.software/
- OSI Open Source Definition: https://opensource.org/definition/
- OSI approved licenses: https://opensource.org/licenses
- Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0.html
- ChooseALicense comparison: https://choosealicense.com/licenses/
- GitHub licensing docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- Mozilla MPL 2.0 FAQ: https://www.mozilla.org/en-US/MPL/2.0/FAQ/
