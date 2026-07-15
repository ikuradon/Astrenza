struct HomeTimelineAccountResetContext: Sendable {
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    let resolvedRelays: [String]
}

struct HomeTimelineAccountResetHandlers: Sendable {
    typealias PresentationTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelinePresentationTransition
    ) -> Void
    typealias ActivityTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelineActivityTransition
    ) -> Void
    typealias ContentSnapshotHandler = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias RelayStatusSnapshotHandler = @MainActor @Sendable (
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) -> Void
    typealias AccountContextTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelineAccountContextTransition
    ) -> Void
    typealias ProjectionViewportTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias Action = @MainActor @Sendable () -> Void
    typealias RuntimeShutdownScheduler = @MainActor @Sendable (
        _ cancellationGeneration: UInt64
    ) -> Void

    let applyPresentationTransition: PresentationTransitionHandler
    let clearPendingEvents: Action
    let applyActivityTransition: ActivityTransitionHandler
    let invalidateListEntries: Action
    let resetRealtimeState: Action
    let applyContentSnapshot: ContentSnapshotHandler
    let applyRelayStatusSnapshot: RelayStatusSnapshotHandler
    let applyProjectionViewportTransition: ProjectionViewportTransitionHandler
    let publishRelayStatusChange: Action
    let applyAccountContextTransition: AccountContextTransitionHandler
    let scheduleRuntimeShutdown: RuntimeShutdownScheduler
}

struct HomeTimelineAccountResetDependencies: Sendable {
    typealias Action = @MainActor @Sendable () -> Void
    typealias ReadSessionEnd = @MainActor @Sendable (
        _ readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    ) -> Void
    typealias LifecycleCancellation = @MainActor @Sendable () -> UInt64
    typealias PresentationReset = @MainActor @Sendable () -> HomeTimelinePresentationTransition
    typealias ActivityReset = @MainActor @Sendable () -> HomeTimelineActivityTransition
    typealias ContentReset = @MainActor @Sendable () -> HomeTimelineContentSnapshot
    typealias RelayStatusReset = @MainActor @Sendable (
        _ resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot

    let endReadSession: ReadSessionEnd
    let flushRelayTraffic: Action
    let cancelLifecycle: LifecycleCancellation
    let cancelGapReconciliation: Action
    let cancelRuntimeEvents: Action
    let resetLinkPreviews: Action
    let resetPresentation: PresentationReset
    let cancelOutbox: Action
    let resetDependencies: Action
    let resetBackwardRequests: Action
    let resetActivity: ActivityReset
    let resetProjection: Action
    let resetRuntimeSetup: Action
    let resetFeedSync: Action
    let resetContent: ContentReset
    let resetRelayStatus: RelayStatusReset
    let resetFilters: Action
}

@MainActor
final class HomeTimelineAccountResetCoordinator {
    private let dependencies: HomeTimelineAccountResetDependencies

    init(dependencies: HomeTimelineAccountResetDependencies) {
        self.dependencies = dependencies
    }

    func reset(
        context: HomeTimelineAccountResetContext,
        handlers: HomeTimelineAccountResetHandlers
    ) {
        dependencies.endReadSession(context.readBoundaryWrite)
        dependencies.flushRelayTraffic()
        let cancellationGeneration = dependencies.cancelLifecycle()
        dependencies.cancelGapReconciliation()
        dependencies.cancelRuntimeEvents()
        dependencies.resetLinkPreviews()
        handlers.applyPresentationTransition(dependencies.resetPresentation())
        dependencies.cancelOutbox()
        dependencies.resetDependencies()
        dependencies.resetBackwardRequests()
        handlers.clearPendingEvents()
        handlers.applyActivityTransition(dependencies.resetActivity())
        handlers.invalidateListEntries()
        dependencies.resetProjection()
        dependencies.resetRuntimeSetup()
        handlers.resetRealtimeState()
        dependencies.resetFeedSync()
        handlers.applyContentSnapshot(dependencies.resetContent())
        handlers.applyRelayStatusSnapshot(
            dependencies.resetRelayStatus(context.resolvedRelays)
        )
        handlers.applyProjectionViewportTransition(.resetToNewest)
        dependencies.resetFilters()
        handlers.publishRelayStatusChange()
        handlers.applyAccountContextTransition(.clear)
        handlers.scheduleRuntimeShutdown(cancellationGeneration)
    }
}
