import AstrenzaCore
import Foundation
@testable import Astrenza

@MainActor
final class RuntimeSetupConfiguratorSpy: HomeTimelineRelayRuntimeConfiguring {
    private(set) var resetCount = 0
    private(set) var requests: [HomeTimelineRelayRuntimeConfigurationRequest] = []
    private(set) var capturedHandlers: HomeTimelineRelayRuntimeConfigurationHandlers?

    func reset() {
        resetCount += 1
    }

    func configure(
        _ request: HomeTimelineRelayRuntimeConfigurationRequest,
        handlers: HomeTimelineRelayRuntimeConfigurationHandlers
    ) async {
        requests.append(request)
        capturedHandlers = handlers
    }
}

@MainActor
final class RuntimeSetupCommandProbe {
    var commands: [HomeTimelineRuntimeSetupCommand] = []
}

private struct RuntimeSetupNIP05Resolver: NostrNIP05Resolving {
    func resolve(
        identifier: String,
        expectedPubkey: String?
    ) async -> NostrNIP05Resolution {
        NostrNIP05Resolution(
            identifier: identifier,
            pubkey: expectedPubkey,
            relays: [],
            status: .absent
        )
    }
}

@MainActor
struct RuntimeSetupTestSystem {
    let account: NostrAccount
    let followedPubkey: String
    let resolvedRelays: [String]
    let defaultRelayURLs = ["wss://home.example", "wss://discovery.example"]
    let policy = NostrSyncPolicy.default(networkType: .wifi, lowPowerMode: false)
    let contactListEvent: NostrEvent
    let feedContext: HomeFeedRuntimeContext
    let contentCoordinator: HomeTimelineContentCoordinator
    let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    let lifecycleToken: HomeTimelineLifecycleToken
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
    let configurator: RuntimeSetupConfiguratorSpy
    let coordinator: HomeTimelineRuntimeSetupCoordinator
    let probe = RuntimeSetupCommandProbe()

    var handlers: HomeTimelineRuntimeSetupHandlers {
        HomeTimelineRuntimeSetupHandlers(
            perform: { [probe] command in
                probe.commands.append(command)
            }
        )
    }

    init(resolvedRelays: [String] = ["wss://home.example"]) throws {
        let accountID = String(repeating: "a", count: 64)
        let followedPubkey = String(repeating: "b", count: 64)
        let account = Self.account(accountID: accountID)
        let contactListEvent = Self.contactListEvent(
            accountID: accountID,
            followedPubkey: followedPubkey
        )
        let contentCoordinator = Self.contentCoordinator(
            accountID: accountID,
            followedPubkey: followedPubkey,
            resolvedRelays: resolvedRelays,
            contactListEvent: contactListEvent
        )
        let lifecycleCoordinator = HomeTimelineLifecycleCoordinator()
        let lifecycleToken = lifecycleCoordinator.begin(accountID: accountID)
        lifecycleCoordinator.setRuntimeBootstrapCompleted(true, for: lifecycleToken)
        let collaborators = try Self.collaborators(
            accountID: accountID,
            followedPubkey: followedPubkey
        )
        let configurator = RuntimeSetupConfiguratorSpy()

        self.account = account
        self.followedPubkey = followedPubkey
        self.resolvedRelays = resolvedRelays
        self.contactListEvent = contactListEvent
        self.feedContext = HomeFeedRuntimeContext(
            definition: collaborators.definition
        )
        self.contentCoordinator = contentCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.lifecycleToken = lifecycleToken
        self.feedSyncCoordinator = collaborators.feedSyncCoordinator
        self.dependencyCoordinator = collaborators.dependencyCoordinator
        self.configurator = configurator
        self.coordinator = HomeTimelineRuntimeSetupCoordinator(
            configurator: configurator,
            contentCoordinator: contentCoordinator,
            dependencyCoordinator: collaborators.dependencyCoordinator,
            projectionController: collaborators.projectionController,
            feedSyncCoordinator: collaborators.feedSyncCoordinator,
            lifecycleCoordinator: lifecycleCoordinator,
            timelineRepository: HomeTimelineRepository(eventStore: nil)
        )
    }

    func request(
        account: NostrAccount? = nil,
        hasRelayRuntime: Bool = true,
        isTerminating: Bool = false,
        forceInstall: Bool = false
    ) -> HomeTimelineRuntimeSetupRequest {
        HomeTimelineRuntimeSetupRequest(
            account: account ?? self.account,
            defaultRelayURLs: defaultRelayURLs,
            policy: policy,
            hasRelayRuntime: hasRelayRuntime,
            isTerminating: isTerminating,
            forceInstall: forceInstall
        )
    }

    private static func account(accountID: String) -> NostrAccount {
        NostrAccount(
            pubkey: accountID,
            displayIdentifier: "account",
            readOnly: true
        )
    }

    private static func contactListEvent(
        accountID: String,
        followedPubkey: String
    ) -> NostrEvent {
        event(
            idCharacter: "3",
            pubkey: accountID,
            createdAt: 5,
            kind: 3,
            tags: [["p", followedPubkey, "wss://hint.example"]]
        )
    }

    private static func contentCoordinator(
        accountID: String,
        followedPubkey: String,
        resolvedRelays: [String],
        contactListEvent: NostrEvent
    ) -> HomeTimelineContentCoordinator {
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)
        _ = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: resolvedRelays,
                followedPubkeys: [followedPubkey],
                noteEvents: [
                    event(
                        idCharacter: "1",
                        pubkey: followedPubkey,
                        createdAt: 10,
                        kind: 1,
                        tags: [[
                            "q",
                            String(repeating: "c", count: 64),
                            "wss://quote.example",
                            String(repeating: "d", count: 64)
                        ]]
                    ),
                    event(
                        idCharacter: "2",
                        pubkey: followedPubkey,
                        createdAt: 30,
                        kind: 6,
                        tags: [
                            [
                                "e",
                                String(repeating: "e", count: 64),
                                "wss://repost.example"
                            ],
                            ["p", String(repeating: "f", count: 64)]
                        ]
                    )
                ],
                metadataEvents: [],
                contactListEvent: contactListEvent
            ),
            accountID: accountID
        )
        return coordinator
    }

    private static func collaborators(
        accountID: String,
        followedPubkey: String
    ) throws -> RuntimeSetupCollaborators {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [followedPubkey], kinds: [1, 6])
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "runtime-setup",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        )
        let projectionController = HomeFeedProjectionController(eventStore: nil)
        projectionController.activate(
            definition: definition,
            window: nil,
            sourceAuthors: [followedPubkey]
        )
        return RuntimeSetupCollaborators(
            definition: definition,
            projectionController: projectionController,
            feedSyncCoordinator: HomeTimelineFeedSyncCoordinator(
                eventStore: nil,
                backwardRequestRegistry: HomeTimelineBackwardRequestRegistry()
            ),
            dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator(
                eventIngestor: HomeTimelineEventIngestor(eventStore: nil),
                profileDirectory: nil,
                nip05Resolver: RuntimeSetupNIP05Resolver(),
                syncPlanner: HomeTimelineSyncPlanner()
            )
        )
    }

    private static func event(
        idCharacter: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]] = []
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(idCharacter), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: String(idCharacter),
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private struct RuntimeSetupCollaborators {
    let definition: NostrFeedDefinitionRecord
    let projectionController: HomeFeedProjectionController
    let feedSyncCoordinator: HomeTimelineFeedSyncCoordinator
    let dependencyCoordinator: HomeTimelineDependencyResolutionCoordinator
}
