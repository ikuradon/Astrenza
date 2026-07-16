import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class StoreSyncInteractionSpy: HomeStoreSyncInteracting {
    enum Call: Equatable {
        case prepare(Set<RuntimeSubscriptionKey>)
        case invalidate(RuntimeSubscriptionKey)
        case invalidateRelay(String)
        #if DEBUG
        case registerForward(HomeFeedRuntimeContext, groupID: String)
        case registerOlder(
            groupID: String,
            context: HomeFeedRuntimeContext,
            anchorEventID: String?
        )
        case registerGap(
            groupID: String,
            context: HomeFeedRuntimeContext,
            newerEventID: String,
            olderEventID: String,
            direction: TimelineGapFillDirection
        )
        #endif
    }

    #if DEBUG
    let activeRequestCount = 4
    let activeContextCount = 3
    let backwardRequestState = HomeTimelineBackwardRequestState(
        requestCount: 2,
        hasOlderPageRequest: true,
        hasGapWork: true,
        hasRequests: true
    )
    #endif

    private(set) var calls: [Call] = []
    private var nextRealtime = false

    func prepareForwardSubscriptions(
        _ subscriptions: Set<RuntimeSubscriptionKey>,
        context: HomeTimelineSyncInteractionContext
    ) {
        calls.append(.prepare(subscriptions))
        publishRealtime(context: context)
    }

    func invalidateForwardSubscription(
        _ key: RuntimeSubscriptionKey,
        context: HomeTimelineSyncInteractionContext
    ) {
        calls.append(.invalidate(key))
        publishRealtime(context: context)
    }

    func invalidateForwardSubscriptions(
        relayURL: String,
        context: HomeTimelineSyncInteractionContext
    ) {
        calls.append(.invalidateRelay(relayURL))
        publishRealtime(context: context)
    }

    #if DEBUG
    func registerForwardContext(
        _ context: HomeFeedRuntimeContext,
        groupID: String
    ) {
        calls.append(.registerForward(context, groupID: groupID))
    }

    func registerOlderPage(
        groupID: String,
        context: HomeFeedRuntimeContext,
        anchorEventID: String?
    ) {
        calls.append(.registerOlder(
            groupID: groupID,
            context: context,
            anchorEventID: anchorEventID
        ))
    }

    func registerGap(
        groupID: String,
        context: HomeFeedRuntimeContext,
        newerEventID: String,
        olderEventID: String,
        direction: TimelineGapFillDirection
    ) {
        calls.append(.registerGap(
            groupID: groupID,
            context: context,
            newerEventID: newerEventID,
            olderEventID: olderEventID,
            direction: direction
        ))
    }
    #endif

    private func publishRealtime(
        context: HomeTimelineSyncInteractionContext
    ) {
        context.effects.apply(.setRealtime(nextRealtime))
        nextRealtime.toggle()
    }
}

@MainActor
final class StoreSyncContextProviderSpy: HomeStoreSyncContextProviding {
    struct Application: Equatable {
        let contextID: Int
        let action: HomeTimelineSyncStoreAction
    }

    private(set) var contextIDs: [Int] = []
    private(set) var applications: [Application] = []

    func syncContext() -> HomeTimelineSyncInteractionContext {
        let contextID = contextIDs.count + 1
        contextIDs.append(contextID)
        return HomeTimelineSyncInteractionContext(
            effects: HomeTimelineSyncInteractionEffects(
                apply: { [weak self] action in
                    self?.applications.append(Application(
                        contextID: contextID,
                        action: action
                    ))
                }
            )
        )
    }
}

@MainActor
struct StoreSyncCoordinatorFixture {
    let interaction: StoreSyncInteractionSpy
    let contexts: StoreSyncContextProviderSpy
    let coordinator: HomeStoreSyncCoordinator

    init() {
        let interaction = StoreSyncInteractionSpy()
        let contexts = StoreSyncContextProviderSpy()
        self.interaction = interaction
        self.contexts = contexts
        coordinator = HomeStoreSyncCoordinator(
            interaction: interaction,
            contexts: contexts
        )
    }

    let firstKey = RuntimeSubscriptionKey(
        relayURL: "wss://one.example",
        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID
    )

    let secondKey = RuntimeSubscriptionKey(
        relayURL: "wss://two.example",
        subscriptionID: NostrHomeForwardREQBuilder.subscriptionID
    )

    var packet: NostrREQPacket {
        NostrREQPacket(
            strategy: .backward,
            subscriptionID: "sync-coordinator-request",
            groupID: "sync-coordinator-group",
            filters: []
        )
    }

    var definition: NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: "home:sync-coordinator",
            accountID: String(repeating: "a", count: 64),
            kind: "home",
            specificationJSON: Data(
                #"{"authors":["author"],"kinds":[1,6]}"#.utf8
            ),
            specificationHash: "sync-coordinator",
            revision: 3,
            createdAt: 1,
            updatedAt: 2
        )
    }

    var feedContext: HomeFeedRuntimeContext {
        HomeFeedRuntimeContext(definition: definition)
    }
}
