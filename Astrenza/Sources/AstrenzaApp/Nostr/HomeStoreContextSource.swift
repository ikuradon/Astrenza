import AstrenzaCore

@MainActor
protocol HomeStoreContextSourcing: AnyObject {
    func loadSnapshot() -> HomeLoadContextSnapshot?
    func hasResolvedRelays() -> Bool
    func loaderState() -> NostrHomeTimelineState?
    func localBackfillEvents(
        account: NostrAccount,
        current: NostrHomeTimelineState
    ) -> [NostrEvent]?
    func resolvedRelays() -> [String]

    func runtimeSnapshot() -> HomeTimelineRuntimeStoreSnapshot?
    func isCurrentFeedContext(_ context: HomeFeedRuntimeContext) -> Bool
    func runtimeApplicationEffects(
        context: HomeTimelineStateInteractionContext
    ) -> HomeTimelineRuntimeApplicationEffects

    func stateProjection() -> HomeTimelineStateContextProjection?

    func featureSnapshot() -> HomeTimelineFeatureInteractionSnapshot?
    func resolveBackwardDependencies(
        _ request: HomeTimelineBackwardDependencyRequest,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool

    func accountSnapshot() -> HomeAccountLifecycleSnapshot?
    func readBoundaryWrite() -> HomeTimelineReadBoundaryWrite?
    func restoreCachedSnapshot(
        account: NostrAccount,
        context: HomeTimelineStateInteractionContext
    ) async -> HomeTimelineCachedStateRestoreOutcome
    func restoredViewport(accountID: String) -> HomeTimelineRestoredViewport?
    func waitForCachedPresentation() async
    func restoreCachedReadState(account: NostrAccount) async
    func load(
        _ request: HomeTimelineAccountStartLoadRequest,
        context: HomeTimelineLoadInteractionContext
    ) async

    func viewportSnapshot() -> HomeViewportStoreSnapshot?
    func scheduleReadBoundarySave()
}

@MainActor
final class HomeStoreContextSource: HomeStoreContextSourcing {
    private let publishedState: HomeTimelinePublishedStateCoordinator
    private let remoteLoad: HomeTimelineRemoteLoadCoordinator
    private let dataInteraction: HomeTimelineDataInteractionWorkflow
    private let runtimeInteraction: HomeTimelineRuntimeInteractionWorkflow
    private let viewportInteraction: HomeTimelineViewportInteractionWorkflow
    private let accountResetInteraction: HomeAccountResetInteractionWorkflow
    private let activityInteraction: HomeTimelineActivityInteractionWorkflow
    private let presentation: HomeTimelinePresentationWorkflow
    private let projectionInteraction: HomeProjectionInteractionWorkflow
    private let stateInteraction: HomeTimelineStateInteractionWorkflow
    private let loadInteraction: HomeTimelineLoadInteractionWorkflow
    private let syncInteraction: HomeTimelineSyncInteractionWorkflow
    private let query: HomeStoreQueryCoordinator
    private let readBoundary: HomeStoreReadBoundaryCoordinator
    private let projectionViewport: HomeProjectionViewportCoordinator
    private let stateProjector = HomeTimelineStateContextProjector()
    private let hasRelayRuntime: Bool

    init(
        components: HomeTimelineStoreComponents,
        query: HomeStoreQueryCoordinator,
        projectionViewport: HomeProjectionViewportCoordinator,
        hasRelayRuntime: Bool
    ) {
        publishedState = components.publishedStateCoordinator
        remoteLoad = components.remoteLoadCoordinator
        dataInteraction = components.dataInteractionWorkflow
        runtimeInteraction = components.runtimeInteractionWorkflow
        viewportInteraction = components.viewportInteractionWorkflow
        accountResetInteraction = components.accountResetInteractionWorkflow
        activityInteraction = components.activityInteractionWorkflow
        presentation = components.presentationWorkflow
        projectionInteraction = components.projectionInteractionWorkflow
        stateInteraction = components.stateInteractionWorkflow
        loadInteraction = components.loadInteractionWorkflow
        syncInteraction = components.syncInteractionWorkflow
        self.query = query
        readBoundary = HomeStoreReadBoundaryCoordinator.live(
            components: components,
            query: query
        )
        self.projectionViewport = projectionViewport
        self.hasRelayRuntime = hasRelayRuntime
    }

    func loadSnapshot() -> HomeLoadContextSnapshot? {
        HomeLoadContextSnapshot(
            hasRelayRuntime: hasRelayRuntime,
            hasTimelineEvents: !dataInteraction.contentState.noteEvents.isEmpty,
            syncPolicy: publishedState.accountContext.syncPolicy
        )
    }

    func hasResolvedRelays() -> Bool {
        !publishedState.content.resolvedRelays.isEmpty
    }

    func loaderState() -> NostrHomeTimelineState? {
        dataInteraction.loaderState(
            relaySyncEvents: syncInteraction.relaySyncEvents
        )
    }

    func localBackfillEvents(
        account: NostrAccount,
        current: NostrHomeTimelineState
    ) -> [NostrEvent]? {
        query.olderBackfillEvents(account: account, current: current)
    }

    func resolvedRelays() -> [String] {
        publishedState.content.resolvedRelays
    }

    func runtimeSnapshot() -> HomeTimelineRuntimeStoreSnapshot? {
        let activity = activityInteraction.state
        return HomeTimelineRuntimeStoreSnapshot(
            account: publishedState.accountContext.account,
            resolvedRelays: publishedState.content.resolvedRelays,
            bootstrapRelayURLs: remoteLoad.bootstrapRelays,
            profileEvents: dataInteraction.contentState.noteEvents,
            policy: publishedState.accountContext.syncPolicy,
            hasRelayRuntime: hasRelayRuntime,
            isTerminating: accountResetInteraction.isRuntimeTerminating,
            isRuntimeActive: activity.phase != .idle,
            isRealtime: activity.isRealtime,
            hasRestoreProjectionAnchor:
                projectionViewport.restoreAnchorEventID != nil,
            isTimelineAtNewestWindow:
                projectionViewport.isAtNewestWindow,
            hasPendingEvents: viewportInteraction.hasBufferedEvents
        )
    }

    func isCurrentFeedContext(_ context: HomeFeedRuntimeContext) -> Bool {
        projectionInteraction.isCurrent(
            context,
            accountID: publishedState.accountContext.account?.pubkey
        )
    }

    func runtimeApplicationEffects(
        context: HomeTimelineStateInteractionContext
    ) -> HomeTimelineRuntimeApplicationEffects {
        stateInteraction.runtimeApplicationEffects(context: context)
    }

    func stateProjection() -> HomeTimelineStateContextProjection? {
        let dependencies = dataInteraction.dependencyResolutionState
        return stateProjector.projection(
            from: HomeTimelineStateStoreSnapshot(
                account: publishedState.accountContext.account,
                resolvedRelays: publishedState.content.resolvedRelays,
                followedPubkeys: publishedState.content.followedPubkeys,
                nip05Resolutions: dependencies.nip05Resolutions,
                hasMoreOlder: publishedState.content.hasMoreOlder,
                hasPendingEvents: viewportInteraction.hasBufferedEvents,
                defaultMaterializationDelayNanoseconds:
                    presentation.interactionState.defaultDelayNanoseconds
            )
        )
    }

    func featureSnapshot() -> HomeTimelineFeatureInteractionSnapshot? {
        HomeTimelineFeatureInteractionSnapshot(
            account: publishedState.accountContext.account,
            resolvedRelays: publishedState.content.resolvedRelays,
            relayListEvent: dataInteraction.contentState.relayListEvent,
            syncPolicy: publishedState.accountContext.syncPolicy,
            hasRelayRuntime: hasRelayRuntime
        )
    }

    func resolveBackwardDependencies(
        _ request: HomeTimelineBackwardDependencyRequest,
        application: HomeTimelineRuntimeApplicationEffects
    ) async -> Bool {
        await runtimeInteraction.enqueueDependencies(
            for: request.event,
            context: HomeTimelineRuntimeEventApplicationContext(
                account: request.account,
                lifecycle: request.lifecycle,
                hasRelayRuntime: hasRelayRuntime
            ),
            application: application
        )
    }

    func accountSnapshot() -> HomeAccountLifecycleSnapshot? {
        HomeAccountLifecycleSnapshot(
            account: publishedState.accountContext.account,
            syncPolicy: publishedState.accountContext.syncPolicy,
            restoreProjectionAnchorEventID:
                projectionViewport.restoreAnchorEventID,
            hasEntries: !publishedState.presentation.entries.isEmpty,
            resolvedRelays: publishedState.content.resolvedRelays,
            hasRelayRuntime: hasRelayRuntime
        )
    }

    func readBoundaryWrite() -> HomeTimelineReadBoundaryWrite? {
        readBoundary.boundaryWrite()
    }

    func restoreCachedSnapshot(
        account: NostrAccount,
        context: HomeTimelineStateInteractionContext
    ) async -> HomeTimelineCachedStateRestoreOutcome {
        await stateInteraction.restoreCachedState(
            accountID: account.pubkey,
            context: context
        )
    }

    func restoredViewport(accountID: String) -> HomeTimelineRestoredViewport? {
        projectionInteraction.restoredViewportState(
            accountID: accountID,
            timelineKey: "home"
        ).map {
            HomeTimelineRestoredViewport(anchorEventID: $0.anchorPostID)
        }
    }

    func waitForCachedPresentation() async {
        _ = await projectionInteraction.waitForPendingPresentation()
    }

    func restoreCachedReadState(account: NostrAccount) async {
        await readBoundary.restore(account: account)
    }

    func load(
        _ request: HomeTimelineAccountStartLoadRequest,
        context: HomeTimelineLoadInteractionContext
    ) async {
        await loadInteraction.loadInitial(
            account: request.account,
            lifecycle: request.lifecycle,
            context: context
        )
    }

    func viewportSnapshot() -> HomeViewportStoreSnapshot? {
        let content = publishedState.content
        return HomeViewportStoreSnapshot(
            account: publishedState.accountContext.account,
            restoreProjectionAnchorEventID:
                projectionViewport.restoreAnchorEventID,
            hasPendingProjectionReload:
                presentation.interactionState.hasPendingNewestProjectionReload,
            canBeginLoadingOlder:
                activityInteraction.state.canBeginLoadingOlder,
            hasMoreOlder: content.hasMoreOlder,
            hasTimelineEvents:
                !dataInteraction.contentState.noteEvents.isEmpty,
            hasResolvedRelays: !content.resolvedRelays.isEmpty,
            hasFollowedPubkeys: !content.followedPubkeys.isEmpty
        )
    }

    func scheduleReadBoundarySave() {
        readBoundary.scheduleSave()
    }
}
