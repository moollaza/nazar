import SwiftUI
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "ui")

extension Notification.Name {
    static let deepLinkToProvider = Notification.Name("DeepLinkToProvider")
    #if DEBUG
    static let simulateStatus = Notification.Name("SimulateStatus")
    #endif
}

enum DashboardSort: String {
    case severity, alphabetical
}

struct DashboardView: View {
    @Environment(StatusManager.self) var manager
    var onOpenSettings: (() -> Void)?
    @State private var selectedProviderId: UUID?
    @State private var searchText = ""
    @State private var showIssuesOnly = false
    @AppStorage("dashboardSort") private var sortOrder: DashboardSort = .severity

    private var filteredSnapshots: [ProviderSnapshot] {
        var result = manager.snapshots
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if showIssuesOnly {
            result = result.filter { $0.overallStatus != .operational || $0.error != nil }
        }
        return result
    }

    /// True when every monitored service is unreachable — suggests no connectivity.
    private var isOffline: Bool {
        !manager.snapshots.isEmpty && manager.snapshots.allSatisfy { $0.error != nil }
    }

    private var mutedIds: Set<UUID> {
        Set(manager.providers.filter(\.isMuted).map(\.id))
    }

    /// Providers the user is actively expecting alerts for: not muted, regardless of error state.
    private var visibleSnapshots: [ProviderSnapshot] {
        manager.snapshots.filter { !mutedIds.contains($0.id) }
    }

    private var issueCount: Int {
        visibleSnapshots.filter { $0.overallStatus != .operational }.count
    }

    private var unreachableCount: Int {
        visibleSnapshots.filter { $0.error != nil }.count
    }

    private var sortedSnapshots: [ProviderSnapshot] {
        switch sortOrder {
        case .severity:
            return filteredSnapshots.sorted {
                if $0.overallStatus != $1.overallStatus {
                    return $0.overallStatus > $1.overallStatus
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .alphabetical:
            return filteredSnapshots.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var selectedSnapshot: ProviderSnapshot? {
        guard let id = selectedProviderId else { return nil }
        return manager.snapshots.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let snapshot = selectedSnapshot {
                let provider = manager.providers.first(where: { $0.id == snapshot.id })
                ServiceDetailView(
                    snapshot: snapshot,
                    catalogId: provider?.catalogEntryId,
                    statusPageURL: provider?.externalURL,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProviderId = nil
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            } else {
                dashboardContent
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkToProvider)) { notification in
            if let id = notification.userInfo?["providerId"] as? UUID {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedProviderId = id
                }
            }
        }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Status Monitor")
                    .font(.headline)
                Spacer()
                // Issues only filter
                HoverButton(
                    icon: showIssuesOnly ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                    isActive: showIssuesOnly,
                    activeColor: .orange,
                    help: showIssuesOnly ? "Show all services" : "Show issues only"
                ) {
                    showIssuesOnly.toggle()
                }

                Picker("Sort", selection: $sortOrder) {
                    Image(systemName: "arrow.up.arrow.down")
                        .tag(DashboardSort.severity)
                    Image(systemName: "textformat.abc")
                        .tag(DashboardSort.alphabetical)
                }
                .pickerStyle(.segmented)
                .frame(width: 72)
                .labelsHidden()

                // Refresh button with spin feedback. Spinner is tied to
                // `manager.isRefreshing` so it reflects actual poll completion
                // rather than a wall-clock timer. `pollAll` coalesces repeat
                // invocations so rapid clicks don't spawn overlapping cycles.
                HoverButton(
                    icon: "arrow.clockwise",
                    fontSize: 12,
                    help: "Refresh all"
                ) {
                    logger.info("Manual refresh triggered")
                    manager.pollAll()
                }
                .disabled(manager.isRefreshing)
                .rotationEffect(.degrees(manager.isRefreshing ? 360 : 0))
                .animation(manager.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: manager.isRefreshing)

                // Settings button — opens the Settings window
                HoverButton(icon: "gearshape", fontSize: 12, help: "Settings") {
                    logger.info("Opening Settings window")
                    onOpenSettings?()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search bar (always visible when services exist)
            if !manager.providers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    TextField("Filter services...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()

            // Content
            if manager.providers.isEmpty {
                emptyState
            } else if manager.snapshots.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading status pages...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                serviceList
            }

            Divider()

            // Footer
            HStack(spacing: 6) {
                if isOffline {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("Offline")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Circle()
                        .fill(Color(nsColor: manager.worstStatus.color))
                        .frame(width: 8, height: 8)
                    if issueCount > 0 {
                        let summary = issueSummary(issues: issueCount, unreachable: unreachableCount)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: manager.worstStatus.textColor))
                    } else {
                        Text("All operational")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let lastUpdate = manager.snapshots.map(\.lastUpdated).max() {
                    // Minute-resolution label (no seconds counter — the ticking
                    // display was distracting). TimelineView re-renders every
                    // 30s so the label stays fresh even if no poll lands.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Updated \(coarseTimeAgo(lastUpdate, now: context.date))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Service List

    /// Built once per body invocation; cuts the per-row provider lookup from
    /// O(providers) to O(1). At 50+ providers the quadratic cost is visible.
    private var providersById: [UUID: Provider] {
        Dictionary(uniqueKeysWithValues: manager.providers.map { ($0.id, $0) })
    }

    private var serviceList: some View {
        let lookup = providersById
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedSnapshots) { snapshot in
                    let provider = lookup[snapshot.id]
                    ProviderRowView(
                        snapshot: snapshot,
                        catalogId: provider?.catalogEntryId,
                        isMuted: provider?.isMuted ?? false,
                        statusPageURL: provider?.externalURL?.absoluteString,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedProviderId = snapshot.id
                            }
                        },
                        onToggleMute: {
                            if let p = provider { manager.toggleMute(for: p) }
                        }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func issueSummary(issues: Int, unreachable: Int) -> String {
        if unreachable == 0 {
            return "\(issues) issue\(issues == 1 ? "" : "s")"
        }
        if unreachable == issues {
            return "\(unreachable) unreachable"
        }
        return "\(issues) issue\(issues == 1 ? "" : "s") (\(unreachable) unreachable)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No services monitored")
                .font(.headline)
            Text("Open Settings to add services from the catalog\nor add a custom status page URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Get Started") {
                onOpenSettings?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Provider Row

struct ProviderRowView: View {
    let snapshot: ProviderSnapshot
    var catalogId: String? = nil
    var isMuted: Bool = false
    var statusPageURL: String? = nil
    let onTap: () -> Void
    var onToggleMute: (() -> Void)?
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon with status badge
            ZStack(alignment: .bottomTrailing) {
                ServiceIconView(name: snapshot.name, catalogId: catalogId)
                Circle()
                    .fill(Color(nsColor: snapshot.overallStatus.color))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            // Name + mute indicator
            Text(snapshot.name)
                .font(.system(.body, weight: .medium))
                .lineLimit(1)

            if isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badge
            if snapshot.error != nil {
                StatusBadge(label: "Unavailable", status: .unknown)
            } else if snapshot.overallStatus == .operational {
                Text("Operational")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                StatusBadge(label: snapshot.overallStatus.label, status: snapshot.overallStatus)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPressed ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)
                      : isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5)
                      : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onHover { hovering in isHovered = hovering }
        .opacity(isMuted ? 0.5 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.name), \(snapshot.error != nil ? "Unavailable" : snapshot.overallStatus.label)\(isMuted ? ", muted" : "")")
        .accessibilityHint("Double-click to view details")
        .contextMenu {
            if let url = statusPageURL {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                } label: {
                    Label("Copy Status Page URL", systemImage: "doc.on.doc")
                }
            }
            Button {
                onToggleMute?()
            } label: {
                Label(
                    isMuted ? "Unmute Service" : "Mute Service",
                    systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
            #if DEBUG
            Divider()
            Button("Simulate Degraded") {
                // Dev mode: mutate snapshot status in memory
                NotificationCenter.default.post(name: .simulateStatus, object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.degradedPerformance])
            }
            Button("Simulate Major Outage") {
                NotificationCenter.default.post(name: .simulateStatus, object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.majorOutage])
            }
            Button("Reset to Operational") {
                NotificationCenter.default.post(name: .simulateStatus, object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.operational])
            }
            #endif
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let label: String
    let status: ComponentStatus

    // Tailwind-inspired palettes: 800-shade text on 100-shade bg (light), 300-shade text on 900-shade bg (dark)
    private var colors: (text: Color, bg: Color) {
        switch status {
        case .majorOutage:
            // Red: red-800 on red-100 / red-300 on red-900
            return (Color(red: 0.60, green: 0.04, blue: 0.04), Color(red: 0.996, green: 0.89, blue: 0.89)) // #991b1b, #fee2e2
        case .partialOutage:
            // Orange: orange-800 on orange-100 / orange-300 on orange-900
            return (Color(red: 0.60, green: 0.22, blue: 0.02), Color(red: 1.0, green: 0.93, blue: 0.84)) // #9a3412, #ffedd5
        case .degradedPerformance, .underMaintenance:
            // Amber: amber-800 on amber-100 / amber-300 on amber-900
            return (Color(red: 0.57, green: 0.29, blue: 0.01), Color(red: 0.996, green: 0.95, blue: 0.78)) // #92400e, #fef3c7
        case .unknown:
            // Gray: gray-700 on gray-100 / gray-300 on gray-800
            return (Color(red: 0.22, green: 0.25, blue: 0.32), Color(red: 0.95, green: 0.96, blue: 0.96)) // #374151, #f3f4f6
        case .operational:
            // Green (shouldn't appear as badge, but just in case)
            return (Color(red: 0.08, green: 0.40, blue: 0.15), Color(red: 0.86, green: 0.99, blue: 0.91)) // #166534, #dcfce7
        }
    }

    private var darkColors: (text: Color, bg: Color) {
        switch status {
        case .majorOutage:
            return (Color(red: 0.99, green: 0.68, blue: 0.68), Color(red: 0.45, green: 0.06, blue: 0.06)) // #fca5a5, #7f1d1d
        case .partialOutage:
            return (Color(red: 0.99, green: 0.73, blue: 0.47), Color(red: 0.49, green: 0.15, blue: 0.01)) // #fdba74, #7c2d12
        case .degradedPerformance, .underMaintenance:
            return (Color(red: 0.99, green: 0.82, blue: 0.36), Color(red: 0.47, green: 0.22, blue: 0.01)) // #fcd34d, #78350f
        case .unknown:
            return (Color(red: 0.61, green: 0.64, blue: 0.69), Color(red: 0.19, green: 0.22, blue: 0.26)) // #9ca3af, #1f2937
        case .operational:
            return (Color(red: 0.52, green: 0.90, blue: 0.60), Color(red: 0.08, green: 0.33, blue: 0.14)) // #86efac, #14532d
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = colorScheme == .dark ? darkColors : colors
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(palette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(palette.bg)
            .clipShape(Capsule())
    }
}

// MARK: - Hover Button

struct HoverButton: View {
    let icon: String
    var fontSize: CGFloat = 11
    var isActive: Bool = false
    var activeColor: Color = .orange
    var help: String = ""
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: fontSize))
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Time helpers

/// Minute-resolution "time ago" label. Avoids showing a ticking seconds
/// counter for fresh data — "< 1 min ago" covers the first minute, then
/// rolls over to "N min ago", "Nh ago", "Nd ago".
func coarseTimeAgo(_ date: Date, now: Date = Date()) -> String {
    let elapsed = now.timeIntervalSince(date)
    if elapsed < 0 { return "just now" }
    if elapsed < 60 { return "< 1 min ago" }
    let minutes = Int(elapsed / 60)
    if minutes < 60 {
        return "\(minutes) min ago"
    }
    let hours = Int(elapsed / 3600)
    if hours < 24 { return "\(hours)h ago" }
    let days = Int(elapsed / 86400)
    return "\(days)d ago"
}
