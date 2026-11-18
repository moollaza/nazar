import Foundation

/// Tracks the "Recovered" badge: when each provider came back from an
/// incident, and when the user first saw it. Persisted so it survives a
/// relaunch.
struct RecoveryTracker {
    /// Hard cap for recoveries the user never saw.
    static let recoveryWindow: TimeInterval = 24 * 3600
    /// The badge goes away this long after the user first has the panel open
    /// while it is showing.
    static let recoverySeenWindow: TimeInterval = 5 * 60
    private static let recoveredAtKey = "recoveredAt"
    private static let recoverySeenAtKey = "recoverySeenAt"

    private(set) var recoveredAt: [UUID: Date] = [:]
    private(set) var recoverySeenAt: [UUID: Date] = [:]

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults, now: @escaping () -> Date) {
        self.defaults = defaults
        self.now = now
    }

    /// Loads persisted state for `known` providers and drops entries that
    /// have already expired.
    mutating func load(knownProviders known: Set<UUID>) {
        func read(_ key: String) -> [UUID: Date] {
            let raw = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
            return raw.reduce(into: [:]) { result, pair in
                guard let id = UUID(uuidString: pair.key), known.contains(id) else { return }
                result[id] = Date(timeIntervalSince1970: pair.value)
            }
        }
        let loadedRecovered = read(Self.recoveredAtKey)
        let loadedSeen = read(Self.recoverySeenAtKey)
        recoveredAt = loadedRecovered.filter {
            Self.isShowing(recovered: $0.value, seen: loadedSeen[$0.key], now: now())
        }
        recoverySeenAt = loadedSeen.filter { recoveredAt[$0.key] != nil }
    }

    private func save() {
        func encode(_ dates: [UUID: Date]) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: dates.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) })
        }
        defaults.set(encode(recoveredAt), forKey: Self.recoveredAtKey)
        defaults.set(encode(recoverySeenAt), forKey: Self.recoverySeenAtKey)
    }

    private static func isShowing(recovered: Date, seen: Date?, now: Date) -> Bool {
        guard now.timeIntervalSince(recovered) < recoveryWindow else { return false }
        if let seen, now.timeIntervalSince(seen) >= recoverySeenWindow { return false }
        return true
    }

    /// The time `id` recovered from an incident, while the badge should still
    /// show: until `recoverySeenWindow` after the user first saw it, and never
    /// past `recoveryWindow`.
    func recentRecovery(for id: UUID) -> Date? {
        guard let date = recoveredAt[id],
              Self.isShowing(recovered: date, seen: recoverySeenAt[id], now: now()) else { return nil }
        return date
    }

    /// Called when the panel is on screen. Starts the 5-minute clock for every
    /// recovery that is showing and has not been seen yet.
    mutating func markSeen() {
        var changed = false
        for id in recoveredAt.keys where recoverySeenAt[id] == nil && recentRecovery(for: id) != nil {
            recoverySeenAt[id] = now()
            changed = true
        }
        if changed { save() }
    }

    /// Removes the Recovered badge for `id` right away.
    mutating func clear(for id: UUID) {
        let removed = recoveredAt.removeValue(forKey: id) != nil
        recoverySeenAt.removeValue(forKey: id)
        if removed { save() }
    }

    /// Remembers when a provider returns to operational after a real incident
    /// (not after `.unknown`, which only means we had no data, nor after
    /// maintenance, which is not an incident), and forgets it when a new
    /// incident starts.
    mutating func record(for id: UUID, from previous: ComponentStatus?, to current: ComponentStatus) {
        if current == .operational {
            guard let previous,
                  previous != .operational,
                  previous != .unknown,
                  previous != .underMaintenance else { return }
            recoveredAt[id] = now()
            recoverySeenAt[id] = nil
            save()
        } else if current != .unknown {
            clear(for: id)
        }
    }
}
