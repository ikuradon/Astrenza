import AstrenzaCore

@MainActor
enum HomeTimelineStoreFactory {
    static func make(
        timelineLoader: NostrHomeTimelineLoader = NostrHomeTimelineLoader(),
        eventStore: NostrEventStore? = try? NostrEventStore.applicationSupport(
            appDirectory: "Astrenza"
        ),
        relayRuntime: NostrRelayRuntime? = nil,
        linkPreviewResolver: NostrLinkPreviewResolver? = nil,
        viewportStateRestorer: any HomeTimelineViewportStateRestoring =
            TimelineRestoreStore(),
        outboxPublisher: NostrOutboxRelayPublisher =
            NostrOutboxRelayPublisher(),
        localMutationPersistence:
            (any HomeTimelineLocalMutationPersisting)? = nil,
        syncPolicy: NostrSyncPolicy = .default(
            networkType: .unknown,
            lowPowerMode: false
        ),
        syncPolicySettingsStore: NostrSyncPolicySettingsStore = .shared
    ) -> NostrHomeTimelineStore {
        let components = HomeTimelineStoreAssembly.assemble(
            HomeTimelineStoreAssemblyInput(
                timelineLoader: timelineLoader,
                eventStore: eventStore,
                relayRuntime: relayRuntime,
                linkPreviewResolver: linkPreviewResolver,
                viewportStateRestorer: viewportStateRestorer,
                outboxPublisher: outboxPublisher,
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
