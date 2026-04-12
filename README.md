# StatusMonitor

macOS menu bar app that monitors SaaS service status pages and alerts on outages.

<!-- TODO: Replace with actual screenshot after UI is finalized -->
![StatusMonitor Screenshot](docs/assets/screenshot.png)

## Features

- Monitor 100+ SaaS services from your menu bar
- Instant notifications on status changes
- Built-in catalog with one-click setup (5 services in under 60 seconds)
- Color-coded menu bar icon (green/yellow/orange/red)
- Supports Atlassian Statuspage and RSS/Atom feeds
- Configurable per-service poll intervals
- Native macOS app (SwiftUI, no Electron)
- Free and source-available ([FSL 1.1](https://fsl.software/), converts to Apache 2.0 in 2028)

## Install

Download the latest `.dmg` from [GitHub Releases](https://github.com/moollaza/status-monitor/releases).

Requires macOS 13 (Ventura) or later.

## Development Setup

**Prerequisites:** Xcode 15+, macOS 13+

```bash
git clone https://github.com/moollaza/status-monitor.git
cd status-monitor
open StatusMonitor.xcodeproj
```

Build and run the `StatusMonitor` scheme in Xcode.

**CLI build:**

```bash
xcodebuild -project StatusMonitor.xcodeproj -scheme StatusMonitor -configuration Release build
```

## Tech Stack

- Swift 5.9+, SwiftUI
- `@Observable` (Swift 5.9 macro)
- `URLSession` for network polling
- App Sandbox with `com.apple.security.network.client`
- `LSUIElement` menu bar accessory (no Dock icon)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute.

## License

[Functional Source License 1.1](https://fsl.software/) (FSL-1.1-Apache-2.0) -- see [LICENSE](LICENSE) for details. Converts to Apache 2.0 on 2028-04-12.
