import Foundation
import Observation
import OSLog
import AppKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "polling")

/// Maximum allowed response size in bytes. Guards against hostile or broken
/// servers that return multi-GB blobs (or gzip bombs) from a status endpoint.
private let maxResponseBytes = 5_000_000

@MainActor
@Observable
class StatusManager {
    var snapshots: [ProviderSnapshot] = []
    var providers: [Provider] = []
    var worstStatus: ComponentStatus = .operational
    var isPolling = false
    /// True while a manual pollAll() cycle is in flight. UI can bind to this
    /// to show/hide a spinner tied to actual completion rather than a timer.
    var isRefreshing = false

    var onWorstStatusChanged: ((ComponentStatus) -> Void)?
    var onPollCycleComplete: (() -> Void)?
    private var timers: [UUID: Timer] = [:]
    private var previousStatuses: [UUID: ComponentStatus] = [:]
    private var failureCounts: [UUID: Int] = [:]
    private var lastFailure: [UUID: Date] = [:]
    /// Timestamps of status transitions per provider. Used to surface a
    /// "Nth change in the last hour" note in notifications when a service
    /// is flapping, since we coalesce notifications to one per provider in
    /// Notification Center.
    private var transitionTimes: [UUID: [Date]] = [:]
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    let session: URLSession
    let notifier: NotificationServicing
    let defaults: UserDefaults
    /// Injectable clock so tests can drive backoff deterministically.
    let now: () -> Date

    nonisolated static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral   // no shared cookies / cache
        config.timeoutIntervalForRequest = 15            // per-chunk timeout
        config.timeoutIntervalForResource = 30           // total-request timeout (was 7 days default)
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCache = nil
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            "User-Agent": "Nazar/\(version) (+https://usenazar.com)"
        ]
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

    init(
        session: URLSession = StatusManager.defaultSession,
        notifier: NotificationServicing = NotificationService.shared,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.notifier = notifier
        self.defaults = defaults
        self.now = now
        loadProviders()
        observeSleepWake()
    }

    // Avoid the back-deployed MainActor deinit path on newer Swift toolchains,
    // which aborts in the macOS XCTest host for this app-lifetime object.
    #if compiler(>=6.2)
    nonisolated deinit {}
    #endif

    /// On sleep: invalidate timers so they don't fire wildly on wake.
    /// On wake: reschedule and pollAll so any transitions we missed while
    /// asleep are observed and notified. Without this, an outage that starts
    /// and ends entirely during sleep goes undetected.
    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPolling else { return }
                logger.info("System sleeping — pausing polls")
                self.timers.values.forEach { $0.invalidate() }
                self.timers.removeAll()
            }
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPolling else { return }
                logger.info("System woke — resuming polls")
                for provider in self.providers where provider.isEnabled {
                    self.schedulePolling(for: provider)
                }
                self.pollAll(force: true)
            }
        }
    }

    // MARK: - Provider Persistence

    func loadProviders() {
        guard let data = defaults.data(forKey: "providers") else {
            providers = []
            return
        }
        do {
            let saved = try JSONDecoder().decode([Provider].self, from: data)
            if !saved.isEmpty {
                providers = saved
                if !defaults.bool(forKey: "hasCompletedOnboarding") {
                    defaults.set(true, forKey: "hasCompletedOnboarding")
                }
            } else {
                providers = []
            }
        } catch {
            // Schema mismatch or corruption — back up the bad blob so it can be
            // recovered manually, then start fresh rather than silently empty.
            let backupKey = "providers_corrupt_\(Int(Date().timeIntervalSince1970))"
            defaults.set(data, forKey: backupKey)
            logger.error("Failed to decode persisted providers (\(error.localizedDescription)). Backed up raw data at \(backupKey).")
            providers = []
        }
    }

    func saveProviders() {
        do {
            let data = try JSONEncoder().encode(providers)
            defaults.set(data, forKey: "providers")
        } catch {
            logger.error("Failed to encode providers for persistence: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func addProvider(_ provider: Provider) -> Bool {
        guard provider.hasValidURL else {
            logger.error("Refused to add provider with invalid URL: \(provider.baseURL)")
            return false
        }
        guard !providers.contains(where: { $0.baseURL == provider.baseURL }) else {
            logger.warning("Refused to add duplicate provider: \(provider.baseURL)")
            return false
        }
        providers.append(provider)
        saveProviders()
        schedulePolling(for: provider)
        Task { await poll(provider: provider) }
        // Mark onboarding complete when first provider is added
        if !defaults.bool(forKey: "hasCompletedOnboarding") {
            defaults.set(true, forKey: "hasCompletedOnboarding")
        }
        logger.info("Added provider: \(provider.name)")
        return true
    }

    func updatePollInterval(for provider: Provider, seconds: Int) {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[idx].pollIntervalSeconds = max(30, seconds)
        saveProviders()
        if isPolling {
            schedulePolling(for: providers[idx])
        }
    }

    func toggleMute(for provider: Provider) {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[idx].isMuted.toggle()
        saveProviders()
        recalcWorstStatus()
    }

    /// Sets the muted state for every provider in `ids` at once. Persists and
    /// recalculates worst status a single time — preferable to looping
    /// `toggleMute` when applying a bulk change from a multi-selection.
    func setMuted(ids: Set<UUID>, isMuted: Bool) {
        guard !ids.isEmpty else { return }
        var changed = false
        for idx in providers.indices where ids.contains(providers[idx].id)
            && providers[idx].isMuted != isMuted {
            providers[idx].isMuted = isMuted
            changed = true
        }
        guard changed else { return }
        saveProviders()
        recalcWorstStatus()
    }

    func removeProvider(_ provider: Provider) {
        removeProviders(ids: [provider.id])
    }

    /// Removes every provider whose id is in `ids`, persisting and recalculating
    /// worst status once at the end. Prefer this over looping `removeProvider`
    /// when deleting multiple services from the UI — it keeps the UserDefaults
    /// write and status recalculation to a single pass.
    func removeProviders(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            timers[id]?.invalidate()
            timers.removeValue(forKey: id)
            previousStatuses.removeValue(forKey: id)
            failureCounts.removeValue(forKey: id)
            lastFailure.removeValue(forKey: id)
            transitionTimes.removeValue(forKey: id)
        }
        providers.removeAll { ids.contains($0.id) }
        snapshots.removeAll { ids.contains($0.id) }
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
        let providerId = provider.id
        timers[providerId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(provider.pollIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Look up the current provider by ID so mute/name/URL edits take effect
                // without waiting for a re-schedule.
                guard let self = self,
                      let current = self.providers.first(where: { $0.id == providerId }) else { return }
                await self.poll(provider: current)
            }
        }
        timers[providerId] = timer
    }

    private let maxConcurrentPolls = 6

    /// Manually refresh every enabled provider. Coalesces concurrent invocations
    /// via `isRefreshing` so rapid Cmd+R / button clicks don't spawn overlapping
    /// task groups. `force: true` bypasses the per-provider backoff window so
    /// a user-initiated refresh always tries, even for recently-failed
    /// providers.
    func pollAll(force: Bool = true) {
        guard !isRefreshing else {
            logger.debug("pollAll dropped: refresh already in flight")
            return
        }
        isRefreshing = true
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
                        await self?.poll(provider: provider, force: force)
                    }
                    running += 1
                }
            }
            isRefreshing = false
            onPollCycleComplete?()
        }
    }

    // Internal (not private) so tests can drive the full pipeline end-to-end
    // against an injected URLSession. Not public; still hidden outside the module.
    func poll(provider: Provider, force: Bool = false) async {
        // Exponential backoff: skip if we failed recently, unless the caller
        // is forcing (user-initiated refresh bypasses backoff).
        // `max(0, ...)` guards against wall-clock rollback (NTP/timezone) that
        // would otherwise leave the gate permanently closed.
        if !force,
           let failures = failureCounts[provider.id], failures > 0,
           let lastFail = lastFailure[provider.id] {
            let backoffSeconds = backoffWindow(for: provider, failures: failures)
            let elapsed = max(0, now().timeIntervalSince(lastFail))
            if elapsed < backoffSeconds {
                return
            }
        }

        guard let url = provider.apiURL else {
            recordFailure(for: provider)
            updateSnapshot(for: provider, error: "Invalid URL — must be https:// with a valid host")
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                recordFailure(for: provider)
                updateSnapshot(for: provider, error: "Non-HTTP response")
                return
            }
            guard (200...299).contains(http.statusCode) else {
                logger.error("Poll HTTP \(http.statusCode) for \(provider.name)")
                recordFailure(for: provider)
                updateSnapshot(for: provider, error: httpErrorMessage(for: http.statusCode))
                return
            }
            guard data.count <= maxResponseBytes else {
                logger.error("Poll response too large for \(provider.name): \(data.count) bytes")
                recordFailure(for: provider)
                updateSnapshot(for: provider, error: "Response too large (\(data.count / 1_000_000) MB)")
                return
            }

            // Success — reset backoff
            failureCounts[provider.id] = 0

            switch provider.type {
            case .statuspage:
                do {
                    try parseStatuspage(data: data, provider: provider)
                } catch let error as DecodingError {
                    logger.error("Statuspage schema mismatch for \(provider.name): \(String(describing: error))")
                    updateSnapshot(for: provider, error: "Status format not recognized")
                }
            case .rss:
                do {
                    try parseRSS(data: data, provider: provider)
                } catch {
                    logger.error("RSS parse failed for \(provider.name): \(error.localizedDescription)")
                    updateSnapshot(for: provider, error: "Could not parse RSS feed")
                }
            }
        } catch let urlError as URLError {
            logger.error("Network error [\(urlError.code.rawValue)] for \(provider.name): \(urlError.localizedDescription)")
            recordFailure(for: provider)
            updateSnapshot(for: provider, error: networkErrorMessage(for: urlError))
        } catch {
            logger.error("Poll failed for \(provider.name): \(error.localizedDescription)")
            recordFailure(for: provider)
            updateSnapshot(for: provider, error: "Unable to read status page")
        }
    }

    private func backoffWindow(for provider: Provider, failures: Int) -> Double {
        let base = min(Double(provider.pollIntervalSeconds) * pow(2, Double(min(failures, 5))), 3600)
        // Jitter in ±50% so many providers failing together don't retry in lockstep.
        return base * Double.random(in: 0.5...1.5)
    }

    private func httpErrorMessage(for code: Int) -> String {
        switch code {
        case 401, 403: return "Access denied (\(code))"
        case 404: return "Status page not found (404) — URL may have changed"
        case 429: return "Rate limited (429)"
        case 500...599: return "Status page unavailable (\(code))"
        case 300...399: return "Unexpected redirect (\(code))"
        default: return "HTTP \(code)"
        }
    }

    private func networkErrorMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No internet connection"
        case .timedOut: return "Request timed out"
        case .cannotFindHost, .dnsLookupFailed: return "Cannot find host"
        case .cannotConnectToHost: return "Cannot connect to host"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "Secure connection failed"
        default: return "Network error"
        }
    }

    private func recordFailure(for provider: Provider) {
        let count = (failureCounts[provider.id] ?? 0) + 1
        failureCounts[provider.id] = count
        lastFailure[provider.id] = now()
        let backoff = min(Double(provider.pollIntervalSeconds) * pow(2, Double(min(count, 5))), 3600)
        logger.warning("Poll failure #\(count) for \(provider.name), backing off \(Int(backoff))s")
    }

    // MARK: - Statuspage JSON Parsing

    private static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }

    private func parseStatuspage(data: Data, provider: Provider) throws {
        let decoder = JSONDecoder()
        let summary = try decoder.decode(StatuspageSummary.self, from: data)

        let indicatorStatus = ComponentStatus(fromIndicator: summary.status.indicator)

        // Build group name lookup for child components (e.g., Asana has US, EU, Japan groups)
        var groupNames: [String: String] = [:]
        for comp in summary.components {
            if comp.group == true {
                groupNames[comp.id] = comp.name
            }
        }

        let components = summary.components
            .filter { $0.group != true }
            .map { comp -> ComponentSnapshot in
                var displayName = comp.name
                if let groupId = comp.groupId, let groupName = groupNames[groupId] {
                    displayName = "\(comp.name) (\(groupName))"
                }
                return ComponentSnapshot(id: comp.id, name: displayName, status: ComponentStatus(fromStatuspage: comp.status))
            }

        // Overall status is the worst of the Atlassian indicator and any
        // component-level status — indicators sometimes lag behind components
        // during rapid incidents.
        let componentMax = components.map(\.status).max() ?? .operational
        let overall = max(indicatorStatus, componentMax)

        // Merge in-progress scheduled maintenances into active incidents so
        // the UI reflects ongoing maintenance windows. Atlassian reports
        // these in `scheduled_maintenances` with `status: "in_progress"`,
        // not in `incidents`.
        let inProgressMaint = (summary.scheduledMaintenances ?? []).filter { $0.status == "in_progress" }
        let combinedIncidents = ((summary.incidents ?? []) + inProgressMaint).prefix(5)

        let incidents = combinedIncidents.map { incident -> IncidentSnapshot in
            let updates = (incident.incidentUpdates ?? []).map { update in
                IncidentUpdateSnapshot(
                    id: update.id,
                    status: update.status,
                    body: update.body ?? "",
                    createdAt: update.createdAt.flatMap(Self.parseDate)
                )
            }
            return IncidentSnapshot(
                id: incident.id,
                name: incident.name,
                impact: ComponentStatus(fromIndicator: incident.impact),
                status: incident.status,
                latestUpdate: incident.incidentUpdates?.first?.body,
                updatedAt: Self.parseDate(incident.updatedAt),
                updates: updates
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

    nonisolated static func rssStatusHeuristic(title: String, description: String) -> ComponentStatus {
        let text = (title + " " + description).lowercased()

        // 1. Resolved family beats everything else. "Resolved: Major outage"
        //    describes a healed incident, not an active one.
        if text.contains("resolved") || text.contains("completed") || text.contains("closed") {
            return .operational
        }

        // 2. Explicit severity words from generic status-page phrasing.
        if text.contains("major") || text.contains("outage") || text.contains("critical") {
            return .majorOutage
        }

        // 3. AWS-style phrasing: titles prefixed with "Service impact:" or
        //    "Service disruption:" are how AWS signals a real regional event.
        //    Treat them as partial outages so the menu bar icon reflects the
        //    severity rather than collapsing to .unknown.
        if text.contains("service impact") ||
           text.contains("service disruption") ||
           text.contains("service issue") {
            return .partialOutage
        }

        // 4. Explicit partial signal.
        if text.contains("partial") { return .partialOutage }

        // 5. Degraded-performance signals — includes the Atlassian lifecycle
        //    verbs (investigating, identified, monitoring) that indicate an
        //    incident is still open, plus GCP/AWS phrasing about error rates.
        if text.contains("degraded") ||
           text.contains("elevated") ||
           text.contains("increased error") ||
           text.contains("investigating") ||
           text.contains("identified") ||
           text.contains("experiencing") {
            return .degradedPerformance
        }

        // 6. Explicit operational signal (rare in feeds but seen in digest-style
        //    "All systems operational" entries).
        if text.contains("operational") { return .operational }

        return .unknown
    }

    private func parseRSS(data: Data, provider: Provider) throws {
        let parser = RSSStatusParser(data: data)
        let items = try parser.parse()

        // Heuristic: check titles/descriptions for outage keywords.
        // Empty feed → operational (no recent items on a status-page feed
        // typically means no incidents).
        let overall: ComponentStatus = items.first.map { item in
            Self.rssStatusHeuristic(title: item.title, description: item.description)
        } ?? .operational

        let incidents = items.prefix(5).map { item -> IncidentSnapshot in
            let itemStatus = Self.rssStatusHeuristic(title: item.title, description: item.description)
            return IncidentSnapshot(
                id: item.guid ?? item.title,
                name: item.title,
                impact: itemStatus,
                status: itemStatus.label,
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
        // Guard against races: the provider may have been removed while this
        // poll was in flight, and its mute state may have been toggled.
        guard let current = providers.first(where: { $0.id == provider.id }) else { return }

        let previousStatus = previousStatuses[provider.id]

        if let idx = snapshots.firstIndex(where: { $0.id == provider.id }) {
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }

        // Notify on status change (not on first poll, skip if muted).
        // Read mute from the current provider, not the captured one.
        if !current.isMuted, let prev = previousStatus, prev != snapshot.overallStatus {
            let changeCount = recordTransition(for: provider.id)
            notifier.notify(
                providerId: current.id,
                provider: current.name,
                from: prev,
                to: snapshot.overallStatus,
                incident: snapshot.activeIncidents.first?.name,
                recentChangeCount: changeCount
            )
        }

        previousStatuses[provider.id] = snapshot.overallStatus
        recalcWorstStatus()
        onPollCycleComplete?()
    }

    /// Appends a transition timestamp for `id`, drops entries older than 1
    /// hour, and returns the count within that window. Caller uses this to
    /// annotate the notification body so flap frequency is visible to the
    /// user even though Notification Center coalesces on identifier.
    private func recordTransition(for id: UUID) -> Int {
        let cutoff = now().addingTimeInterval(-3600)
        var times = (transitionTimes[id] ?? []).filter { $0 >= cutoff }
        times.append(now())
        transitionTimes[id] = times
        return times.count
    }

    /// Marks a provider's snapshot as errored while preserving the last-good
    /// status/components/incidents. This way a transient parse or network
    /// failure mid-incident doesn't wipe user-visible state back to green.
    private func updateSnapshot(for provider: Provider, error: String) {
        guard providers.contains(where: { $0.id == provider.id }) else { return }

        let snapshot: ProviderSnapshot
        if let idx = snapshots.firstIndex(where: { $0.id == provider.id }) {
            let prior = snapshots[idx]
            snapshot = ProviderSnapshot(
                id: prior.id,
                name: provider.name,
                overallStatus: prior.error == nil ? prior.overallStatus : .unknown,
                components: prior.error == nil ? prior.components : [],
                activeIncidents: prior.error == nil ? prior.activeIncidents : [],
                lastUpdated: prior.lastUpdated, // keep last-known-good time
                error: error
            )
            snapshots[idx] = snapshot
        } else {
            snapshot = ProviderSnapshot(
                id: provider.id,
                name: provider.name,
                overallStatus: .unknown,
                components: [],
                activeIncidents: [],
                lastUpdated: Date(),
                error: error
            )
            snapshots.append(snapshot)
        }
        recalcWorstStatus()
        onPollCycleComplete?()
    }

    func recalcWorstStatus() {
        let mutedIds = Set(providers.filter(\.isMuted).map(\.id))
        // Include errored snapshots: they carry the last-good overallStatus,
        // and `.unknown` (no prior data) has severity 1 so it surfaces above
        // "operational" but is overridden by any real degraded/outage state.
        let newStatus = snapshots
            .filter { !mutedIds.contains($0.id) }
            .map(\.overallStatus)
            .max() ?? .operational
        if newStatus != worstStatus {
            worstStatus = newStatus
            onWorstStatusChanged?(newStatus)
        }
    }

    /// Count of providers whose most recent poll failed.
    var unreachableCount: Int {
        snapshots.filter { $0.error != nil }.count
    }
}
