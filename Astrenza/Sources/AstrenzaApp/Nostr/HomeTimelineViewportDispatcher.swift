import AstrenzaCore

struct HomeTimelineViewportApplicationEffects: Sendable {
    typealias Action = @MainActor @Sendable () -> Void
    typealias Account = @MainActor @Sendable (
        _ account: NostrAccount
    ) -> Void
    typealias ProjectionViewportTransition = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias RealtimeFollowPermission = @MainActor @Sendable (
        _ allowsRealtimeFollow: Bool
    ) -> Void
    typealias PresentationTransition = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias PendingEventCountPublication = @MainActor @Sendable (
        _ publication: HomeTimelinePendingEventCountPublication
    ) -> Void
    typealias AccountLifecycle = @MainActor @Sendable (
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void
    typealias PresentationWaiter = @MainActor @Sendable () async -> Bool

    let applyProjectionViewportTransition: ProjectionViewportTransition
    let reloadNewestProjectionWindow: Account
    let materializeEntries: RealtimeFollowPermission
    let waitForPendingPresentation: PresentationWaiter
    let applyRestoreProjectionAnchor: Account
    let applyPresentationTransition: PresentationTransition
    let scheduleReadStateSave: Action
    let applyPendingEventCountPublication: PendingEventCountPublication
    let clearPendingProjectionReload: Action
    let scheduleLinkPreviewResolution: Action
    let refreshLatest: AccountLifecycle
    let loadOlder: AccountLifecycle
}

@MainActor
struct HomeTimelineViewportDispatcher {
    func apply(
        _ application: HomeTimelineViewportApplication,
        effects: HomeTimelineViewportApplicationEffects
    ) {
        switch application {
        case .applyProjectionViewportTransition(let transition):
            effects.applyProjectionViewportTransition(transition)
        case .reloadNewestProjectionWindow(let account):
            effects.reloadNewestProjectionWindow(account)
        case .materializeEntries(let allowsRealtimeFollow):
            effects.materializeEntries(allowsRealtimeFollow)
        case .applyRestoreProjectionAnchor(let account):
            effects.applyRestoreProjectionAnchor(account)
        case .applyPresentationTransition(let transition):
            effects.applyPresentationTransition(transition)
        case .scheduleReadStateSave:
            effects.scheduleReadStateSave()
        case .applyPendingEventCountPublication(let publication):
            effects.applyPendingEventCountPublication(publication)
        case .clearPendingProjectionReload:
            effects.clearPendingProjectionReload()
        case .scheduleLinkPreviewResolution:
            effects.scheduleLinkPreviewResolution()
        }
    }

    func perform(
        _ load: HomeTimelineViewportInteractionLoad,
        effects: HomeTimelineViewportApplicationEffects
    ) async {
        switch load {
        case .refreshLatest(let account, let lifecycle):
            await effects.refreshLatest(account, lifecycle)
        case .loadOlder(let account, let lifecycle):
            await effects.loadOlder(account, lifecycle)
        }
    }
}
