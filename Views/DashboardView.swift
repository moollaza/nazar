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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenSettings: ((SettingsTab) -> Void)?
    @State private var selectedProviderId: UUID?
    @State private var searchText = ""
    @State private var showIssuesOnly = false
    @State private var pendingRemoval: Provider?
    @FocusState private var searchFocused: Bool
    @AppStorage("dashboardSort") private var sortOrder: DashboardSort = .severity

    /// Most catalog matches to list while filtering; enough to find a service
    /// without pushing the monitored matches out of view.
    private static let catalogMatchLimit = 6

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private func needsAttention(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.overallStatus != .operational || snapshot.error != nil
    }

    private var filteredSnapshots: [ProviderSnapshot] {
        var result = manager.snapshots
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        if showIssuesOnly {
            result = result.filter(needsAttention)
        }
        return result
    }

    /// Catalog services matching the filter text that are not monitored yet.
    private var catalogMatches: [CatalogEntry] {
        guard !query.isEmpty else { return [] }
        let monitored = Set(manager.providers.compactMap(\.catalogEntryId))
        let monitoredURLs = Set(manager.providers.map(\.baseURL))
        return Array(
            Catalog.shared.search(query)
                .lazy
                .filter { !monitored.contains($0.id) && !monitoredURLs.contains(Provider(from: $0).baseURL) }
                .prefix(Self.catalogMatchLimit)
        )
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
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            } else {
                dashboardContent
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { pendingRemoval = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if note.object is FloatingPanel { pendingRemoval = nil }
        }
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
            header

            // The field's 8pt inner padding plus this 8pt outer padding puts
            // the magnifying glass on the same 16pt line as the header text.
            searchField
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            Divider()

            // Content
            if manager.providers.isEmpty && query.isEmpty {
                OnboardingPicker(
                    onBrowse: { onOpenSettings?(.catalog) },
                    onSuggest: { NSWorkspace.shared.open(ServiceRequest.url()) }
                )
            } else if !manager.providers.isEmpty && manager.snapshots.isEmpty && query.isEmpty {
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

            // Onboarding has its own bottom bar.
            if !(manager.providers.isEmpty && query.isEmpty) {
                Divider()

                if let provider = pendingRemoval {
                    removalBar(for: provider)
                } else {
                    footer
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Nazar")
                .font(.headline)

            Spacer()

            HoverButton(
                icon: showIssuesOnly ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                fontSize: 13,
                isActive: showIssuesOnly,
                activeColor: Color(nsColor: ComponentStatus.partialOutage.color),
                help: showIssuesOnly ? "Show all services" : "Show issues only"
            ) {
                showIssuesOnly.toggle()
            }

            sortMenu

            HoverButton(icon: "plus", fontSize: 13, help: "Add a service") {
                searchFocused = true
            }

            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                Label("Status (Issues First)", systemImage: "square.stack").tag(DashboardSort.severity)
                Label("Name (A–Z)", systemImage: "textformat").tag(DashboardSort.alphabetical)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 24)
        .help(sortOrder == .severity ? "Sorted by status, issues first" : "Sorted by name (A–Z)")
        .accessibilityLabel("Sort")
    }

    private var moreMenu: some View {
        Menu {
            Button("Refresh Now") {
                logger.info("Manual refresh triggered")
                manager.pollAll()
            }
            .keyboardShortcut("r")
            .disabled(manager.isRefreshing)

            Divider()

            Button("Add Custom Status Page…") { onOpenSettings?(.services) }
            Button("Browse Catalog…") { onOpenSettings?(.catalog) }
            Button("Suggest a Service…") { NSWorkspace.shared.open(ServiceRequest.url()) }

            Divider()

            Button("Settings…") {
                logger.info("Opening Settings window")
                onOpenSettings?(.services)
            }
            Button("Send Feedback…") { onOpenSettings?(.feedback) }

            Divider()

            Button("Quit Nazar") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 24)
        .help("Settings and more")
        .accessibilityLabel("Settings and more")
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter or add a service…", text: $searchText)
                .accessibilityIdentifier("dashboard-filter")
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                // The field takes focus when the panel opens, so it gets Escape
                // before the panel does. Clear the text first, then close.
                .onExitCommand {
                    if searchText.isEmpty {
                        NSApp.windows.first { $0 is FloatingPanel }?.close()
                    } else {
                        searchText = ""
                    }
                }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if isOffline {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: ComponentStatus.majorOutage.textColor))
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: ComponentStatus.majorOutage.textColor))
            } else if !manager.snapshots.isEmpty {
                Circle()
                    .fill(Color(nsColor: manager.worstStatus.color))
                    .frame(width: 8, height: 8)
                if issueCount > 0 {
                    Text(issueSummary(issues: issueCount, unreachable: unreachableCount))
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    private func removalBar(for provider: Provider) -> some View {
        HStack(spacing: 8) {
            Text("Remove \(provider.name)?")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { pendingRemoval = nil }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            Button("Remove", role: .destructive) {
                logger.info("Removed from dashboard: \(provider.name)")
                if selectedProviderId == provider.id { selectedProviderId = nil }
                manager.removeProvider(provider)
                pendingRemoval = nil
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.73, green: 0.11, blue: 0.11)) // #B91C1C: white label stays 6.5:1 in both modes
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Service List

    /// Built once per body invocation; cuts the per-row provider lookup from
    /// O(providers) to O(1). At 50+ providers the quadratic cost is visible.
    private var providersById: [UUID: Provider] {
        Dictionary(uniqueKeysWithValues: manager.providers.map { ($0.id, $0) })
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

    private var serviceList: some View {
        let lookup = providersById
        let snapshots = sortedSnapshots
        let matches = catalogMatches

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(snapshots) { snapshot in
                    let provider = lookup[snapshot.id]
                    ProviderRowView(
                        snapshot: snapshot,
                        catalogId: provider?.catalogEntryId,
                        isMuted: provider?.isMuted ?? false,
                        statusPageURL: provider?.externalURL,
                        recoveredAt: manager.recentRecovery(for: snapshot.id),
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedProviderId = snapshot.id
                            }
                        },
                        onToggleMute: {
                            if let p = provider { manager.toggleMute(for: p) }
                        },
                        onRemove: {
                            pendingRemoval = provider
                        },
                        onClearRecovery: {
                            manager.clearRecovery(for: snapshot.id)
                        }
                    )
                }

                if !query.isEmpty {
                    if snapshots.isEmpty {
                        Text(showIssuesOnly
                             ? "No services with issues match “\(query)”"
                             : "No monitored service matches “\(query)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    if !matches.isEmpty {
                        SectionHeader(title: "Add from Catalog")
                        ForEach(matches) { entry in
                            CatalogAddRow(entry: entry) {
                                if manager.addProvider(Provider(from: entry)) {
                                    logger.info("Added from dashboard: \(entry.name)")
                                }
                            }
                        }
                    }
                    if matches.isEmpty {
                        Button {
                            NSWorkspace.shared.open(ServiceRequest.url(name: query))
                        } label: {
                            Label("Suggest “\(query)” for the catalog", systemImage: "plus.bubble")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(nsColor: .accessibleLink))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    Button {
                        onOpenSettings?(.services)
                    } label: {
                        Label("Add a custom status page in Settings…", systemImage: "link.badge.plus")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .accessibleLink))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else if showIssuesOnly && snapshots.isEmpty {
                    Text("No issues right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            // Matches the 4pt inset of the row hover fill, so a hovered first
            // or last row doesn't touch the dividers above and below the list.
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Service Request

/// The catalog request issue form, with the name and URL filled in when known.
enum ServiceRequest {
    static func url(name: String? = nil, statusURL: String? = nil) -> URL {
        var components = URLComponents(string: "https://github.com/moollaza/nazar/issues/new")!
        var items = [URLQueryItem(name: "template", value: "service_request.yml")]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "title", value: "[Service]: \(name)"))
            items.append(URLQueryItem(name: "service-name", value: name))
        }
        if let statusURL, !statusURL.isEmpty {
            items.append(URLQueryItem(name: "status-url", value: statusURL))
        }
        components.queryItems = items
        return components.url!
    }
}

// MARK: - Onboarding

/// Shown while nothing is monitored: services matched from installed apps
/// (pre-checked) plus a few popular ones, added in one step.
struct OnboardingPicker: View {
    @Environment(StatusManager.self) var manager
    var onBrowse: () -> Void
    var onSuggest: () -> Void
    @State private var appMatches: [CatalogEntry] = []
    @State private var selected: Set<String> = []
    @State private var scanned = false

    private static let popularIds = ["openai", "anthropic", "aws", "cloudflare", "github", "vercel", "stripe"]

    private var popular: [CatalogEntry] {
        let matched = Set(appMatches.map(\.id))
        let byId = Dictionary(Catalog.shared.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = Self.popularIds.filter { !matched.contains($0) }.compactMap { byId[$0] }
        return Array(entries.prefix(appMatches.isEmpty ? 6 : 2))
    }

    /// Catalog size rounded down to the hundred, e.g. "1,800+".
    private var catalogSize: String {
        "\((Catalog.shared.entries.count / 100 * 100).formatted())+"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    welcome
                    if !appMatches.isEmpty {
                        sectionHeader("Found \(appMatches.count) on your Mac", note: "stays on this Mac") {
                            selectAllButton
                        }
                        ForEach(appMatches) { row(for: $0) }
                    }
                    if scanned {
                        sectionHeader("Popular", note: appMatches.isEmpty ? "no matches in your apps" : nil) {
                            EmptyView()
                        }
                        ForEach(popular) { row(for: $0) }
                    }
                    Button(action: onBrowse) {
                        Text("Browse all \(catalogSize) services")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding-browse")
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            HStack {
                Button("Missing one? Suggest it", action: onSuggest)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .accessibleLink))
                Spacer()
                Button(watchTitle, action: watch)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .task {
            guard !scanned else { return }
            appMatches = Catalog.shared.suggestFromInstalledApps()
            selected = Set(appMatches.map(\.id))
            scanned = true
        }
    }

    private var watchTitle: String {
        switch selected.count {
        case 0: return "Watch"
        case 1: return "Watch 1 Service"
        default: return "Watch \(selected.count) Services"
        }
    }

    private var selectAllButton: some View {
        let ids = Set(appMatches.map(\.id))
        let allOn = ids.isSubset(of: selected)
        return Button(allOn ? "Select None" : "Select All") {
            if allOn { selected.subtract(ids) } else { selected.formUnion(ids) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(Color(nsColor: .accessibleLink))
    }

    private var welcome: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Nazar")
                    .font(.headline)
                Text("Pick what you rely on. Nazar flags outages in your menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func sectionHeader<Trailing: View>(
        _ title: String, note: String?, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let note {
                Text("· \(note)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(for entry: CatalogEntry) -> some View {
        let isOn = Binding(
            get: { selected.contains(entry.id) },
            set: { if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) } }
        )
        return HStack(spacing: 10) {
            Toggle(entry.name, isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            ServiceIconView(name: entry.name, catalogId: entry.id)
            Text(entry.name)
                .lineLimit(1)
            Spacer()
            Text(entry.category)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
    }

    private func watch() {
        let chosen = (appMatches + popular).filter { selected.contains($0.id) }
        for entry in chosen {
            _ = manager.addProvider(Provider(from: entry))
        }
        logger.info("Onboarding added \(chosen.count) services")
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Catalog Add Row

struct CatalogAddRow: View {
    let entry: CatalogEntry
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ServiceIconView(name: entry.name, catalogId: entry.id)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                Text(entry.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Monitor \(entry.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(nsColor: .quaternarySystemFill) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add \(entry.name), \(entry.category)")
    }
}

// MARK: - Provider Row

struct ProviderRowView: View {
    let snapshot: ProviderSnapshot
    var catalogId: String? = nil
    var isMuted: Bool = false
    var statusPageURL: URL? = nil
    /// Set while the Recovered badge should show (see StatusManager.recentRecovery).
    var recoveredAt: Date? = nil
    let onTap: () -> Void
    var onToggleMute: (() -> Void)?
    var onRemove: (() -> Void)?
    var onClearRecovery: (() -> Void)?
    @State private var isHovered = false
    @State private var isPressed = false

    private var openableURL: URL? {
        guard let url = statusPageURL, url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    enum RowStatus {
        case unavailable
        case recovered(Date)
        case operational
        case issue(ComponentStatus)
    }

    private var rowStatus: RowStatus {
        if snapshot.error != nil { return .unavailable }
        if snapshot.overallStatus == .operational {
            if let recoveredAt { return .recovered(recoveredAt) }
            return .operational
        }
        return .issue(snapshot.overallStatus)
    }

    private var statusLabel: String {
        switch rowStatus {
        case .unavailable: return "Unavailable"
        case .recovered(let date): return "Recovered \(coarseTimeAgo(date))"
        case .operational: return ComponentStatus.operational.label
        case .issue(let status): return status.label
        }
    }

    private var isRecovered: Bool {
        if case .recovered = rowStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon with status badge
            ZStack(alignment: .bottomTrailing) {
                ServiceIconView(name: snapshot.name, catalogId: catalogId)
                Circle()
                    .fill(Color(nsColor: snapshot.overallStatus.color))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }

            Text(snapshot.name)
                .font(.system(.body, weight: .medium))
                .lineLimit(1)

            if isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Notifications muted")
            }

            Spacer()

            switch rowStatus {
            case .unavailable:
                StatusBadge(label: "Unavailable", status: .unknown)
            case .recovered(let date):
                // A tap gesture, not a Button: a Button inside the row stops
                // `.accessibilityElement(children: .combine)` from merging the
                // row into one element, so VoiceOver and UI tests lose its label.
                StatusBadge(label: "Recovered", status: .operational)
                    .onTapGesture { onClearRecovery?() }
                    .help("Recovered \(coarseTimeAgo(date)). Click to clear.")
            case .operational:
                Text("Operational")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .issue(let status):
                StatusBadge(label: status.label, status: status)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPressed ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)
                      : isHovered ? Color(nsColor: .quaternarySystemFill)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.name), \(statusLabel)\(isMuted ? ", muted" : "")")
        .accessibilityHint("Double-click to view details")
        .accessibilityIdentifier("service-row-\(catalogId ?? snapshot.name)")
        .accessibilityAction(named: isMuted ? "Unmute" : "Mute") { onToggleMute?() }
        .accessibilityActions {
            if isRecovered {
                Button("Clear Recovered") { onClearRecovery?() }
            }
        }
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            if let url = openableURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Status Page", systemImage: "arrow.up.right.square")
                }
            }
            if let url = statusPageURL {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Label("Copy Status Page URL", systemImage: "doc.on.doc")
                }
            }
            if isRecovered {
                Button {
                    onClearRecovery?()
                } label: {
                    Label("Clear Recovered", systemImage: "checkmark.circle")
                }
            }
            Divider()
            Button {
                onToggleMute?()
            } label: {
                Label(
                    isMuted ? "Unmute Notifications" : "Mute Notifications",
                    systemImage: isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
            Divider()
            Button(role: .destructive) {
                onRemove?()
            } label: {
                Label("Remove \(snapshot.name)…", systemImage: "trash")
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

    var body: some View {
        let palette = status.badgeColors
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(Color(nsColor: palette.text))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: palette.background))
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
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? activeColor.opacity(0.18)
                              : isHovered ? Color(nsColor: .quaternarySystemFill)
                              : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
