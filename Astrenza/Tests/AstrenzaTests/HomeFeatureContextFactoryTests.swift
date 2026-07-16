import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline feature interaction context factory")
@MainActor
struct HomeFeatureContextFactoryTests {
    @Test("One live snapshot projects every feature interaction state")
    func projectsFeatureStates() {
        let fixture = FeatureInteractionContextFactoryFixture()
        let factory = fixture.factory
        let localMutation = factory.localMutationContext()
        let gapBackfill = factory.gapBackfillContext()
        let publish = factory.publishContext(account: fixture.account)
        let backward = factory.backwardContext()
        let linkPreview = factory.linkPreviewInteraction()

        #expect(localMutation.state == HomeLocalMutationInteractionState(
            accountID: fixture.account.pubkey
        ))
        #expect(gapBackfill.state.account == fixture.account)
        #expect(gapBackfill.state.hasRelayRuntime)
        #expect(gapBackfill.state.resolvedRelays == fixture.resolvedRelays)
        #expect(publish.state == HomeTimelinePublishInteractionState(
            account: fixture.account,
            accountWriteRelays: fixture.writeRelays,
            fallbackRelays: fixture.resolvedRelays
        ))
        #expect(backward.state == HomeTimelineBackwardInteractionState(
            account: fixture.account,
            resolvedRelays: fixture.resolvedRelays
        ))
        #expect(linkPreview.state == HomeTimelineLinkPreviewInteractionState(
            accountID: fixture.account.pubkey,
            resolvedRelays: fixture.resolvedRelays,
            policy: fixture.syncPolicy
        ))
    }

    @Test("Every typed effect routes through supplied applications")
    func routesFeatureEffects() async {
        let fixture = FeatureInteractionContextFactoryFixture()
        let factory = fixture.factory
        let filter = factory.filterContext()
        let sync = factory.syncContext()
        let localMutation = factory.localMutationContext()
        let gapBackfill = factory.gapBackfillContext()
        let publish = factory.publishContext(account: fixture.account)
        let backward = factory.backwardContext()
        let linkPreview = factory.linkPreviewInteraction()
        let dependencyRequest = fixture.dependencyRequest

        filter.effects.apply(.invalidateListEntries)
        sync.effects.apply(.setRealtime(true))
        localMutation.effects.apply(.materializeEntries)
        gapBackfill.effects.apply(.materializeEntries)
        publish.effects.apply(.materializeEntries)
        await publish.effects.perform(.persistDatabase(fixture.account))
        backward.effects.apply(.scheduleLinkPreviewResolution)
        let didResolve = await backward.effects.resolveDependencies(
            dependencyRequest
        )
        linkPreview.effects.didUpdate()
        linkPreview.effects.apply(.applyRelayStatusTransition(
            fixture.relayTransition
        ))

        #expect(!didResolve)
        #expect(fixture.probe.applicationFixture.probe.events == [
            .invalidateListEntries,
            .setRealtime(true),
            .materializeEntries,
            .materializeEntries,
            .materializeEntries,
            .persistDatabase(fixture.account.pubkey),
            .scheduleLinkPreviewResolution,
            .relayTransition(fixture.relayTransition)
        ])
        #expect(fixture.probe.events == [
            .backwardDependency(dependencyRequest),
            .linkPreviewUpdated
        ])
    }

    @Test("Publish validity reads the current account after context creation")
    func publishAccountValidityIsLive() {
        let fixture = FeatureInteractionContextFactoryFixture()
        let publish = fixture.factory.publishContext(account: fixture.account)

        #expect(
            publish.effects.environment.currentAccountID() ==
                fixture.account.pubkey
        )

        fixture.probe.snapshot = HomeTimelineFeatureInteractionSnapshot(
            account: fixture.replacementAccount,
            resolvedRelays: [],
            relayListEvent: nil,
            syncPolicy: .default(),
            hasRelayRuntime: false
        )
        #expect(
            publish.effects.environment.currentAccountID() ==
                fixture.replacementAccount.pubkey
        )

        fixture.probe.snapshot = nil
        #expect(publish.effects.environment.currentAccountID() == nil)
    }
}

@MainActor
private final class FeatureInteractionContextFactoryProbe {
    enum Event: Equatable {
        case backwardDependency(HomeTimelineBackwardDependencyRequest)
        case linkPreviewUpdated
    }

    var snapshot: HomeTimelineFeatureInteractionSnapshot?
    let applicationFixture = StoreApplicationDispatcherFixture()
    private(set) var events: [Event] = []

    init(snapshot: HomeTimelineFeatureInteractionSnapshot) {
        self.snapshot = snapshot
    }

    var environment: HomeFeatureInteractionEnvironment {
        HomeFeatureInteractionEnvironment(
            snapshot: { [self] in snapshot },
            applications: applicationFixture.effects,
            resolveBackwardDependencies: { [self] request in
                events.append(.backwardDependency(request))
                return false
            },
            didUpdateLinkPreview: { [self] in
                events.append(.linkPreviewUpdated)
            }
        )
    }
}

@MainActor
private struct FeatureInteractionContextFactoryFixture {
    let account = NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "feature-context",
        readOnly: true
    )
    let replacementAccount = NostrAccount(
        pubkey: String(repeating: "b", count: 64),
        displayIdentifier: "replacement",
        readOnly: true
    )
    let resolvedRelays = ["wss://fallback.example"]
    let writeRelays = ["wss://write.example", "wss://both.example"]
    let syncPolicy = NostrSyncPolicy.default(
        networkType: .cellular,
        lowPowerMode: true
    )
    let probe: FeatureInteractionContextFactoryProbe

    init() {
        probe = FeatureInteractionContextFactoryProbe(
            snapshot: HomeTimelineFeatureInteractionSnapshot(
                account: account,
                resolvedRelays: resolvedRelays,
                relayListEvent: NostrEvent(
                    id: String(repeating: "1", count: 64),
                    pubkey: account.pubkey,
                    createdAt: 100,
                    kind: 10_002,
                    tags: [
                        ["r", "wss://write.example", "write"],
                        ["r", "wss://both.example"]
                    ],
                    content: "",
                    sig: String(repeating: "2", count: 128)
                ),
                syncPolicy: syncPolicy,
                hasRelayRuntime: true
            )
        )
    }

    var factory: HomeFeatureContextFactory {
        HomeFeatureContextFactory(
            environment: probe.environment
        )
    }

    var dependencyRequest: HomeTimelineBackwardDependencyRequest {
        HomeTimelineBackwardDependencyRequest(
            event: NostrEvent(
                id: String(repeating: "3", count: 64),
                pubkey: account.pubkey,
                createdAt: 101,
                kind: 1,
                tags: [],
                content: "dependency",
                sig: String(repeating: "4", count: 128)
            ),
            account: account,
            lifecycle: HomeTimelineLifecycleToken(
                accountID: account.pubkey,
                generation: 7
            )
        )
    }

    var relayTransition: HomeTimelineRelayStatusTransition {
        HomeTimelineRelayStatusTransition(
            snapshot: HomeTimelineRelayStatusSnapshot(
                runtimeStates: [:],
                connectedRelayCount: 0,
                plannedRelayCount: 0
            ),
            invalidatedRealtimeRelayURL: nil,
            publishesStatusChange: false
        )
    }
}
