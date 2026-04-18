import SwiftUI

enum StatusFilter: String, CaseIterable {
    case all = "All"
    case issuesOnly = "Issues Only"
}

struct ServiceDetailView: View {
    let snapshot: ProviderSnapshot
    var catalogId: String?
    var statusPageURL: URL?
    let onBack: () -> Void

    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var hasSetDefaultFilter = false

    private var defaultFilter: StatusFilter {
        snapshot.components.contains(where: { $0.status != .operational }) ? .issuesOnly : .all
    }

    private var filteredComponents: [ComponentSnapshot] {
        var result = snapshot.components

        // Apply status filter
        if statusFilter == .issuesOnly {
            result = result.filter { $0.status != .operational }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onBack()
                        }
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .medium))
                            Text("Services")
                                .font(.system(size: 12))
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

                    Spacer()

                    if let url = statusPageURL, url.scheme?.lowercased() == "https" {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 2) {
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

                HStack(spacing: 8) {
                    ServiceIconView(name: snapshot.name, catalogId: catalogId)

                    Text(snapshot.name)
                        .font(.system(.headline))

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(nsColor: snapshot.overallStatus.color))
                            .frame(width: 8, height: 8)
                        Text(snapshot.overallStatus.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(coarseTimeAgo(snapshot.lastUpdated, now: context.date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // One outer ScrollView wraps incidents + component list so the
            // header (back button, title, timestamp) stays pinned and nothing
            // can grow offscreen. Previously the incidents section had no
            // scroll container, so services with many in-progress maintenance
            // items (e.g. Zoom) pushed the back button off the panel and
            // trapped the user until they force-quit the app.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Active incidents
                    if !snapshot.activeIncidents.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Active Incidents")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(Array(snapshot.activeIncidents.enumerated()), id: \.element.id) { index, incident in
                                IncidentRow(incident: incident, defaultExpanded: index == 0)
                                if index < snapshot.activeIncidents.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.bottom, 4)

                        Divider()
                    }

                    // Search + filter bar
                    if !snapshot.components.isEmpty {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                TextField("Filter components...", text: $searchText)
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

                            Picker("Filter", selection: $statusFilter) {
                                ForEach(StatusFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider()

                        // Component list
                        let components = filteredComponents
                        if components.isEmpty {
                            VStack(spacing: 8) {
                                if statusFilter == .issuesOnly && searchText.isEmpty {
                                    Text("All \(snapshot.components.count) components operational")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No matching components")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .padding(.vertical, 16)
                        } else {
                            ForEach(components) { comp in
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                            }
                        }
                    } else if snapshot.activeIncidents.isEmpty {
                        VStack(spacing: 8) {
                            Text("No component data available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .onAppear {
            if !hasSetDefaultFilter {
                statusFilter = defaultFilter
                hasSetDefaultFilter = true
            }
        }
        .onChange(of: snapshot.id) {
            // Reset filter default when navigating to a different service
            statusFilter = defaultFilter
            searchText = ""
            hasSetDefaultFilter = true
        }
    }
}

// MARK: - Collapsible Incident Row

/// Status-page-style collapsible row. Collapsed: icon + title + status +
/// chevron. Expanded: the full update timeline (or latestUpdate fallback).
/// First incident in the list is expanded by default so the most relevant
/// problem is visible without a click.
struct IncidentRow: View {
    let incident: IncidentSnapshot
    let defaultExpanded: Bool
    @State private var isExpanded: Bool
    @State private var isHovered = false

    init(incident: IncidentSnapshot, defaultExpanded: Bool) {
        self.incident = incident
        self.defaultExpanded = defaultExpanded
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: incident.impact.color))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        Text(incident.status.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .padding(.top, 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isHovered ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.4) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded body: timeline if present, else latestUpdate
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !incident.updates.isEmpty {
                        ForEach(incident.updates) { update in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(update.status.capitalized)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                        if let date = update.createdAt {
                                            Text(date, style: .relative)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Text(update.body)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    } else if let update = incident.latestUpdate {
                        Text(update)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 28) // align under title text (past the icon)
                .padding(.trailing, 16)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
    }
}
