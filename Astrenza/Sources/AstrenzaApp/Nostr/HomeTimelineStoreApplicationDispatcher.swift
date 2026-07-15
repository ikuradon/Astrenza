import AstrenzaCore

struct HomeTimelineStoreApplicationEffects: Sendable {
    typealias PresentationTransition = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ContentSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshot = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias ListProjectionInvalidation = @MainActor @Sendable (
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) -> Void
    typealias PendingEventCountPublication = @MainActor @Sendable (
        _ publication: HomeTimelinePendingEventCountPublication
    ) -> Void
    typealias ProjectionReload = @MainActor @Sendable (
        _ account: NostrAccount,
        _ anchorEventID: String?
    ) -> Void
    typealias Action = @MainActor @Sendable () -> Void
    typealias MaterializationSchedule = @MainActor @Sendable (
        _ delayNanoseconds: UInt64?,
        _ allowsRealtimeFollow: Bool?
    ) -> Void
    typealias RelayStatusTransition = @MainActor @Sendable (
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> Void
    typealias Realtime = @MainActor @Sendable (_ isRealtime: Bool) -> Void
    typealias BackwardCompletion = @MainActor @Sendable (
        _ completion: NostrBackwardREQCompletion
    ) -> Void
    typealias RuntimeEvent = @MainActor @Sendable (
        _ relayURL: String,
        _ subscriptionID: String,
        _ event: NostrEvent
    ) async -> Void

    let applyPresentationTransition: PresentationTransition
    let applyContentSnapshot: ContentSnapshot
    let applyRelayStatusSnapshot: RelayStatusSnapshot
    let applyListProjectionInvalidation: ListProjectionInvalidation
    let applyPendingEventCountPublication: PendingEventCountPublication
    let reloadProjection: ProjectionReload
    let requestNewestProjectionReload: Action
    let scheduleMaterialization: MaterializationSchedule
    let materializeEntries: Action
    let applyRelayStatusTransition: RelayStatusTransition
    let setRealtime: Realtime
    let handleBackwardCompletion: BackwardCompletion
    let invalidateListEntries: Action
    let scheduleLinkPreviewResolution: Action
    let handleRuntimeEvent: RuntimeEvent
}

@MainActor
struct HomeTimelineStoreApplicationDispatcher {
    func apply(
        _ application: HomeTimelineStateInteractionApplication,
        effects: HomeTimelineStoreApplicationEffects
    ) {
        switch application {
        case .applyPresentationTransition(let transition):
            effects.applyPresentationTransition(transition)
        case .applyContentSnapshot(let snapshot):
            effects.applyContentSnapshot(snapshot)
        case .applyRelayStatusSnapshot(let snapshot):
            effects.applyRelayStatusSnapshot(snapshot)
        case .applyListProjectionInvalidation(let invalidation):
            effects.applyListProjectionInvalidation(invalidation)
        case .applyPendingEventCountPublication(let publication):
            effects.applyPendingEventCountPublication(publication)
        case .reloadProjection(let account, let anchorEventID):
            effects.reloadProjection(account, anchorEventID)
        case .requestNewestProjectionReload:
            effects.requestNewestProjectionReload()
        case .scheduleMaterialization(let delay, let allowsRealtimeFollow):
            effects.scheduleMaterialization(delay, allowsRealtimeFollow)
        case .materializeEntries:
            effects.materializeEntries()
        case .applyRelayStatusTransition(let transition):
            effects.applyRelayStatusTransition(transition)
        }
    }

    func apply(
        _ application: HomeTimelineRuntimeStoreAction,
        effects: HomeTimelineStoreApplicationEffects
    ) {
        switch application {
        case .setRealtime(let isRealtime):
            effects.setRealtime(isRealtime)
        case .applyRelayStatusTransition(let transition):
            effects.applyRelayStatusTransition(transition)
        case .handleBackwardCompletion(let completion):
            effects.handleBackwardCompletion(completion)
        case .invalidateListEntries:
            effects.invalidateListEntries()
        case .scheduleMaterialization:
            effects.scheduleMaterialization(nil, nil)
        case .scheduleLinkPreviewResolution:
            effects.scheduleLinkPreviewResolution()
        }
    }

    func perform(
        _ application: HomeTimelineRuntimeStoreAsyncAction,
        effects: HomeTimelineStoreApplicationEffects
    ) async {
        switch application {
        case .handleEvent(let relayURL, let subscriptionID, let event):
            await effects.handleRuntimeEvent(
                relayURL,
                subscriptionID,
                event
            )
        }
    }
}
