import AstrenzaCore

struct HomeTimelineRelayRuntimeConfigurationIdentity: Equatable {
    let accountID: String
    let lifecycleGeneration: UInt64
    let resolvedRelays: [String]
    let followedPubkeys: [String]
    let contactListEventID: String?
}

struct HomeTimelineRelayRuntimeConfigurationRequest {
    let identity: HomeTimelineRelayRuntimeConfigurationIdentity
    let account: NostrAccount
    let contactItems: [NostrContactListItem]
    let defaultRelayURLs: [String]
    let policy: NostrSyncPolicy
    let forceInstall: Bool
}

struct HomeTimelineRelayRuntimeFeedPreparation {
    let context: HomeFeedRuntimeContext
    let newestCreatedAt: Int?
    let newestCreatedAtByRelay: [String: Int]?
    let initialCreatedAt: Int?
}

@MainActor
struct HomeTimelineRelayRuntimeConfigurationHandlers {
    typealias CurrentIdentity = @MainActor @Sendable () -> HomeTimelineRelayRuntimeConfigurationIdentity?
    typealias DependencyPreparation = @MainActor @Sendable () async -> Void
    typealias FeedPreparation = @MainActor @Sendable () -> HomeTimelineRelayRuntimeFeedPreparation?
    typealias InstallPreparation = @MainActor @Sendable (
        _ packets: [NostrREQPacket],
        _ runtimeKeys: Set<RuntimeSubscriptionKey>,
        _ context: HomeFeedRuntimeContext
    ) -> Void
    typealias FeedContextValidity = @MainActor @Sendable (_ context: HomeFeedRuntimeContext) -> Bool
    typealias FailureHandler = @MainActor @Sendable (_ message: String) -> Void

    let currentIdentity: CurrentIdentity
    let prepareDependencies: DependencyPreparation
    let prepareFeed: FeedPreparation
    let prepareInstall: InstallPreparation
    let isFeedContextCurrent: FeedContextValidity
    let didFail: FailureHandler
}

struct HomeTimelineRelayRuntimeConfigurationClient {
    typealias Readiness = @MainActor @Sendable () async -> Bool
    typealias TrafficConfiguration = @MainActor @Sendable (
        _ accountID: String,
        _ policy: NostrSyncPolicy
    ) async -> Void
    typealias RelayUpdate = @MainActor @Sendable (_ relayURLs: [String]) async -> Void
    typealias RelayInstallation = @MainActor @Sendable (_ relayURLs: [String]) async throws -> Void
    typealias ForwardInstallation = @MainActor @Sendable (_ packets: [NostrREQPacket]) async throws -> Void

    let waitUntilReady: Readiness
    let setTrafficContext: TrafficConfiguration
    let updateProfileRelayURLs: RelayUpdate
    let setDefaultRelays: RelayInstallation
    let installForward: ForwardInstallation
}

@MainActor
final class HomeTimelineRelayRuntimeConfigurator {
    private let client: HomeTimelineRelayRuntimeConfigurationClient?
    private let syncPlanner: HomeTimelineSyncPlanner
    private var sequence: UInt64 = 0
    private var installedForwardPackets: [NostrREQPacket] = []

    init(
        client: HomeTimelineRelayRuntimeConfigurationClient?,
        syncPlanner: HomeTimelineSyncPlanner = HomeTimelineSyncPlanner()
    ) {
        self.client = client
        self.syncPlanner = syncPlanner
    }

    convenience init(
        relayRuntime: NostrRelayRuntime?,
        runtimeEventPump: HomeTimelineRuntimeEventPump,
        dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator,
        syncPlanner: HomeTimelineSyncPlanner
    ) {
        let client = relayRuntime.map { relayRuntime in
            HomeTimelineRelayRuntimeConfigurationClient(
                waitUntilReady: {
                    await runtimeEventPump.waitUntilReady()
                },
                setTrafficContext: { accountID, policy in
                    await relayRuntime.setTrafficContext(accountID: accountID, policy: policy)
                },
                updateProfileRelayURLs: { relayURLs in
                    await dependencyCoordinator.updateProfileRelayURLs(relayURLs)
                },
                setDefaultRelays: { relayURLs in
                    try await relayRuntime.setDefaultRelays(relayURLs)
                },
                installForward: { packets in
                    try await relayRuntime.installForward(
                        packets,
                        replacingGroupIDsWithPrefix: HomeTimelineSyncPlanner.homeForwardGroupPrefix
                    )
                }
            )
        }
        self.init(client: client, syncPlanner: syncPlanner)
    }

    func reset() {
        sequence &+= 1
        installedForwardPackets = []
    }

    func configure(
        _ request: HomeTimelineRelayRuntimeConfigurationRequest,
        handlers: HomeTimelineRelayRuntimeConfigurationHandlers
    ) async {
        guard let client else { return }
        sequence &+= 1
        let expectedSequence = sequence

        func remainsCurrent() -> Bool {
            !Task.isCancelled &&
                sequence == expectedSequence &&
                handlers.currentIdentity() == request.identity
        }

        do {
            guard await client.waitUntilReady() else { return }
            guard remainsCurrent() else { return }
            await client.setTrafficContext(request.identity.accountID, request.policy)
            guard remainsCurrent() else { return }
            await client.updateProfileRelayURLs(request.defaultRelayURLs)
            guard remainsCurrent() else { return }
            try await client.setDefaultRelays(request.defaultRelayURLs)
            guard remainsCurrent() else { return }
            await handlers.prepareDependencies()
            guard remainsCurrent(),
                  let preparation = handlers.prepareFeed()
            else { return }

            let plan = syncPlanner.forwardPlan(
                account: request.account,
                followedPubkeys: request.identity.followedPubkeys,
                contactItems: request.contactItems,
                newestCreatedAt: preparation.newestCreatedAt,
                newestCreatedAtByRelay: preparation.newestCreatedAtByRelay,
                initialCreatedAt: preparation.initialCreatedAt,
                relayURLs: request.identity.resolvedRelays,
                policy: request.policy
            )
            guard remainsCurrent() else { return }
            let scopedPackets = Self.feedScopedPackets(
                plan.packets,
                context: preparation.context
            )
            guard request.forceInstall || installedForwardPackets != scopedPackets else { return }
            handlers.prepareInstall(
                scopedPackets,
                Self.runtimeKeys(
                    packets: scopedPackets,
                    defaultRelayURLs: request.defaultRelayURLs
                ),
                preparation.context
            )
            try await client.installForward(scopedPackets)
            guard remainsCurrent(),
                  handlers.isFeedContextCurrent(preparation.context)
            else { return }
            installedForwardPackets = scopedPackets
        } catch {
            guard remainsCurrent() else { return }
            handlers.didFail(String(describing: error))
        }
    }

    private static func feedScopedPackets(
        _ packets: [NostrREQPacket],
        context: HomeFeedRuntimeContext
    ) -> [NostrREQPacket] {
        let specificationToken = String(context.specificationHash.prefix(12))
        return packets.map { packet in
            NostrREQPacket(
                strategy: packet.strategy,
                subscriptionID: packet.subscriptionID,
                groupID: "\(packet.groupID)-feed-r\(context.revision)-\(specificationToken)",
                filters: packet.filters,
                relayURLs: packet.relayURLs
            )
        }
    }

    private static func runtimeKeys(
        packets: [NostrREQPacket],
        defaultRelayURLs: [String]
    ) -> Set<RuntimeSubscriptionKey> {
        Set(packets.flatMap { packet in
            NostrREQScheduler.forwardChunks(packet)
        }.flatMap { packet in
            let relayURLs = packet.relayURLs.isEmpty
                ? defaultRelayURLs
                : defaultRelayURLs.filter { packet.relayURLs.contains($0) }
            return relayURLs.map { relayURL in
                RuntimeSubscriptionKey(
                    relayURL: relayURL,
                    subscriptionID: packet.subscriptionID
                )
            }
        })
    }
}
