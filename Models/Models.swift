import Foundation
import AppKit

// MARK: - Provider Configuration

struct Provider: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var baseURL: String          // e.g. "https://status.anthropic.com"
    var type: ProviderType
    var pollIntervalSeconds: Int
    var isEnabled: Bool

    init(name: String, baseURL: String, type: ProviderType = .statuspage, pollIntervalSeconds: Int = 60, isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.type = type
        self.pollIntervalSeconds = pollIntervalSeconds
        self.isEnabled = isEnabled
    }

    var apiURL: URL? {
        switch type {
        case .statuspage:
            return URL(string: "\(baseURL)/api/v2/summary.json")
        case .rss:
            return URL(string: baseURL)
        }
    }

    static let defaults: [Provider] = [
        Provider(name: "Anthropic", baseURL: "https://status.anthropic.com"),
        Provider(name: "Asana", baseURL: "https://status.asana.com"),
        Provider(name: "GitHub", baseURL: "https://www.githubstatus.com"),
        Provider(name: "OpenAI", baseURL: "https://status.openai.com"),
        Provider(name: "Slack", baseURL: "https://status.slack.com"),
        Provider(name: "Vercel", baseURL: "https://www.vercel-status.com"),
    ]
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
    let incidents: [StatuspageIncident]
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
    let status: String         // "operational", "degraded_performance", "partial_outage", "major_outage"
    let description: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, description
        case updatedAt = "updated_at"
    }
}

struct StatuspageIncident: Codable, Identifiable {
    let id: String
    let name: String
    let status: String         // "investigating", "identified", "monitoring", "resolved"
    let impact: String         // "none", "minor", "major", "critical"
    let createdAt: String
    let updatedAt: String
    let incidentUpdates: [StatuspageIncidentUpdate]

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
    let body: String
    let createdAt: String

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
    case unknown

    var severity: Int {
        switch self {
        case .operational: return 0
        case .degradedPerformance: return 1
        case .partialOutage: return 2
        case .majorOutage: return 3
        case .unknown: return -1
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
        case .unknown: return "Unknown"
        }
    }

    var color: NSColor {
        switch self {
        case .operational: return .systemGreen
        case .degradedPerformance: return .systemYellow
        case .partialOutage: return .systemOrange
        case .majorOutage: return .systemRed
        case .unknown: return .systemGray
        }
    }

    var iconInfo: (name: String, color: NSColor) {
        switch self {
        case .operational: return ("checkmark.circle.fill", .systemGreen)
        case .degradedPerformance: return ("exclamationmark.triangle.fill", .systemYellow)
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
}
