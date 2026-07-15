import AstrenzaCore

struct HomeTimelinePendingEventsState: Equatable, Sendable {
    let account: NostrAccount?
    let hasPendingProjectionReload: Bool
}

struct HomeTimelinePendingEventsEffects: Sendable {
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias ProjectionViewportTransitionEffect = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias PendingEventCountEffect = @MainActor @Sendable (
        _ publication: HomeTimelinePendingEventCountPublication
    ) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void

    let applyProjectionViewportTransition: ProjectionViewportTransitionEffect
    let reloadNewestProjection: AccountEffect
    let applyPendingEventCountPublication: PendingEventCountEffect
    let clearPendingProjectionReload: VoidEffect
    let materializeEntries: VoidEffect
    let scheduleLinkPreviewResolution: VoidEffect
}

@MainActor
final class HomeTimelinePendingEventsWorkflow {
    private let buffer: HomeTimelinePendingEventBuffer

    init(buffer: HomeTimelinePendingEventBuffer) {
        self.buffer = buffer
    }

    var hasBufferedEvents: Bool {
        buffer.hasEvents
    }

    @discardableResult
    func apply(
        _ state: HomeTimelinePendingEventsState,
        effects: HomeTimelinePendingEventsEffects
    ) -> Bool {
        guard let account = state.account else { return false }
        let hadPendingEvents = buffer.hasEvents ||
            state.hasPendingProjectionReload

        effects.applyProjectionViewportTransition(.resetToNewest)
        effects.reloadNewestProjection(account)
        clear(effects: effects)
        effects.clearPendingProjectionReload()
        effects.materializeEntries()
        effects.scheduleLinkPreviewResolution()
        return hadPendingEvents
    }

    @discardableResult
    func clear(effects: HomeTimelinePendingEventsEffects) -> Bool {
        buffer.removeAll(
            onCountPublication: effects.applyPendingEventCountPublication
        )
    }

    #if DEBUG
    func replaceEventIDs(
        _ eventIDs: Set<String>,
        effects: HomeTimelinePendingEventsEffects
    ) {
        buffer.replaceEventIDs(
            eventIDs,
            onCountPublication: effects.applyPendingEventCountPublication
        )
    }
    #endif
}
