import Foundation
import AppKit
import OSLog

private let catalogLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "catalog")

// MARK: - Catalog Entry (read-only reference data)

struct CatalogEntry: Identifiable, Codable, Equatable {
    let id: String          // kebab-case slug, e.g. "github"
    let name: String        // Display name, e.g. "GitHub"
    let baseURL: String     // Status page base URL
    let type: ProviderType  // .statuspage or .rss
    let category: String    // e.g. "Developer Tools"
    let platform: String?   // "atlassian", "incident.io", etc.

    enum CodingKeys: String, CodingKey {
        case id, name, type, category, platform
        case baseURL = "base_url"
    }
}

// MARK: - Catalog (static bundled data)

struct Catalog {
    let entries: [CatalogEntry]
    let categories: [String]

    /// Pre-computed category counts for picker display
    let categoryCounts: [(String, Int)]

    static let shared: Catalog = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            catalogLogger.error("catalog.json missing from app bundle — catalog will be empty")
            return Catalog(entries: [], categories: [], categoryCounts: [])
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            catalogLogger.error("Failed to read catalog.json: \(error.localizedDescription)")
            return Catalog(entries: [], categories: [], categoryCounts: [])
        }
        // Per-entry tolerant decode so one malformed row doesn't nuke the whole file.
        let decoded = decodeTolerantly(data: data)
        let sorted = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let categories = Array(Set(sorted.map(\.category))).sorted()
        var countsByCategory: [String: Int] = [:]
        for entry in sorted { countsByCategory[entry.category, default: 0] += 1 }
        let categoryCounts = categories.map { ($0, countsByCategory[$0] ?? 0) }.sorted { $0.1 > $1.1 }
        catalogLogger.info("Loaded \(sorted.count) catalog entries")
        return Catalog(entries: sorted, categories: categories, categoryCounts: categoryCounts)
    }()

    /// Decodes a JSON array of CatalogEntry tolerantly — a single malformed entry
    /// is skipped with a warning rather than failing the whole file.
    private static func decodeTolerantly(data: Data) -> [CatalogEntry] {
        let decoder = JSONDecoder()
        // Fast path: well-formed file decodes in one shot.
        if let entries = try? decoder.decode([CatalogEntry].self, from: data) {
            return entries
        }
        // Slow path: decode as array of raw JSON values, attempt each separately.
        guard let anyArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            catalogLogger.error("catalog.json is not a JSON array of objects")
            return []
        }
        var results: [CatalogEntry] = []
        for (idx, item) in anyArray.enumerated() {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let entry = try? decoder.decode(CatalogEntry.self, from: itemData) else {
                let name = (item["name"] as? String) ?? "<unknown>"
                catalogLogger.warning("Skipped malformed catalog entry #\(idx) (\(name))")
                continue
            }
            results.append(entry)
        }
        return results
    }

    func entries(in category: String) -> [CatalogEntry] {
        entries.filter { $0.category == category }
    }

    func search(_ query: String) -> [CatalogEntry] {
        guard !query.isEmpty else { return entries }
        let q = query.lowercased()
        // Score: 0 = name starts with query, 1 = name word starts with query,
        // 2 = name contains query, 3 = URL contains query
        var scored: [(entry: CatalogEntry, score: Int)] = []
        for entry in entries {
            let name = entry.name.lowercased()
            if name.hasPrefix(q) {
                scored.append((entry, 0))
            } else if name.components(separatedBy: .whitespaces).contains(where: { $0.hasPrefix(q) }) {
                scored.append((entry, 1))
            } else if name.contains(q) {
                scored.append((entry, 2))
            } else if entry.baseURL.lowercased().contains(q) {
                scored.append((entry, 3))
            }
        }
        return scored
            .sorted { $0.score == $1.score
                ? $0.entry.name.localizedCaseInsensitiveCompare($1.entry.name) == .orderedAscending
                : $0.score < $1.score }
            .map(\.entry)
    }

    /// Returns catalog entries that match installed applications in /Applications.
    /// Uses strict matching to avoid false positives (e.g. "Obsidian" != "Obsidian Security").
    func suggestFromInstalledApps() -> [CatalogEntry] {
        let fm = FileManager.default
        var appNames: Set<String> = []

        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                for item in contents where item.hasSuffix(".app") {
                    let name = item.replacingOccurrences(of: ".app", with: "").lowercased()
                    appNames.insert(name)
                    // Also insert without common suffixes
                    let normalized = name
                        .replacingOccurrences(of: " desktop", with: "")
                        .replacingOccurrences(of: ".us", with: "")
                    if normalized != name { appNames.insert(normalized) }
                }
            }
        }

        guard !appNames.isEmpty else { return [] }

        return entries.filter { entry in
            let entryName = entry.name.lowercased()
            guard entryName.count >= 4 else { return false }

            return appNames.contains(where: { appName in
                guard appName.count >= 4 else { return false }
                // Exact match: "figma" == "figma"
                if appName == entryName { return true }
                // App name equals full catalog entry name (handles "1password" == "1password")
                // Entry name starts with app name and next char is a space/separator
                // e.g. "github" matches "github" but not "github desktop"
                // App name starts with entry name: "grammarly desktop" matches "grammarly"
                if appName.hasPrefix(entryName + " ") || appName.hasPrefix(entryName + "-") { return true }
                if entryName.hasPrefix(appName + " ") || entryName.hasPrefix(appName + "-") { return true }
                return false
            })
        }
    }
}

// MARK: - Provider Configuration

struct Provider: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String
    var type: ProviderType
    var pollIntervalSeconds: Int
    var isEnabled: Bool
    var catalogEntryId: String?  // matches CatalogEntry.id if created from catalog
    var isMuted: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, type, pollIntervalSeconds, isEnabled, catalogEntryId, isMuted
    }

    init(name: String, baseURL: String, type: ProviderType = .statuspage, pollIntervalSeconds: Int = 60, isEnabled: Bool = true, catalogEntryId: String? = nil, isMuted: Bool = false) {
        self.id = UUID()
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.type = type
        self.pollIntervalSeconds = max(30, pollIntervalSeconds)
        self.isEnabled = isEnabled
        self.catalogEntryId = catalogEntryId
        self.isMuted = isMuted
    }

    init(from entry: CatalogEntry) {
        self.init(name: entry.name, baseURL: entry.baseURL, type: entry.type, catalogEntryId: entry.id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        type = try container.decode(ProviderType.self, forKey: .type)
        pollIntervalSeconds = try container.decode(Int.self, forKey: .pollIntervalSeconds)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        catalogEntryId = try container.decodeIfPresent(String.self, forKey: .catalogEntryId)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }

    var hasValidURL: Bool {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    var apiURL: URL? {
        guard hasValidURL else { return nil }
        switch type {
        case .statuspage:
            return URL(string: "\(baseURL)/api/v2/summary.json")
        case .rss:
            return URL(string: baseURL)
        }
    }

    /// URL suitable for opening in the user's browser (NSWorkspace.open). Nil
    /// when the baseURL is not a valid https URL — prevents `file://`,
    /// `javascript:`, `x-apple.*` and other schemes from reaching NSWorkspace.
    var externalURL: URL? {
        guard hasValidURL, let url = URL(string: baseURL) else { return nil }
        return url
    }

    static let defaults: [Provider] = []
}

enum ProviderType: String, Codable, CaseIterable {
    case statuspage   // Atlassian Statuspage JSON API
    case rss          // Generic RSS/Atom feed
}

// MARK: - Atlassian Statuspage API Response

struct StatuspageSummary: Codable {
    let page: StatuspagePage
    let status: StatuspageOverall
    let components: [StatuspageComponent]
    let incidents: [StatuspageIncident]?
    let scheduledMaintenances: [StatuspageIncident]?

    enum CodingKeys: String, CodingKey {
        case page, status, components, incidents
        case scheduledMaintenances = "scheduled_maintenances"
    }
}

struct StatuspagePage: Codable {
    let name: String
    let url: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case name, url
        case updatedAt = "updated_at"
    }
}

struct StatuspageOverall: Codable {
    let indicator: String      // "none", "minor", "major", "critical"
    let description: String
}

struct StatuspageComponent: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let description: String?
    let updatedAt: String?
    let group: Bool?
    let groupId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, description
        case updatedAt = "updated_at"
        case group
        case groupId = "group_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(String.self, forKey: .status)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        group = try container.decodeIfPresent(Bool.self, forKey: .group)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
    }
}

struct StatuspageIncident: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let createdAt: String?
    let updatedAt: String
    let incidentUpdates: [StatuspageIncidentUpdate]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, impact
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case incidentUpdates = "incident_updates"
    }
}

struct StatuspageIncidentUpdate: Codable, Identifiable {
    let id: String
    let status: String
    let body: String?        // optional — incident.io variants sometimes omit body
    let createdAt: String?   // optional — some responses omit created_at on silently-created updates

    enum CodingKeys: String, CodingKey {
        case id, status, body
        case createdAt = "created_at"
    }
}

// MARK: - Normalized Status Model (internal)

enum ComponentStatus: String, Codable, Comparable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"
    case unknown

    var severity: Int {
        switch self {
        case .operational: return 0
        case .unknown: return 1            // elevated so unrecognised/errored state surfaces instead of masquerading as healthy
        case .degradedPerformance: return 2
        case .underMaintenance: return 2
        case .partialOutage: return 3
        case .majorOutage: return 4
        }
    }

    static func < (lhs: ComponentStatus, rhs: ComponentStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var label: String {
        switch self {
        case .operational: return "Operational"
        case .degradedPerformance: return "Degraded"
        case .partialOutage: return "Partial Outage"
        case .majorOutage: return "Major Outage"
        case .underMaintenance: return "Maintenance"
        case .unknown: return "Unknown"
        }
    }

    var color: NSColor {
        switch self {
        case .operational: return .systemGreen
        case .degradedPerformance: return .systemYellow
        case .underMaintenance: return .systemYellow
        case .partialOutage: return .systemOrange
        case .majorOutage: return .systemRed
        case .unknown: return .systemGray
        }
    }

    /// High-contrast color safe for use as text foreground (meets WCAG 4.5:1 on light/dark backgrounds)
    var textColor: NSColor {
        switch self {
        case .operational: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .systemGreen
                : NSColor(red: 0.08, green: 0.40, blue: 0.15, alpha: 1) // dark green #166534
        }
        case .degradedPerformance, .underMaintenance: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .systemYellow
                : NSColor(red: 0.52, green: 0.35, blue: 0.0, alpha: 1) // dark amber #855A00
        }
        case .partialOutage: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .systemOrange
                : NSColor(red: 0.60, green: 0.22, blue: 0.02, alpha: 1) // dark orange #9a3412
        }
        case .majorOutage: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .systemRed
                : NSColor(red: 0.60, green: 0.04, blue: 0.04, alpha: 1) // dark red #991b1b
        }
        case .unknown: return .secondaryLabelColor
        }
    }

    var iconInfo: (name: String, color: NSColor) {
        switch self {
        case .operational: return ("checkmark.circle.fill", .systemGreen)
        case .degradedPerformance: return ("exclamationmark.triangle.fill", .systemYellow)
        case .underMaintenance: return ("wrench.fill", .systemYellow)
        case .partialOutage: return ("exclamationmark.triangle.fill", .systemOrange)
        case .majorOutage: return ("xmark.circle.fill", .systemRed)
        case .unknown: return ("questionmark.circle.fill", .systemGray)
        }
    }

    init(fromStatuspage raw: String) {
        self = ComponentStatus(rawValue: raw) ?? .unknown
    }

    init(fromIndicator raw: String) {
        switch raw {
        case "none": self = .operational
        case "minor": self = .degradedPerformance
        case "major": self = .partialOutage
        case "critical": self = .majorOutage
        case "maintenance": self = .underMaintenance
        default: self = .unknown
        }
    }
}

struct ProviderSnapshot: Identifiable {
    let id: UUID                        // matches Provider.id
    let name: String
    var overallStatus: ComponentStatus
    var components: [ComponentSnapshot]
    var activeIncidents: [IncidentSnapshot]
    var lastUpdated: Date
    var error: String?

    var hasActiveIncidents: Bool { !activeIncidents.isEmpty }
}

struct ComponentSnapshot: Identifiable {
    let id: String
    let name: String
    let status: ComponentStatus
}

struct IncidentSnapshot: Identifiable {
    let id: String
    let name: String
    let impact: ComponentStatus
    let status: String
    let latestUpdate: String?
    let updatedAt: Date?
    let updates: [IncidentUpdateSnapshot]

    init(id: String, name: String, impact: ComponentStatus, status: String, latestUpdate: String?, updatedAt: Date?, updates: [IncidentUpdateSnapshot] = []) {
        self.id = id
        self.name = name
        self.impact = impact
        self.status = status
        self.latestUpdate = latestUpdate
        self.updatedAt = updatedAt
        self.updates = updates
    }
}

struct IncidentUpdateSnapshot: Identifiable {
    let id: String
    let status: String
    let body: String
    let createdAt: Date?
}
