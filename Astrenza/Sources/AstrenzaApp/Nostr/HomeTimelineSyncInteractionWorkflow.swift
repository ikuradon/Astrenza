@MainActor
protocol HomeTimelineFeedSyncTracking: AnyObject {
    var isRealtime: Bool { get }
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

    init(
        feedSync: any HomeTimelineFeedSyncTracking,
        backwardRequests: any HomeTimelineBackwardRequestTracking
    ) {
        self.feedSync = feedSync
        self.backwardRequests = backwardRequests
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
