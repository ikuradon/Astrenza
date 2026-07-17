import AstrenzaCore

private struct HomeTimelineStoreRelayInstallers {
    let source: HomeTimelineDependencyResolutionCoordinator.SourcePacketInstaller?
    let backward: HomeTimelineBackwardRequestCoordinator.PacketInstaller?
}

private struct HomeTimelineStoreBackwardCoordination {
    let registry: HomeTimelineBackwardRequestRegistry
    let coordinator: HomeTimelineBackwardRequestCoordinator
    let gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
}

@MainActor
extension HomeTimelineStoreAssembly {
    static func makePersistence(
        _ input: HomeTimelineStoreAssemblyInput
    ) -> HomeTimelineStorePersistenceGraph {
        let persistenceWorker = input.eventStore.map(HomeTimelinePersistenceWorker.init)
        let contentCoordinator = HomeTimelineContentCoordinator(eventStore: input.eventStore)
        let eventIngestor = HomeTimelineEventIngestor(eventStore: input.eventStore)
        let backfillPersistence = HomeTimelineBackfillPersistence(eventStore: input.eventStore)
        let timelineRepository = HomeTimelineRepository(eventStore: input.eventStore)
        let gapReconciliationCoordinator = HomeTimelineGapReconciliationCoordinator(
            reconciler: HomeTimelineGapReconciler(
                eventStore: input.eventStore,
                relayClient: input.timelineLoader.relayClient
            ),
            persistence: backfillPersistence
        )
        let homeFeedProjection = HomeFeedProjectionController(eventStore: input.eventStore)
        let snapshotCoordinator = HomeTimelineSnapshotCoordinator(
            persistenceWorker: persistenceWorker,
            projectionController: homeFeedProjection
        )
        return HomeTimelineStorePersistenceGraph(
            persistenceWorker: persistenceWorker,
            contentCoordinator: contentCoordinator,
            eventIngestor: eventIngestor,
            backfillPersistence: backfillPersistence,
            timelineRepository: timelineRepository,
            gapReconciliationCoordinator: gapReconciliationCoordinator,
            homeFeedProjection: homeFeedProjection,
            snapshotCoordinator: snapshotCoordinator,
            filterCoordinator: HomeTimelineFilterCoordinator(eventStore: input.eventStore)
        )
    }

    static func makeCoordination(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph
    ) -> HomeTimelineStoreCoordinationGraph {
        let syncPlanner = HomeTimelineSyncPlanner()
        let installers = makeRelayInstallers(input)
        let backward = makeBackwardCoordination(
            input,
            persistence: persistence,
            syncPlanner: syncPlanner,
            installer: installers.backward
        )
        let profileDirectory = input.relayRuntime.map {
            NostrProfileDirectory(eventStore: input.eventStore, relayRuntime: $0)
        }
        let dependencyCoordinator = HomeTimelineDependencyResolutionCoordinator(
            eventIngestor: persistence.eventIngestor,
            profileDirectory: profileDirectory,
            nip05Resolver: input.timelineLoader.nip05Resolver,
            syncPlanner: syncPlanner,
            sourcePacketInstaller: installers.source
        )
        let presentationCoordinator = HomeTimelinePresentationCoordinator()
        let lifecycleCoordinator = HomeTimelineLifecycleCoordinator()
        return HomeTimelineStoreCoordinationGraph(
            syncPlanner: syncPlanner,
            backwardRequestRegistry: backward.registry,
            backwardRequestCoordinator: backward.coordinator,
            gapBackfillWorkflow: backward.gapBackfillWorkflow,
            feedSyncCoordinator: backward.feedSyncCoordinator,
            dependencyCoordinator: dependencyCoordinator,
            listProjectionCache: HomeTimelineListProjectionCache(),
            activityCoordinator: HomeTimelineActivityCoordinator(),
            presentationCoordinator: presentationCoordinator,
            materializationCoordinator: HomeTimelineMaterializationCoordinator(
                contentCoordinator: persistence.contentCoordinator,
                filterCoordinator: persistence.filterCoordinator,
                presentationCoordinator: presentationCoordinator,
                projectionController: persistence.homeFeedProjection,
                worker: HomeTimelineMaterializationWorker(
                    repository: persistence.timelineRepository,
                    filterProjector: HomeTimelineFilterProjector(
                        eventStore: input.eventStore
                    )
                )
            ),
            pendingEventBuffer: HomeTimelinePendingEventBuffer(),
            lifecycleCoordinator: lifecycleCoordinator
        )
    }

    private static func makeRelayInstallers(
        _ input: HomeTimelineStoreAssemblyInput
    ) -> HomeTimelineStoreRelayInstallers {
        guard let relayRuntime = input.relayRuntime else {
            return HomeTimelineStoreRelayInstallers(source: nil, backward: nil)
        }
        return HomeTimelineStoreRelayInstallers(
            source: { packets in
                try await relayRuntime.installBackward(packets, mergeField: .ids)
            },
            backward: { packets, mergeField in
                try await relayRuntime.installBackward(packets, mergeField: mergeField)
            }
        )
    }

    private static func makeBackwardCoordination(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        syncPlanner: HomeTimelineSyncPlanner,
        installer: HomeTimelineBackwardRequestCoordinator.PacketInstaller?
    ) -> HomeTimelineStoreBackwardCoordination {
        let registry = HomeTimelineBackwardRequestRegistry()
        let coordinator = HomeTimelineBackwardRequestCoordinator(
            contentCoordinator: persistence.contentCoordinator,
            timelineRepository: persistence.timelineRepository,
            projectionController: persistence.homeFeedProjection,
            backwardRequestRegistry: registry,
            syncPlanner: syncPlanner,
            packetInstaller: installer,
            gapStatePersistence: persistence.backfillPersistence
        )
        return HomeTimelineStoreBackwardCoordination(
            registry: registry,
            coordinator: coordinator,
            gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow(
                requester: coordinator
            ),
            feedSyncCoordinator: HomeTimelineFeedSyncCoordinator(
                eventStore: input.eventStore,
                backwardRequestRegistry: registry
            )
        )
    }
}
