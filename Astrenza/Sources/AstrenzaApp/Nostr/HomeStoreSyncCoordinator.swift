import AstrenzaCore

@MainActor
protocol HomeStoreSyncInteracting: AnyObject {
    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>,
        context: HomeTimelineSyncInteractionContext
    )

    func invalidateForwardSubscription(
        _ key: RuntimeSubscriptionKey,
        context: HomeTimelineSyncInteractionContext
    )

    func invalidateForwardSubscriptions(
        relayURL: String,
        context: HomeTimelineSyncInteractionContext
    )

    #if DEBUG
    var activeRequestCount: Int { get }
    var activeContextCount: Int { get }
    var backwardRequestState: HomeTimelineBackwardRequestState { get }

    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    )

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
    #endif
}

extension HomeTimelineSyncInteractionWorkflow: HomeStoreSyncInteracting {}

@MainActor
protocol HomeStoreSyncContextProviding: AnyObject {
    func syncContext() -> HomeTimelineSyncInteractionContext
}

extension HomeStoreContextCoordinator: HomeStoreSyncContextProviding {}

@MainActor
final class HomeStoreSyncCoordinator {
    private let interaction: any HomeStoreSyncInteracting
    private let contexts: any HomeStoreSyncContextProviding

    init(
        interaction: any HomeStoreSyncInteracting,
        contexts: any HomeStoreSyncContextProviding
    ) {
        self.interaction = interaction
        self.contexts = contexts
    }

    static func live(
        components: HomeTimelineStoreComponents,
        contexts: HomeStoreContextCoordinator
    ) -> HomeStoreSyncCoordinator {
        HomeStoreSyncCoordinator(
            interaction: components.syncInteractionWorkflow,
            contexts: contexts
        )
    }

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>
    ) {
        interaction.prepareForwardSubscriptions(
            subscriptions,
            context: contexts.syncContext()
        )
    }

    func invalidateForwardSubscription(_ key: RuntimeSubscriptionKey) {
        interaction.invalidateForwardSubscription(
            key,
            context: contexts.syncContext()
        )
    }

    func invalidateForwardSubscriptions(relayURL: String) {
        interaction.invalidateForwardSubscriptions(
            relayURL: relayURL,
            context: contexts.syncContext()
        )
    }
}

#if DEBUG
extension HomeStoreSyncCoordinator {
    func setRealtimeForTesting(_ isRealtime: Bool) {
        contexts.syncContext().effects.apply(
            .setRealtime(isRealtime)
        )
    }

    func registerOlderFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        anchorEventID: String?
    ) {
        interaction.registerOlderPage(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            anchorEventID: anchorEventID
        )
    }

    func registerForwardFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord
    ) {
        interaction.registerForwardContext(
            HomeFeedRuntimeContext(definition: definition),
            groupID: packet.groupID
        )
    }

    func registerGapFeedRequest(
        packet: NostrREQPacket,
        definition: NostrFeedDefinitionRecord,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        interaction.registerGap(
            groupID: packet.groupID,
            context: HomeFeedRuntimeContext(definition: definition),
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        )
    }

    var backwardRequestCount: Int {
        interaction.backwardRequestState.requestCount
    }

    var activeRequestCount: Int {
        interaction.activeRequestCount
    }

    var activeContextCount: Int {
        interaction.activeContextCount
    }
}
#endif
