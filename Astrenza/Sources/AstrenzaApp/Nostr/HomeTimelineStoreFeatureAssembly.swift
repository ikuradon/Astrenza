import AstrenzaCore

private struct HomeTimelineStoreApplicationFeatures {
    let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let presentationWorkflow: HomeTimelinePresentationWorkflow
    let viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow
}

private struct HomeTimelineStoreLoadFeatures {
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow
}

private struct HomeTimelineStorePeripheralFeatures {
    let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    let readStateCoordinator: HomeTimelineReadStateCoordinator
    let outboxCoordinator: HomeTimelineOutboxCoordinator
    let publishWorkflow: HomeTimelinePublishWorkflow?
    let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
}

@MainActor
extension HomeTimelineStoreAssembly {
    static func makeFeatures(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph
    ) -> HomeTimelineStoreFeatureGraph {
        let peripherals = makePeripheralFeatures(input, persistence: persistence)
        let applications = makeApplicationFeatures(
            input,
            persistence: persistence,
            coordination: coordination,
            relayRuntime: relayRuntime,
            peripherals: peripherals
        )
        let loads = makeLoadFeatures(
            input,
            persistence: persistence,
            coordination: coordination,
            relayRuntime: relayRuntime
        )
        return HomeTimelineStoreFeatureGraph(
            stateInteractionWorkflow: applications.stateInteractionWorkflow,
            accountStartWorkflow: applications.accountStartWorkflow,
            presentationWorkflow: applications.presentationWorkflow,
            linkPreviewInteractionWorkflow:
                HomeLinkPreviewInteractionWorkflow(
                    linkPreviews: peripherals.linkPreviewCoordinator,
                    relayStatus: relayRuntime.relayStatusCoordinator
                ),
            viewportInteractionWorkflow:
                applications.viewportInteractionWorkflow,
            remoteLoadCoordinator: loads.remoteLoadCoordinator,
            loadInteractionWorkflow: loads.loadInteractionWorkflow,
            linkPreviewCoordinator: peripherals.linkPreviewCoordinator,
            readStateCoordinator: peripherals.readStateCoordinator,
            outboxCoordinator: peripherals.outboxCoordinator,
            publishWorkflow: peripherals.publishWorkflow,
            localMutationCoordinator: peripherals.localMutationCoordinator
        )
    }

    static func makeAccountResetWorkflow(
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        runtimeEvents: HomeTimelineStoreRuntimeEventGraph,
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph,
        features: HomeTimelineStoreFeatureGraph
    ) -> HomeTimelineAccountResetWorkflow {
        let coordinator = HomeTimelineAccountResetCoordinator(
            dependencies: HomeTimelineAccountResetDependencies(
                endReadSession: { readBoundaryWrite in
                    features.readStateCoordinator.endSession(flushing: readBoundaryWrite)
                },
                flushRelayTraffic: relayRuntime.relayStatusCoordinator.flushTraffic,
                cancelLifecycle: coordination.lifecycleCoordinator.cancel,
                cancelGapReconciliation: runtimeEvents.backwardCompletionWorkflow.cancel,
                cancelRuntimeEvents: runtimeEvents.runtimeSessionCoordinator.cancelRuntimeEvents,
                resetLinkPreviews: features.linkPreviewCoordinator.reset,
                resetPresentation: coordination.presentationCoordinator.reset,
                cancelOutbox: features.outboxCoordinator.cancel,
                resetDependencies: coordination.dependencyCoordinator.reset,
                resetBackwardRequests: coordination.backwardRequestRegistry.reset,
                resetActivity: coordination.activityCoordinator.reset,
                resetProjection: persistence.homeFeedProjection.reset,
                resetRuntimeSetup: relayRuntime.runtimeSetupCoordinator.reset,
                resetFeedSync: {
                    coordination.feedSyncCoordinator.reset(
                        finishingActiveRequestsWith: .cancelled
                    )
                },
                resetContent: persistence.contentCoordinator.reset,
                resetRelayStatus: relayRuntime.relayStatusCoordinator.reset,
                resetFilters: persistence.filterCoordinator.reset
            )
        )
        return HomeTimelineAccountResetWorkflow(
            resetCoordinator: coordinator,
            runtimeShutdownCoordinator: relayRuntime.runtimeShutdownCoordinator
        )
    }

    private static func makeApplicationFeatures(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph,
        peripherals: HomeTimelineStorePeripheralFeatures
    ) -> HomeTimelineStoreApplicationFeatures {
        let persistenceCoordinator = HomeTimelinePersistenceCoordinator(
            snapshotPersistence: persistence.snapshotCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let accountStartWorkflow = makeAccountStartWorkflow(
            input,
            lifecycle: coordination.lifecycleCoordinator,
            outbox: peripherals.outboxCoordinator
        )
        let stateApplicationCoordinator = HomeTimelineStateApplicationCoordinator(
            snapshotCoordinator: persistence.snapshotCoordinator,
            presentationCoordinator: coordination.presentationCoordinator,
            contentCoordinator: persistence.contentCoordinator,
            dependencyCoordinator: coordination.dependencyCoordinator,
            relayStatusCoordinator: relayRuntime.relayStatusCoordinator,
            projectionController: persistence.homeFeedProjection,
            listProjectionCache: coordination.listProjectionCache,
            pendingEventBuffer: coordination.pendingEventBuffer
        )
        let presentationWorkflow = HomeTimelinePresentationWorkflow(
            coordinator: coordination.presentationCoordinator
        )
        let pendingEventsWorkflow = HomeTimelinePendingEventsWorkflow(
            buffer: coordination.pendingEventBuffer
        )
        let paginationWorkflow = HomeTimelinePaginationWorkflow(
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let stateWorkflow = HomeTimelineStateWorkflow(
            stateApplication: stateApplicationCoordinator,
            persistence: persistenceCoordinator
        )
        return HomeTimelineStoreApplicationFeatures(
            stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow(
                stateWorkflow: stateWorkflow,
                relayStatus: relayRuntime.relayStatusCoordinator
            ),
            accountStartWorkflow: accountStartWorkflow,
            presentationWorkflow: presentationWorkflow,
            viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow(
                presentation: presentationWorkflow,
                pendingEvents: pendingEventsWorkflow,
                pagination: paginationWorkflow
            )
        )
    }

    private static func makeAccountStartWorkflow(
        _ input: HomeTimelineStoreAssemblyInput,
        lifecycle: HomeTimelineLifecycleCoordinator,
        outbox: any HomeTimelineOutboxActivating
    ) -> HomeTimelineAccountStartWorkflow {
        HomeTimelineAccountStartWorkflow(
            coordinator: HomeTimelineAccountStartCoordinator(
                lifecycleCoordinator: lifecycle,
                resolveSyncPolicy: { accountID, fallback in
                    input.syncPolicySettingsStore.policy(
                        accountID: accountID,
                        fallback: fallback
                    )
                }
            ),
            outbox: outbox
        )
    }

    private static func makeLoadFeatures(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph
    ) -> HomeTimelineStoreLoadFeatures {
        let remoteLoadCoordinator = HomeTimelineRemoteLoadCoordinator(
            loader: input.timelineLoader,
            relayEventPersistence: relayRuntime.relayStatusCoordinator
        )
        let initialLoad = HomeTimelineInitialLoadWorkflow(
            remoteLoader: remoteLoadCoordinator,
            activityCoordinator: coordination.activityCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let refresh = HomeTimelineRefreshWorkflow(
            remoteLoader: remoteLoadCoordinator,
            activityCoordinator: coordination.activityCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let olderPage = HomeTimelineOlderPageWorkflow(
            requester: coordination.backwardRequestCoordinator,
            remoteLoader: remoteLoadCoordinator,
            activityCoordinator: coordination.activityCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let loadWorkflow = HomeTimelineLoadWorkflow(
            initialLoad: initialLoad,
            refresh: refresh,
            olderPage: olderPage,
            outcomeApplication: HomeTimelineLoadApplicationCoordinator(
                lifecycleCoordinator: coordination.lifecycleCoordinator
            )
        )
        return HomeTimelineStoreLoadFeatures(
            remoteLoadCoordinator: remoteLoadCoordinator,
            loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow(
                loadWorkflow: loadWorkflow,
                relayStatus: relayRuntime.relayStatusCoordinator
            )
        )
    }

    private static func makePeripheralFeatures(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph
    ) -> HomeTimelineStorePeripheralFeatures {
        let linkPreviewCoordinator = HomeTimelineLinkPreviewCoordinator(
            eventStore: input.eventStore,
            resolver: input.linkPreviewResolver
        )
        let readStateCoordinator = HomeTimelineReadStateCoordinator(
            eventStore: input.eventStore,
            persistenceWorker: persistence.persistenceWorker
        )
        let outboxCoordinator = HomeTimelineOutboxCoordinator(
            drainer: HomeTimelineOutboxDrainer(
                eventStore: input.eventStore,
                publisher: input.outboxPublisher
            )
        )
        let publishWorkflow = input.eventStore.map { eventStore in
            HomeTimelinePublishWorkflow(
                publisher: HomeTimelinePublishCoordinator(eventStore: eventStore),
                contentManager: persistence.contentCoordinator,
                projectionManager: persistence.homeFeedProjection,
                outbox: outboxCoordinator
            )
        }
        let localMutationCoordinator = (
            input.localMutationPersistence ?? input.eventStore
        ).map(HomeTimelineLocalMutationCoordinator.init)
        return HomeTimelineStorePeripheralFeatures(
            linkPreviewCoordinator: linkPreviewCoordinator,
            readStateCoordinator: readStateCoordinator,
            outboxCoordinator: outboxCoordinator,
            publishWorkflow: publishWorkflow,
            localMutationCoordinator: localMutationCoordinator
        )
    }
}
