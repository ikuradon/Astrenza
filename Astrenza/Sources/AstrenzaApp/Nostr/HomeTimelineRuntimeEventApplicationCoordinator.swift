import AstrenzaCore

struct HomeTimelineRuntimeEventApplicationContext: Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let hasRelayRuntime: Bool
}

enum HomeTimelineRuntimeEventApplicationCommand: Equatable, Sendable {
    case reloadProjection(
        anchorEventID: String?,
        materialization: HomeTimelineRuntimeEventApplicationPlan.DeletionMaterialization
    )
    case requestNewestProjectionReloadAndSchedule(allowsRealtimeFollow: Bool)
    case scheduleMaterialization(HomeTimelineRuntimeEventApplicationPlan.MaterializationSchedule)
}

struct HomeTimelineRuntimeEventApplicationHandlers: Sendable {
    typealias ListProjectionInvalidationHandler = @MainActor @Sendable (
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) -> Void
    typealias PendingCountHandler = @MainActor @Sendable (_ count: Int) -> Void
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRuntimeEventApplicationCommand
    ) -> Void
    typealias MetadataPersistenceHandler = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias SourceInstallFailureHandler = @MainActor @Sendable (_ message: String) -> Void

    let applyListProjectionInvalidation: ListProjectionInvalidationHandler
    let pendingCountChanged: PendingCountHandler
    let perform: CommandHandler
    let persistTimelineMetadata: MetadataPersistenceHandler
    let sourceInstallFailed: SourceInstallFailureHandler
}

@MainActor
final class HomeTimelineRuntimeEventApplicationCoordinator {
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let listProjectionCache: HomeTimelineListProjectionCache
    private let pendingEventBuffer: HomeTimelinePendingEventBuffer
    private let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        contentCoordinator: HomeTimelineContentCoordinator,
        dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator,
        listProjectionCache: HomeTimelineListProjectionCache,
        pendingEventBuffer: HomeTimelinePendingEventBuffer,
        backwardRequestRegistry: HomeTimelineBackwardRequestRegistry,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.contentCoordinator = contentCoordinator
        self.dependencyCoordinator = dependencyCoordinator
        self.listProjectionCache = listProjectionCache
        self.pendingEventBuffer = pendingEventBuffer
        self.backwardRequestRegistry = backwardRequestRegistry
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func apply(
        _ plan: HomeTimelineRuntimeEventApplicationPlan,
        backwardRequestKey: String?,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        guard isCurrent(context) else { return false }
        if plan.invalidatesListEntries {
            invalidateListEntries(handlers: handlers)
        }
        if let metadataEvent = plan.metadataEvent {
            let effectiveMetadataEvent = rememberLatestMetadataEvent(
                metadataEvent,
                handlers: handlers
            )
            resolveNIP05IfNeeded(
                for: effectiveMetadataEvent,
                context: context,
                handlers: handlers
            )
        }
        if let eventID = plan.backwardTimelineEventID,
           let backwardRequestKey {
            backwardRequestRegistry.recordTimelineEvent(eventID, for: backwardRequestKey)
        }
        if let eventID = plan.sourceEventIDToFinish {
            dependencyCoordinator.finishSourceEvent(eventID: eventID)
        }
        if let dependencyEvent = plan.dependencyEvent {
            guard await enqueueDependencies(
                for: dependencyEvent,
                context: context,
                handlers: handlers
            ) else { return false }
        }
        if let embeddedDependencyEvent = plan.embeddedDependencyEvent {
            guard await enqueueDependencies(
                for: embeddedDependencyEvent,
                context: context,
                handlers: handlers
            ) else { return false }
        }
        if let deletion = plan.deletion {
            let deletedAnchor = contentCoordinator.removeEventsDeletedFromCurrentProjection(
                by: deletion.event
            )
            handlers.perform(.reloadProjection(
                anchorEventID: deletedAnchor,
                materialization: deletion.materialization
            ))
        }
        if let projectionUpdate = plan.projectionUpdate {
            switch projectionUpdate {
            case .reloadNewestAndSchedule(let allowsRealtimeFollow):
                handlers.perform(.requestNewestProjectionReloadAndSchedule(
                    allowsRealtimeFollow: allowsRealtimeFollow
                ))
            case .bufferPendingEvent(let eventID):
                _ = pendingEventBuffer.insert(
                    eventID: eventID,
                    onCountChange: handlers.pendingCountChanged
                )
            }
        }
        if let schedule = plan.materializationSchedule {
            handlers.perform(.scheduleMaterialization(schedule))
        }
        return isCurrent(context)
    }

    @discardableResult
    func rememberLatestMetadataEvent(
        _ event: NostrEvent,
        consultEventStore: Bool = true,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) -> NostrEvent {
        let update = contentCoordinator.rememberLatestMetadataEvent(
            event,
            consultEventStore: consultEventStore
        )
        if update.didChange {
            invalidateListEntries(handlers: handlers)
        }
        return update.event
    }

    func resolveNIP05IfNeeded(
        for metadataEvent: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) {
        dependencyCoordinator.resolveNIP05IfNeeded(for: metadataEvent) { [weak self] in
            guard let self, isCurrent(context) else { return }
            invalidateListEntries(handlers: handlers)
            handlers.perform(.scheduleMaterialization(.standard))
            await handlers.persistTimelineMetadata(context.account)
        }
    }

    func enqueueDependencies(
        for event: NostrEvent,
        context: HomeTimelineRuntimeEventApplicationContext,
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) async -> Bool {
        let content = contentCoordinator.snapshot
        guard context.hasRelayRuntime, !content.resolvedRelays.isEmpty else {
            return isCurrent(context)
        }
        let result = await dependencyCoordinator.enqueueDependencies(
            for: event,
            liveMetadataEvents: content.metadataEvents,
            liveNoteEventIDs: Set(content.noteEvents.map(\.id)),
            availableRelayURLs: content.resolvedRelays
        )
        guard isCurrent(context) else { return false }

        for profile in result.cachedProfiles {
            _ = rememberLatestMetadataEvent(
                profile,
                consultEventStore: false,
                handlers: handlers
            )
        }
        if !result.cachedProfiles.isEmpty || result.didResolveCachedDependencies {
            handlers.perform(.scheduleMaterialization(.standard))
        }
        if result.didEnqueueSourceDependencies {
            _ = dependencyCoordinator.scheduleSourcePacketInstall(
                onFailure: handlers.sourceInstallFailed
            )
        }
        return true
    }

    private func invalidateListEntries(
        handlers: HomeTimelineRuntimeEventApplicationHandlers
    ) {
        handlers.applyListProjectionInvalidation(listProjectionCache.invalidate())
    }

    private func isCurrent(
        _ context: HomeTimelineRuntimeEventApplicationContext
    ) -> Bool {
        lifecycleCoordinator.isCurrent(context.lifecycle) &&
            context.lifecycle.accountID == context.account.pubkey
    }
}
