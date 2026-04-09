import SwiftUI

struct DashboardView: View {
    @Environment(StatusManager.self) var manager
    @State private var expandedProvider: UUID?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Status Monitor")
                    .font(.headline)
                Spacer()
                Button(action: { manager.pollAll() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh all")

                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if manager.snapshots.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading status pages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(manager.snapshots.sorted(by: { $0.overallStatus > $1.overallStatus })) { snapshot in
                            ProviderRowView(
                                snapshot: snapshot,
                                isExpanded: expandedProvider == snapshot.id,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedProvider = expandedProvider == snapshot.id ? nil : snapshot.id
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
        .frame(width: 420, height: 520)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(manager)
        }
    }
}

// MARK: - Provider Row

struct ProviderRowView: View {
    let snapshot: ProviderSnapshot
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: snapshot.overallStatus.color))
                    .frame(width: 10, height: 10)

                Text(snapshot.name)
                    .font(.system(.body, weight: .medium))

                Spacer()

                if let error = snapshot.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
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
                    // Components
                    if !snapshot.components.isEmpty {
                        ForEach(snapshot.components) { comp in
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
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
    }
}
