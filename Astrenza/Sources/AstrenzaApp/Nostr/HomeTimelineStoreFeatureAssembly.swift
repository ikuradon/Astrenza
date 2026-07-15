import AstrenzaCore

private struct HomeTimelineStoreApplicationFeatures {
    let persistenceCoordinator: HomeTimelinePersistenceCoordinator
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let loadApplicationCoordinator: HomeTimelineLoadApplicationCoordinator
    let stateApplicationCoordinator: HomeTimelineStateApplicationCoordinator
}

private struct HomeTimelineStoreLoadFeatures {
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let initialLoadWorkflow: HomeTimelineInitialLoadWorkflow
    let refreshWorkflow: HomeTimelineRefreshWorkflow
    let olderPageWorkflow: HomeTimelineOlderPageWorkflow
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
            persistenceCoordinator: applications.persistenceCoordinator,
            accountStartWorkflow: applications.accountStartWorkflow,
            loadApplicationCoordinator: applications.loadApplicationCoordinator,
            stateApplicationCoordinator: applications.stateApplicationCoordinator,
            remoteLoadCoordinator: loads.remoteLoadCoordinator,
            initialLoadWorkflow: loads.initialLoadWorkflow,
            refreshWorkflow: loads.refreshWorkflow,
            olderPageWorkflow: loads.olderPageWorkflow,
            linkPreviewCoordinator: peripherals.linkPreviewCoordinator,
            readStateCoordinator: peripherals.readStateCoordinator,
            outboxCoordinator: peripherals.outboxCoordinator,
            publishWorkflow: peripherals.publishWorkflow,
            localMutationCoordinator: peripherals.localMutationCoordinator
        )
    }

    static func makeAccountReset(
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        runtimeEvents: HomeTimelineStoreRuntimeEventGraph,
        relayRuntime: HomeTimelineStoreRelayRuntimeGraph,
        features: HomeTimelineStoreFeatureGraph
    ) -> HomeTimelineAccountResetCoordinator {
        HomeTimelineAccountResetCoordinator(
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
        let loadApplicationCoordinator = HomeTimelineLoadApplicationCoordinator(
            lifecycleCoordinator: coordination.lifecycleCoordinator
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
        return HomeTimelineStoreApplicationFeatures(
            persistenceCoordinator: persistenceCoordinator,
            accountStartWorkflow: accountStartWorkflow,
            loadApplicationCoordinator: loadApplicationCoordinator,
            stateApplicationCoordinator: stateApplicationCoordinator
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
        return HomeTimelineStoreLoadFeatures(
            remoteLoadCoordinator: remoteLoadCoordinator,
            initialLoadWorkflow: HomeTimelineInitialLoadWorkflow(
                remoteLoader: remoteLoadCoordinator,
                activityCoordinator: coordination.activityCoordinator,
                lifecycleCoordinator: coordination.lifecycleCoordinator
            ),
            refreshWorkflow: HomeTimelineRefreshWorkflow(
                remoteLoader: remoteLoadCoordinator,
                activityCoordinator: coordination.activityCoordinator,
                lifecycleCoordinator: coordination.lifecycleCoordinator
            ),
            olderPageWorkflow: HomeTimelineOlderPageWorkflow(
                requester: coordination.backwardRequestCoordinator,
                remoteLoader: remoteLoadCoordinator,
                activityCoordinator: coordination.activityCoordinator,
                lifecycleCoordinator: coordination.lifecycleCoordinator
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
