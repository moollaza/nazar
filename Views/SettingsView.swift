import SwiftUI

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
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newType: ProviderType = .statuspage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Providers")
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

            List {
                ForEach(manager.providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.system(.body, weight: .medium))
                            HStack(spacing: 4) {
                                Text(provider.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Picker("", selection: Binding<Int>(
                            get: { provider.pollIntervalSeconds },
                            set: { manager.updatePollInterval(for: provider, seconds: $0) }
                        )) {
                            ForEach(pollIntervalOptions, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .help("Poll interval")
                        Text(provider.type.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            manager.removeProvider(provider)
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
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
    }

    private var addProviderSheet: some View {
        VStack(spacing: 16) {
            Text("Add Provider")
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
}
