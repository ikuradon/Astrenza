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

enum HomeTimelineFeedSyncStoreAction: Equatable, Sendable {
    case setRealtime(Bool)
}

struct HomeFeedSyncInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineFeedSyncStoreAction
    ) -> Void

    let apply: ApplicationEffect
}

struct HomeFeedSyncInteractionContext: Sendable {
    let effects: HomeFeedSyncInteractionEffects
}

@MainActor
final class HomeTimelineFeedSyncInteractionWorkflow {
    private let feedSync: any HomeTimelineFeedSyncTracking

    init(feedSync: any HomeTimelineFeedSyncTracking) {
        self.feedSync = feedSync
    }

    var activeRequestCount: Int {
        feedSync.activeRequestCount
    }

    var activeContextCount: Int {
        feedSync.activeContextCount
    }

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>,
        context: HomeFeedSyncInteractionContext
    ) {
        feedSync.prepareForwardSubscriptions(subscriptions)
        publishRealtime(context: context)
    }

    func invalidateForwardSubscription(
        _ key: RuntimeSubscriptionKey,
        context: HomeFeedSyncInteractionContext
    ) {
        guard HomeTimelineSyncPlanner.isHomeForwardSubscription(
            key.subscriptionID
        ) else { return }
        feedSync.invalidateForwardSubscription(key)
        publishRealtime(context: context)
    }

    func invalidateForwardSubscriptions(
        relayURL: String,
        context: HomeFeedSyncInteractionContext
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

    private func publishRealtime(
        context: HomeFeedSyncInteractionContext
    ) {
        context.effects.apply(.setRealtime(feedSync.isRealtime))
    }
}
