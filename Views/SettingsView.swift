import SwiftUI
import ServiceManagement
import UserNotifications
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

/// Shared store for the tab that should be selected when `SettingsView`
/// appears. Written by `AppDelegate.openSettings(tab:)` before opening or
/// fronting the window. The view reads it on appear and on `tabRequested`
/// notification so that right-click menu actions can target a specific tab
/// even when the settings window was already open.
enum SettingsInitialTab {
    static var value: SettingsTab = .services
}

extension Notification.Name {
    static let settingsTabRequested = Notification.Name("SettingsTabRequested")
}

struct SettingsView: View {
    @Environment(StatusManager.self) var manager
    @State private var selectedTab: SettingsTab = SettingsInitialTab.value

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
                    ServicesSettingsView(onAddServices: { selectedTab = .catalog })
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
        .onAppear {
            selectedTab = SettingsInitialTab.value
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabRequested)) { note in
            if let tab = note.userInfo?["tab"] as? SettingsTab {
                selectedTab = tab
            }
        }
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @Environment(StatusManager.self) var manager
    var onAddServices: (() -> Void)?
    @State private var providerToRemove: Provider?
    @State private var showAddCustom = false
    @State private var sortOrder = [KeyPathComparator(\Provider.name, comparator: .localizedStandard)]

    var sortedProviders: [Provider] {
        manager.providers.sorted(using: sortOrder)
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
                Button("Browse Catalog") { onAddServices?() }
                    .controlSize(.small)
                Button("Add Custom...") { showAddCustom = true }
                    .controlSize(.small)
            }
            .padding()

            if manager.providers.isEmpty {
                VStack(spacing: 12) {
                    Text("No services added")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Browse the catalog to find services to monitor.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Add Services") {
                        onAddServices?()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedProviders, sortOrder: $sortOrder) {
                    TableColumn("Service", value: \.name) { provider in
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
                        }
                    }

                    TableColumn("Interval") { provider in
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
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .width(70)

                    TableColumn("Muted") { provider in
                        Button {
                            manager.toggleMute(for: provider)
                        } label: {
                            Image(systemName: provider.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                                .foregroundStyle(provider.isMuted ? .orange : .secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(provider.isMuted ? "Unmute" : "Mute")
                    }
                    .width(50)

                    TableColumn("") { provider in
                        Button {
                            providerToRemove = provider
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .help("Remove service")
                    }
                    .width(30)
                }
                .alternatingRowBackgrounds()
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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var candidate: Provider {
        Provider(name: trimmedName, baseURL: trimmedURL, type: type)
    }

    private var validationMessage: String? {
        if trimmedName.isEmpty || trimmedURL.isEmpty { return nil }
        if !candidate.hasValidURL {
            return "URL must be a valid https:// address with a host"
        }
        if manager.providers.contains(where: { $0.baseURL == candidate.baseURL }) {
            return "A service with this URL is already being monitored"
        }
        return nil
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !trimmedURL.isEmpty && validationMessage == nil
    }

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

            if let message = validationMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") {
                    manager.addProvider(candidate)
                    logger.info("Added custom provider: \(trimmedName)")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
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
    @State private var selectedCategory: String? = nil
    @State private var visibleCount = 100
    @State private var suggestions: [CatalogEntry] = []
    @State private var suggestionsGenerated = false

    private static let pageSize = 100
    private static let suggestedTag = "__suggested__"

    private var catalog: Catalog { Catalog.shared }

    private var monitoredIds: Set<String> {
        Set(manager.providers.compactMap(\.catalogEntryId))
    }

    private var unmonitoredSuggestions: [CatalogEntry] {
        suggestions.filter { !monitoredIds.contains($0.id) }
    }

    private var isSuggestedCategory: Bool {
        selectedCategory == Self.suggestedTag
    }

    private var allFilteredEntries: [CatalogEntry] {
        if !searchText.isEmpty {
            return catalog.search(searchText)
        } else if isSuggestedCategory {
            return unmonitoredSuggestions
        } else if let category = selectedCategory {
            return catalog.entries(in: category)
        } else {
            return catalog.entries
        }
    }

    private var displayedEntries: [CatalogEntry] {
        Array(allFilteredEntries.prefix(visibleCount))
    }

    private func generateSuggestions() {
        suggestions = catalog.suggestFromInstalledApps()
        suggestionsGenerated = true
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

            // Category picker
            if searchText.isEmpty {
                HStack {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories (\(catalog.entries.count))")
                            .tag(nil as String?)
                        Divider()
                        Label("Suggested for You", systemImage: "laptopcomputer")
                            .tag(Self.suggestedTag as String?)
                        Divider()
                        ForEach(catalog.categoryCounts, id: \.0) { category, count in
                            Text("\(category) (\(count))")
                                .tag(category as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()

            // Service list with progressive loading
            if isSuggestedCategory && !suggestionsGenerated {
                // First time viewing Suggested — prompt to scan
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Find services from your installed apps")
                        .font(.headline)
                    Text("Scans app names in /Applications to match against the catalog.\nNo data leaves your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Scan Apps") {
                        generateSuggestions()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List {
                    if isSuggestedCategory {
                        // Privacy note + regenerate for Suggested
                        Section {
                            ForEach(displayedEntries) { entry in
                                catalogToggle(for: entry)
                            }
                        } footer: {
                            HStack {
                                Text("Based on apps in /Applications. Nothing leaves your device.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Rescan") { generateSuggestions() }
                                    .font(.caption2)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if unmonitoredSuggestions.isEmpty && suggestionsGenerated {
                            Section {
                                Text("No suggestions found. Try adding more apps or browse the catalog.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                    } else {
                        Section(searchText.isEmpty && selectedCategory == nil ? "All Services" : "") {
                            ForEach(displayedEntries) { entry in
                                catalogToggle(for: entry)
                            }
                            if visibleCount < allFilteredEntries.count {
                                Button("Show More (\(allFilteredEntries.count - visibleCount) remaining)") {
                                    visibleCount += Self.pageSize
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onChange(of: selectedCategory) { visibleCount = Self.pageSize }
                .onChange(of: searchText) { visibleCount = Self.pageSize }
            }
        }
    }

    @ViewBuilder
    private func catalogToggle(for entry: CatalogEntry) -> some View {
        let isMonitored = monitoredIds.contains(entry.id)
        HStack {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                    if let host = URL(string: entry.baseURL)?.host {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            if selectedCategory == nil {
                Text(entry.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preferences Tab

struct PreferencesSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @State private var systemNotificationsAllowed: Bool? = nil

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
                if systemNotificationsAllowed == false {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications are disabled in System Settings")
                                .font(.caption)
                            Button("Open Notification Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    Toggle("Send notifications on status changes", isOn: $notificationsEnabled)
                    Text("You'll be notified when a monitored service's status changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    systemNotificationsAllowed = settings.authorizationStatus == .authorized
                }
            }
        }
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
                    Text("Nazar")
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
            Text("Nazar polls public status pages (Atlassian Statuspage and RSS feeds) on a configurable interval and shows you the current status of the services you depend on. When a status changes, you get a notification.")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/moollaza/nazar")!)
                Link("Report a Bug", destination: URL(string: "https://github.com/moollaza/nazar/issues/new?template=bug_report.yml")!)
                Link("Request a Feature", destination: URL(string: "https://github.com/moollaza/nazar/issues/new?template=feature_request.yml")!)
            }
            .font(.body)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
