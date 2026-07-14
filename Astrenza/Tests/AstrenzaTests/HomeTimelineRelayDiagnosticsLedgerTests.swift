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
}
