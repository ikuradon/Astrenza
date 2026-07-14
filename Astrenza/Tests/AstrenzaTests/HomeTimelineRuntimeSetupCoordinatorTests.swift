import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline runtime setup coordinator")
@MainActor
struct HomeTimelineRuntimeSetupCoordinatorTests {
    @Test("Setup builds runtime configuration from current content and lifecycle")
    func buildsConfigurationFromCurrentState() async throws {
        let system = try RuntimeSetupTestSystem()

        await system.coordinator.configure(
            system.request(forceInstall: true),
            handlers: system.handlers
        )

        let request = try #require(system.configurator.requests.first)
        #expect(request.identity == HomeTimelineRelayRuntimeConfigurationIdentity(
            accountID: system.account.pubkey,
            lifecycleGeneration: system.lifecycleToken.generation,
            resolvedRelays: system.resolvedRelays,
            followedPubkeys: [system.followedPubkey],
            contactListEventID: system.contactListEvent.id
        ))
        #expect(request.account == system.account)
        #expect(request.contactItems == [NostrContactListItem(
            pubkey: system.followedPubkey,
            relayHints: ["wss://hint.example"]
        )])
        #expect(request.defaultRelayURLs == system.defaultRelayURLs)
        #expect(request.policy == system.policy)
        #expect(request.forceInstall)
    }

    @Test("Configuration handlers prepare feed sync and surface runtime state")
    func handlersPrepareFeedSyncAndCommands() async throws {
        let system = try RuntimeSetupTestSystem()
        await system.coordinator.configure(system.request(), handlers: system.handlers)
        let handlers = try #require(system.configurator.capturedHandlers)

        #expect(handlers.currentIdentity() == system.configurator.requests[0].identity)
        await handlers.prepareDependencies()
        let preparation = try #require(handlers.prepareFeed())
        #expect(preparation.context == system.feedContext)
        #expect(preparation.newestCreatedAt == 30)
        #expect(preparation.initialCreatedAt == 10)
        #expect(preparation.newestCreatedAtByRelay == nil)

        let packet = NostrREQPacket(
            strategy: .forward,
            subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
            groupID: "home-forward",
            filters: []
        )
        let runtimeKeys = [RuntimeSubscriptionKey(
            relayURL: system.resolvedRelays[0],
            subscriptionID: packet.subscriptionID
        )]
        handlers.prepareInstall(
            [packet],
            Set(runtimeKeys),
            preparation.context
        )

        let registration = try #require(
            system.feedSyncCoordinator.registration(for: packet)
        )
        #expect(registration.context == preparation.context)
        #expect(system.probe.commands == [.setRealtime(false)])
        #expect(handlers.isFeedContextCurrent(preparation.context))

        handlers.didFail("install failed")
        #expect(system.probe.commands == [
            .setRealtime(false),
            .recordDiagnostic(HomeTimelineRuntimeSetupDiagnostic(
                relayURL: system.resolvedRelays[0],
                subscriptionID: NostrHomeForwardREQBuilder.subscriptionID,
                message: "install failed"
            ))
        ])
    }

    @Test("Captured identity and feed validity follow the active lifecycle")
    func handlersRejectSupersededLifecycle() async throws {
        let system = try RuntimeSetupTestSystem()
        await system.coordinator.configure(system.request(), handlers: system.handlers)
        let handlers = try #require(system.configurator.capturedHandlers)

        _ = system.contentCoordinator.replaceFollowedPubkeys([
            system.followedPubkey,
            String(repeating: "c", count: 64)
        ])
        #expect(handlers.currentIdentity()?.followedPubkeys.count == 2)

        system.lifecycleCoordinator.cancel()
        #expect(handlers.currentIdentity() == nil)
        #expect(!handlers.isFeedContextCurrent(system.feedContext))
    }

    @Test(
        "Invalid setup state never reaches the relay configurator",
        arguments: RuntimeSetupRejection.allCases
    )
    func rejectsInvalidSetupState(_ rejection: RuntimeSetupRejection) async throws {
        let resolvedRelays: [String] = rejection == .noResolvedRelays
            ? []
            : ["wss://home.example"]
        let system = try RuntimeSetupTestSystem(resolvedRelays: resolvedRelays)
        var account = system.account
        var hasRelayRuntime = true
        var isTerminating = false

        switch rejection {
        case .noRelayRuntime:
            hasRelayRuntime = false
        case .terminating:
            isTerminating = true
        case .bootstrapIncomplete:
            system.lifecycleCoordinator.setRuntimeBootstrapCompleted(
                false,
                for: system.lifecycleToken
            )
        case .noResolvedRelays:
            break
        case .staleAccount:
            account = NostrAccount(
                pubkey: String(repeating: "d", count: 64),
                displayIdentifier: "stale",
                readOnly: true
            )
        }

        await system.coordinator.configure(
            system.request(
                account: account,
                hasRelayRuntime: hasRelayRuntime,
                isTerminating: isTerminating
            ),
            handlers: system.handlers
        )

        #expect(system.configurator.requests.isEmpty)
        #expect(system.probe.commands.isEmpty)
    }

    @Test("Reset delegates installed packet invalidation to the configurator")
    func resetDelegatesToConfigurator() throws {
        let system = try RuntimeSetupTestSystem()

        system.coordinator.reset()

        #expect(system.configurator.resetCount == 1)
    }
}

enum RuntimeSetupRejection: CaseIterable, Sendable, CustomTestStringConvertible {
    case noRelayRuntime
    case terminating
    case bootstrapIncomplete
    case noResolvedRelays
    case staleAccount

    var testDescription: String {
        switch self {
        case .noRelayRuntime: "no relay runtime"
        case .terminating: "runtime termination"
        case .bootstrapIncomplete: "bootstrap incomplete"
        case .noResolvedRelays: "no resolved relays"
        case .staleAccount: "stale account"
        }
    }
}
