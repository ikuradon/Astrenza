import AstrenzaCore

@MainActor
enum HomeTimelineStoreFactory {
    static func make(
        timelineLoader: NostrHomeTimelineLoader? = nil,
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
        do {
            return makeStore(
                timelineLoader: timelineLoader,
                eventStore: try NostrEventStore.applicationSupport(
                    appDirectory: "Astrenza"
                ),
                startupFailureMessage: nil,
                relayRuntime: relayRuntime,
                linkPreviewResolver: linkPreviewResolver,
                viewportStateRestorer: viewportStateRestorer,
                outboxPublisher: outboxPublisher,
                localMutationPersistence: localMutationPersistence,
                syncPolicy: syncPolicy,
                syncPolicySettingsStore: syncPolicySettingsStore
            )
        } catch {
            return makeStore(
                timelineLoader: timelineLoader,
                eventStore: nil,
                startupFailureMessage:
                    "Database unavailable: \(error.localizedDescription)",
                relayRuntime: relayRuntime,
                linkPreviewResolver: linkPreviewResolver,
                viewportStateRestorer: viewportStateRestorer,
                outboxPublisher: outboxPublisher,
                localMutationPersistence: localMutationPersistence,
                syncPolicy: syncPolicy,
                syncPolicySettingsStore: syncPolicySettingsStore
            )
        }
    }

    static func make(
        timelineLoader: NostrHomeTimelineLoader? = nil,
        eventStore: NostrEventStore?,
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
        makeStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            startupFailureMessage: nil,
            relayRuntime: relayRuntime,
            linkPreviewResolver: linkPreviewResolver,
            viewportStateRestorer: viewportStateRestorer,
            outboxPublisher: outboxPublisher,
            localMutationPersistence: localMutationPersistence,
            syncPolicy: syncPolicy,
            syncPolicySettingsStore: syncPolicySettingsStore
        )
    }

    private static func makeStore(
        timelineLoader: NostrHomeTimelineLoader?,
        eventStore: NostrEventStore?,
        startupFailureMessage: String?,
        relayRuntime: NostrRelayRuntime?,
        linkPreviewResolver: NostrLinkPreviewResolver?,
        viewportStateRestorer: any HomeTimelineViewportStateRestoring,
        outboxPublisher: NostrOutboxRelayPublisher?,
        localMutationPersistence:
            (any HomeTimelineLocalMutationPersisting)?,
        syncPolicy: NostrSyncPolicy,
        syncPolicySettingsStore: NostrSyncPolicySettingsStore
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
                startupFailureMessage: startupFailureMessage,
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
            ),
            blossomServerResolver: NostrBlossomServerResolver(
                eventStore: eventStore,
                relayClient: resolvedTimelineLoader.relayClient
            ),
            profilePageResolver: NostrProfilePageResolver(
                eventStore: eventStore,
                relayClient: resolvedTimelineLoader.relayClient
            )
        )
    }
}
