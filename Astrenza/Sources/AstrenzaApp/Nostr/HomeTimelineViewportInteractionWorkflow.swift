import AstrenzaCore

struct HomeTimelineViewportInteractionState: Sendable {
    let presentation: HomeTimelinePresentationAppState
    let pendingEvents: HomeTimelinePendingEventsState
    let pagination: HomeTimelinePaginationState
}

enum HomeTimelineViewportApplication {
    case applyProjectionViewportTransition(
        HomeTimelineProjectionViewportTransition
    )
    case reloadNewestProjectionWindow(NostrAccount)
    case materializeEntries(allowsRealtimeFollow: Bool)
    case applyRestoreProjectionAnchor(NostrAccount)
    case applyPresentationTransition(HomeTimelinePresentationTransition)
    case scheduleReadStateSave
    case applyPendingEventCountPublication(
        HomeTimelinePendingEventCountPublication
    )
    case clearPendingProjectionReload
    case scheduleLinkPreviewResolution
}

enum HomeTimelineViewportInteractionLoad: Equatable, Sendable {
    case refreshLatest(NostrAccount, HomeTimelineLifecycleToken)
    case loadOlder(NostrAccount, HomeTimelineLifecycleToken)
}

struct HomeTimelineViewportInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineViewportApplication
    ) -> Void
    typealias LoadEffect = @MainActor @Sendable (
        _ load: HomeTimelineViewportInteractionLoad
    ) async -> Void
    typealias PresentationWaiter = @MainActor @Sendable () async -> Bool

    let apply: ApplicationEffect
    let load: LoadEffect
    let waitForPendingPresentation: PresentationWaiter
}

struct HomeTimelineViewportInteractionContext: Sendable {
    let state: HomeTimelineViewportInteractionState
    let presentationEffects: HomeTimelinePresentationEffects
    let pendingEventsEffects: HomeTimelinePendingEventsEffects
    let paginationEffects: HomeTimelinePaginationEffects
}

@MainActor
final class HomeTimelineViewportInteractionWorkflow {
    private let presentation: HomeTimelinePresentationWorkflow
    private let pendingEvents: HomeTimelinePendingEventsWorkflow
    private let pagination: HomeTimelinePaginationWorkflow

    init(
        presentation: HomeTimelinePresentationWorkflow,
        pendingEvents: HomeTimelinePendingEventsWorkflow,
        pagination: HomeTimelinePaginationWorkflow
    ) {
        self.presentation = presentation
        self.pendingEvents = pendingEvents
        self.pagination = pagination
    }

    var hasBufferedEvents: Bool {
        pendingEvents.hasBufferedEvents
    }

    func setRestoreProjectionAnchor(
        _ anchorEventID: String?,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.setRestoreProjectionAnchor(
            anchorEventID,
            state: context.state.presentation,
            effects: context.presentationEffects
        )
    }

    func refresh(_ context: HomeTimelineViewportInteractionContext) {
        pagination.refresh(
            context.state.pagination,
            effects: context.paginationEffects
        )
    }

    func refreshLatest(
        _ context: HomeTimelineViewportInteractionContext
    ) async {
        await pagination.refreshLatest(
            context.state.pagination,
            effects: context.paginationEffects
        )
    }

    func setTimelineAtNewestWindow(
        _ isAtNewestWindow: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.setTimelineAtNewestWindow(
            isAtNewestWindow,
            state: context.state.presentation,
            effects: context.presentationEffects
        )
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.setTimelineScrollActive(
            isActive,
            effects: context.presentationEffects
        )
    }

    func dismissUnreadBadge(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        presentation.dismissUnreadBadge(
            effects: context.presentationEffects
        )
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs,
            effects: context.presentationEffects
        )
    }

    func markNewestMaterializedWindowRead(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        presentation.markNewestMaterializedWindowRead(
            effects: context.presentationEffects
        )
    }

    @discardableResult
    func applyPendingNewEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) async -> Bool {
        await pendingEvents.apply(
            context.state.pendingEvents,
            effects: context.pendingEventsEffects
        )
    }

    @discardableResult
    func clearPendingEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool {
        pendingEvents.clear(
            effects: context.pendingEventsEffects
        )
    }

    func loadOlder(_ context: HomeTimelineViewportInteractionContext) {
        pagination.loadOlder(
            context.state.pagination,
            effects: context.paginationEffects
        )
    }
}

#if DEBUG
extension HomeTimelineViewportInteractionWorkflow {
    func replacePendingEventIDs(
        _ eventIDs: Set<String>,
        context: HomeTimelineViewportInteractionContext
    ) {
        pendingEvents.replaceEventIDs(
            eventIDs,
            effects: context.pendingEventsEffects
        )
    }
}
#endif
