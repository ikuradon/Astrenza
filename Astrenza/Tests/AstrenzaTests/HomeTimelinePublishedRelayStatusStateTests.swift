import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline published relay status state")
@MainActor
struct PublishedRelayStatusStateTests {
    @Test("A snapshot atomically replaces runtime states and counts")
    func changedSnapshotApplies() throws {
        let state = HomeTimelinePublishedRelayStatusState(revision: 4)
        let snapshot = relayStatusSnapshot(
            runtimeStates: ["wss://relay.example": .connected],
            connectedRelayCount: 1,
            plannedRelayCount: 2
        )

        let next = try #require(state.applying(snapshot))

        #expect(next.snapshot == snapshot)
        #expect(next.revision == 4)
    }

    @Test("Status publication advances revision even when the snapshot is unchanged")
    func statusPublicationAdvancesRevision() throws {
        let state = HomeTimelinePublishedRelayStatusState(revision: 7)
        let unchanged = relayStatusSnapshot()

        #expect(state.applying(unchanged) == nil)
        let next = try #require(state.applying(
            unchanged,
            publishingStatusChange: true
        ))
        #expect(next.snapshot == unchanged)
        #expect(next.revision == 8)
    }

    @Test("Standalone status publication preserves wrapping revision semantics")
    func standalonePublicationWrapsRevision() {
        let state = HomeTimelinePublishedRelayStatusState(revision: .max)

        let next = state.publishingStatusChange()

        #expect(next.revision == .min)
        #expect(next.snapshot == state.snapshot)
    }

    @Test("A selected relay field notifies its observer once")
    func selectedRelayFieldNotifiesOnce() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        let observation = observePublishedState(store.relayStatusRevision)

        store.testingApplyRelayStatusSnapshot(relayStatusSnapshot())
        #expect(observation.count == 0)

        store.testingApplyRelayStatusTransition(HomeTimelineRelayStatusTransition(
            snapshot: relayStatusSnapshot(
                runtimeStates: ["wss://relay.example": .connected],
                connectedRelayCount: 1,
                plannedRelayCount: 2
            ),
            invalidatedRealtimeRelayURL: nil,
            publishesStatusChange: true
        ))

        #expect(observation.count == 1)
        #expect(store.relayStatusRevision == 1)
        #expect(store.relayRuntimeStates == ["wss://relay.example": .connected])
        #expect(store.relayStatusCounts.connected == 1)
        #expect(store.relayStatusCounts.planned == 2)
    }

    @Test("Realtime invalidation runs even when relay publication state is unchanged")
    func noOpTransitionStillInvalidatesRealtime() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        store.testingSetHomeTimelineRealtime(true)

        store.testingApplyRelayStatusTransition(HomeTimelineRelayStatusTransition(
            snapshot: relayStatusSnapshot(),
            invalidatedRealtimeRelayURL: "wss://relay.example",
            publishesStatusChange: false
        ))

        #expect(!store.isHomeTimelineRealtime)
    }
}

private func relayStatusSnapshot(
    runtimeStates: [String: NostrRelayConnectionState] = [:],
    connectedRelayCount: Int = 0,
    plannedRelayCount: Int = 1
) -> HomeTimelineRelayStatusSnapshot {
    HomeTimelineRelayStatusSnapshot(
        runtimeStates: runtimeStates,
        connectedRelayCount: connectedRelayCount,
        plannedRelayCount: plannedRelayCount
    )
}
