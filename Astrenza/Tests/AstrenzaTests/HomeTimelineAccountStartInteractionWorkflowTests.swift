import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account start interaction workflow")
@MainActor
struct HomeTimelineAccountStartInteractionTests {
    @Test("Input, dynamic state, and dependencies cross the typed boundary")
    func routesInputStateAndDependencies() async throws {
        let fixture = AccountStartInteractionFixture(hasRelayRuntime: true)

        fixture.workflow.start(
            account: fixture.account,
            context: fixture.context
        )
        let effects = try #require(fixture.handler.effects)

        #expect(fixture.handler.inputs == [HomeTimelineAccountStartInput(
            account: fixture.account,
            hasRelayRuntime: true
        )])
        #expect(effects.state() == fixture.expectedState)

        fixture.probe.state = fixture.replacementState
        #expect(effects.state() == fixture.expectedReplacementState)
        #expect(await effects.restoreCachedSnapshot(fixture.account))
        #expect(
            effects.restoredViewport(fixture.account.pubkey)
                == fixture.restoredViewport
        )
        await effects.waitForCachedPresentation()
        await effects.load(fixture.account, fixture.lifecycle)

        #expect(fixture.probe.dependencies == [
            .restoreCachedSnapshot(fixture.account),
            .restoreViewport(fixture.account.pubkey),
            .waitForCachedPresentation,
            .load(HomeTimelineAccountStartLoadRequest(
                account: fixture.account,
                lifecycle: fixture.lifecycle
            ))
        ])
    }

    @Test("Every Store mutation is emitted as one typed action")
    func routesEveryApplicationEffect() throws {
        let fixture = AccountStartInteractionFixture(hasRelayRuntime: false)

        fixture.workflow.start(
            account: fixture.account,
            context: fixture.context
        )
        let application = try #require(fixture.handler.effects?.application)
        application.cancelCurrentAccount()
        application.applyAccountContextTransition(.activate(
            fixture.account,
            syncPolicy: fixture.syncPolicy
        ))
        application.startRuntimeSession()
        application.prepareHomeFeedDefinition(fixture.account)
        application.applyProjectionViewportTransition(.restoreViewport(
            anchorEventID: "anchor"
        ))
        application.reloadNewestProjectionWindow(fixture.account)
        application.materializeEntries()
        application.applyRestoreProjectionAnchor(fixture.account)
        application.installProvisionalRuntimeBootstrap(fixture.account)
        application.restoreHomeFeedReadState(fixture.account)
        application.setPhase(.resolvingRelays)
        application.publishOutboxRelayResults()

        #expect(fixture.probe.actions == [
            .cancelCurrentAccount,
            .applyAccountContextTransition(.activate(
                fixture.account,
                syncPolicy: fixture.syncPolicy
            )),
            .startRuntimeSession,
            .prepareHomeFeedDefinition(fixture.account),
            .applyProjectionViewportTransition(.restoreViewport(
                anchorEventID: "anchor"
            )),
            .reloadNewestProjectionWindow(fixture.account),
            .materializeEntries,
            .applyRestoreProjectionAnchor(fixture.account),
            .installProvisionalRuntimeBootstrap(fixture.account),
            .restoreHomeFeedReadState(fixture.account),
            .setPhase(.resolvingRelays),
            .publishOutboxRelayResults
        ])
    }
}

@MainActor
private final class AccountStartInteractionHandlerSpy:
    HomeTimelineAccountStartHandling {
    private(set) var inputs: [HomeTimelineAccountStartInput] = []
    private(set) var effects: HomeTimelineAccountStartEffects?

    func start(
        _ input: HomeTimelineAccountStartInput,
        effects: HomeTimelineAccountStartEffects
    ) {
        inputs.append(input)
        self.effects = effects
    }
}

@MainActor
private final class AccountStartInteractionProbe {
    var state: HomeTimelineAccountStartStoreState
    let restoredViewport: HomeTimelineRestoredViewport
    private(set) var actions: [HomeTimelineAccountStartStoreAction] = []
    private(set) var dependencies: [AccountStartInteractionDependency] = []

    init(
        state: HomeTimelineAccountStartStoreState,
        restoredViewport: HomeTimelineRestoredViewport
    ) {
        self.state = state
        self.restoredViewport = restoredViewport
    }

    var effects: HomeAccountStartInteractionEffects {
        HomeAccountStartInteractionEffects(
            environment: HomeTimelineAccountStartEnvironment(
                state: { [self] in state },
                restoreCachedSnapshot: { [self] account in
                    dependencies.append(.restoreCachedSnapshot(account))
                    return true
                },
                restoredViewport: { [self] accountID in
                    dependencies.append(.restoreViewport(accountID))
                    return restoredViewport
                },
                waitForCachedPresentation: { [self] in
                    dependencies.append(.waitForCachedPresentation)
                }
            ),
            apply: { [self] action in
                actions.append(action)
            },
            load: { [self] request in
                dependencies.append(.load(request))
            }
        )
    }
}

private enum AccountStartInteractionDependency: Equatable, Sendable {
    case restoreCachedSnapshot(NostrAccount)
    case restoreViewport(String)
    case waitForCachedPresentation
    case load(HomeTimelineAccountStartLoadRequest)
}

@MainActor
private struct AccountStartInteractionFixture {
    let account = accountStartInteractionAccount()
    let syncPolicy = NostrSyncPolicy.default(
        networkType: .cellular,
        lowPowerMode: true
    )
    let restoredViewport = HomeTimelineRestoredViewport(
        anchorEventID: "viewport"
    )
    let lifecycle: HomeTimelineLifecycleToken
    let probe: AccountStartInteractionProbe
    let handler = AccountStartInteractionHandlerSpy()
    let workflow: HomeAccountStartInteractionWorkflow
    let hasRelayRuntime: Bool

    init(hasRelayRuntime: Bool) {
        self.hasRelayRuntime = hasRelayRuntime
        let account = accountStartInteractionAccount()
        let lifecycleCoordinator = HomeTimelineLifecycleCoordinator()
        lifecycle = lifecycleCoordinator.begin(accountID: account.pubkey)
        probe = AccountStartInteractionProbe(
            state: HomeTimelineAccountStartStoreState(
                accountID: "previous",
                syncPolicy: NostrSyncPolicy.default(networkType: .wifi),
                restoreProjectionAnchorEventID: "restore",
                hasEntries: true,
                hasResolvedRelays: false
            ),
            restoredViewport: restoredViewport
        )
        workflow = HomeAccountStartInteractionWorkflow(
            accountStart: handler
        )
    }

    var context: HomeAccountStartInteractionContext {
        HomeAccountStartInteractionContext(
            state: HomeTimelineAccountStartInteractionState(
                hasRelayRuntime: hasRelayRuntime
            ),
            effects: probe.effects
        )
    }

    var expectedState: HomeTimelineAccountStartState {
        HomeTimelineAccountStartState(
            accountID: "previous",
            syncPolicy: .default(networkType: .wifi),
            restoreProjectionAnchorEventID: "restore",
            hasEntries: true,
            hasResolvedRelays: false
        )
    }

    var replacementState: HomeTimelineAccountStartStoreState {
        HomeTimelineAccountStartStoreState(
            accountID: account.pubkey,
            syncPolicy: syncPolicy,
            restoreProjectionAnchorEventID: nil,
            hasEntries: false,
            hasResolvedRelays: true
        )
    }

    var expectedReplacementState: HomeTimelineAccountStartState {
        HomeTimelineAccountStartState(
            accountID: account.pubkey,
            syncPolicy: syncPolicy,
            restoreProjectionAnchorEventID: nil,
            hasEntries: false,
            hasResolvedRelays: true
        )
    }
}

private func accountStartInteractionAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "c", count: 64),
        displayIdentifier: "interaction",
        readOnly: true
    )
}
