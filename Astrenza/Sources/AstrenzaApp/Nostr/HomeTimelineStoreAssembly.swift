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
    let loadWorkflow: HomeTimelineLoadWorkflow
    let eventStore: NostrEventStore?
    let contentCoordinator: HomeTimelineContentCoordinator
    let runtimeEventWorkflow: HomeTimelineRuntimeEventWorkflow
    let runtimeWorkflow: HomeTimelineRuntimeWorkflow
    let gapBackfillWorkflow: HomeTimelineGapBackfillWorkflow
    let backwardCompletionWorkflow: HomeTimelineBackwardCompletionWorkflow
    let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    let filterCoordinator: HomeTimelineFilterCoordinator
    let listProjectionCache: HomeTimelineListProjectionCache
    let activityCoordinator: HomeTimelineActivityCoordinator
    let presentationCoordinator: HomeTimelinePresentationCoordinator
    let pendingEventsWorkflow: HomeTimelinePendingEventsWorkflow
    let materializationCoordinator: HomeTimelineMaterializationCoordinator
    let pendingEventBuffer: HomeTimelinePendingEventBuffer
    let backwardRequestRegistry: HomeTimelineBackwardRequestRegistry
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let accountResetWorkflow: HomeTimelineAccountResetWorkflow
    let relayStatusCoordinator: HomeTimelineRelayStatusCoordinator
    let linkPreviewCoordinator: HomeTimelineLinkPreviewCoordinator
    let readStateCoordinator: HomeTimelineReadStateCoordinator
    let timelineRepository: HomeTimelineRepository
    let homeFeedProjection: HomeFeedProjectionController
    let stateWorkflow: HomeTimelineStateWorkflow
    let publishWorkflow: HomeTimelinePublishWorkflow?
    let localMutationCoordinator: HomeTimelineLocalMutationCoordinator?
    let relayRuntime: NostrRelayRuntime?
    let outboxCoordinator: HomeTimelineOutboxCoordinator
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
    let stateWorkflow: HomeTimelineStateWorkflow
    let accountStartWorkflow: HomeTimelineAccountStartWorkflow
    let pendingEventsWorkflow: HomeTimelinePendingEventsWorkflow
    let remoteLoadCoordinator: HomeTimelineRemoteLoadCoordinator
    let loadWorkflow: HomeTimelineLoadWorkflow
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
            loadWorkflow: graph.features.loadWorkflow,
            eventStore: input.eventStore,
            contentCoordinator: graph.persistence.contentCoordinator,
            runtimeEventWorkflow: graph.runtimeEvents.runtimeEventWorkflow,
            runtimeWorkflow: HomeTimelineRuntimeWorkflow(
                session: graph.runtimeEvents.runtimeSessionCoordinator,
                setup: graph.relayRuntime.runtimeSetupCoordinator,
                packetRouter: graph.relayRuntime.runtimePacketWorkflow
            ),
            gapBackfillWorkflow: graph.coordination.gapBackfillWorkflow,
            backwardCompletionWorkflow: graph.runtimeEvents.backwardCompletionWorkflow,
            dependencyCoordinator: graph.coordination.dependencyCoordinator,
            filterCoordinator: graph.persistence.filterCoordinator,
            listProjectionCache: graph.coordination.listProjectionCache,
            activityCoordinator: graph.coordination.activityCoordinator,
            presentationCoordinator: graph.coordination.presentationCoordinator,
            pendingEventsWorkflow: graph.features.pendingEventsWorkflow,
            materializationCoordinator: graph.coordination.materializationCoordinator,
            pendingEventBuffer: graph.coordination.pendingEventBuffer,
            backwardRequestRegistry: graph.coordination.backwardRequestRegistry,
            feedSyncCoordinator: graph.coordination.feedSyncCoordinator,
            lifecycleCoordinator: graph.coordination.lifecycleCoordinator,
            accountStartWorkflow: graph.features.accountStartWorkflow,
            accountResetWorkflow: graph.accountResetWorkflow,
            relayStatusCoordinator: graph.relayRuntime.relayStatusCoordinator,
            linkPreviewCoordinator: graph.features.linkPreviewCoordinator,
            readStateCoordinator: graph.features.readStateCoordinator,
            timelineRepository: graph.persistence.timelineRepository,
            homeFeedProjection: graph.persistence.homeFeedProjection,
            stateWorkflow: graph.features.stateWorkflow,
            publishWorkflow: graph.features.publishWorkflow,
            localMutationCoordinator: graph.features.localMutationCoordinator,
            relayRuntime: input.relayRuntime,
            outboxCoordinator: graph.features.outboxCoordinator
        )
    }
}
