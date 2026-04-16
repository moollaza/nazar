# StatusMonitor

The fastest way to stay on top of outages and service updates for 1,600+ SaaS tools — right from your macOS menu bar.

[**moollaza.github.io/status-monitor**](https://moollaza.github.io/status-monitor/) · [Download](https://github.com/moollaza/status-monitor/releases) · [Request a service](https://github.com/moollaza/status-monitor/issues/new?template=service_request.yml)

![StatusMonitor Screenshot](docs/assets/screenshot.png)

## Features

- Monitor 1,600+ SaaS services from your menu bar
- Instant notifications on status changes
- Built-in catalog with one-click setup (5 services in under 60 seconds)
- Color-coded menu bar icon (green/yellow/orange/red)
- Supports Atlassian Statuspage, incident.io, and RSS/Atom feeds
- Configurable per-service poll intervals
- Native macOS app (SwiftUI, no Electron)
- Free and source-available ([FSL 1.1](https://fsl.software/), converts to Apache 2.0 in 2028)

## Install

Download the latest `.dmg` from [GitHub Releases](https://github.com/moollaza/status-monitor/releases).

Requires macOS 14 (Sonoma) or later.

## Development Setup

**Prerequisites:** Xcode 15+, macOS 14+

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. To request a missing service, use the [Service Request issue template](https://github.com/moollaza/status-monitor/issues/new?template=service_request.yml).

## License

[Functional Source License 1.1](https://fsl.software/) (FSL-1.1-Apache-2.0) -- see [LICENSE](LICENSE) for details. Converts to Apache 2.0 on 2028-04-12.
