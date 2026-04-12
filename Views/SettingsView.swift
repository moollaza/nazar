import SwiftUI
import ServiceManagement
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "ui")

private let pollIntervalOptions: [(label: String, seconds: Int)] = [
    ("30s", 30),
    ("1m", 60),
    ("2m", 120),
    ("5m", 300),
    ("15m", 900),
]

// MARK: - Main Settings View (Sidebar Navigation)

enum SettingsTab: String, CaseIterable {
    case services = "Services"
    case catalog = "Catalog"
    case preferences = "Preferences"
    case feedback = "Feedback"
    case help = "Help"

    var icon: String {
        switch self {
        case .services: return "list.bullet"
        case .catalog: return "square.grid.2x2"
        case .preferences: return "gearshape"
        case .feedback: return "bubble.left"
        case .help: return "questionmark.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(StatusManager.self) var manager
    @State private var selectedTab: SettingsTab = .services

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch selectedTab {
                case .services:
                    ServicesSettingsView()
                        .environment(manager)
                case .catalog:
                    CatalogSettingsView()
                        .environment(manager)
                case .preferences:
                    PreferencesSettingsView()
                case .feedback:
                    FeedbackView()
                case .help:
                    HelpSettingsView()
                }
            }
            .frame(minWidth: 450, minHeight: 400)
        }
        .frame(width: 680, height: 480)
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @Environment(StatusManager.self) var manager
    @State private var providerToRemove: Provider?
    @State private var showAddCustom = false

    var sortedProviders: [Provider] {
        manager.providers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Monitored Services")
                    .font(.headline)
                Text("(\(manager.providers.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Custom...") { showAddCustom = true }
                    .controlSize(.small)
            }
            .padding()

            if manager.providers.isEmpty {
                VStack(spacing: 8) {
                    Text("No services added")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Go to the Catalog tab to add services.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Table header
                HStack(spacing: 0) {
                    Text("Service")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Interval")
                        .frame(width: 70, alignment: .center)
                    Text("Muted")
                        .frame(width: 50, alignment: .center)
                    Text("")
                        .frame(width: 30)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                Divider()

                List {
                    ForEach(sortedProviders) { provider in
                        HStack(spacing: 8) {
                            ServiceIconView(name: provider.name, catalogId: provider.catalogEntryId)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(provider.name)
                                    .font(.system(.body, weight: .medium))
                                Text(provider.baseURL)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            // Poll interval
                            Menu {
                                ForEach(pollIntervalOptions, id: \.seconds) { option in
                                    Button(option.label) {
                                        manager.updatePollInterval(for: provider, seconds: option.seconds)
                                    }
                                }
                            } label: {
                                Text(intervalLabel(for: provider.pollIntervalSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 35)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()

                            // Mute toggle
                            Button {
                                manager.toggleMute(for: provider)
                            } label: {
                                Image(systemName: provider.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                                    .foregroundStyle(provider.isMuted ? .orange : .secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .help(provider.isMuted ? "Unmute" : "Mute")
                            .frame(width: 24)

                            // Remove
                            Button {
                                providerToRemove = provider
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .help("Remove service")
                            .frame(width: 24)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showAddCustom) {
            AddCustomServiceView()
                .environment(manager)
        }
        .alert("Remove Service", isPresented: Binding(
            get: { providerToRemove != nil },
            set: { if !$0 { providerToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { providerToRemove = nil }
            Button("Remove", role: .destructive) {
                if let provider = providerToRemove {
                    manager.removeProvider(provider)
                    providerToRemove = nil
                }
            }
        } message: {
            Text("Remove \(providerToRemove?.name ?? "this service")? You can add it back from the catalog.")
        }
    }

    private func intervalLabel(for seconds: Int) -> String {
        pollIntervalOptions.first(where: { $0.seconds == seconds })?.label ?? "\(seconds)s"
    }
}

// MARK: - Add Custom Service (sheet within Settings)

struct AddCustomServiceView: View {
    @Environment(StatusManager.self) var manager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var type: ProviderType = .statuspage

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Service")
                .font(.headline)

            TextField("Name (e.g. My Service)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Status Page URL (e.g. https://status.example.com)", text: $url)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $type) {
                ForEach(ProviderType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)

            Text("Supports Atlassian Statuspage, incident.io, and RSS/Atom feeds. For Statuspage/incident.io, use the base URL (e.g. https://status.example.com). For RSS, provide the full feed URL.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    let provider = Provider(name: name, baseURL: url, type: type)
                    manager.addProvider(provider)
                    logger.info("Added custom provider: \(name)")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Catalog Tab

struct CatalogSettingsView: View {
    @Environment(StatusManager.self) var manager
    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = Set(Catalog.shared.categories)

    private var catalog: Catalog { Catalog.shared }

    private static let popularIds: Set<String> = [
        "github", "cloudflare", "vercel", "openai", "anthropic",
        "stripe", "discord", "notion", "figma", "datadog"
    ]

    private var popularEntries: [CatalogEntry] {
        catalog.entries.filter { Self.popularIds.contains($0.id) }
    }

    private var monitoredIds: Set<String> {
        Set(manager.providers.compactMap(\.catalogEntryId))
    }

    private var filteredEntries: [(String, [CatalogEntry])] {
        catalog.categories.compactMap { category in
            let entries: [CatalogEntry]
            if searchText.isEmpty {
                entries = catalog.entries(in: category)
            } else {
                entries = catalog.search(searchText).filter { $0.category == category }
            }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Service Catalog")
                    .font(.headline)
                Text("(\(catalog.entries.count) available)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(monitoredIds.count) monitoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search services...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Category list
            List {
                // Popular services (shown when not searching)
                if searchText.isEmpty && !popularEntries.isEmpty {
                    Section("Popular") {
                        ForEach(popularEntries) { entry in
                            catalogToggle(for: entry)
                        }
                    }
                }

                ForEach(filteredEntries, id: \.0) { category, entries in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedCategories.contains(category) },
                            set: { if $0 { expandedCategories.insert(category) } else { expandedCategories.remove(category) } }
                        )
                    ) {
                        ForEach(entries) { entry in
                            catalogToggle(for: entry)
                        }
                    } label: {
                        HStack {
                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("(\(entries.count))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func catalogToggle(for entry: CatalogEntry) -> some View {
        let isMonitored = monitoredIds.contains(entry.id)
        Toggle(isOn: Binding(
            get: { isMonitored },
            set: { newValue in
                if newValue {
                    manager.addProvider(Provider(from: entry))
                    logger.info("Added from catalog: \(entry.name)")
                } else if let provider = manager.providers.first(where: { $0.catalogEntryId == entry.id }) {
                    manager.removeProvider(provider)
                    logger.info("Removed from catalog: \(entry.name)")
                }
            }
        )) {
            Text(entry.name)
                .font(.body)
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Preferences Tab

struct PreferencesSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logger.error("Launch at login failed: \(error.localizedDescription)")
                        }
                    }
                ))
            }

            Section("Notifications") {
                Toggle("Send notifications on status changes", isOn: $notificationsEnabled)
                Text("You'll be notified when a monitored service's status changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Help Tab

struct HelpSettingsView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App info
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Status Monitor")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Made by MoollApps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("How It Works")
                .font(.headline)
            Text("Status Monitor polls public status pages (Atlassian Statuspage and RSS feeds) on a configurable interval and shows you the current status of your services. When a status changes, you get a notification.")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/moollaza/status-monitor")!)
                Link("Report a Bug", destination: URL(string: "https://github.com/moollaza/status-monitor/issues/new?template=bug_report.yml")!)
                Link("Request a Feature", destination: URL(string: "https://github.com/moollaza/status-monitor/issues/new?template=feature_request.yml")!)
            }
            .font(.body)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
