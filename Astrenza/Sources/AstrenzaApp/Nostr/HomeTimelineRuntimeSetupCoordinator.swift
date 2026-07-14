import AstrenzaCore

@MainActor
protocol HomeTimelineRelayRuntimeConfiguring: AnyObject {
    func reset()

    func configure(
        _ request: HomeTimelineRelayRuntimeConfigurationRequest,
        handlers: HomeTimelineRelayRuntimeConfigurationHandlers
    ) async
}

extension HomeTimelineRelayRuntimeConfigurator: HomeTimelineRelayRuntimeConfiguring {}

struct HomeTimelineRuntimeSetupRequest: Equatable, Sendable {
    let account: NostrAccount
    let defaultRelayURLs: [String]
    let policy: NostrSyncPolicy
    let hasRelayRuntime: Bool
    let isTerminating: Bool
    let forceInstall: Bool
}

struct HomeTimelineRuntimeSetupDiagnostic: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let message: String
}

enum HomeTimelineRuntimeSetupCommand: Equatable, Sendable {
    case setRealtime(Bool)
    case recordDiagnostic(HomeTimelineRuntimeSetupDiagnostic)
}

struct HomeTimelineRuntimeSetupHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRuntimeSetupCommand
    ) -> Void

    let perform: CommandHandler
}

@MainActor
final class HomeTimelineRuntimeSetupCoordinator {
    private let configurator: any HomeTimelineRelayRuntimeConfiguring
    private let contentCoordinator: HomeTimelineContentCoordinator
    private let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    private let projectionController: HomeFeedProjectionController
    private let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let timelineRepository: HomeTimelineRepository

    init(
        configurator: any HomeTimelineRelayRuntimeConfiguring,
        contentCoordinator: HomeTimelineContentCoordinator,
        dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator,
        projectionController: HomeFeedProjectionController,
        feedSyncCoordinator: HomeTimelineFeedSyncCoordinator,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator,
        timelineRepository: HomeTimelineRepository
    ) {
        self.configurator = configurator
        self.contentCoordinator = contentCoordinator
        self.dependencyCoordinator = dependencyCoordinator
        self.projectionController = projectionController
        self.feedSyncCoordinator = feedSyncCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.timelineRepository = timelineRepository
    }

    func reset() {
        configurator.reset()
    }

    func configure(
        _ request: HomeTimelineRuntimeSetupRequest,
        handlers: HomeTimelineRuntimeSetupHandlers
    ) async {
        guard request.hasRelayRuntime,
              !request.isTerminating,
              lifecycleCoordinator.hasCompletedRuntimeBootstrap,
              let identity = currentIdentity(accountID: request.account.pubkey),
              !identity.resolvedRelays.isEmpty
        else { return }

        let content = contentCoordinator.snapshot
        await configurator.configure(
            HomeTimelineRelayRuntimeConfigurationRequest(
                identity: identity,
                account: request.account,
                contactItems: NostrContactList.items(from: content.contactListEvent),
                defaultRelayURLs: request.defaultRelayURLs,
                policy: request.policy,
                forceInstall: request.forceInstall
            ),
            handlers: configurationHandlers(
                account: request.account,
                identity: identity,
                handlers: handlers
            )
        )
    }

    private func configurationHandlers(
        account: NostrAccount,
        identity: HomeTimelineRelayRuntimeConfigurationIdentity,
        handlers: HomeTimelineRuntimeSetupHandlers
    ) -> HomeTimelineRelayRuntimeConfigurationHandlers {
        HomeTimelineRelayRuntimeConfigurationHandlers(
            currentIdentity: { [weak self] in
                self?.currentIdentity(accountID: account.pubkey)
            },
            prepareDependencies: { [weak self] in
                guard let self else { return }
                await dependencyCoordinator.ensureProfiles(
                    for: contentCoordinator.noteEvents
                )
            },
            prepareFeed: { [weak self] in
                self?.prepareFeed(account: account)
            },
            prepareInstall: { [weak self] packets, runtimeKeys, context in
                self?.prepareInstall(
                    packets: packets,
                    runtimeKeys: runtimeKeys,
                    context: context,
                    handlers: handlers
                )
            },
            isFeedContextCurrent: { [weak self] context in
                self?.isFeedContextCurrent(context, accountID: account.pubkey) == true
            },
            didFail: { message in
                handlers.perform(.recordDiagnostic(HomeTimelineRuntimeSetupDiagnostic(
                    relayURL: identity.resolvedRelays.first ?? "runtime",
                    subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                    message: message
                )))
            }
        )
    }

    private func currentIdentity(
        accountID: String
    ) -> HomeTimelineRelayRuntimeConfigurationIdentity? {
        guard let lifecycle = lifecycleCoordinator.token(for: accountID) else {
            return nil
        }
        let content = contentCoordinator.snapshot
        return HomeTimelineRelayRuntimeConfigurationIdentity(
            accountID: accountID,
            lifecycleGeneration: lifecycle.generation,
            resolvedRelays: content.resolvedRelays,
            followedPubkeys: content.followedPubkeys,
            contactListEventID: content.contactListEvent?.id
        )
    }

    private func prepareFeed(
        account: NostrAccount
    ) -> HomeTimelineRelayRuntimeFeedPreparation? {
        let content = contentCoordinator.snapshot
        projectionController.ensureDefinition(
            accountID: account.pubkey,
            followedPubkeys: content.followedPubkeys,
            liveEvents: content.noteEvents
        )
        guard let context = projectionController.runtimeContext() else {
            return nil
        }
        return HomeTimelineRelayRuntimeFeedPreparation(
            context: context,
            newestCreatedAt: content.noteEvents.map(\.createdAt).max(),
            newestCreatedAtByRelay: timelineRepository.newestCreatedAtByRelay(
                accountID: account.pubkey,
                timelineKey: "home",
                relayURLs: content.resolvedRelays
            ),
            initialCreatedAt: content.noteEvents.map(\.createdAt).min()
        )
    }

    private func prepareInstall(
        packets: [NostrREQPacket],
        runtimeKeys: Set<RuntimeSubscriptionKey>,
        context: HomeFeedRuntimeContext,
        handlers: HomeTimelineRuntimeSetupHandlers
    ) {
        feedSyncCoordinator.prepareForwardSubscriptions(runtimeKeys)
        handlers.perform(.setRealtime(feedSyncCoordinator.isRealtime))
        for packet in packets {
            feedSyncCoordinator.registerForwardContext(
                context,
                groupID: packet.groupID
            )
        }
    }

    private func isFeedContextCurrent(
        _ context: HomeFeedRuntimeContext,
        accountID: String
    ) -> Bool {
        lifecycleCoordinator.token(for: accountID) != nil &&
            projectionController.isCurrent(context, accountID: accountID)
    }
}
