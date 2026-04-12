import SwiftUI
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "ui")

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
    @State private var isRefreshing = false

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

    /// True when the app has no connectivity (all snapshots are errors)
    private var isOffline: Bool {
        !manager.snapshots.isEmpty && manager.snapshots.allSatisfy { $0.error != nil }
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
                    statusPageURL: provider.flatMap { URL(string: $0.baseURL) },
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
        .onReceive(NotificationCenter.default.publisher(for: .init("DeepLinkToProvider"))) { notification in
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

                // Refresh button with spin feedback
                HoverButton(
                    icon: "arrow.clockwise",
                    fontSize: 12,
                    help: "Refresh all"
                ) {
                    logger.info("Manual refresh triggered")
                    isRefreshing = true
                    manager.pollAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isRefreshing = false
                    }
                }
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)

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
                    let issueCount = manager.snapshots.filter { $0.error == nil && $0.overallStatus != .operational }.count
                    if issueCount > 0 {
                        Text("\(issueCount) issue\(issueCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: manager.worstStatus.color))
                    } else {
                        Text("All operational")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let lastUpdate = manager.snapshots.map(\.lastUpdated).max() {
                    Text("Updated \(lastUpdate, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Service List

    private var serviceList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sortedSnapshots) { snapshot in
                    let provider = manager.providers.first(where: { $0.id == snapshot.id })
                    ProviderRowView(
                        snapshot: snapshot,
                        catalogId: provider?.catalogEntryId,
                        isMuted: provider?.isMuted ?? false,
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
                StatusBadge(label: "Unavailable", color: .gray)
            } else if snapshot.overallStatus == .operational {
                Text("Operational")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                StatusBadge(label: snapshot.overallStatus.label, color: Color(nsColor: snapshot.overallStatus.color))
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
        .contextMenu {
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
                NotificationCenter.default.post(name: .init("SimulateStatus"), object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.degradedPerformance])
            }
            Button("Simulate Major Outage") {
                NotificationCenter.default.post(name: .init("SimulateStatus"), object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.majorOutage])
            }
            Button("Reset to Operational") {
                NotificationCenter.default.post(name: .init("SimulateStatus"), object: nil,
                    userInfo: ["id": snapshot.id, "status": ComponentStatus.operational])
            }
            #endif
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
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
