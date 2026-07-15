import AstrenzaCore
@testable import Astrenza

enum SyncInteractionRelayStatusEvent: Equatable {
    case readEvents
    case snapshot(resolvedRelays: [String])
    case record(HomeTimelineRelayStatusRecord)
}

@MainActor
final class SyncInteractionRelayStatusSpy: HomeTimelineRelayStatusTracking {
    private let syncEvents: [NostrRelaySyncEventRecord]
    private let currentSnapshot: HomeTimelineRelayStatusSnapshot
    private let transition: HomeTimelineRelayStatusTransition
    private(set) var interactions: [SyncInteractionRelayStatusEvent] = []

    init(
        syncEvents: [NostrRelaySyncEventRecord] = [],
        snapshot: HomeTimelineRelayStatusSnapshot =
            HomeTimelineRelayStatusSnapshot(
                runtimeStates: [:],
                connectedRelayCount: 0,
                plannedRelayCount: 0
            ),
        transition: HomeTimelineRelayStatusTransition =
            HomeTimelineRelayStatusTransition(
                snapshot: HomeTimelineRelayStatusSnapshot(
                    runtimeStates: [:],
                    connectedRelayCount: 0,
                    plannedRelayCount: 0
                ),
                invalidatedRealtimeRelayURL: nil,
                publishesStatusChange: false
            )
    ) {
        self.syncEvents = syncEvents
        self.currentSnapshot = snapshot
        self.transition = transition
    }

    var events: [NostrRelaySyncEventRecord] {
        interactions.append(.readEvents)
        return syncEvents
    }

    func snapshot(
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot {
        interactions.append(.snapshot(resolvedRelays: resolvedRelays))
        return currentSnapshot
    }

    func record(
        _ record: HomeTimelineRelayStatusRecord
    ) -> HomeTimelineRelayStatusTransition {
        interactions.append(.record(record))
        return transition
    }
}

@MainActor
final class RelayStatusFeedSyncStub: HomeTimelineFeedSyncTracking {
    let isRealtime = false
    let activeRequestCount = 0
    let activeContextCount = 0

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>
    ) {}

    func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey) {}

    func invalidateForwardSubscriptions(relayURL: String) {}

    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    ) {}
}

@MainActor
final class RelayStatusBackwardRequestStub: HomeTimelineBackwardRequestTracking {
    let requestState = HomeTimelineBackwardRequestState.idle

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    ) {}

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {}
}

@MainActor
struct SyncRelayStatusFixture {
    let relayURL: String
    let syncEvent: NostrRelaySyncEventRecord
    let snapshot: HomeTimelineRelayStatusSnapshot
    let expectedTransition: HomeTimelineRelayStatusTransition
    let relayStatus: SyncInteractionRelayStatusSpy
    let workflow: HomeTimelineSyncInteractionWorkflow
    let record: HomeTimelineRelayStatusRecord

    init() {
        let relayURL = "wss://relay.example"
        let syncEvent = NostrRelaySyncEventRecord(
            accountID: "account",
            timelineKey: "home",
            relayURL: relayURL,
            kind: .eose,
            occurredAt: 100,
            subscriptionID: "home-forward",
            eventCount: 4,
            message: "EOSE"
        )
        let snapshot = HomeTimelineRelayStatusSnapshot(
            runtimeStates: [relayURL: .connected],
            connectedRelayCount: 1,
            plannedRelayCount: 1
        )
        let expectedTransition = HomeTimelineRelayStatusTransition(
            snapshot: snapshot,
            invalidatedRealtimeRelayURL: nil,
            publishesStatusChange: true
        )
        let relayStatus = SyncInteractionRelayStatusSpy(
            syncEvents: [syncEvent],
            snapshot: snapshot,
            transition: expectedTransition
        )
        self.relayURL = relayURL
        self.syncEvent = syncEvent
        self.snapshot = snapshot
        self.expectedTransition = expectedTransition
        self.relayStatus = relayStatus
        self.workflow = HomeTimelineSyncInteractionWorkflow(
            feedSync: RelayStatusFeedSyncStub(),
            backwardRequests: RelayStatusBackwardRequestStub(),
            relayStatus: relayStatus
        )
        self.record = HomeTimelineRelayStatusRecord(
            accountID: "account",
            resolvedRelays: [relayURL],
            relayURL: relayURL,
            kind: .partialFailure,
            subscriptionID: "home-forward",
            eventCount: 2,
            newestCreatedAt: 80,
            oldestCreatedAt: 40,
            message: "partial"
        )
    }
}
