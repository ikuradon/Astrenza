import AstrenzaCore

@MainActor
protocol HomeTimelinePresentationCoordinating: AnyObject {
    typealias MaterializeHandler = @MainActor @Sendable (
        _ allowsRealtimeFollow: Bool
    ) -> Void

    func setScrollActive(
        _ isActive: Bool,
        materialize: @escaping MaterializeHandler
    )

    func dismissUnreadBadge() -> HomeTimelinePresentationTransition

    func markVisiblePostsRead(
        _ visiblePostIDs: [TimelinePost.ID]
    ) -> HomeTimelinePresentationTransition?

    func markNewestWindowRead() -> HomeTimelinePresentationTransition?
}

extension HomeTimelinePresentationCoordinator: HomeTimelinePresentationCoordinating {}

struct HomeTimelinePresentationAppState: Sendable {
    let account: NostrAccount?
    let restoreProjectionAnchorEventID: String?
    let homeFeedID: String?
}

struct HomeTimelinePresentationEffects: Sendable {
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias ProjectionViewportTransitionEffect = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias MaterializeEffect = @MainActor @Sendable (
        _ allowsRealtimeFollow: Bool
    ) -> Void
    typealias TransitionEffect = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ViewportEffect = @MainActor @Sendable (
        _ state: TimelineViewportState,
        _ feedID: String,
        _ scopeID: String
    ) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void

    let applyProjectionViewportTransition: ProjectionViewportTransitionEffect
    let reloadNewestProjectionWindow: AccountEffect
    let materializeEntries: MaterializeEffect
    let applyRestoreProjectionAnchor: AccountEffect
    let scheduleViewportState: ViewportEffect
    let applyPresentationTransition: TransitionEffect
    let scheduleReadStateSave: VoidEffect
}

@MainActor
final class HomeTimelinePresentationWorkflow {
    private let coordinator: any HomeTimelinePresentationCoordinating

    init(coordinator: any HomeTimelinePresentationCoordinating) {
        self.coordinator = coordinator
    }

    func setRestoreProjectionAnchor(
        _ anchorEventID: String?,
        state: HomeTimelinePresentationAppState,
        effects: HomeTimelinePresentationEffects
    ) {
        effects.applyProjectionViewportTransition(.setRestoreAnchor(anchorEventID))
        guard let account = state.account else { return }
        if anchorEventID == nil {
            effects.reloadNewestProjectionWindow(account)
            effects.materializeEntries(false)
        } else {
            effects.applyRestoreProjectionAnchor(account)
        }
    }

    func saveViewportState(
        _ viewport: TimelineViewportState,
        state: HomeTimelinePresentationAppState,
        effects: HomeTimelinePresentationEffects
    ) {
        guard viewport.timelineKey == "home",
              let account = state.account,
              account.pubkey == viewport.accountID,
              let feedID = state.homeFeedID
        else { return }
        effects.scheduleViewportState(viewport, feedID, account.pubkey)
    }

    func setTimelineAtNewestWindow(
        _ isAtNewestWindow: Bool,
        state: HomeTimelinePresentationAppState,
        effects: HomeTimelinePresentationEffects
    ) {
        guard !isAtNewestWindow || state.restoreProjectionAnchorEventID == nil else { return }
        effects.applyProjectionViewportTransition(.setNewestWindow(
            isAtNewestWindow
        ))
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        effects: HomeTimelinePresentationEffects
    ) {
        coordinator.setScrollActive(isActive) { allowsRealtimeFollow in
            effects.materializeEntries(allowsRealtimeFollow)
        }
    }

    func dismissUnreadBadge(effects: HomeTimelinePresentationEffects) {
        effects.applyPresentationTransition(
            coordinator.dismissUnreadBadge()
        )
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        effects: HomeTimelinePresentationEffects
    ) {
        guard let transition = coordinator.markVisiblePostsRead(
            visiblePostIDs
        ) else { return }
        applyReadTransition(transition, effects: effects)
    }

    func markNewestMaterializedWindowRead(
        effects: HomeTimelinePresentationEffects
    ) {
        guard let transition = coordinator.markNewestWindowRead() else { return }
        applyReadTransition(transition, effects: effects)
    }

    private func applyReadTransition(
        _ transition: HomeTimelinePresentationTransition,
        effects: HomeTimelinePresentationEffects
    ) {
        effects.applyPresentationTransition(transition)
        effects.scheduleReadStateSave()
    }
}
