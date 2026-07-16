import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home load context factory")
@MainActor
struct HomeLoadContextFactoryTests {
    @Test("Contexts capture operation state while providers stay live")
    func contextStateAndProvidersUseTheirRequiredLifetimes() {
        let fixture = LoadContextFactoryFixture()
        let initialContext = fixture.factory.context()

        #expect(initialContext.state == HomeTimelineLoadInteractionState(
            hasRelayRuntime: true,
            hasTimelineEvents: false
        ))

        fixture.probe.snapshot = HomeLoadContextSnapshot(
            hasRelayRuntime: false,
            hasTimelineEvents: true
        )
        fixture.probe.hasResolvedRelays = true
        fixture.probe.currentState = fixture.replacementState
        fixture.probe.resolvedRelays = fixture.replacementRelays

        #expect(fixture.factory.context().state ==
            HomeTimelineLoadInteractionState(
                hasRelayRuntime: false,
                hasTimelineEvents: true
            ))
        #expect(initialContext.effects.environment.hasResolvedRelays())
        #expect(
            initialContext.effects.environment.currentState() ==
                fixture.replacementState
        )
        #expect(initialContext.effects.environment.localBackfillEvents(
            fixture.account,
            fixture.replacementState
        ) == [fixture.backfillEvent])
        #expect(
            initialContext.effects.environment.resolvedRelays() ==
                fixture.replacementRelays
        )
        #expect(fixture.probe.providerEvents == [
            .hasResolvedRelays,
            .currentState,
            .localBackfill(fixture.account.pubkey),
            .resolvedRelays
        ])

        fixture.probe.snapshot = nil
        #expect(fixture.factory.context().state ==
            HomeTimelineLoadInteractionState(
                hasRelayRuntime: false,
                hasTimelineEvents: false
            ))
    }

    @Test("Sync and async applications route through supplied effects")
    func routesLoadApplications() async {
        let fixture = LoadContextFactoryFixture()
        let context = fixture.factory.context()
        let followedPubkeys = [
            fixture.account.pubkey,
            String(repeating: "b", count: 64)
        ]

        context.effects.apply(.restartAccount(fixture.account))
        context.effects.apply(.replaceFollowedPubkeys(followedPubkeys))
        context.effects.apply(.materializeEntries)
        context.effects.apply(.setPhase(.loaded))
        await context.effects.perform(.configureRuntime(fixture.account))
        await context.effects.perform(.persistDatabase(fixture.account))

        #expect(fixture.probe.applicationEvents == [
            .restartAccount(fixture.account.pubkey),
            .replaceFollowedPubkeys(followedPubkeys),
            .materializeEntries,
            .setPhase(.loaded),
            .configureRuntime(fixture.account.pubkey),
            .persistDatabase(fixture.account.pubkey)
        ])
    }
}

@MainActor
private final class LoadContextFactoryProbe {
    enum ProviderEvent: Equatable {
        case hasResolvedRelays
        case currentState
        case localBackfill(String)
        case resolvedRelays
    }

    enum ApplicationEvent: Equatable {
        case restartAccount(String)
        case replaceFollowedPubkeys([String])
        case materializeEntries
        case setPhase(NostrHomeTimelinePhase)
        case configureRuntime(String)
        case persistDatabase(String)
    }

    var snapshot: HomeLoadContextSnapshot?
    var hasResolvedRelays = false
    var currentState: NostrHomeTimelineState?
    var resolvedRelays: [String] = []
    let backfillEvent: NostrEvent
    private(set) var providerEvents: [ProviderEvent] = []
    private(set) var applicationEvents: [ApplicationEvent] = []

    init(
        snapshot: HomeLoadContextSnapshot,
        currentState: NostrHomeTimelineState,
        backfillEvent: NostrEvent
    ) {
        self.snapshot = snapshot
        self.currentState = currentState
        self.backfillEvent = backfillEvent
    }

    var environment: HomeLoadContextEnvironment {
        HomeLoadContextEnvironment(
            snapshot: { [self] in snapshot },
            providers: HomeTimelineLoadEnvironment(
                hasResolvedRelays: { [self] in
                    providerEvents.append(.hasResolvedRelays)
                    return hasResolvedRelays
                },
                currentState: { [self] in
                    providerEvents.append(.currentState)
                    return currentState
                },
                localBackfillEvents: { [self] account, _ in
                    providerEvents.append(.localBackfill(account.pubkey))
                    return [backfillEvent]
                },
                resolvedRelays: { [self] in
                    providerEvents.append(.resolvedRelays)
                    return resolvedRelays
                }
            ),
            applications: applicationEffects
        )
    }

    private var applicationEffects: HomeTimelineLoadApplicationEffects {
        HomeTimelineLoadApplicationEffects(
            applyActivityTransition: { _ in },
            applyRelayStatusTransition: { _ in },
            installProvisionalRuntimeBootstrap: { _ in },
            restartAccount: { [self] account in
                applicationEvents.append(.restartAccount(account.pubkey))
            },
            replaceTimelineState: { _ in },
            replaceRuntimeBootstrapState: { _ in },
            replaceFollowedPubkeys: { [self] pubkeys in
                applicationEvents.append(.replaceFollowedPubkeys(pubkeys))
            },
            materializeEntries: { [self] in
                applicationEvents.append(.materializeEntries)
            },
            setPhase: { [self] phase in
                applicationEvents.append(.setPhase(phase))
            },
            configureRuntime: { [self] account in
                applicationEvents.append(.configureRuntime(account.pubkey))
            },
            persistDatabase: { [self] account in
                applicationEvents.append(.persistDatabase(account.pubkey))
            }
        )
    }
}

@MainActor
private struct LoadContextFactoryFixture {
    let account: NostrAccount
    let replacementState: NostrHomeTimelineState
    let replacementRelays: [String]
    let backfillEvent: NostrEvent
    let probe: LoadContextFactoryProbe
    let factory: HomeLoadContextFactory

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "load-context",
            readOnly: true
        )
        let initialState = NostrHomeTimelineState(
            relays: ["wss://initial.example"],
            followedPubkeys: [account.pubkey],
            noteEvents: [],
            metadataEvents: []
        )
        let replacementRelays = ["wss://replacement.example"]
        let replacementState = NostrHomeTimelineState(
            relays: replacementRelays,
            followedPubkeys: [account.pubkey],
            noteEvents: [],
            metadataEvents: []
        )
        let backfillEvent = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: account.pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "backfill",
            sig: String(repeating: "2", count: 128)
        )
        let probe = LoadContextFactoryProbe(
            snapshot: HomeLoadContextSnapshot(
                hasRelayRuntime: true,
                hasTimelineEvents: false
            ),
            currentState: initialState,
            backfillEvent: backfillEvent
        )

        self.account = account
        self.replacementState = replacementState
        self.replacementRelays = replacementRelays
        self.backfillEvent = backfillEvent
        self.probe = probe
        factory = HomeLoadContextFactory(environment: probe.environment)
    }
}
