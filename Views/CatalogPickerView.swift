import SwiftUI

struct CatalogPickerView: View {
    @Environment(StatusManager.self) var manager
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var expandedCategories: Set<String> = Set(Catalog.shared.categories)
    let isOnboarding: Bool
    let onDismiss: () -> Void

    private var catalog: Catalog { Catalog.shared }

    private var alreadyMonitoredIds: Set<String> {
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

    private var newSelectionCount: Int {
        selectedIds.subtracting(alreadyMonitoredIds).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Browse Services")
                    .font(.headline)
                Spacer()
                Button(isOnboarding ? "Skip" : "Done") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search services...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Category list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries, id: \.0) { category, entries in
                        // Category header
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedCategories.contains(category) {
                                    expandedCategories.remove(category)
                                } else {
                                    expandedCategories.insert(category)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: expandedCategories.contains(category) ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .frame(width: 12)
                                Text(category)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("(\(entries.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        if expandedCategories.contains(category) {
                            ForEach(entries) { entry in
                                CatalogEntryRow(
                                    entry: entry,
                                    isSelected: selectedIds.contains(entry.id) || alreadyMonitoredIds.contains(entry.id),
                                    isDisabled: alreadyMonitoredIds.contains(entry.id),
                                    onToggle: {
                                        if selectedIds.contains(entry.id) {
                                            selectedIds.remove(entry.id)
                                        } else {
                                            selectedIds.insert(entry.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer with Add button
            HStack {
                if newSelectionCount > 0 {
                    Text("\(newSelectionCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: addSelected) {
                    Text(newSelectionCount > 0 ? "Add \(newSelectionCount) Selected" : "Add Selected")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newSelectionCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func addSelected() {
        let newIds = selectedIds.subtracting(alreadyMonitoredIds)
        for entry in catalog.entries where newIds.contains(entry.id) {
            manager.addProvider(Provider(from: entry))
        }
        if isOnboarding {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
        onDismiss()
    }
}

// MARK: - Catalog Entry Row

struct CatalogEntryRow: View {
    let entry: CatalogEntry
    let isSelected: Bool
    let isDisabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            if !isDisabled { onToggle() }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isDisabled ? .gray : (isSelected ? .accentColor : .secondary))
                    .font(.body)

                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(isDisabled ? .secondary : .primary)

                Spacer()

                if isDisabled {
                    Text("Added")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
