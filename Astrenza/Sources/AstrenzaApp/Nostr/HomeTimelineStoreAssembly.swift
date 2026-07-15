import AstrenzaCore

struct HomeTimelineStoreAssemblyInput {
    let timelineLoader: NostrHomeTimelineLoader
    let eventStore: NostrEventStore?
    let relayRuntime: NostrRelayRuntime?
    let linkPreviewResolver: NostrLinkPreviewResolver?
    let outboxPublisher: NostrOutboxRelayPublisher
    let localMutationPersistence: (any HomeTimelineLocalMutationPersisting)?
    let syncPolicySettingsStore: NostrSyncPolicySettingsStore
}

struct HomeTimelineStoreComponents {
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow
    let viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow
    let eventStore: NostrEventStore?
    let dataInteractionWorkflow: HomeTimelineDataInteractionWorkflow
    let runtimeInteractionWorkflow: HomeTimelineRuntimeInteractionWorkflow
    let gapBackfillInteractionWorkflow:
        HomeGapBackfillInteractionWorkflow
    let backwardInteractionWorkflow: HomeTimelineBackwardInteractionWorkflow
    let filterInteractionWorkflow:
        HomeTimelineFilterInteractionWorkflow
    let queryInteractionWorkflow:
        HomeTimelineQueryInteractionWorkflow
    let activityInteractionWorkflow:
        HomeTimelineActivityInteractionWorkflow
    let presentationWorkflow: HomeTimelinePresentationWorkflow
    let projectionInteractionWorkflow:
        HomeProjectionInteractionWorkflow
    let syncInteractionWorkflow: HomeTimelineSyncInteractionWorkflow
    let accountStartInteractionWorkflow:
        HomeAccountStartInteractionWorkflow
    let accountResetInteractionWorkflow:
        HomeAccountResetInteractionWorkflow
    let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    let publishInteractionWorkflow: HomeTimelinePublishInteractionWorkflow?
    let localMutationInteractionWorkflow:
        HomeLocalMutationInteractionWorkflow?
    let relayRuntime: NostrRelayRuntime?
}

struct HomeTimelineStorePersistenceGraph {
    let persistenceWorker: HomeTimelinePersistenceWorker?
    let contentCoordinator: HomeTimelineContentCoordinator
    let eventIngestor: HomeTimelineEventIngestor
    let backfillPersistence: HomeTimelineBackfillPersistence
    let timelineRepository: HomeTimelineRepository
    let gapReconciliationCoordinator: HomeTimelineGapReconciliationCoordinator
    let homeFeedProjection: HomeFeedProjectionController
    let snapshotCoordinator: HomeTimelineSnapshotCoordinator
    let filterCoordinator: HomeTimelineFilterCoordinator
}

struct HomeTimelineStoreCoordinationGraph {
    let syncPlanner: HomeTimelineSyncPlanner
    let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    let backwardRequestCoordinator: HomeTimelineBackwardRequestCoordinator
    let gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    let listProjectionCache: HomeTimelineListProjectionCache
    let activityCoordinator: HomeTimelineActivityCoordinator
    let presentationCoordinator: HomeTimelinePresentationCoordinator
    let materializationCoordinator: HomeTimelineMaterializationCoordinator
    let pendingEventBuffer: HomeTimelinePendingEventBuffer
    let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
}

struct HomeTimelineStoreRuntimeEventGraph {
    let backwardCompletionWorkflow: HomeTimelineBackwardCompletionWorkflow
    let runtimeEventWorkflow: HomeTimelineRuntimeEventWorkflow
    let runtimeEventPump: HomeTimelineRuntimeEventPump
    let runtimeSessionCoordinator: HomeTimelineRuntimeSessionCoordinator
}

struct HomeTimelineStoreRelayRuntimeGraph {
    let runtimeShutdownCoordinator: HomeTimelineRuntimeShutdownCoordinator
    let runtimeSetupCoordinator: HomeTimelineRuntimeSetupCoordinator
    let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    let runtimePacketWorkflow: HomeTimelineRuntimePacketWorkflow
}

struct HomeTimelineStoreFeatureGraph {
    let stateInteractionWorkflow: HomeTimelineStateInteractionWorkflow
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let presentationWorkflow: HomeTimelinePresentationWorkflow
    let viewportInteractionWorkflow: HomeTimelineViewportInteractionWorkflow
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let loadInteractionWorkflow: HomeTimelineLoadInteractionWorkflow
    let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    let readStateCoordinator: HomeTimelineReadStateCoordinator
    let outboxCoordinator: HomeTimelineOutboxCoordinator
    let publishWorkflow: HomeTimelinePublishWorkflow?
    let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
}

struct HomeTimelineStoreAssemblyGraph {
    let persistence: HomeTimelineStorePersistenceGraph
    let coordination: HomeTimelineStoreCoordinationGraph
    let runtimeEvents: HomeTimelineStoreRuntimeEventGraph
    let relayRuntime: HomeTimelineStoreRelayRuntimeGraph
    let features: HomeTimelineStoreFeatureGraph
    let accountResetWorkflow: HomeTimelineAccountResetWorkflow
}

@MainActor
enum HomeTimelineStoreAssembly {
    static func assemble(
        _ input: HomeTimelineStoreAssemblyInput
    ) -> HomeTimelineStoreComponents {
        let persistence = makePersistence(input)
        let coordination = makeCoordination(input, persistence: persistence)
        let runtimeEvents = makeRuntimeEvents(
            input,
            persistence: persistence,
            coordination: coordination
        )
        let relayRuntime = makeRelayRuntime(
            input,
            persistence: persistence,
            coordination: coordination,
            runtimeEvents: runtimeEvents
        )
        let features = makeFeatures(
            input,
            persistence: persistence,
            coordination: coordination,
            relayRuntime: relayRuntime
        )
        let accountResetWorkflow = makeAccountResetWorkflow(
            persistence: persistence,
            coordination: coordination,
            runtimeEvents: runtimeEvents,
            relayRuntime: relayRuntime,
            features: features
        )
        return makeComponents(
            input: input,
            graph: HomeTimelineStoreAssemblyGraph(
                persistence: persistence,
                coordination: coordination,
                runtimeEvents: runtimeEvents,
                relayRuntime: relayRuntime,
                features: features,
                accountResetWorkflow: accountResetWorkflow
            )
        )
    }

    private static func makeComponents(
        input: HomeTimelineStoreAssemblyInput,
        graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineStoreComponents {
        HomeTimelineStoreComponents(
            remoteLoadCoordinator: graph.features.remoteLoadCoordinator,
            loadInteractionWorkflow: graph.features.loadInteractionWorkflow,
            viewportInteractionWorkflow:
                graph.features.viewportInteractionWorkflow,
            eventStore: input.eventStore,
            dataInteractionWorkflow: makeDataInteraction(from: graph),
            runtimeInteractionWorkflow: HomeTimelineRuntimeInteractionWorkflow(
                runtime: HomeTimelineRuntimeWorkflow(
                    session: graph.runtimeEvents.runtimeSessionCoordinator,
                    setup: graph.relayRuntime.runtimeSetupCoordinator,
                    packetRouter: graph.relayRuntime.runtimePacketWorkflow
                ),
                events: graph.runtimeEvents.runtimeEventWorkflow,
                lifecycle: graph.coordination.lifecycleCoordinator,
                relayStatus: graph.relayRuntime.relayStatusCoordinator
            ),
            gapBackfillInteractionWorkflow: makeGapBackfillInteraction(from: graph),
            backwardInteractionWorkflow: HomeTimelineBackwardInteractionWorkflow(
                backward: graph.runtimeEvents.backwardCompletionWorkflow
            ),
            filterInteractionWorkflow: makeFilterInteraction(from: graph),
            queryInteractionWorkflow: makeQueryInteraction(from: graph),
            activityInteractionWorkflow:
                makeActivityInteraction(from: graph),
            presentationWorkflow: graph.features.presentationWorkflow,
            projectionInteractionWorkflow:
                makeProjectionInteraction(from: graph),
            syncInteractionWorkflow: makeSyncInteraction(from: graph),
            accountStartInteractionWorkflow:
                HomeAccountStartInteractionWorkflow(
                    accountStart: graph.features.accountStartWorkflow
                ),
            accountResetInteractionWorkflow:
                HomeAccountResetInteractionWorkflow(
                    accountReset: graph.accountResetWorkflow
                ),
            stateInteractionWorkflow: graph.features.stateInteractionWorkflow,
            publishInteractionWorkflow: graph.features.publishWorkflow.map {
                HomeTimelinePublishInteractionWorkflow(publish: $0)
            },
            localMutationInteractionWorkflow: makeLocalMutationInteraction(from: graph),
            relayRuntime: input.relayRuntime
        )
    }

    private static func makeGapBackfillInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeGapBackfillInteractionWorkflow {
        HomeGapBackfillInteractionWorkflow(
            gapBackfill: graph.coordination.gapBackfillWorkflow
        )
    }

    private static func makeSyncInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineSyncInteractionWorkflow {
        HomeTimelineSyncInteractionWorkflow(
            feedSync: graph.coordination.feedSyncCoordinator,
            backwardRequests: graph.coordination.backwardRequestRegistry,
            relayStatus: graph.relayRuntime.relayStatusCoordinator
        )
    }

    private static func makeFilterInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineFilterInteractionWorkflow {
        HomeTimelineFilterInteractionWorkflow(
            filter: graph.persistence.filterCoordinator
        )
    }

    private static func makeQueryInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineQueryInteractionWorkflow {
        HomeTimelineQueryInteractionWorkflow(
            repository: graph.persistence.timelineRepository,
            listProjectionCache: graph.coordination.listProjectionCache
        )
    }

    private static func makeActivityInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineActivityInteractionWorkflow {
        HomeTimelineActivityInteractionWorkflow(
            activity: graph.coordination.activityCoordinator
        )
    }

    private static func makeProjectionInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeProjectionInteractionWorkflow {
        HomeProjectionInteractionWorkflow(
            projection: graph.persistence.homeFeedProjection,
            readState: graph.features.readStateCoordinator,
            materialization: graph.coordination.materializationCoordinator
        )
    }

    private static func makeDataInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeTimelineDataInteractionWorkflow {
        HomeTimelineDataInteractionWorkflow(
            content: graph.persistence.contentCoordinator,
            dependencies: graph.coordination.dependencyCoordinator
        )
    }

    private static func makeLocalMutationInteraction(
        from graph: HomeTimelineStoreAssemblyGraph
    ) -> HomeLocalMutationInteractionWorkflow? {
        graph.features.localMutationCoordinator.map {
            HomeLocalMutationInteractionWorkflow(localMutation: $0)
        }
    }
}
