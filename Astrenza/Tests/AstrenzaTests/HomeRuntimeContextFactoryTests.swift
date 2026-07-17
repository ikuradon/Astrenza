import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home runtime context factory")
@MainActor
struct HomeRuntimeContextFactoryTests {
    @Test("Contexts project a fresh snapshot for each operation")
    func contextsProjectFreshSnapshots() {
        let fixture = RuntimeContextFactoryFixture()

        #expect(fixture.factory.interactionContext().state ==
            HomeTimelineRuntimeInteractionState(
                account: fixture.account,
                resolvedRelays: fixture.initialSnapshot.resolvedRelays,
                bootstrapRelayURLs:
                    fixture.initialSnapshot.bootstrapRelayURLs,
                policy: fixture.initialSnapshot.policy,
                hasRelayRuntime: true,
                isTerminating: false
            ))
        #expect(fixture.factory.eventContext().state ==
            HomeTimelineRuntimeEventInteractionState(
                account: fixture.account,
                resolvedRelays: fixture.initialSnapshot.resolvedRelays,
                hasRelayRuntime: true,
                receivedWhileRealtime: true
            ))

        fixture.probe.snapshot = fixture.replacementSnapshot

        #expect(fixture.factory.interactionContext().state ==
            HomeTimelineRuntimeInteractionState(
                account: fixture.replacementAccount,
                resolvedRelays: fixture.replacementSnapshot.resolvedRelays,
                bootstrapRelayURLs:
                    fixture.replacementSnapshot.bootstrapRelayURLs,
                policy: fixture.replacementSnapshot.policy,
                hasRelayRuntime: false,
                isTerminating: true
            ))
        #expect(fixture.factory.eventContext().state ==
            HomeTimelineRuntimeEventInteractionState(
                account: fixture.replacementAccount,
                resolvedRelays: fixture.replacementSnapshot.resolvedRelays,
                hasRelayRuntime: false,
                receivedWhileRealtime: false
            ))
        #expect(fixture.factory.dependencyState() ==
            HomeTimelineRuntimeDependencyState(
                account: fixture.replacementAccount,
                hasRelayRuntime: false
            ))
    }

    @Test("Existing effects read packet and presentation state live")
    func effectsKeepRuntimeStateLive() throws {
        let fixture = RuntimeContextFactoryFixture()
        let interaction = fixture.factory.interactionContext()
        let event = fixture.factory.eventContext()

        fixture.probe.snapshot = fixture.replacementSnapshot

        let packet = try #require(
            interaction.effects.environment.packetContext(nil)
        )
        #expect(!packet.isActive)
        #expect(packet.accountID == fixture.replacementAccount.pubkey)
        #expect(
            packet.resolvedRelays ==
                fixture.replacementSnapshot.resolvedRelays
        )
        #expect(packet.isCurrentFeedContext(fixture.feedContext))
        #expect(fixture.probe.validatedFeedIDs == ["home:replacement"])
        #expect(interaction.effects.environment.isAccountCurrent(
            fixture.replacementAccount.pubkey
        ))
        #expect(!event.effects.environment.isAccountCurrent(
            fixture.account.pubkey
        ))
        #expect(event.effects.environment.presentationState(true) ==
            HomeTimelineRuntimeEventPresentationState(
                receivedWhileRealtime: true,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            ))

        fixture.probe.snapshot = nil
        #expect(interaction.effects.environment.packetContext(nil) == nil)
        #expect(!event.effects.environment.isAccountCurrent(
            fixture.replacementAccount.pubkey
        ))
    }

    @Test("Runtime applications route through supplied applications")
    func routesRuntimeApplications() async {
        let fixture = RuntimeContextFactoryFixture()
        let interaction = fixture.factory.interactionContext()
        let event = fixture.factory.eventContext()

        interaction.effects.apply(.setRealtime(true))
        await interaction.effects.perform(.handleEvent(
            relayURL: "wss://relay.example",
            subscriptionID: "runtime-context",
            event: fixture.event
        ))
        event.effects.apply(.scheduleLinkPreviewResolution)
        interaction.effects.runtimeApplication
            .applyListProjectionInvalidation(
                HomeTimelineListProjectionInvalidation(revision: 7)
            )
        event.effects.runtimeApplication.sourceInstallFailed("install failed")

        #expect(fixture.probe.applicationFixture.probe.events == [
            .setRealtime(true),
            .runtimeEvent(
                relayURL: "wss://relay.example",
                subscriptionID: "runtime-context",
                eventID: fixture.event.id
            ),
            .scheduleLinkPreviewResolution
        ])
        #expect(fixture.probe.runtimeApplications == [
            .listProjectionInvalidation(7),
            .sourceInstallFailed("install failed")
        ])
    }
}

@MainActor
private final class RuntimeContextFactoryProbe {
    var snapshot: HomeTimelineRuntimeStoreSnapshot?
    let applicationFixture = StoreApplicationDispatcherFixture()
    private(set) var runtimeApplications: [RuntimeContextApplication] = []
    private(set) var validatedFeedIDs: [String] = []

    init(snapshot: HomeTimelineRuntimeStoreSnapshot) {
        self.snapshot = snapshot
    }

    var environment: HomeRuntimeContextEnvironment {
        HomeRuntimeContextEnvironment(
            snapshot: { [self] in snapshot },
            isCurrentFeedContext: { [self] context in
                validatedFeedIDs.append(context.feedID)
                return context.feedID == "home:replacement"
            },
            waitForPendingPresentation: {},
            runtimeApplication: runtimeApplicationEffects,
            applications: applicationFixture.effects
        )
    }

    private var runtimeApplicationEffects:
        HomeTimelineRuntimeApplicationEffects {
        HomeTimelineRuntimeApplicationEffects(
            applyListProjectionInvalidation: { [self] invalidation in
                runtimeApplications.append(
                    .listProjectionInvalidation(invalidation.revision)
                )
            },
            applyPendingEventCountPublication: { _ in },
            reloadProjection: { _, _ in },
            reloadNewestProjection: { _ in },
            scheduleMaterialization: { _ in },
            persistTimelineMetadata: { _ in },
            sourceInstallFailed: { [self] message in
                runtimeApplications.append(.sourceInstallFailed(message))
            }
        )
    }
}

private enum RuntimeContextApplication: Equatable {
    case listProjectionInvalidation(Int)
    case sourceInstallFailed(String)
}

@MainActor
private struct RuntimeContextFactoryFixture {
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let initialSnapshot: HomeTimelineRuntimeStoreSnapshot
    let replacementSnapshot: HomeTimelineRuntimeStoreSnapshot
    let feedContext: HomeFeedRuntimeContext
    let event: NostrEvent
    let probe: RuntimeContextFactoryProbe
    let factory: HomeRuntimeContextFactory

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "runtime-context",
            readOnly: true
        )
        let replacementAccount = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "replacement",
            readOnly: true
        )
        let initialSnapshot = Self.makeInitialSnapshot(account: account)
        let replacementSnapshot = Self.makeReplacementSnapshot(
            account: replacementAccount
        )
        let probe = RuntimeContextFactoryProbe(snapshot: initialSnapshot)

        self.account = account
        self.replacementAccount = replacementAccount
        self.initialSnapshot = initialSnapshot
        self.replacementSnapshot = replacementSnapshot
        feedContext = Self.feedContext(accountID: "replacement")
        event = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: account.pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "runtime context",
            sig: String(repeating: "2", count: 128)
        )
        self.probe = probe
        factory = HomeRuntimeContextFactory(environment: probe.environment)
    }

    private static func makeInitialSnapshot(
        account: NostrAccount
    ) -> HomeTimelineRuntimeStoreSnapshot {
        HomeTimelineRuntimeStoreSnapshot(
            account: account,
            resolvedRelays: ["wss://initial.example"],
            bootstrapRelayURLs: ["wss://bootstrap-initial.example"],
            policy: .default(
                networkType: .cellular,
                lowPowerMode: false
            ),
            hasRelayRuntime: true,
            isTerminating: false,
            isRuntimeActive: true,
            isRealtime: true,
            hasRestoreProjectionAnchor: true,
            isTimelineAtNewestWindow: false,
            hasPendingEvents: true
        )
    }

    private static func makeReplacementSnapshot(
        account: NostrAccount
    ) -> HomeTimelineRuntimeStoreSnapshot {
        HomeTimelineRuntimeStoreSnapshot(
            account: account,
            resolvedRelays: ["wss://replacement.example"],
            bootstrapRelayURLs: ["wss://bootstrap-replacement.example"],
            policy: .default(
                networkType: .wifi,
                lowPowerMode: true
            ),
            hasRelayRuntime: false,
            isTerminating: true,
            isRuntimeActive: false,
            isRealtime: false,
            hasRestoreProjectionAnchor: false,
            isTimelineAtNewestWindow: true,
            hasPendingEvents: false
        )
    }

    private static func feedContext(
        accountID: String
    ) -> HomeFeedRuntimeContext {
        HomeFeedRuntimeContext(definition: NostrFeedDefinitionRecord(
            feedID: "home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "runtime-context",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        ))
    }
}
