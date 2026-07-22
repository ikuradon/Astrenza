import AstrenzaCore

struct HomeTimelinePendingEventsState: Equatable, Sendable {
    let account: NostrAccount?
    let hasPendingProjectionReload: Bool
    let presentationAnchorEventID: String?

    init(
        account: NostrAccount?,
        hasPendingProjectionReload: Bool,
        presentationAnchorEventID: String? = nil
    ) {
        self.account = account
        self.hasPendingProjectionReload = hasPendingProjectionReload
        self.presentationAnchorEventID = presentationAnchorEventID
    }
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
    typealias PresentationWaiter = @MainActor @Sendable () async -> Bool

    let applyProjectionViewportTransition: ProjectionViewportTransitionEffect
    let reloadNewestProjection: AccountEffect
    let applyPendingEventCountPublication: PendingEventCountEffect
    let clearPendingProjectionReload: VoidEffect
    let materializeEntries: VoidEffect
    let waitForPendingPresentation: PresentationWaiter
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
    ) async -> Bool {
        guard let account = state.account else { return false }
        let hadPendingEvents = buffer.hasEvents ||
            state.hasPendingProjectionReload

        if let anchorEventID = state.presentationAnchorEventID {
            effects.applyProjectionViewportTransition(
                .setRestoreAnchor(anchorEventID)
            )
        }
        effects.reloadNewestProjection(account)
        if state.presentationAnchorEventID != nil {
            effects.applyProjectionViewportTransition(
                .setRestoreAnchor(nil)
            )
        }
        effects.materializeEntries()
        guard await effects.waitForPendingPresentation(), !Task.isCancelled else {
            return false
        }
        clear(effects: effects)
        effects.clearPendingProjectionReload()
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
