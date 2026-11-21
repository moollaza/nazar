import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "history")

/// Incident history per provider, kept in memory only. Statuspage and
/// incident.io history comes from `/api/v2/incidents.json`, fetched at most
/// once an hour; Datadog history arrives with every poll of `config.json`.
@Observable
@MainActor
final class HistoryStore {
    static let refreshInterval: TimeInterval = 3600
    static let maxResponseBytes = 5_000_000

    private(set) var intervals: [UUID: [IncidentInterval]] = [:]
    private var attemptedAt: [UUID: Date] = [:]
    /// The provider type each entry was built for, so a type change
    /// drops history that no longer applies.
    private var builtFor: [UUID: ProviderType] = [:]

    func history(for id: UUID, now: Date) -> ServiceHistory? {
        intervals[id].map { ServiceHistory(intervals: $0, now: now) }
    }

    func record(_ newIntervals: [IncidentInterval], for provider: Provider) {
        sync(provider)
        intervals[provider.id] = newIntervals
    }

    func remove(_ id: UUID) {
        intervals.removeValue(forKey: id)
        attemptedAt.removeValue(forKey: id)
        builtFor.removeValue(forKey: id)
    }

    /// Starts a fetch of the provider's history feed when an hour has passed
    /// since the last attempt. The fetch runs on its own so a status poll
    /// never waits for it. A failed fetch keeps the last good intervals.
    /// `isCurrent` re-checks after the fetch that the provider still exists
    /// with the same type, so a late result can't land on a stale entry.
    @discardableResult
    func refreshIfNeeded(
        provider: Provider,
        session: URLSession,
        now: Date,
        isCurrent: @escaping @MainActor (Provider) -> Bool
    ) -> Task<Void, Never>? {
        sync(provider)
        guard let url = provider.historyURL else { return nil }
        if let last = attemptedAt[provider.id], now.timeIntervalSince(last) < Self.refreshInterval { return nil }
        attemptedAt[provider.id] = now
        return Task { [weak self] in
            let fetched = await Self.fetch(url: url, session: session, name: provider.name)
            guard let self, let fetched, isCurrent(provider) else { return }
            self.intervals[provider.id] = fetched
        }
    }

    /// Drops a provider's history when its type changed since it was built.
    func sync(_ provider: Provider) {
        if let previous = builtFor[provider.id], previous != provider.type {
            remove(provider.id)
        }
        builtFor[provider.id] = provider.type
    }

    private nonisolated static func fetch(url: URL, session: URLSession, name: String) async -> [IncidentInterval]? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("History fetch for \(name) returned HTTP \(code)")
                return nil
            }
            guard data.count <= maxResponseBytes else {
                logger.warning("History response too large for \(name): \(data.count) bytes")
                return nil
            }
            let list = try JSONDecoder().decode(StatuspageIncidentList.self, from: data)
            return list.incidents.compactMap(IncidentInterval.init(statuspage:))
        } catch {
            logger.warning("History fetch failed for \(name): \(error.localizedDescription)")
            return nil
        }
    }
}
