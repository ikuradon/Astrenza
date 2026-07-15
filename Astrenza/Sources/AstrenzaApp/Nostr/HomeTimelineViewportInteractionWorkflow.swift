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
    case scheduleViewportState(TimelineViewportState)
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

    let apply: ApplicationEffect
    let load: LoadEffect
}

struct HomeTimelineViewportInteractionContext: Sendable {
    let state: HomeTimelineViewportInteractionState
    let effects: HomeTimelineViewportInteractionEffects
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
            effects: presentationEffects(for: context.effects)
        )
    }

    func saveViewportState(
        _ viewport: TimelineViewportState,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.saveViewportState(
            viewport,
            state: context.state.presentation,
            effects: presentationEffects(for: context.effects)
        )
    }

    func refresh(_ context: HomeTimelineViewportInteractionContext) {
        pagination.refresh(
            context.state.pagination,
            effects: paginationEffects(for: context.effects)
        )
    }

    func refreshLatest(
        _ context: HomeTimelineViewportInteractionContext
    ) async {
        await pagination.refreshLatest(
            context.state.pagination,
            effects: paginationEffects(for: context.effects)
        )
    }

    func setTimelineAtNewestWindow(
        _ isAtNewestWindow: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.setTimelineAtNewestWindow(
            isAtNewestWindow,
            state: context.state.presentation,
            effects: presentationEffects(for: context.effects)
        )
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.setTimelineScrollActive(
            isActive,
            effects: presentationEffects(for: context.effects)
        )
    }

    func dismissUnreadBadge(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        presentation.dismissUnreadBadge(
            effects: presentationEffects(for: context.effects)
        )
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineViewportInteractionContext
    ) {
        presentation.markMaterializedPostsRead(
            visiblePostIDs: visiblePostIDs,
            effects: presentationEffects(for: context.effects)
        )
    }

    func markNewestMaterializedWindowRead(
        _ context: HomeTimelineViewportInteractionContext
    ) {
        presentation.markNewestMaterializedWindowRead(
            effects: presentationEffects(for: context.effects)
        )
    }

    @discardableResult
    func applyPendingNewEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool {
        pendingEvents.apply(
            context.state.pendingEvents,
            effects: pendingEventsEffects(for: context.effects)
        )
    }

    @discardableResult
    func clearPendingEvents(
        _ context: HomeTimelineViewportInteractionContext
    ) -> Bool {
        pendingEvents.clear(
            effects: pendingEventsEffects(for: context.effects)
        )
    }

    func loadOlder(_ context: HomeTimelineViewportInteractionContext) {
        pagination.loadOlder(
            context.state.pagination,
            effects: paginationEffects(for: context.effects)
        )
    }

    private func presentationEffects(
        for effects: HomeTimelineViewportInteractionEffects
    ) -> HomeTimelinePresentationEffects {
        HomeTimelinePresentationEffects(
            applyProjectionViewportTransition: { transition in
                effects.apply(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { account in
                effects.apply(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: { allowsRealtimeFollow in
                effects.apply(.materializeEntries(
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            },
            applyRestoreProjectionAnchor: { account in
                effects.apply(.applyRestoreProjectionAnchor(account))
            },
            scheduleViewportState: { state in
                effects.apply(.scheduleViewportState(state))
            },
            applyPresentationTransition: { transition in
                effects.apply(.applyPresentationTransition(transition))
            },
            scheduleReadStateSave: {
                effects.apply(.scheduleReadStateSave)
            }
        )
    }

    private func pendingEventsEffects(
        for effects: HomeTimelineViewportInteractionEffects
    ) -> HomeTimelinePendingEventsEffects {
        HomeTimelinePendingEventsEffects(
            applyProjectionViewportTransition: { transition in
                effects.apply(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjection: { account in
                effects.apply(.reloadNewestProjectionWindow(account))
            },
            applyPendingEventCountPublication: { publication in
                effects.apply(.applyPendingEventCountPublication(publication))
            },
            clearPendingProjectionReload: {
                effects.apply(.clearPendingProjectionReload)
            },
            materializeEntries: {
                effects.apply(.materializeEntries(allowsRealtimeFollow: false))
            },
            scheduleLinkPreviewResolution: {
                effects.apply(.scheduleLinkPreviewResolution)
            }
        )
    }

    private func paginationEffects(
        for effects: HomeTimelineViewportInteractionEffects
    ) -> HomeTimelinePaginationEffects {
        HomeTimelinePaginationEffects(
            applyProjectionViewportTransition: { transition in
                effects.apply(.applyProjectionViewportTransition(transition))
            },
            refreshLatest: { account, lifecycle in
                await effects.load(.refreshLatest(account, lifecycle))
            },
            loadOlder: { account, lifecycle in
                await effects.load(.loadOlder(account, lifecycle))
            }
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
            effects: pendingEventsEffects(for: context.effects)
        )
    }
}
#endif
