import Foundation
import Observation

@MainActor
@Observable
class StatusManager {
    var snapshots: [ProviderSnapshot] = []
    var providers: [Provider] = []
    var worstStatus: ComponentStatus = .operational
    var isPolling = false

    var onWorstStatusChanged: ((ComponentStatus) -> Void)?
    private var timers: [UUID: Timer] = [:]
    private var previousStatuses: [UUID: ComponentStatus] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init() {
        loadProviders()
    }

    // MARK: - Provider Persistence

    func loadProviders() {
        if let data = UserDefaults.standard.data(forKey: "providers"),
           let saved = try? JSONDecoder().decode([Provider].self, from: data),
           !saved.isEmpty {
            providers = saved
            // Migration: existing users who haven't seen onboarding
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        } else if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            // User completed onboarding but removed all providers
            providers = []
        } else {
            // First launch — onboarding will handle provider selection
            providers = []
        }
    }

    func saveProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: "providers")
        }
    }

    func addProvider(_ provider: Provider) {
        providers.append(provider)
        saveProviders()
        schedulePolling(for: provider)
        Task { await poll(provider: provider) }
    }

    func removeProvider(_ provider: Provider) {
        timers[provider.id]?.invalidate()
        timers.removeValue(forKey: provider.id)
        providers.removeAll { $0.id == provider.id }
        snapshots.removeAll { $0.id == provider.id }
        previousStatuses.removeValue(forKey: provider.id)
        saveProviders()
        recalcWorstStatus()
    }

    // MARK: - Polling

    func startPolling() {
        isPolling = true
        let enabled = providers.filter(\.isEnabled)
        for provider in enabled {
            schedulePolling(for: provider)
        }
        // Initial poll with concurrency cap
        Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for provider in enabled {
                    if running >= maxConcurrentPolls {
                        await group.next()
                        running -= 1
                    }
                    group.addTask { @MainActor [weak self] in
                        await self?.poll(provider: provider)
                    }
                    running += 1
                }
            }
        }
    }

    func stopPolling() {
        isPolling = false
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    private func schedulePolling(for provider: Provider) {
        timers[provider.id]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(provider.pollIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll(provider: provider)
            }
        }
        timers[provider.id] = timer
    }

    private let maxConcurrentPolls = 6

    func pollAll() {
        let enabled = providers.filter(\.isEnabled)
        Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for provider in enabled {
                    if running >= maxConcurrentPolls {
                        await group.next()
                        running -= 1
                    }
                    group.addTask { @MainActor [weak self] in
                        await self?.poll(provider: provider)
                    }
                    running += 1
                }
            }
        }
    }

    private func poll(provider: Provider) async {
        guard let url = provider.apiURL else {
            updateSnapshot(for: provider, error: "Invalid URL")
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                updateSnapshot(for: provider, error: "Unable to reach status page")
                return
            }

            switch provider.type {
            case .statuspage:
                try parseStatuspage(data: data, provider: provider)
            case .rss:
                try parseRSS(data: data, provider: provider)
            }
        } catch {
            updateSnapshot(for: provider, error: "Unable to read status page")
        }
    }

    // MARK: - Statuspage JSON Parsing

    private static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }

    private func parseStatuspage(data: Data, provider: Provider) throws {
        let decoder = JSONDecoder()
        let summary = try decoder.decode(StatuspageSummary.self, from: data)

        let overall = ComponentStatus(fromIndicator: summary.status.indicator)
        let components = summary.components.map {
            ComponentSnapshot(id: $0.id, name: $0.name, status: ComponentStatus(fromStatuspage: $0.status))
        }
        let incidents = (summary.incidents ?? []).prefix(5).map { incident in
            IncidentSnapshot(
                id: incident.id,
                name: incident.name,
                impact: ComponentStatus(fromIndicator: incident.impact),
                status: incident.status,
                latestUpdate: incident.incidentUpdates?.first?.body,
                updatedAt: Self.parseDate(incident.updatedAt)
            )
        }

        let snapshot = ProviderSnapshot(
            id: provider.id,
            name: provider.name,
            overallStatus: overall,
            components: components,
            activeIncidents: Array(incidents),
            lastUpdated: Date(),
            error: nil
        )

        applySnapshot(snapshot, for: provider)
    }

    // MARK: - RSS Parsing (basic)

    private func parseRSS(data: Data, provider: Provider) throws {
        let parser = RSSStatusParser(data: data)
        let items = parser.parse()

        // Heuristic: check titles/descriptions for outage keywords
        let overall: ComponentStatus = items.first.map { item in
            let text = (item.title + " " + item.description).lowercased()
            if text.contains("major") || text.contains("outage") { return .majorOutage }
            if text.contains("partial") { return .partialOutage }
            if text.contains("degraded") || text.contains("elevated") { return .degradedPerformance }
            if text.contains("resolved") || text.contains("operational") { return .operational }
            return .unknown
        } ?? .unknown

        let incidents = items.prefix(5).map { item in
            IncidentSnapshot(
                id: item.guid ?? item.title,
                name: item.title,
                impact: overall,
                status: "rss",
                latestUpdate: item.description,
                updatedAt: item.pubDate
            )
        }

        let snapshot = ProviderSnapshot(
            id: provider.id,
            name: provider.name,
            overallStatus: overall,
            components: [],
            activeIncidents: Array(incidents),
            lastUpdated: Date(),
            error: nil
        )

        applySnapshot(snapshot, for: provider)
    }

    // MARK: - Snapshot Management

    private func applySnapshot(_ snapshot: ProviderSnapshot, for provider: Provider) {
        let previousStatus = previousStatuses[provider.id]

        if let idx = snapshots.firstIndex(where: { $0.id == provider.id }) {
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }

        // Notify on status change (not on first poll)
        if let prev = previousStatus, prev != snapshot.overallStatus {
            NotificationService.shared.notify(
                provider: provider.name,
                from: prev,
                to: snapshot.overallStatus,
                incident: snapshot.activeIncidents.first?.name
            )
        }

        previousStatuses[provider.id] = snapshot.overallStatus
        recalcWorstStatus()
    }

    private func updateSnapshot(for provider: Provider, error: String) {
        let snapshot = ProviderSnapshot(
            id: provider.id,
            name: provider.name,
            overallStatus: .unknown,
            components: [],
            activeIncidents: [],
            lastUpdated: Date(),
            error: error
        )
        if let idx = snapshots.firstIndex(where: { $0.id == provider.id }) {
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        recalcWorstStatus()
    }

    private func recalcWorstStatus() {
        let newStatus = snapshots
            .filter { $0.error == nil }
            .map(\.overallStatus)
            .max() ?? .operational
        if newStatus != worstStatus {
            worstStatus = newStatus
            onWorstStatusChanged?(newStatus)
        }
    }
}
