import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store status coordinator")
@MainActor
struct HomeStoreStatusCoordinatorTests {
    @Test("Activity intents become published transitions")
    func activityIntentsPublishTransitions() {
        let fixture = StoreStatusFixture()
        let explicit = StoreStatusFixture.activityTransition(
            phase: .resolvingRelays,
            isRealtime: false,
            changes: [.phase]
        )
        let intentTransition = StoreStatusFixture.activityTransition(
            phase: .resolvingRelays,
            isRealtime: true,
            changes: [.realtime]
        )
        fixture.activity.intentTransition = intentTransition

        fixture.coordinator.applyActivityTransition(explicit)
        fixture.coordinator.applyActivityIntent(.setRealtime(true))

        #expect(fixture.activity.intents == [.setRealtime(true)])
        #expect(fixture.publisher.events == [
            .activity(explicit),
            .activity(intentTransition)
        ])
        #expect(
            fixture.coordinator.activitySnapshot.phase == .resolvingRelays
        )
        #expect(fixture.coordinator.activitySnapshot.isRealtime)
    }

    @Test("Relay updates preserve invalidation and publication semantics")
    func relayUpdatesPreserveSemantics() {
        let fixture = StoreStatusFixture()
        let direct = HomeTimelineRelayStatusSnapshot(
            runtimeStates: [:],
            connectedRelayCount: 1,
            plannedRelayCount: 2
        )
        let transitioned = HomeTimelineRelayStatusSnapshot(
            runtimeStates: ["wss://one.example": .waitingForRetry],
            connectedRelayCount: 0,
            plannedRelayCount: 2
        )
        let transition = HomeTimelineRelayStatusTransition(
            snapshot: transitioned,
            invalidatedRealtimeRelayURL: "wss://one.example",
            publishesStatusChange: true
        )

        fixture.coordinator.applyRelayStatusSnapshot(direct)
        let invalidated = fixture.coordinator.applyRelayStatusTransition(
            transition
        )
        fixture.coordinator.publishRelayStatusChange()

        #expect(invalidated == "wss://one.example")
        #expect(fixture.publisher.events == [
            .relaySnapshot(direct, publishingStatusChange: false),
            .relayTransition(transition),
            .publishRelayStatusChange
        ])
        #expect(
            fixture.coordinator.relayStatusSnapshot.runtimeStates ==
                transitioned.runtimeStates
        )
        #expect(fixture.coordinator.relayStatusRevision == 2)
    }

    @Test("Relay counts refresh from current resolved relays")
    func relayCountsUseCurrentResolvedRelays() {
        let fixture = StoreStatusFixture()
        fixture.publisher.content = HomeTimelinePublishedContentState(
            resolvedRelays: ["wss://one.example", "wss://two.example"]
        )
        fixture.sync.relaySnapshot = HomeTimelineRelayStatusSnapshot(
            runtimeStates: ["wss://one.example": .connected],
            connectedRelayCount: 1,
            plannedRelayCount: 2
        )

        fixture.coordinator.refreshRelayStatusCounts()

        #expect(fixture.sync.resolvedRelayInputs == [
            ["wss://one.example", "wss://two.example"]
        ])
        #expect(
            fixture.coordinator.relayStatusSnapshot.connectedRelayCount == 1
        )
        #expect(
            fixture.coordinator.relayStatusSnapshot.plannedRelayCount == 2
        )
    }

    @Test("Activity status combines relay backward and dependency state")
    func activityStatusCombinesWorkState() {
        let fixture = StoreStatusFixture()
        let expectedStatus = NostrTimelineActivityStatus(
            title: "Resolving referenced posts",
            detail: "Fetching events referenced by visible posts",
            compactLabel: "Resolving"
        )
        fixture.activity.statusResult = expectedStatus
        fixture.sync.backwardRequestState = HomeTimelineBackwardRequestState(
            requestCount: 2,
            hasOlderPageRequest: true,
            hasGapWork: true,
            hasRequests: true
        )
        fixture.dependencies.dependencyWorkState =
            HomeTimelineDependencyWorkState(
                hasPendingWork: true,
                pendingSourceRequestCount: 3
            )

        let status = fixture.coordinator.activityStatus()

        #expect(status == expectedStatus)
        #expect(fixture.activity.statusContexts == [
            HomeTimelineActivityContext(
                connectedRelayCount: 1,
                plannedRelayCount: 3,
                hasOlderPageRequest: true,
                hasGapWork: true,
                hasBackwardRequests: true,
                hasPendingDependencyWork: true
            )
        ])
    }
}

private enum StoreStatusPublisherEvent: Equatable {
    case activity(HomeTimelineActivityTransition)
    case relaySnapshot(
        HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool
    )
    case relayTransition(HomeTimelineRelayStatusTransition?)
    case publishRelayStatusChange
}

@MainActor
private final class StoreStatusPublisherSpy: HomeStoreStatusPublishing {
    var content: HomeTimelinePublishedContentState
    var activity: HomeTimelinePublishedActivityState
    var relayStatus: HomeTimelinePublishedRelayStatusState
    private(set) var events: [StoreStatusPublisherEvent] = []

    init(
        content: HomeTimelinePublishedContentState,
        activity: HomeTimelinePublishedActivityState,
        relayStatus: HomeTimelinePublishedRelayStatusState
    ) {
        self.content = content
        self.activity = activity
        self.relayStatus = relayStatus
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        events.append(.activity(transition))
        if let next = activity.applying(transition) {
            activity = next
        }
    }

    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool
    ) {
        events.append(.relaySnapshot(
            snapshot,
            publishingStatusChange: publishingStatusChange
        ))
        if let next = relayStatus.applying(
            snapshot,
            publishingStatusChange: publishingStatusChange
        ) {
            relayStatus = next
        }
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> String? {
        events.append(.relayTransition(transition))
        guard let transition else { return nil }
        if let next = relayStatus.applying(
            transition.snapshot,
            publishingStatusChange: transition.publishesStatusChange
        ) {
            relayStatus = next
        }
        return transition.invalidatedRealtimeRelayURL
    }

    func publishRelayStatusChange() {
        events.append(.publishRelayStatusChange)
        relayStatus = relayStatus.publishingStatusChange()
    }
}

@MainActor
private final class StoreActivityInteractionSpy:
    HomeStoreActivityInteracting {
    var intentTransition = StoreStatusFixture.activityTransition(
        phase: .idle,
        isRealtime: false,
        changes: []
    )
    var statusResult: NostrTimelineActivityStatus?
    private(set) var intents: [HomeTimelineActivityIntent] = []
    private(set) var statusContexts: [HomeTimelineActivityContext] = []

    func perform(
        _ intent: HomeTimelineActivityIntent
    ) -> HomeTimelineActivityTransition {
        intents.append(intent)
        return intentTransition
    }

    func status(
        context: HomeTimelineActivityContext
    ) -> NostrTimelineActivityStatus? {
        statusContexts.append(context)
        return statusResult
    }
}

@MainActor
private final class StoreSyncStatusSourceSpy:
    HomeStoreSyncStatusSourcing {
    var backwardRequestState = HomeTimelineBackwardRequestState.idle
    var relaySnapshot = HomeTimelineRelayStatusSnapshot(
        runtimeStates: [:],
        connectedRelayCount: 0,
        plannedRelayCount: 1
    )
    private(set) var resolvedRelayInputs: [[String]] = []

    func relayStatusSnapshot(
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot {
        resolvedRelayInputs.append(resolvedRelays)
        return relaySnapshot
    }
}

@MainActor
private final class StoreDependencyWorkSourceSpy:
    HomeStoreDependencyWorkSourcing {
    var dependencyWorkState = HomeTimelineDependencyWorkState(
        hasPendingWork: false,
        pendingSourceRequestCount: 0
    )
}

@MainActor
private struct StoreStatusFixture {
    let publisher = StoreStatusPublisherSpy(
        content: HomeTimelinePublishedContentState(
            resolvedRelays: ["wss://one.example"]
        ),
        activity: HomeTimelinePublishedActivityState(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: true,
            isRealtime: false
        ),
        relayStatus: HomeTimelinePublishedRelayStatusState(
            runtimeStates: ["wss://one.example": .connected],
            connectedRelayCount: 1,
            plannedRelayCount: 3
        )
    )
    let activity = StoreActivityInteractionSpy()
    let sync = StoreSyncStatusSourceSpy()
    let dependencies = StoreDependencyWorkSourceSpy()
    let coordinator: HomeStoreStatusCoordinator

    init() {
        coordinator = HomeStoreStatusCoordinator(
            publisher: publisher,
            activity: activity,
            sync: sync,
            dependencies: dependencies
        )
    }

    static func activityTransition(
        phase: NostrHomeTimelinePhase,
        isRealtime: Bool,
        changes: HomeTimelineActivityChanges
    ) -> HomeTimelineActivityTransition {
        HomeTimelineActivityTransition(
            snapshot: HomeTimelineActivitySnapshot(
                phase: phase,
                isRefreshing: false,
                isLoadingOlder: true,
                isRealtime: isRealtime
            ),
            changes: changes
        )
    }
}
