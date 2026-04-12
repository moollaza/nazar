import SwiftUI

enum DashboardSort: String {
    case severity, alphabetical
}

private let detailViewComponentThreshold = 10

struct DashboardView: View {
    @Environment(StatusManager.self) var manager
    @State private var expandedProvider: UUID?
    @State private var selectedProviderId: UUID?
    @State private var showSettings = false
    @State private var showCatalogPicker = false
    @State private var searchText = ""
    @AppStorage("dashboardSort") private var sortOrder: DashboardSort = .severity
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var filteredSnapshots: [ProviderSnapshot] {
        guard !searchText.isEmpty else { return manager.snapshots }
        return manager.snapshots.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    onBack: { selectedProviderId = nil }
                )
                .transition(.move(edge: .trailing))
            } else {
                dashboardContent
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(manager)
        }
        .sheet(isPresented: $showCatalogPicker) {
            CatalogPickerView(isOnboarding: false) {
                showCatalogPicker = false
            }
            .environment(manager)
            .frame(width: 400, height: 480)
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Status Monitor")
                    .font(.headline)
                Spacer()
                Picker("Sort", selection: $sortOrder) {
                    Image(systemName: "exclamationmark.triangle")
                        .help("Sort by severity")
                        .tag(DashboardSort.severity)
                    Image(systemName: "textformat.abc")
                        .help("Sort alphabetically")
                        .tag(DashboardSort.alphabetical)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .labelsHidden()
                Button(action: { manager.pollAll() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh all")

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search bar (shown when 5+ services)
            if manager.providers.count >= 5 {
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
                .padding(.bottom, 8)
            }

            Divider()

            if manager.providers.isEmpty && !hasCompletedOnboarding {
                // First launch: show catalog picker inline
                CatalogPickerView(isOnboarding: true) {
                    hasCompletedOnboarding = true
                }
                .environment(manager)
            } else if manager.providers.isEmpty {
                // Post-onboarding empty state
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No services monitored")
                        .font(.headline)
                    Text("Add services to start monitoring their status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Browse Catalog") {
                        showCatalogPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.snapshots.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading status pages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(sortedSnapshots) { snapshot in
                            let provider = manager.providers.first(where: { $0.id == snapshot.id })
                            ProviderRowView(
                                snapshot: snapshot,
                                catalogId: provider?.catalogEntryId,
                                statusPageURL: provider.flatMap { URL(string: $0.baseURL) },
                                isExpanded: expandedProvider == snapshot.id,
                                onTap: {
                                    if snapshot.components.count >= detailViewComponentThreshold {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedProviderId = snapshot.id
                                        }
                                    } else {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedProvider = expandedProvider == snapshot.id ? nil : snapshot.id
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer
            HStack {
                Circle()
                    .fill(Color(nsColor: manager.worstStatus.color))
                    .frame(width: 8, height: 8)
                Text(manager.worstStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

// MARK: - Provider Row

struct ProviderRowView: View {
    let snapshot: ProviderSnapshot
    var catalogId: String? = nil
    var statusPageURL: URL? = nil
    let isExpanded: Bool
    let onTap: () -> Void
    @State private var showAllComponents = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    ServiceIconView(name: snapshot.name, catalogId: catalogId)
                    Circle()
                        .fill(Color(nsColor: snapshot.overallStatus.color))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }

                Text(snapshot.name)
                    .font(.system(.body, weight: .medium))

                Spacer()

                if snapshot.error != nil {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(snapshot.overallStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Components — show non-operational by default
                    if !snapshot.components.isEmpty {
                        let degraded = snapshot.components.filter { $0.status != .operational }
                        let componentsToShow = showAllComponents ? snapshot.components : degraded

                        if !componentsToShow.isEmpty {
                            ForEach(componentsToShow) { comp in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: comp.status.color))
                                        .frame(width: 6, height: 6)
                                    Text(comp.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(comp.status.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if !showAllComponents {
                            Text("All \(snapshot.components.count) components operational")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if snapshot.components.count > degraded.count {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showAllComponents.toggle()
                                }
                            } label: {
                                Text(showAllComponents ? "Show issues only" : "Show all \(snapshot.components.count) components")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Active incidents
                    if !snapshot.activeIncidents.isEmpty {
                        Divider()
                        Text("Active Incidents")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(snapshot.activeIncidents) { incident in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color(nsColor: incident.impact.color))
                                    Text(incident.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                if let update = incident.latestUpdate {
                                    Text(update)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }

                    // View Status Page link
                    if let url = statusPageURL {
                        Divider()
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Text("View Status Page")
                                    .font(.caption)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background((isExpanded || isHovered) ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        .onHover { hovering in isHovered = hovering }
    }
}
