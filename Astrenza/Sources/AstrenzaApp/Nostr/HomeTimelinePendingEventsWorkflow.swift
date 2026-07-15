import AstrenzaCore

struct HomeTimelinePendingEventsState: Equatable, Sendable {
    let account: NostrAccount?
    let hasBufferedEvents: Bool
    let hasPendingProjectionReload: Bool
}

struct HomeTimelinePendingEventsEffects: Sendable {
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias ProjectionViewportTransitionEffect = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void

    let applyProjectionViewportTransition: ProjectionViewportTransitionEffect
    let reloadNewestProjection: AccountEffect
    let clearBufferedEvents: VoidEffect
    let clearPendingProjectionReload: VoidEffect
    let materializeEntries: VoidEffect
    let scheduleLinkPreviewResolution: VoidEffect
}

@MainActor
final class HomeTimelinePendingEventsWorkflow {
    @discardableResult
    func apply(
        _ state: HomeTimelinePendingEventsState,
        effects: HomeTimelinePendingEventsEffects
    ) -> Bool {
        guard let account = state.account else { return false }
        let hadPendingEvents = state.hasBufferedEvents ||
            state.hasPendingProjectionReload

        effects.applyProjectionViewportTransition(.resetToNewest)
        effects.reloadNewestProjection(account)
        effects.clearBufferedEvents()
        effects.clearPendingProjectionReload()
        effects.materializeEntries()
        effects.scheduleLinkPreviewResolution()
        return hadPendingEvents
    }
}
