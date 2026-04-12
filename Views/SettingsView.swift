import SwiftUI
import ServiceManagement

private let pollIntervalOptions: [(label: String, seconds: Int)] = [
    ("30s", 30),
    ("1m", 60),
    ("2m", 120),
    ("5m", 300),
    ("15m", 900),
]

struct SettingsView: View {
    @Environment(StatusManager.self) var manager
    @State private var showAddProvider = false
    @State private var showCatalogPicker = false
    @State private var providerToRemove: Provider?
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newType: ProviderType = .statuspage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Services")
                    .font(.headline)
                Spacer()
                Button("Browse Catalog") { showCatalogPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Add Custom") { showAddProvider.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if manager.providers.isEmpty {
                VStack(spacing: 8) {
                    Text("No services added")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use Browse Catalog to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.providers) { provider in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(.body, weight: .medium))
                                Text(provider.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            // Poll interval — compact
                            Menu {
                                ForEach(pollIntervalOptions, id: \.seconds) { option in
                                    Button {
                                        manager.updatePollInterval(for: provider, seconds: option.seconds)
                                    } label: {
                                        HStack {
                                            Text(option.label)
                                            if provider.pollIntervalSeconds == option.seconds {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Text(intervalLabel(for: provider.pollIntervalSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Poll interval")

                            // Mute toggle
                            Button {
                                manager.toggleMute(for: provider)
                            } label: {
                                Image(systemName: provider.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundStyle(provider.isMuted ? .orange : .secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .help(provider.isMuted ? "Unmute service" : "Mute service")

                            // Remove button
                            Button {
                                providerToRemove = provider
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .help("Remove service")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("\(manager.providers.count) services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in toggleLaunchAtLogin(newValue) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
        }
        .frame(width: 440, height: 400)
        .sheet(isPresented: $showAddProvider) {
            addProviderSheet
        }
        .sheet(isPresented: $showCatalogPicker) {
            CatalogPickerView(isOnboarding: false) {
                showCatalogPicker = false
            }
            .environment(manager)
            .frame(width: 400, height: 480)
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

    private var addProviderSheet: some View {
        VStack(spacing: 16) {
            Text("Add Custom Service")
                .font(.headline)

            TextField("Name (e.g. Anthropic)", text: $newName)
                .textFieldStyle(.roundedBorder)

            TextField("URL (e.g. https://status.anthropic.com)", text: $newURL)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $newType) {
                ForEach(ProviderType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Text("For Atlassian Statuspage sites, use the base URL. The app appends /api/v2/summary.json automatically. For RSS, provide the full feed URL.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    resetAddForm()
                    showAddProvider = false
                }
                Spacer()
                Button("Add") {
                    let provider = Provider(name: newName, baseURL: newURL, type: newType)
                    manager.addProvider(provider)
                    resetAddForm()
                    showAddProvider = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func resetAddForm() {
        newName = ""
        newURL = ""
        newType = .statuspage
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login failed: \(error.localizedDescription)")
        }
    }
}
