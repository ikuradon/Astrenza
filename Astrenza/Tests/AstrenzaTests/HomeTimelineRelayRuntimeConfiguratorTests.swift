import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline relay runtime configurator")
struct HomeTimelineRelayRuntimeConfiguratorTests {
    @Test("Identical packets are deduplicated unless installation is forced")
    @MainActor
    func deduplicatesUnlessForced() async throws {
        let recorder = RelayRuntimeConfigurationRecorder()
        let configurator = HomeTimelineRelayRuntimeConfigurator(
            client: recorder.client(waitUntilReady: { true })
        )
        let fixture = try configurationFixture()
        recorder.currentIdentity = fixture.identity

        await configurator.configure(fixture.request, handlers: fixture.handlers(recorder: recorder))
        await configurator.configure(fixture.request, handlers: fixture.handlers(recorder: recorder))
        await configurator.configure(
            fixture.request(forceInstall: true),
            handlers: fixture.handlers(recorder: recorder)
        )

        #expect(recorder.installAttempts.count == 2)
        #expect(recorder.installPreparations.count == 2)
        let firstPreparation = try #require(recorder.installPreparations.first)
        #expect(firstPreparation.runtimeKeys == [
            RuntimeSubscriptionKey(
                relayURL: "wss://one.example",
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID
            ),
            RuntimeSubscriptionKey(
                relayURL: "wss://two.example",
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID
            )
        ])
        let specificationToken = String(fixture.context.specificationHash.prefix(12))
        #expect(firstPreparation.packets.allSatisfy {
            $0.groupID.contains("-feed-r\(fixture.context.revision)-\(specificationToken)")
        })
        #expect(recorder.trafficAccountIDs.count == 3)
        #expect(recorder.defaultRelayUpdates.count == 3)
    }

    @Test("A newer configuration supersedes an older readiness waiter")
    @MainActor
    func newerConfigurationSupersedesReadinessWaiter() async throws {
        let recorder = RelayRuntimeConfigurationRecorder()
        let readiness = RelayRuntimeConfigurationReadinessGate()
        let configurator = HomeTimelineRelayRuntimeConfigurator(
            client: recorder.client(waitUntilReady: {
                await readiness.waitUntilReady()
            })
        )
        let fixture = try configurationFixture()
        recorder.currentIdentity = fixture.identity
        let handlers = fixture.handlers(recorder: recorder)

        let firstTask = Task { @MainActor in
            await configurator.configure(fixture.request, handlers: handlers)
        }
        try #require(await waitUntil {
            await readiness.callCount() == 1
        })

        await configurator.configure(fixture.request, handlers: handlers)
        await readiness.releaseFirstWaiter()
        await firstTask.value

        #expect(recorder.installAttempts.count == 1)
        #expect(recorder.installPreparations.count == 1)
        #expect(recorder.trafficAccountIDs.count == 1)
        #expect(recorder.failures.isEmpty)
    }

    @Test("A cancelled configuration cannot resume after readiness")
    @MainActor
    func cancelledConfigurationCannotResume() async throws {
        let recorder = RelayRuntimeConfigurationRecorder()
        let readiness = RelayRuntimeConfigurationReadinessGate()
        let configurator = HomeTimelineRelayRuntimeConfigurator(
            client: recorder.client(waitUntilReady: {
                await readiness.waitUntilReady()
            })
        )
        let fixture = try configurationFixture()
        recorder.currentIdentity = fixture.identity
        let handlers = fixture.handlers(recorder: recorder)

        let task = Task { @MainActor in
            await configurator.configure(fixture.request, handlers: handlers)
        }
        try #require(await waitUntil {
            await readiness.callCount() == 1
        })
        task.cancel()
        await readiness.releaseFirstWaiter()
        await task.value

        #expect(recorder.trafficAccountIDs.isEmpty)
        #expect(recorder.installAttempts.isEmpty)
        #expect(recorder.installPreparations.isEmpty)
        #expect(recorder.failures.isEmpty)
    }

    @Test("A failed installation remains retryable and reports the current failure")
    @MainActor
    func failedInstallationRemainsRetryable() async throws {
        let recorder = RelayRuntimeConfigurationRecorder()
        recorder.installError = .installationFailed
        let configurator = HomeTimelineRelayRuntimeConfigurator(
            client: recorder.client(waitUntilReady: { true })
        )
        let fixture = try configurationFixture()
        recorder.currentIdentity = fixture.identity
        let handlers = fixture.handlers(recorder: recorder)

        await configurator.configure(fixture.request, handlers: handlers)
        recorder.installError = nil
        await configurator.configure(fixture.request, handlers: handlers)
        await configurator.configure(fixture.request, handlers: handlers)

        #expect(recorder.installAttempts.count == 2)
        #expect(recorder.installPreparations.count == 2)
        #expect(recorder.failures == ["installationFailed"])
    }

    @MainActor
    private func configurationFixture() throws -> RelayRuntimeConfigurationFixture {
        let accountID = String(repeating: "a", count: 64)
        let followedPubkey = String(repeating: "b", count: 64)
        let relays = ["wss://one.example", "wss://two.example"]
        let identity = HomeTimelineRelayRuntimeConfigurationIdentity(
            accountID: accountID,
            lifecycleGeneration: 7,
            resolvedRelays: relays,
            followedPubkeys: [followedPubkey],
            contactListEventID: "contacts"
        )
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [followedPubkey], kinds: [1, 6])
        )
        let context = HomeFeedRuntimeContext(
            definition: NostrFeedDefinitionRecord(
                feedID: "feed:home:\(accountID)",
                accountID: accountID,
                kind: "home",
                specificationJSON: specification,
                specificationHash: "specification",
                revision: 3,
                createdAt: 1,
                updatedAt: 1
            )
        )
        return RelayRuntimeConfigurationFixture(
            identity: identity,
            account: NostrAccount(
                pubkey: accountID,
                displayIdentifier: "account",
                readOnly: true
            ),
            context: context,
            relays: relays
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private struct RelayRuntimeConfigurationFixture {
    let identity: HomeTimelineRelayRuntimeConfigurationIdentity
    let account: NostrAccount
    let context: HomeFeedRuntimeContext
    let relays: [String]

    var request: HomeTimelineRelayRuntimeConfigurationRequest {
        request(forceInstall: false)
    }

    func request(forceInstall: Bool) -> HomeTimelineRelayRuntimeConfigurationRequest {
        HomeTimelineRelayRuntimeConfigurationRequest(
            identity: identity,
            account: account,
            contactItems: [],
            defaultRelayURLs: relays,
            policy: .default(),
            forceInstall: forceInstall
        )
    }

    func handlers(
        recorder: RelayRuntimeConfigurationRecorder
    ) -> HomeTimelineRelayRuntimeConfigurationHandlers {
        let context = self.context
        return HomeTimelineRelayRuntimeConfigurationHandlers(
            currentIdentity: { [recorder] in
                recorder.currentIdentity
            },
            prepareDependencies: { [recorder] in
                recorder.dependencyPreparationCount += 1
            },
            prepareFeed: { [recorder, context] in
                recorder.feedPreparationCount += 1
                return HomeTimelineRelayRuntimeFeedPreparation(
                    context: context,
                    newestCreatedAt: nil,
                    newestCreatedAtByRelay: nil,
                    initialCreatedAt: nil
                )
            },
            prepareInstall: { [recorder] packets, runtimeKeys, _ in
                recorder.installPreparations.append(
                    RelayRuntimeInstallPreparation(
                        packets: packets,
                        runtimeKeys: runtimeKeys
                    )
                )
            },
            isFeedContextCurrent: { [recorder, context] candidate in
                recorder.isFeedContextCurrent && candidate == context
            },
            didFail: { [recorder] message in
                recorder.failures.append(message)
            }
        )
    }

    init(
        identity: HomeTimelineRelayRuntimeConfigurationIdentity,
        account: NostrAccount,
        context: HomeFeedRuntimeContext,
        relays: [String]
    ) {
        self.identity = identity
        self.account = account
        self.context = context
        self.relays = relays
    }
}

@MainActor
private final class RelayRuntimeConfigurationRecorder {
    var currentIdentity: HomeTimelineRelayRuntimeConfigurationIdentity?
    var isFeedContextCurrent = true
    var installError: RelayRuntimeConfigurationTestError?
    var trafficAccountIDs: [String] = []
    var profileRelayUpdates: [[String]] = []
    var defaultRelayUpdates: [[String]] = []
    var installAttempts: [[NostrREQPacket]] = []
    var installPreparations: [RelayRuntimeInstallPreparation] = []
    var dependencyPreparationCount = 0
    var feedPreparationCount = 0
    var failures: [String] = []

    func client(
        waitUntilReady: @escaping HomeTimelineRelayRuntimeConfigurationClient.Readiness
    ) -> HomeTimelineRelayRuntimeConfigurationClient {
        HomeTimelineRelayRuntimeConfigurationClient(
            waitUntilReady: waitUntilReady,
            setTrafficContext: { [weak self] accountID, _ in
                self?.trafficAccountIDs.append(accountID)
            },
            updateProfileRelayURLs: { [weak self] relayURLs in
                self?.profileRelayUpdates.append(relayURLs)
            },
            setDefaultRelays: { [weak self] relayURLs in
                self?.defaultRelayUpdates.append(relayURLs)
            },
            installForward: { [weak self] packets in
                guard let self else { return }
                installAttempts.append(packets)
                if let installError {
                    throw installError
                }
            }
        )
    }
}

private struct RelayRuntimeInstallPreparation {
    let packets: [NostrREQPacket]
    let runtimeKeys: Set<RuntimeSubscriptionKey>
}

private enum RelayRuntimeConfigurationTestError: Error {
    case installationFailed
}

private actor RelayRuntimeConfigurationReadinessGate {
    private var calls = 0
    private var firstWaiter: CheckedContinuation<Void, Never>?

    func waitUntilReady() async -> Bool {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { continuation in
                firstWaiter = continuation
            }
        }
        return true
    }

    func callCount() -> Int {
        calls
    }

    func releaseFirstWaiter() {
        firstWaiter?.resume()
        firstWaiter = nil
    }
}
