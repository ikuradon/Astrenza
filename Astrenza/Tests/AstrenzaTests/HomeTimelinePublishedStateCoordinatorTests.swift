import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline published state coordinator")
@MainActor
struct PublishedStateCoordinatorTests {
    @Test("Content state publishes only when its snapshot changes")
    func contentPublicationIsDeduplicated() {
        let coordinator = HomeTimelinePublishedStateCoordinator(
            syncPolicy: .default(networkType: .unknown)
        )
        let observation = observePublishedState(coordinator.resolvedRelays)
        let changed = HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["follow"],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: false
        )

        coordinator.applyContentSnapshot(.initial)
        coordinator.applyContentSnapshot(changed)
        coordinator.applyContentSnapshot(changed)

        #expect(observation.count == 1)
        #expect(coordinator.content.resolvedRelays == [
            "wss://relay.example"
        ])
        #expect(coordinator.content.followedPubkeys == ["follow"])
        #expect(!coordinator.content.hasMoreOlder)
    }

    @Test("Account context owns its initial policy and atomic transitions")
    func accountContextPreservesPolicy() {
        let initialPolicy = NostrSyncPolicy.default(networkType: .wifi)
        let activePolicy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "published-state",
            readOnly: true
        )
        let coordinator = HomeTimelinePublishedStateCoordinator(
            syncPolicy: initialPolicy
        )

        #expect(coordinator.accountContext.account == nil)
        #expect(coordinator.accountContext.syncPolicy == initialPolicy)

        coordinator.applyAccountContextTransition(.activate(
            account,
            syncPolicy: activePolicy
        ))
        #expect(coordinator.accountContext.account == account)
        #expect(coordinator.accountContext.syncPolicy == activePolicy)

        coordinator.applyAccountContextTransition(.clear)
        #expect(coordinator.accountContext.account == nil)
        #expect(coordinator.accountContext.syncPolicy == activePolicy)
    }

    @Test("Realtime invalidation is independent from relay publication")
    func relayInvalidationSurvivesNoOpPublication() {
        let coordinator = HomeTimelinePublishedStateCoordinator(
            syncPolicy: .default(networkType: .unknown)
        )
        let observation = observePublishedState(
            coordinator.relayStatusRevision
        )
        let snapshot = HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 0,
            plannedRelayCount: 1
        )

        let invalidatedRelay = coordinator.applyRelayStatusTransition(
            HomeTimelineRelayStatusTransition(
                snapshot: snapshot,
                invalidatedRealtimeRelayURL: "wss://relay.example",
                publishesStatusChange: false
            )
        )

        #expect(invalidatedRelay == "wss://relay.example")
        #expect(observation.count == 0)

        let secondInvalidation = coordinator.applyRelayStatusTransition(
            HomeTimelineRelayStatusTransition(
                snapshot: snapshot,
                invalidatedRealtimeRelayURL: nil,
                publishesStatusChange: true
            )
        )

        #expect(secondInvalidation == nil)
        #expect(observation.count == 1)
        #expect(coordinator.relayStatus.revision == 1)
    }

    @Test("Entry observation ignores unrelated published state")
    func entryObservationIsIsolated() {
        let coordinator = HomeTimelinePublishedStateCoordinator(
            syncPolicy: .default(networkType: .unknown)
        )
        let observation = observePublishedState(coordinator.entries)

        coordinator.applyActivityTransition(HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .loaded,
                isRefreshing: false,
                isLoadingOlder: false,
                isRealtime: false
            ),
            changes: [.phase]
        ))
        coordinator.applyPendingEventCountPublication(
            HomeTimelinePendingEventCountPublication(count: 2)
        )

        #expect(observation.count == 0)
    }
}
