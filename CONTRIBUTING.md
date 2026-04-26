# Contributing to Nazar

Thanks for your interest in contributing! This guide covers the basics.

## How to Contribute

1. **Fork** the repo and create a branch from `main`
2. **For bugs:** open an issue first using the [bug report template](https://github.com/moollaza/nazar/issues/new?template=bug_report.yml)
3. **For features:** open an issue first using the [feature request template](https://github.com/moollaza/nazar/issues/new?template=feature_request.yml)
4. Make your changes and **submit a PR**

## Development Setup

See the [README](README.md#development-setup) for prerequisites and build instructions.

## Code Style

- Follow [Apple's Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `@Observable` (not `ObservableObject`)
- `StatusManager` is `@MainActor` -- all snapshot mutations must happen on the main thread
- New providers: add to the catalog via `Resources/catalog.json`

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). This drives the automated release pipeline — commit prefixes determine the next version bump and populate the changelog.

Format: `type(scope): short description`

| Prefix | When to use | Bumps |
|---|---|---|
| `feat:` | New user-visible capability | minor (1.1 → 1.2) |
| `fix:` | Bug fix | patch (1.1.1 → 1.1.2) |
| `perf:` | Performance improvement | patch |
| `refactor:` | Code change with no behavior difference | patch |
| `docs:` | Documentation only | patch |
| `test:` | Test-only change | no release |
| `chore:` | Tooling, dependencies, etc. | no release |
| `ci:` | CI/build-pipeline changes | no release |

Breaking changes: add `!` after the type/scope (e.g. `feat!:`) **or** include a `BREAKING CHANGE:` footer. These trigger a major bump.

Examples:

```
feat(catalog): add Google Cloud to the catalog
fix(notifications): prevent double-alert on rapid status flaps
fix!(api): require https:// in custom provider URLs

BREAKING CHANGE: http:// URLs are no longer accepted — re-add any as https://.
```

Scope is optional but helpful. Keep the first line under ~72 chars; use the body for detail.

## Pull Request Process

- Fill out the [PR template](.github/PULL_REQUEST_TEMPLATE.md)
- Keep PRs focused -- one feature or fix per PR
- Ensure the app builds with no warnings
- Test on macOS 14+ if possible

## Releases

Releases are semi-automated via [release-please](https://github.com/googleapis/release-please):

1. When commits with `feat:` or `fix:` land on `main`, the **Release PR** is opened/updated automatically with the bumped version + a generated `CHANGELOG.md`.
2. Merging the Release PR creates a git tag + empty GitHub release.
3. A maintainer builds the notarized DMG locally and uploads it:

   ```
   git checkout vX.Y.Z
   scripts/release.sh
   gh release upload vX.Y.Z build/release/Nazar-X.Y.Z.dmg
   ```

The DMG build step runs locally (not in CI) because notarization needs the Developer ID cert + Keychain credentials, which aren't stored in GitHub.

## Issue Reporting

- Use the GitHub issue templates
- Include your macOS version and app version
- Include steps to reproduce for bugs

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please read it before participating.
