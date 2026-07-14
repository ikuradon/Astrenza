import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline relay status coordinator")
struct HomeTimelineRelayStatusCoordinatorTests {
    @Test("Runtime states classify diagnostics and invalidate realtime outside connected")
    @MainActor
    func runtimeStateTransitionsOwnDiagnosticsAndRealtimeInvalidation() throws {
        let eventStore = try NostrEventStore.inMemory()
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: eventStore),
            now: { 200 }
        )
        let accountID = String(repeating: "a", count: 64)
        let relayURL = "wss://relay.example"
        let resolvedRelays = [relayURL]

        let connecting = try #require(coordinator.handleRuntimeStateChange(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            state: .connecting
        ))
        #expect(connecting.snapshot.runtimeStates == [relayURL: .connecting])
        #expect(connecting.snapshot.connectedRelayCount == 0)
        #expect(connecting.snapshot.plannedRelayCount == 1)
        #expect(connecting.invalidatedRealtimeRelayURL == relayURL)
        #expect(!connecting.publishesStatusChange)
        #expect(coordinator.events.isEmpty)

        let connected = try #require(coordinator.handleRuntimeStateChange(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            state: .connected
        ))
        #expect(connected.snapshot.runtimeStates == [relayURL: .connected])
        #expect(connected.snapshot.connectedRelayCount == 1)
        #expect(connected.invalidatedRealtimeRelayURL == nil)
        #expect(connected.publishesStatusChange)

        let retrying = try #require(coordinator.handleRuntimeStateChange(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            state: .retrying
        ))
        #expect(retrying.snapshot.runtimeStates == [relayURL: .retrying])
        #expect(retrying.snapshot.connectedRelayCount == 0)
        #expect(retrying.invalidatedRealtimeRelayURL == relayURL)
        #expect(retrying.publishesStatusChange)

        let diagnostics = coordinator.events
        #expect(diagnostics.map(\.kind) == [.connected, .reconnect])
        #expect(diagnostics.map(\.message) == ["connected", "retrying"])
        #expect(diagnostics.allSatisfy { $0.occurredAt == 200 })
        let persisted = try eventStore.relaySyncEvents(
            accountID: accountID,
            timelineKey: "home",
            relayURL: relayURL,
            limit: 10
        )
        #expect(persisted.map(\.kind) == [.reconnect, .connected])
    }

    @Test("Unplanned relay state changes are ignored")
    @MainActor
    func ignoresUnplannedRelayStateChanges() {
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: nil),
            now: { 200 }
        )

        let transition = coordinator.handleRuntimeStateChange(
            accountID: String(repeating: "a", count: 64),
            resolvedRelays: ["wss://planned.example"],
            relayURL: "wss://other.example",
            state: .connected
        )

        #expect(transition == nil)
        #expect(coordinator.snapshot(
            resolvedRelays: ["wss://planned.example"]
        ).runtimeStates.isEmpty)
        #expect(coordinator.events.isEmpty)
    }

    @Test("Runtime failure states map to stable diagnostic kinds")
    @MainActor
    func mapsRuntimeFailureStatesToDiagnostics() throws {
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: nil),
            now: { 200 }
        )
        let accountID = String(repeating: "a", count: 64)
        let relayURL = "wss://relay.example"
        let resolvedRelays = [relayURL]

        for state in [
            NostrRelayConnectionState.waitingForRetry,
            .error,
            .rejected,
            .suspended
        ] {
            let transition = try #require(coordinator.handleRuntimeStateChange(
                accountID: accountID,
                resolvedRelays: resolvedRelays,
                relayURL: relayURL,
                state: state
            ))
            #expect(transition.invalidatedRealtimeRelayURL == relayURL)
            #expect(transition.publishesStatusChange)
        }

        #expect(coordinator.events.map(\.kind) == [
            .reconnect,
            .partialFailure,
            .rejected,
            .suspended
        ])
    }

    @Test("NOTICE classification and AUTH deduplication stay inside the coordinator")
    @MainActor
    func classifiesNoticeAndDeduplicatesAuthenticationChallenges() throws {
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: nil),
            now: { 200 }
        )
        let accountID = String(repeating: "a", count: 64)
        let relayURL = "wss://relay.example"
        let resolvedRelays = [relayURL]

        let timeout = try #require(coordinator.handleNotice(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            message: "Idle TIMEOUT"
        ))
        let failure = try #require(coordinator.handleNotice(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            message: "relay maintenance"
        ))
        let authentication = try #require(coordinator.handleAuthenticationChallenge(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            challenge: "challenge"
        ))
        let duplicate = coordinator.handleAuthenticationChallenge(
            accountID: accountID,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            challenge: "challenge"
        )

        #expect(timeout.publishesStatusChange)
        #expect(failure.publishesStatusChange)
        #expect(authentication.publishesStatusChange)
        #expect(duplicate == nil)
        #expect(coordinator.events.map(\.kind) == [
            .timeout,
            .partialFailure,
            .authRequired
        ])
    }

    @Test("Reset clears runtime states and diagnostics as one boundary")
    @MainActor
    func resetClearsRuntimeStateAndDiagnostics() throws {
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: nil),
            now: { 200 }
        )
        let accountID = String(repeating: "a", count: 64)
        let relayURL = "wss://relay.example"
        _ = coordinator.handleRuntimeStateChange(
            accountID: accountID,
            resolvedRelays: [relayURL],
            relayURL: relayURL,
            state: .connected
        )
        #expect(!coordinator.events.isEmpty)

        let snapshot = coordinator.reset(resolvedRelays: [])

        #expect(snapshot.runtimeStates.isEmpty)
        #expect(snapshot.connectedRelayCount == 0)
        #expect(snapshot.plannedRelayCount == 1)
        #expect(coordinator.events.isEmpty)
    }

    @Test("Generic diagnostics update counts from fresh reachable history")
    @MainActor
    func genericDiagnosticsUpdateReachableCounts() {
        let coordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(eventStore: nil),
            now: { 200 }
        )
        let relayURL = "wss://relay.example"

        let transition = coordinator.record(
            accountID: String(repeating: "a", count: 64),
            resolvedRelays: [relayURL],
            relayURL: relayURL,
            kind: .eose,
            subscriptionID: "astrenza-home-forward",
            message: "EOSE received"
        )

        #expect(transition.snapshot.runtimeStates.isEmpty)
        #expect(transition.snapshot.connectedRelayCount == 1)
        #expect(transition.snapshot.plannedRelayCount == 1)
        #expect(transition.invalidatedRealtimeRelayURL == nil)
        #expect(transition.publishesStatusChange)
    }
}
