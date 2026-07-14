import AstrenzaCore
import Foundation

@MainActor
final class HomeTimelineRelayDiagnosticsLedger {
    private let eventStore: NostrEventStore?
    private let persistenceWorker: HomeTimelinePersistenceWorker?
    private let eventLimit: Int

    private(set) var events: [NostrRelaySyncEventRecord] = []

    init(
        eventStore: NostrEventStore?,
        persistenceWorker: HomeTimelinePersistenceWorker? = nil,
        eventLimit: Int = 500
    ) {
        self.eventStore = eventStore
        self.persistenceWorker = persistenceWorker
        self.eventLimit = eventLimit
    }

    func reset() {
        events.removeAll(keepingCapacity: true)
    }

    func replaceEvents(_ events: [NostrRelaySyncEventRecord]) {
        self.events = Array(events.suffix(eventLimit))
    }

    @discardableResult
    func record(
        accountID: String,
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        occurredAt: Int,
        subscriptionID: String?,
        eventCount: Int = 0,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil,
        message: String?
    ) -> NostrRelaySyncEventRecord {
        let event = NostrRelaySyncEventRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: relayURL,
            kind: kind,
            occurredAt: occurredAt,
            subscriptionID: subscriptionID,
            eventCount: eventCount,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            latencyMilliseconds: nil,
            message: message
        )
        events.append(event)
        trimEventsIfNeeded()
        try? eventStore?.saveRelaySyncEvents([event])
        return event
    }

    func persistFetchedEvents(_ events: [NostrRelaySyncEventRecord]) async {
        guard !events.isEmpty, let persistenceWorker else { return }
        let normalizedEvents = events.map(Self.normalizeFetchedEvent)
        try? await persistenceWorker.saveRelaySyncEvents(normalizedEvents)
    }

    func hasRecentEvent(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        message: String?,
        searchLimit: Int = 8
    ) -> Bool {
        events.reversed().prefix(searchLimit).contains { event in
            event.relayURL == relayURL && event.kind == kind && event.message == message
        }
    }

    func statusCounts(
        resolvedRelays: [String],
        runtimeStates: [String: NostrRelayConnectionState],
        now: Int = Int(Date().timeIntervalSince1970),
        freshnessWindowSeconds: Int = 180
    ) -> (connected: Int, planned: Int) {
        let planned = resolvedRelays.count
        guard planned > 0 else { return (connected: 0, planned: 1) }

        let recentlyReachableRelayURLs = Set(
            events.lazy
                .filter { event in
                    event.timelineKey == "home" &&
                        Self.isRecentlyReachable(
                            event,
                            now: now,
                            freshnessWindowSeconds: freshnessWindowSeconds
                        )
                }
                .map(\.relayURL)
        )
        let connected = resolvedRelays.count { relayURL in
            if let runtimeState = runtimeStates[relayURL] {
                return runtimeState == .connected
            }
            return recentlyReachableRelayURLs.contains(relayURL)
        }
        return (connected: connected, planned: planned)
    }

    private func trimEventsIfNeeded() {
        guard events.count > eventLimit else { return }
        events.removeFirst(events.count - eventLimit)
    }

    private static func normalizeFetchedEvent(
        _ event: NostrRelaySyncEventRecord
    ) -> NostrRelaySyncEventRecord {
        let updatesTimelineCursor = isTimelineCursorSubscription(event.subscriptionID)
        return NostrRelaySyncEventRecord(
            accountID: event.accountID,
            timelineKey: event.timelineKey,
            relayURL: event.relayURL,
            kind: event.kind,
            occurredAt: event.occurredAt,
            subscriptionID: event.subscriptionID,
            eventCount: event.eventCount,
            newestCreatedAt: updatesTimelineCursor ? event.newestCreatedAt : nil,
            oldestCreatedAt: updatesTimelineCursor ? event.oldestCreatedAt : nil,
            latencyMilliseconds: event.latencyMilliseconds,
            message: event.message
        )
    }

    private static func isTimelineCursorSubscription(_ subscriptionID: String?) -> Bool {
        guard let subscriptionID else { return false }
        return subscriptionID.hasPrefix("astrenza-home") ||
            subscriptionID.hasPrefix("astrenza-neg-gap") ||
            subscriptionID.hasPrefix("astrenza-gap-events")
    }

    private static func isRecentlyReachable(
        _ event: NostrRelaySyncEventRecord,
        now: Int,
        freshnessWindowSeconds: Int
    ) -> Bool {
        guard now - event.occurredAt <= freshnessWindowSeconds else { return false }
        switch event.kind {
        case .connected, .eose, .authRequired, .paymentRequired:
            return true
        case .closed, .reconnect, .timeout, .partialFailure, .rejected, .suspended, .negentropy:
            return false
        }
    }
}
