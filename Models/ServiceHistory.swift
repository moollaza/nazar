import Foundation

/// How bad a day or an incident was. Ordered so `max` picks the worst:
/// a real incident always outranks maintenance.
enum HistorySeverity: Int, Comparable, Codable {
    case clear, maintenance, minor, major

    static func < (lhs: HistorySeverity, rhs: HistorySeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps a Statuspage / incident.io `impact` value. `none` (an
    /// informational post) carries no severity and is dropped.
    init?(statuspageImpact impact: String) {
        switch impact.lowercased() {
        case "critical", "major": self = .major
        case "minor": self = .minor
        case "maintenance": self = .maintenance
        default: return nil
        }
    }

    /// Maps a live component status, for feeds that report an incident's
    /// impact as the status of the components it affects (Datadog).
    init?(componentStatus status: ComponentStatus) {
        switch status {
        case .majorOutage: self = .major
        case .partialOutage, .degradedPerformance: self = .minor
        case .underMaintenance: self = .maintenance
        case .operational, .unknown: return nil
        }
    }
}

/// One incident or maintenance window as published by the status page.
struct IncidentInterval: Equatable {
    let start: Date
    /// Nil while the incident is still open.
    let end: Date?
    let severity: HistorySeverity
}

extension IncidentInterval {
    /// Statuses after which an incident is over even if `resolved_at` is empty.
    static let closedStatuses: Set<String> = ["resolved", "postmortem", "completed"]

    init?(statuspage incident: StatuspageHistoryIncident) {
        // Maintenance that has not started yet is a plan, not history.
        guard incident.status?.lowercased() != "scheduled",
              let severity = incident.impact.flatMap(HistorySeverity.init(statuspageImpact:)) else { return nil }
        let isMaintenance = severity == .maintenance
        let startText = (isMaintenance ? incident.scheduledFor : nil) ?? incident.startedAt ?? incident.createdAt
        guard let start = startText.flatMap(StatusDate.parse) else { return nil }
        let closed = Self.closedStatuses.contains(incident.status?.lowercased() ?? "")
        let end = incident.resolvedAt.flatMap(StatusDate.parse)
            ?? (isMaintenance ? incident.scheduledUntil.flatMap(StatusDate.parse) : nil)
            ?? (closed ? incident.updatedAt.flatMap(StatusDate.parse) : nil)
        self.init(start: start, end: end, severity: severity)
    }
}

extension DatadogConfig {
    /// The page's full incident and maintenance history.
    var historyIntervals: [IncidentInterval] {
        let incidents: [IncidentInterval] = (incidents ?? []).compactMap { incident in
            guard let start = incident.publishedDate.flatMap(StatusDate.parse) else { return nil }
            // An incident that names no affected component still happened;
            // with nothing to grade it by, it counts as minor.
            let severity = (incident.componentsAffected ?? [])
                .compactMap { HistorySeverity(componentStatus: ComponentStatus(fromDatadog: $0.status ?? "")) }
                .max() ?? .minor
            let end = incident.resolved == true
                ? (incident.resolvedDate ?? incident.lastModifiedAt).flatMap(StatusDate.parse) ?? start
                : nil
            return IncidentInterval(start: start, end: end, severity: severity)
        }
        let maintenances: [IncidentInterval] = (maintenances ?? []).compactMap { maint in
            guard let start = maint.scheduledStartDate.flatMap(StatusDate.parse) else { return nil }
            return IncidentInterval(start: start, end: maint.scheduledEndDate.flatMap(StatusDate.parse), severity: .maintenance)
        }
        return incidents + maintenances
    }
}

/// The last 28 days of one service, built from its incident intervals.
struct ServiceHistory: Equatable {
    static let dayCount = 28

    /// One entry per calendar day, oldest first; the last entry is today.
    let days: [HistorySeverity]
    /// Share of the last 28 × 24 hours with no incident open, 0...1.
    /// Maintenance never counts against it.
    let incidentFree: Double
    /// Incidents (not maintenance) that overlap the 28 calendar days.
    let issueCount: Int
    /// Start of the most recent of those incidents, before clipping.
    let lastIssue: Date?
    let now: Date
    let calendar: Calendar
    private let firstDay: Date

    init(intervals: [IncidentInterval], now: Date, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(Self.dayCount - 1), to: today) ?? today
        self.firstDay = firstDay
        let dayStarts = (0...Self.dayCount).map { calendar.date(byAdding: .day, value: $0, to: firstDay) ?? firstDay }

        // An open incident runs until now.
        let closed = intervals.map { (start: $0.start, end: min($0.end ?? now, now), severity: $0.severity) }
            .filter { $0.end > $0.start }

        days = (0..<Self.dayCount).map { i in
            closed
                .filter { $0.start < dayStarts[i + 1] && $0.end > dayStarts[i] }
                .map(\.severity)
                .max() ?? .clear
        }

        let incidents = closed.filter { $0.severity != .maintenance }
        let inStrip = incidents.filter { $0.end > firstDay }
        issueCount = inStrip.count
        lastIssue = inStrip.map(\.start).max()

        // The percent uses a rolling window so it doesn't jump at midnight.
        // Overlapping incidents count once: merge before summing.
        let window = Double(Self.dayCount) * 86_400
        let windowStart = now.addingTimeInterval(-window)
        let clipped: [(start: Date, end: Date)] = incidents.compactMap {
            let start = max($0.start, windowStart)
            return $0.end > start ? (start, $0.end) : nil
        }
        var downtime: TimeInterval = 0
        var run: (start: Date, end: Date)?
        for interval in clipped.sorted(by: { $0.start < $1.start }) {
            if let current = run, interval.start <= current.end {
                run = (current.start, max(current.end, interval.end))
            } else {
                if let current = run { downtime += current.end.timeIntervalSince(current.start) }
                run = interval
            }
        }
        if let current = run { downtime += current.end.timeIntervalSince(current.start) }
        incidentFree = max(0, 1 - downtime / window)
    }

    /// The strip entry for the calendar day containing `date`, or nil
    /// outside the 28 days.
    func day(for date: Date) -> HistorySeverity? {
        guard let index = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day,
              days.indices.contains(index) else { return nil }
        return days[index]
    }

    /// "100%" only with no incident time at all; otherwise one decimal,
    /// rounded down so a short incident never shows as 100.0%.
    var incidentFreeText: String {
        guard incidentFree < 1 else { return "100%" }
        let tenths = min((incidentFree * 1000).rounded(.down) / 10, 99.9)
        return String(format: "%.1f%%", tenths)
    }

    var incidentFreeSummary: String { "\(incidentFreeText) incident-free over \(Self.dayCount) days" }

    var issueSummary: String {
        guard issueCount > 0, let lastIssue else { return "No issues in \(Self.dayCount) days" }
        let noun = issueCount == 1 ? "issue" : "issues"
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastIssue),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        let when = daysAgo <= 0 ? "today" : daysAgo == 1 ? "1 day ago" : "\(daysAgo) days ago"
        return "\(issueCount) \(noun) in \(Self.dayCount) days, last \(when)"
    }
}

// MARK: - Statuspage / incident.io history feed (`/api/v2/incidents.json`)

struct StatuspageIncidentList: Decodable {
    let incidents: [StatuspageHistoryIncident]
}

struct StatuspageHistoryIncident: Decodable {
    let id: String
    let status: String?
    let impact: String?
    let createdAt: String?
    let startedAt: String?
    let resolvedAt: String?
    let updatedAt: String?
    let scheduledFor: String?
    let scheduledUntil: String?

    enum CodingKeys: String, CodingKey {
        case id, status, impact
        case createdAt = "created_at"
        case startedAt = "started_at"
        case resolvedAt = "resolved_at"
        case updatedAt = "updated_at"
        case scheduledFor = "scheduled_for"
        case scheduledUntil = "scheduled_until"
    }
}
