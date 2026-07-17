import AstrenzaCore

@MainActor
protocol HomeTimelineFeedSyncTracking: AnyObject {
    var isRealtime: Bool { get }
    var initialSyncState: HomeTimelineInitialSyncState { get }
    var initialSyncProgress: HomeTimelineInitialSyncProgress { get }
    var activeRequestCount: Int { get }
    var activeContextCount: Int { get }

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>
    )

    func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey)

    func invalidateForwardSubscriptions(relayURL: String)

    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    )
}

extension HomeTimelineFeedSyncCoordinator: HomeTimelineFeedSyncTracking {}

@MainActor
protocol HomeTimelineBackwardRequestTracking: AnyObject {
    var requestState: HomeTimelineBackwardRequestState { get }

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    )

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    )
}

extension HomeTimelineBackwardRequestRegistry:
    HomeTimelineBackwardRequestTracking {}

@MainActor
protocol HomeTimelineRelayStatusTracking: HomeTimelineRelayStatusRecording {
    var events: [NostrRelaySyncEventRecord] { get }

    func snapshot(
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot
}

extension HomeTimelineRelayStatusCoordinator: HomeTimelineRelayStatusTracking {
    func record(
        _ record: HomeTimelineRelayStatusRecord
    ) -> HomeTimelineRelayStatusTransition {
        self.record(
            accountID: record.accountID,
            resolvedRelays: record.resolvedRelays,
            relayURL: record.relayURL,
            kind: record.kind,
            subscriptionID: record.subscriptionID,
            eventCount: record.eventCount,
            newestCreatedAt: record.newestCreatedAt,
            oldestCreatedAt: record.oldestCreatedAt,
            message: record.message
        )
    }
}

enum HomeTimelineSyncStoreAction: Equatable, Sendable {
    case setRealtime(Bool)
}

struct HomeTimelineSyncInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineSyncStoreAction
    ) -> Void

    let apply: ApplicationEffect
}

struct HomeTimelineSyncInteractionContext: Sendable {
    let effects: HomeTimelineSyncInteractionEffects
}

@MainActor
final class HomeTimelineSyncInteractionWorkflow {
    private let feedSync: any HomeTimelineFeedSyncTracking
    private let backwardRequests: any HomeTimelineBackwardRequestTracking
    private let relayStatus: any HomeTimelineRelayStatusTracking

    init(
        feedSync: any HomeTimelineFeedSyncTracking,
        backwardRequests: any HomeTimelineBackwardRequestTracking,
        relayStatus: any HomeTimelineRelayStatusTracking
    ) {
        self.feedSync = feedSync
        self.backwardRequests = backwardRequests
        self.relayStatus = relayStatus
    }

    var activeRequestCount: Int {
        feedSync.activeRequestCount
    }

    var activeContextCount: Int {
        feedSync.activeContextCount
    }

    var backwardRequestState: HomeTimelineBackwardRequestState {
        backwardRequests.requestState
    }

    var initialSyncState: HomeTimelineInitialSyncState {
        feedSync.initialSyncState
    }

    var initialSyncProgress: HomeTimelineInitialSyncProgress {
        feedSync.initialSyncProgress
    }

    var relaySyncEvents: [NostrRelaySyncEventRecord] {
        relayStatus.events
    }

    func relayStatusSnapshot(
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot {
        relayStatus.snapshot(resolvedRelays: resolvedRelays)
    }

    func recordRelayStatus(
        _ record: HomeTimelineRelayStatusRecord
    ) -> HomeTimelineRelayStatusTransition {
        relayStatus.record(record)
    }

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>,
        context: HomeTimelineSyncInteractionContext
    ) {
        feedSync.prepareForwardSubscriptions(subscriptions)
        publishRealtime(context: context)
    }

    func invalidateForwardSubscription(
        _ key: RuntimeSubscriptionKey,
        context: HomeTimelineSyncInteractionContext
    ) {
        guard HomeTimelineSyncPlanner.isHomeForwardSubscription(
            key.subscriptionID
        ) else { return }
        feedSync.invalidateForwardSubscription(key)
        publishRealtime(context: context)
    }

    func invalidateForwardSubscriptions(
        relayURL: String,
        context: HomeTimelineSyncInteractionContext
    ) {
        feedSync.invalidateForwardSubscriptions(relayURL: relayURL)
        publishRealtime(context: context)
    }

    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    ) {
        feedSync.registerForwardContext(context, groupID: groupID)
    }

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    ) {
        backwardRequests.registerOlderPage(
            groupID: groupID,
            context: context,
            anchorEventID: anchorEventID
        )
    }

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        backwardRequests.registerGap(
            groupID: groupID,
            context: context,
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        )
    }

    private func publishRealtime(
        context: HomeTimelineSyncInteractionContext
    ) {
        context.effects.apply(.setRealtime(feedSync.isRealtime))
    }
}
