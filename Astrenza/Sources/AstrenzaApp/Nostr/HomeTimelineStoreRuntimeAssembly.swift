import AstrenzaCore

@MainActor
extension HomeTimelineStoreAssembly {
    static func makeRuntimeEvents(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph
    ) -> HomeTimelineStoreRuntimeEventGraph {
        let backwardCompletionWorkflow = makeBackwardCompletionWorkflow(
            persistence: persistence,
            coordination: coordination
        )
        let runtimeEventWorkflow = makeRuntimeEventWorkflow(
            persistence: persistence,
            coordination: coordination
        )
        let runtimeEventPump = HomeTimelineRuntimeEventPump()
        let runtimeStream: HomeTimelineRuntimeSessionCoordinator.RuntimeStream?
        if let relayRuntime = input.relayRuntime {
            runtimeStream = { await relayRuntime.events() }
        } else {
            runtimeStream = nil
        }
        let runtimeSessionCoordinator = HomeTimelineRuntimeSessionCoordinator(
            runtimeEventPump: runtimeEventPump,
            runtimeStream: runtimeStream,
            profileUpdateObserver: coordination.dependencyCoordinator,
            profileUpdateApplication: runtimeEventWorkflow,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        return HomeTimelineStoreRuntimeEventGraph(
            backwardCompletionWorkflow: backwardCompletionWorkflow,
            runtimeEventWorkflow: runtimeEventWorkflow,
            runtimeEventPump: runtimeEventPump,
            runtimeSessionCoordinator: runtimeSessionCoordinator
        )
    }

    static func makeRelayRuntime(
        _ input: HomeTimelineStoreAssemblyInput,
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph,
        runtimeEvents: HomeTimelineStoreRuntimeEventGraph
    ) -> HomeTimelineStoreRelayRuntimeGraph {
        let runtimeShutdownCoordinator = HomeTimelineRuntimeShutdownCoordinator(
            scheduler: HomeTimelineRelayRuntimeTerminator(),
            runtimeSession: runtimeEvents.runtimeSessionCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator,
            terminateRuntime: runtimeTermination(input.relayRuntime)
        )
        let configurator = HomeTimelineRelayRuntimeConfigurator(
            relayRuntime: input.relayRuntime,
            runtimeEventPump: runtimeEvents.runtimeEventPump,
            dependencyCoordinator: coordination.dependencyCoordinator,
            syncPlanner: coordination.syncPlanner
        )
        let runtimeSetupCoordinator = HomeTimelineRuntimeSetupCoordinator(
            configurator: configurator,
            contentCoordinator: persistence.contentCoordinator,
            dependencyCoordinator: coordination.dependencyCoordinator,
            projectionController: persistence.homeFeedProjection,
            feedSyncCoordinator: coordination.feedSyncCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator,
            timelineRepository: persistence.timelineRepository
        )
        let relayStatusCoordinator = HomeTimelineRelayStatusCoordinator(
            diagnostics: HomeTimelineRelayDiagnosticsLedger(
                eventStore: input.eventStore,
                persistenceWorker: persistence.persistenceWorker
            )
        )
        let packetCoordinator = HomeTimelineRuntimePacketCoordinator(
            feedSyncCoordinator: coordination.feedSyncCoordinator,
            relayStatusCoordinator: relayStatusCoordinator
        )
        return HomeTimelineStoreRelayRuntimeGraph(
            runtimeShutdownCoordinator: runtimeShutdownCoordinator,
            runtimeSetupCoordinator: runtimeSetupCoordinator,
            relayStatusCoordinator: relayStatusCoordinator,
            runtimePacketWorkflow: HomeTimelineRuntimePacketWorkflow(
                packetHandler: packetCoordinator
            )
        )
    }

    private static func makeBackwardCompletionWorkflow(
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph
    ) -> HomeTimelineBackwardCompletionWorkflow {
        let completionCoordinator = HomeTimelineBackwardCompletionApplicationCoordinator(
            backwardRequestRegistry: coordination.backwardRequestRegistry,
            dependencyCoordinator: coordination.dependencyCoordinator,
            contentCoordinator: persistence.contentCoordinator,
            projectionController: persistence.homeFeedProjection,
            persistence: persistence.backfillPersistence
        )
        let gapApplication = HomeTimelineGapReconciliationApplicationCoordinator(
            reconciliationCoordinator: persistence.gapReconciliationCoordinator,
            contentCoordinator: persistence.contentCoordinator,
            timelineRepository: persistence.timelineRepository,
            projectionController: persistence.homeFeedProjection,
            backwardRequestRegistry: coordination.backwardRequestRegistry,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        return HomeTimelineBackwardCompletionWorkflow(
            completionCoordinator: completionCoordinator,
            gapReconciliation: gapApplication
        )
    }

    private static func makeRuntimeEventWorkflow(
        persistence: HomeTimelineStorePersistenceGraph,
        coordination: HomeTimelineStoreCoordinationGraph
    ) -> HomeTimelineRuntimeEventWorkflow {
        let eventProcessor = HomeTimelineRuntimeEventProcessor(
            eventIngestor: persistence.eventIngestor,
            backwardRequestRegistry: coordination.backwardRequestRegistry,
            feedSyncCoordinator: coordination.feedSyncCoordinator
        )
        let eventApplication = HomeTimelineRuntimeEventApplicationCoordinator(
            contentCoordinator: persistence.contentCoordinator,
            dependencyCoordinator: coordination.dependencyCoordinator,
            listProjectionCache: coordination.listProjectionCache,
            pendingEventBuffer: coordination.pendingEventBuffer,
            backwardRequestRegistry: coordination.backwardRequestRegistry,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        let eventCoordinator = HomeTimelineRuntimeEventCoordinator(
            processor: eventProcessor,
            applicationCoordinator: eventApplication,
            contentCoordinator: persistence.contentCoordinator,
            projectionController: persistence.homeFeedProjection,
            feedEventRecorder: coordination.feedSyncCoordinator,
            lifecycleCoordinator: coordination.lifecycleCoordinator
        )
        return HomeTimelineRuntimeEventWorkflow(coordinator: eventCoordinator)
    }

    private static func runtimeTermination(
        _ relayRuntime: NostrRelayRuntime?
    ) -> HomeTimelineRuntimeShutdownCoordinator.RuntimeTermination? {
        guard let relayRuntime else { return nil }
        return { await relayRuntime.terminate() }
    }
}
