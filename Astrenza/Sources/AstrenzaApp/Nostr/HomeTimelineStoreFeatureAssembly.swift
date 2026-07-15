import AstrenzaCore

private struct HomeTimelineStoreApplicationFeatures {
    let stateWorkflow: HomeTimelineStateWorkflow
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow
}

private struct HomeTimelineStoreLoadFeatures {
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let loadWorkflow: HomeTimelineLoadWorkflow
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
        let applications = makeApplicationFeatures(
            input,
            persistence: persistence,
            coordination: coordination,
            relayRuntime: relayRuntime
        )
        let loads = makeLoadFeatures(
            input,
            persistence: persistence,
            coordination: coordination,
            relayRuntime: relayRuntime
        )
        let peripherals = makePeripheralFeatures(input, persistence: persistence)
        return HomeTimelineStoreFeatureGraph(
            stateWorkflow: applications.stateWorkflow,
            accountStartWorkflow: applications.accountStartWorkflow,
            viewportInteractionWorkflow:
                applications.viewportInteractionWorkflow,
            remoteLoadCoordinator: loads.remoteLoadCoordinator,
            loadWorkflow: loads.loadWorkflow,
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
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph
    ) -> HomeTimelineStoreApplicationFeatures {
        let persistenceCoordinator = HomeTimelinePersistenceCoordinator(
            snapshotPersistence: persistence.snapshotCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let accountStartWorkflow = HomeTimelineAccountStartWorkflow(
            coordinator: HomeTimelineAccountStartCoordinator(
                lifecycleCoordinator: coordination.lifecycleCoordinator,
                resolveSyncPolicy: { accountID, fallback in
                    input.syncPolicySettingsStore.policy(
                        accountID: accountID,
                        fallback: fallback
                    )
                }
            )
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
        let pendingEventsWorkflow = HomeTimelinePendingEventsWorkflow()
        let paginationWorkflow = HomeTimelinePaginationWorkflow(
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        return HomeTimelineStoreApplicationFeatures(
            stateWorkflow: HomeTimelineStateWorkflow(
                stateApplication: stateApplicationCoordinator,
                persistence: persistenceCoordinator
            ),
            accountStartWorkflow: accountStartWorkflow,
            viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow(
                presentation: presentationWorkflow,
                pendingEvents: pendingEventsWorkflow,
                pagination: paginationWorkflow
            )
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
        return HomeTimelineStoreLoadFeatures(
            remoteLoadCoordinator: remoteLoadCoordinator,
            loadWorkflow: HomeTimelineLoadWorkflow(
                initialLoad: initialLoad,
                refresh: refresh,
                olderPage: olderPage,
                outcomeApplication: HomeTimelineLoadApplicationCoordinator(
                    lifecycleCoordinator: coordination.lifecycleCoordinator
                )
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
                projectionManager: persistence.homeFeedProjection
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
