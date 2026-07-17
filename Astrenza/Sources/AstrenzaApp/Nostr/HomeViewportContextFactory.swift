import AstrenzaCore

struct HomeViewportStoreSnapshot: Sendable {
    let account: NostrAccount?
    let restoreProjectionAnchorEventID: String?
    let hasPendingProjectionReload: Bool
    let canBeginLoadingOlder: Bool
    let hasMoreOlder: Bool
    let hasTimelineEvents: Bool
    let hasResolvedRelays: Bool
    let hasFollowedPubkeys: Bool

    static var empty: Self {
        HomeViewportStoreSnapshot(
            account: nil,
            restoreProjectionAnchorEventID: nil,
            hasPendingProjectionReload: false,
            canBeginLoadingOlder: false,
            hasMoreOlder: false,
            hasTimelineEvents: false,
            hasResolvedRelays: false,
            hasFollowedPubkeys: false
        )
    }
}

struct HomeViewportContextEnvironment: Sendable {
    typealias SnapshotProvider = @MainActor @Sendable (
    ) -> HomeViewportStoreSnapshot?

    let snapshot: SnapshotProvider
    let applications: HomeTimelineViewportApplicationEffects
}

@MainActor
struct HomeViewportContextFactory {
    private let snapshot: HomeViewportContextEnvironment.SnapshotProvider
    private let presentationEffects: HomeTimelinePresentationEffects
    private let pendingEventsEffects: HomeTimelinePendingEventsEffects
    private let paginationEffects: HomeTimelinePaginationEffects

    init(environment: HomeViewportContextEnvironment) {
        snapshot = environment.snapshot
        let dispatcher = HomeTimelineViewportDispatcher()
        let effects = HomeTimelineViewportInteractionEffects(
            apply: { application in
                dispatcher.apply(
                    application,
                    effects: environment.applications
                )
            },
            load: { load in
                await dispatcher.perform(
                    load,
                    effects: environment.applications
                )
            },
            waitForPendingPresentation: {
                await environment.applications.waitForPendingPresentation()
            }
        )
        presentationEffects = Self.presentationEffects(
            from: effects
        )
        pendingEventsEffects = Self.pendingEventsEffects(
            from: effects
        )
        paginationEffects = Self.paginationEffects(
            from: effects
        )
    }

    func context() -> HomeTimelineViewportInteractionContext {
        let snapshot = snapshot() ?? .empty
        return HomeTimelineViewportInteractionContext(
            state: HomeTimelineViewportInteractionState(
                presentation: HomeTimelinePresentationAppState(
                    account: snapshot.account,
                    restoreProjectionAnchorEventID:
                        snapshot.restoreProjectionAnchorEventID
                ),
                pendingEvents: HomeTimelinePendingEventsState(
                    account: snapshot.account,
                    hasPendingProjectionReload:
                        snapshot.hasPendingProjectionReload
                ),
                pagination: HomeTimelinePaginationState(
                    account: snapshot.account,
                    canBeginLoadingOlder: snapshot.canBeginLoadingOlder,
                    hasMoreOlder: snapshot.hasMoreOlder,
                    hasTimelineEvents: snapshot.hasTimelineEvents,
                    hasResolvedRelays: snapshot.hasResolvedRelays,
                    hasFollowedPubkeys: snapshot.hasFollowedPubkeys
                )
            ),
            presentationEffects: presentationEffects,
            pendingEventsEffects: pendingEventsEffects,
            paginationEffects: paginationEffects
        )
    }

    private static func presentationEffects(
        from effects: HomeTimelineViewportInteractionEffects
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
            applyPresentationTransition: { transition in
                effects.apply(.applyPresentationTransition(transition))
            },
            scheduleReadStateSave: {
                effects.apply(.scheduleReadStateSave)
            }
        )
    }

    private static func pendingEventsEffects(
        from effects: HomeTimelineViewportInteractionEffects
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
            waitForPendingPresentation: {
                await effects.waitForPendingPresentation()
            },
            scheduleLinkPreviewResolution: {
                effects.apply(.scheduleLinkPreviewResolution)
            }
        )
    }

    private static func paginationEffects(
        from effects: HomeTimelineViewportInteractionEffects
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
