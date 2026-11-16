import Foundation

enum AppleSystemStatus {
    static func feedURL(for pageURL: String) -> URL? {
        guard let page = URLComponents(string: pageURL),
              page.scheme?.lowercased() == "https",
              page.user == nil, page.password == nil,
              page.port == nil || page.port == 443,
              page.query == nil, page.fragment == nil else { return nil }

        let path: String
        switch (page.host?.lowercased(), page.percentEncodedPath) {
        case ("developer.apple.com", "/system-status"),
             ("developer.apple.com", "/system-status/"):
            path = "https://developer.apple.com/system-status/data/system_status_en_US.js"
        case ("www.apple.com", "/support/systemstatus"),
             ("www.apple.com", "/support/systemstatus/"):
            path = "https://www.apple.com/support/systemstatus/data/system_status_en_US.js"
        default:
            return nil
        }
        return URL(string: path)
    }

    static func snapshot(from data: Data, provider: Provider, now: Date) throws -> ProviderSnapshot {
        let feed = try JSONDecoder().decode(AppleFeed.self, from: jsonData(from: data))
        guard feed.drpost != true, !feed.services.isEmpty else { throw FeedError.unavailable }

        var components: [ComponentSnapshot] = []
        var incidents: [IncidentSnapshot] = []
        for service in feed.services {
            guard !service.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FeedError.malformed
            }
            var status = ComponentStatus.operational
            var incidentIDs: Set<String> = []
            for event in service.events {
                guard !event.messageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw FeedError.malformed
                }
                guard let impact = event.activeStatus(at: now) else { continue }
                status = max(status, impact)
                guard impact != .operational else { continue }
                let id = "\(service.serviceName.utf8.count):\(service.serviceName)\(event.messageId)"
                guard incidentIDs.insert(id).inserted else { continue }
                incidents.append(IncidentSnapshot(
                    id: id,
                    name: "\(service.serviceName): \(event.statusType)",
                    impact: impact,
                    status: impact == .underMaintenance ? "ongoing" : event.eventStatus,
                    latestUpdate: event.message,
                    updatedAt: event.startDate
                ))
            }
            components.append(ComponentSnapshot(id: service.serviceName, name: service.serviceName, status: status))
        }
        incidents.sort {
            if $0.impact.severity != $1.impact.severity { return $0.impact.severity > $1.impact.severity }
            if $0.updatedAt != $1.updatedAt { return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            return $0.id < $1.id
        }
        return ProviderSnapshot(
            id: provider.id,
            name: provider.name,
            overallStatus: components.map(\.status).max() ?? .unknown,
            components: components,
            activeIncidents: Array(incidents.prefix(5)),
            lastUpdated: now,
            error: nil
        )
    }

    private static func jsonData(from data: Data) throws -> Data {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        guard var text = String(data: bytes, encoding: .utf8) else { throw FeedError.malformed }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("jsonCallback(") {
            text.removeFirst("jsonCallback(".count)
            if text.hasSuffix(";") { text.removeLast() }
            guard text.hasSuffix(")") else { throw FeedError.malformed }
            text.removeLast()
        }
        return Data(text.utf8)
    }

    private enum FeedError: Error {
        case malformed
        case unavailable
    }
}

private struct AppleFeed: Decodable {
    let drpost: Bool?
    let services: [AppleService]
}

private struct AppleService: Decodable {
    let serviceName: String
    let events: [AppleEvent]
}

private struct AppleEvent: Decodable {
    let messageId: String
    let statusType: String
    let eventStatus: String
    let message: String?
    let epochStartDate: Double?
    let epochEndDate: Double?

    var startDate: Date? { Self.date(from: epochStartDate) }

    func activeStatus(at now: Date) -> ComponentStatus? {
        let lifecycle = eventStatus.lowercased()
        if lifecycle == "resolved" || lifecycle == "completed" { return nil }
        guard lifecycle == "ongoing" || lifecycle == "upcoming" else { return .unknown }

        let kind = statusType.lowercased()
        if kind == "maintenance" {
            if let start = startDate, let end = Self.date(from: epochEndDate), start < end {
                return start <= now && now < end ? .underMaintenance : nil
            }
            return lifecycle == "ongoing" ? .underMaintenance : nil
        }
        guard lifecycle == "ongoing" else { return nil }
        // Apple can supply placeholder end epochs for ongoing incidents.
        switch kind {
        case "outage": return .majorOutage
        case "issue": return .partialOutage
        case "performance": return .degradedPerformance
        case "available": return .operational
        default: return .unknown
        }
    }

    private static func date(from epoch: Double?) -> Date? {
        guard let epoch, epoch.isFinite, epoch > 0,
              epoch / 1_000 <= Date.distantFuture.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: epoch / 1_000)
    }
}
