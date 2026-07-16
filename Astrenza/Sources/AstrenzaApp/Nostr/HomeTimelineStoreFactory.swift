import AstrenzaCore

@MainActor
enum HomeTimelineStoreFactory {
    static func make(
        timelineLoader: NostrHomeTimelineLoader? = nil,
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(
            appDirectory: "Astrenza"
        ),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil,
        viewportStateRestorer: any HomeTimelineViewportStateRestoring =
            TimelineRestoreStore(),
        outboxPublisher: NostrOutboxRelayPublisher? = nil,
        localMutationPersistence:
            (any HomeTimelineLocalMutationPersisting)? = nil,
        syncPolicy: NostrSyncPolicy = .default(
            networkType: .unknown,
            lowPowerMode: false
        ),
        syncPolicySettingsStore: NostrSyncPolicySettingsStore = .shared
    ) -> NostrHomeTimelineStore {
        let resolvedTimelineLoader = timelineLoader ?? relayRuntime.map {
            NostrHomeTimelineLoader(
                relayClient: NostrRelayRuntimeClient(runtime: $0)
            )
        } ?? NostrHomeTimelineLoader()
        let resolvedOutboxPublisher = outboxPublisher ?? relayRuntime.map {
            NostrOutboxRelayPublisher(relayRuntime: $0)
        } ?? NostrOutboxRelayPublisher()
        let components = HomeTimelineStoreAssembly.assemble(
            HomeTimelineStoreAssemblyInput(
                timelineLoader: resolvedTimelineLoader,
                eventStore: eventStore,
                relayRuntime: relayRuntime,
                linkPreviewResolver: linkPreviewResolver,
                viewportStateRestorer: viewportStateRestorer,
                outboxPublisher: resolvedOutboxPublisher,
                localMutationPersistence: localMutationPersistence,
                initialSyncPolicy: syncPolicy,
                syncPolicySettingsStore: syncPolicySettingsStore
            )
        )
        return NostrHomeTimelineStore(
            composition: HomeStoreComposition.make(
                components: components
            )
        )
    }
}
