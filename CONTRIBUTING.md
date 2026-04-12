# Contributing to StatusMonitor

Thanks for your interest in contributing! This guide covers the basics.

## How to Contribute

1. **Fork** the repo and create a branch from `main`
2. **For bugs:** open an issue first using the [bug report template](https://github.com/moollaza/status-monitor/issues/new?template=bug_report.yml)
3. **For features:** open an issue first using the [feature request template](https://github.com/moollaza/status-monitor/issues/new?template=feature_request.yml)
4. Make your changes and **submit a PR**

## Development Setup

See the [README](README.md#development-setup) for prerequisites and build instructions.

## Code Style

- Follow [Apple's Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `@Observable` (not `ObservableObject`)
- `StatusManager` is `@MainActor` -- all snapshot mutations must happen on the main thread
- New providers: add to the catalog via `Resources/catalog.json`

## Pull Request Process

- Fill out the [PR template](.github/PULL_REQUEST_TEMPLATE.md)
- Keep PRs focused -- one feature or fix per PR
- Ensure the app builds with no warnings
- Test on macOS 13+ if possible

## Issue Reporting

- Use the GitHub issue templates
- Include your macOS version and app version
- Include steps to reproduce for bugs

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please read it before participating.
