import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline relay diagnostics ledger")
struct HomeTimelineRelayDiagnosticsLedgerTests {
    @Test("Runtime diagnostics stay bounded while every event remains durable")
    @MainActor
    func runtimeDiagnosticsAreBoundedAndPersisted() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: eventStore,
            eventLimit: 3
        )

        for index in 0..<5 {
            ledger.record(
                accountID: accountID,
                relayURL: "wss://relay-\(index).example",
                kind: .connected,
                occurredAt: 100 + index,
                subscriptionID: nil,
                message: "connected-\(index)"
            )
        }

        #expect(ledger.events.map(\.relayURL) == [
            "wss://relay-2.example",
            "wss://relay-3.example",
            "wss://relay-4.example"
        ])
        #expect(!ledger.hasRecentEvent(
            relayURL: "wss://relay-1.example",
            kind: .connected,
            message: "connected-1"
        ))
        #expect(ledger.hasRecentEvent(
            relayURL: "wss://relay-4.example",
            kind: .connected,
            message: "connected-4"
        ))

        let persisted = try eventStore.relaySyncEvents(
            accountID: accountID,
            timelineKey: "home",
            relayURL: nil,
            limit: 10
        )
        #expect(persisted.count == 5)
    }

    @Test("Production diagnostics preserve write order through the persistence worker")
    @MainActor
    func productionDiagnosticsPersistOffMainActorInOrder() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let worker = HomeTimelinePersistenceWorker(eventStore: eventStore)
        let accountID = String(repeating: "a", count: 64)
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: eventStore,
            persistenceWorker: worker
        )

        for index in 0..<5 {
            ledger.record(
                accountID: accountID,
                relayURL: "wss://relay.example",
                kind: .eose,
                occurredAt: 100 + index,
                subscriptionID: "astrenza-home-\(index)",
                eventCount: index,
                message: "eose-\(index)"
            )
        }

        await ledger.waitForPendingDiagnosticPersistence()

        let persisted = try eventStore.relaySyncEvents(
            accountID: accountID,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            limit: 10
        )
        #expect(persisted.map(\.message) == [
            "eose-4", "eose-3", "eose-2", "eose-1", "eose-0"
        ])
    }

    @Test("Relay counts combine fresh history with authoritative runtime state")
    @MainActor
    func relayStatusCountsUseRuntimeOverride() {
        let ledger = HomeTimelineRelayDiagnosticsLedger(eventStore: nil)
        ledger.replaceEvents([
            event(relayURL: "wss://history.example", kind: .eose, occurredAt: 100)
        ])
        let relays = [
            "wss://history.example",
            "wss://runtime.example",
            "wss://offline.example"
        ]

        let combined = ledger.statusCounts(
            resolvedRelays: relays,
            runtimeStates: ["wss://runtime.example": .connected],
            now: 200
        )
        #expect(combined.connected == 2)
        #expect(combined.planned == 3)

        let overridden = ledger.statusCounts(
            resolvedRelays: relays,
            runtimeStates: [
                "wss://history.example": .retrying,
                "wss://runtime.example": .connected
            ],
            now: 200
        )
        #expect(overridden.connected == 1)
        #expect(overridden.planned == 3)

        let stale = ledger.statusCounts(
            resolvedRelays: relays,
            runtimeStates: [:],
            now: 400
        )
        #expect(stale.connected == 0)
        #expect(stale.planned == 3)

        let empty = ledger.statusCounts(resolvedRelays: [], runtimeStates: [:], now: 400)
        #expect(empty.connected == 0)
        #expect(empty.planned == 1)
    }

    @Test("Reachability index follows replacements and newly recorded evidence")
    @MainActor
    func reachabilityIndexTracksLedgerMutations() {
        let accountID = String(repeating: "a", count: 64)
        let relayURL = "wss://relay.example"
        let ledger = HomeTimelineRelayDiagnosticsLedger(eventStore: nil)

        ledger.replaceEvents([
            event(relayURL: relayURL, kind: .eose, occurredAt: 100)
        ])
        #expect(ledger.statusCounts(
            resolvedRelays: [relayURL],
            runtimeStates: [:],
            now: 200
        ).connected == 1)

        ledger.replaceEvents([])
        #expect(ledger.statusCounts(
            resolvedRelays: [relayURL],
            runtimeStates: [:],
            now: 200
        ).connected == 0)

        ledger.record(
            accountID: accountID,
            relayURL: relayURL,
            kind: .connected,
            occurredAt: 210,
            subscriptionID: nil,
            message: "connected"
        )
        #expect(ledger.statusCounts(
            resolvedRelays: [relayURL],
            runtimeStates: [:],
            now: 220
        ).connected == 1)
    }

    @Test("Fetched diagnostics retain cursors only for timeline subscriptions")
    @MainActor
    func fetchedDiagnosticsNormalizeCursors() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let worker = HomeTimelinePersistenceWorker(eventStore: eventStore)
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: eventStore,
            persistenceWorker: worker
        )
        let timelineEvent = event(
            relayURL: "wss://timeline.example",
            kind: .eose,
            occurredAt: 100,
            subscriptionID: "astrenza-home-0",
            newestCreatedAt: 90,
            oldestCreatedAt: 10
        )
        let dependencyEvent = event(
            relayURL: "wss://dependency.example",
            kind: .eose,
            occurredAt: 101,
            subscriptionID: "astrenza-profile-0",
            newestCreatedAt: 80,
            oldestCreatedAt: 20
        )

        await ledger.persistFetchedEvents([timelineEvent, dependencyEvent])

        let timelineHistory = try eventStore.relaySyncEvents(
            accountID: timelineEvent.accountID,
            timelineKey: "home",
            relayURL: timelineEvent.relayURL,
            limit: 1
        )
        #expect(timelineHistory.first?.newestCreatedAt == 90)
        #expect(timelineHistory.first?.oldestCreatedAt == 10)

        let dependencyHistory = try eventStore.relaySyncEvents(
            accountID: dependencyEvent.accountID,
            timelineKey: "home",
            relayURL: dependencyEvent.relayURL,
            limit: 1
        )
        #expect(dependencyHistory.first?.newestCreatedAt == nil)
        #expect(dependencyHistory.first?.oldestCreatedAt == nil)
    }

    @Test("Relay traffic flushes at batch and elapsed-time thresholds")
    @MainActor
    func relayTrafficUsesBatchAndTimeThresholds() {
        let writer = RelayTrafficWriterRecorder()
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: nil,
            trafficBatchSize: 3,
            trafficFlushIntervalSeconds: 5,
            relayTrafficWriter: { deltas in
                try writer.write(deltas)
            }
        )

        ledger.recordTraffic(trafficDelta(occurredAt: 100, receivedBytes: 1))
        ledger.recordTraffic(trafficDelta(occurredAt: 102, receivedBytes: 2))
        ledger.recordTraffic(trafficDelta(occurredAt: 103, receivedBytes: 3))
        ledger.recordTraffic(trafficDelta(occurredAt: 104, receivedBytes: 4))
        ledger.recordTraffic(trafficDelta(occurredAt: 108, receivedBytes: 5))
        ledger.recordTraffic(trafficDelta(occurredAt: 109, receivedBytes: 6))

        #expect(writer.attempts.map { $0.map(\.receivedBytes) } == [
            [1],
            [2, 3, 4],
            [5, 6]
        ])
        #expect(ledger.pendingRelayTrafficDeltaCount == 0)
    }

    @Test("A failed relay traffic write restores the batch in original order")
    @MainActor
    func failedRelayTrafficWriteRestoresBatch() {
        let writer = RelayTrafficWriterRecorder(failuresRemaining: 1)
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: nil,
            trafficBatchSize: 2,
            trafficFlushIntervalSeconds: 5,
            relayTrafficWriter: { deltas in
                try writer.write(deltas)
            }
        )

        ledger.recordTraffic(trafficDelta(occurredAt: 100, receivedBytes: 1))
        #expect(ledger.pendingRelayTrafficDeltaCount == 1)

        ledger.recordTraffic(trafficDelta(occurredAt: 101, receivedBytes: 2))

        #expect(writer.attempts.map { $0.map(\.receivedBytes) } == [
            [1],
            [1, 2]
        ])
        #expect(ledger.pendingRelayTrafficDeltaCount == 0)
    }

    @Test("Relay traffic uses the event store as its default writer")
    @MainActor
    func relayTrafficUsesEventStoreWriter() throws {
        let eventStore = try NostrEventStore.inMemory()
        let ledger = HomeTimelineRelayDiagnosticsLedger(eventStore: eventStore)

        ledger.recordTraffic(trafficDelta(occurredAt: 100, receivedBytes: 7))

        let totals = try eventStore.relayTrafficTotals(
            accountID: String(repeating: "a", count: 64),
            start: 0,
            end: 200
        )
        #expect(totals.receivedBytes == 7)
        #expect(totals.receivedMessages == 1)
    }

    @Test("Session shutdown flushes subthreshold relay traffic before reset")
    @MainActor
    func sessionShutdownFlushesPendingTraffic() {
        let writer = RelayTrafficWriterRecorder()
        let ledger = HomeTimelineRelayDiagnosticsLedger(
            eventStore: nil,
            trafficBatchSize: 50,
            trafficFlushIntervalSeconds: 5,
            relayTrafficWriter: { deltas in
                try writer.write(deltas)
            }
        )
        ledger.recordTraffic(trafficDelta(occurredAt: 100, receivedBytes: 1))
        ledger.recordTraffic(trafficDelta(occurredAt: 101, receivedBytes: 2))
        #expect(ledger.pendingRelayTrafficDeltaCount == 1)

        ledger.flushTraffic(now: 102)
        ledger.reset()

        #expect(writer.attempts.map { $0.map(\.receivedBytes) } == [[1], [2]])
        #expect(ledger.pendingRelayTrafficDeltaCount == 0)
    }

    private func event(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        occurredAt: Int,
        subscriptionID: String? = nil,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil
    ) -> NostrRelaySyncEventRecord {
        NostrRelaySyncEventRecord(
            accountID: String(repeating: "a", count: 64),
            timelineKey: "home",
            relayURL: relayURL,
            kind: kind,
            occurredAt: occurredAt,
            subscriptionID: subscriptionID,
            eventCount: 1,
            newestCreatedAt: newestCreatedAt,
            oldestCreatedAt: oldestCreatedAt,
            message: "event"
        )
    }

    private func trafficDelta(
        occurredAt: Int,
        receivedBytes: Int
    ) -> NostrRelayTrafficDelta {
        NostrRelayTrafficDelta(
            accountID: String(repeating: "a", count: 64),
            relayURL: "wss://relay.example",
            occurredAt: occurredAt,
            networkType: .wifi,
            syncMode: .ownRelayList,
            receivedBytes: receivedBytes,
            sentBytes: 0,
            receivedMessages: 1,
            sentMessages: 0
        )
    }
}

@MainActor
private final class RelayTrafficWriterRecorder {
    private(set) var attempts: [[NostrRelayTrafficDelta]] = []
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func write(_ deltas: [NostrRelayTrafficDelta]) throws {
        attempts.append(deltas)
        guard failuresRemaining > 0 else { return }
        failuresRemaining -= 1
        throw RelayTrafficWriterRecorderError.writeFailed
    }
}

private enum RelayTrafficWriterRecorderError: Error {
    case writeFailed
}
