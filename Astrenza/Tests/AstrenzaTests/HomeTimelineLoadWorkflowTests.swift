import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline load workflow")
@MainActor
struct HomeTimelineLoadWorkflowTests {
    @Test("Initial loading routes its state, commands, and outcome context")
    func initialLoadRoutesEffects() async throws {
        let fixture = LoadWorkflowFixture()
        fixture.initialLoad.readsRelayAvailability = true
        fixture.initialLoad.configuresRuntime = true
        fixture.initialLoad.commands = [
            .applyActivityTransition(fixture.activityTransition),
            .installProvisionalRuntimeBootstrap(fixture.account)
        ]
        fixture.initialLoad.outcome = .loaded(fixture.state)
        fixture.initialLoad.operation = .runtimeBootstrap(
            hadCachedBootstrap: true
        )
        let request = HomeTimelineInitialLoadRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasRelayRuntime: true
        )

        await fixture.workflow.loadInitial(request, effects: fixture.effects)

        #expect(fixture.initialLoad.request == request)
        #expect(fixture.initialLoad.hasResolvedRelays == true)
        #expect(fixture.probe.relayAvailabilityReads == 1)
        #expect(fixture.probe.activityTransitions == [fixture.activityTransition])
        #expect(fixture.probe.provisionalAccounts == [fixture.account])
        #expect(fixture.probe.configuredAccounts == [fixture.account])
        let context = try #require(fixture.outcomeApplication.contexts.first)
        #expect(context.account == fixture.account)
        #expect(context.lifecycle == fixture.lifecycle)
        #expect(context.operation == .runtimeBootstrap(hadCachedBootstrap: true))
        #expect(context.resolvedRelays == fixture.resolvedRelays)
    }

    @Test("Refresh loading prepares current state and routes refresh commands")
    func refreshRoutesEffects() async throws {
        let fixture = LoadWorkflowFixture()
        fixture.refresh.commands = [
            .applyActivityTransition(fixture.activityTransition),
            .restartAccount(fixture.account)
        ]
        fixture.refresh.outcome = .failed("refresh unavailable")
        let request = HomeTimelineRefreshRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasTimelineEvents: true,
            hasRelayRuntime: false
        )

        await fixture.workflow.refreshLatest(request, effects: fixture.effects)

        #expect(fixture.refresh.request == request)
        #expect(fixture.refresh.remoteInput == HomeTimelineRefreshRemoteInput(
            current: fixture.state
        ))
        #expect(fixture.probe.currentStateReads == 1)
        #expect(fixture.probe.activityTransitions == [fixture.activityTransition])
        #expect(fixture.probe.restartedAccounts == [fixture.account])
        let context = try #require(fixture.outcomeApplication.contexts.first)
        #expect(context.operation == .refresh)
        #expect(context.resolvedRelays == fixture.resolvedRelays)
    }

    @Test("Older loading prepares database backfill and routes diagnostics")
    func olderPageRoutesEffects() async throws {
        let fixture = LoadWorkflowFixture()
        fixture.olderPage.commands = [
            .applyActivityTransition(fixture.activityTransition),
            .recordDiagnostic(fixture.backwardDiagnostic)
        ]
        fixture.olderPage.outcome = .cancelled
        let request = HomeTimelineOlderPageRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasRelayRuntime: false
        )

        await fixture.workflow.loadOlder(request, effects: fixture.effects)

        #expect(fixture.olderPage.request == request)
        let input = try #require(fixture.olderPage.remoteInput)
        #expect(input.current == fixture.state)
        #expect(input.localBackfillEvents == [])
        #expect(fixture.probe.currentStateReads == 1)
        #expect(fixture.probe.backfillRequests == [fixture.account.pubkey])
        #expect(fixture.probe.activityTransitions == [fixture.activityTransition])
        #expect(fixture.probe.backwardDiagnostics == [fixture.backwardDiagnostic])
        let context = try #require(fixture.outcomeApplication.contexts.first)
        #expect(context.operation == .older)
    }

    @Test("Outcome application commands stay behind the application effect boundary")
    func applicationCommandsRouteEffects() async {
        let fixture = LoadWorkflowFixture()
        fixture.initialLoad.outcome = .loaded(fixture.state)
        fixture.outcomeApplication.commands = [
            .replaceState(fixture.state, replacement: .complete),
            .replaceState(fixture.state, replacement: .runtimeBootstrap),
            .replaceFollowedPubkeys([fixture.account.pubkey]),
            .materializeEntries,
            .recordDiagnostic(fixture.loadDiagnostic),
            .setPhase(.loaded)
        ]
        fixture.outcomeApplication.runsPersistenceEffects = true
        let request = HomeTimelineInitialLoadRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasRelayRuntime: false
        )

        await fixture.workflow.loadInitial(request, effects: fixture.effects)

        #expect(fixture.probe.timelineStates == [fixture.state])
        #expect(fixture.probe.runtimeBootstrapStates == [fixture.state])
        #expect(fixture.probe.followedPubkeySets == [[fixture.account.pubkey]])
        #expect(fixture.probe.materializationCount == 1)
        #expect(fixture.probe.loadDiagnostics == [fixture.loadDiagnostic])
        #expect(fixture.probe.phases == [.loaded])
        #expect(fixture.probe.persistedAccounts == [fixture.account])
        #expect(fixture.probe.configuredAccounts == [fixture.account])
    }
}

@MainActor
private final class InitialLoadRunnerSpy: HomeTimelineInitialLoadRunning {
    var request: HomeTimelineInitialLoadRequest?
    var commands: [HomeTimelineInitialLoadCommand] = []
    var outcome: HomeTimelineRemoteLoadOutcome?
    var operation: HomeTimelineLoadOperation = .initial
    var readsRelayAvailability = false
    var configuresRuntime = false
    var hasResolvedRelays: Bool?

    func load(
        _ request: HomeTimelineInitialLoadRequest,
        handlers: HomeTimelineInitialLoadHandlers
    ) async {
        self.request = request
        commands.forEach(handlers.perform)
        if readsRelayAvailability {
            hasResolvedRelays = handlers.hasResolvedRelays()
        }
        if configuresRuntime {
            await handlers.configureRuntime(request.account)
        }
        guard let outcome else { return }
        await handlers.applyOutcome(
            outcome,
            operation,
            request.account,
            request.lifecycle
        )
    }
}

@MainActor
private final class RefreshRunnerSpy: HomeTimelineRefreshRunning {
    var request: HomeTimelineRefreshRequest?
    var remoteInput: HomeTimelineRefreshRemoteInput?
    var commands: [HomeTimelineRefreshCommand] = []
    var outcome: HomeTimelineRemoteLoadOutcome?

    func refresh(
        _ request: HomeTimelineRefreshRequest,
        handlers: HomeTimelineRefreshHandlers
    ) async {
        self.request = request
        remoteInput = handlers.prepareRemoteInput(request.account)
        commands.forEach(handlers.perform)
        guard let outcome else { return }
        await handlers.applyRemoteOutcome(
            outcome,
            request.account,
            request.lifecycle
        )
    }
}

@MainActor
private final class OlderPageRunnerSpy: HomeTimelineOlderPageRunning {
    var request: HomeTimelineOlderPageRequest?
    var remoteInput: HomeTimelineOlderPageRemoteInput?
    var commands: [HomeTimelineOlderPageCommand] = []
    var outcome: HomeTimelineRemoteLoadOutcome?

    func load(
        _ request: HomeTimelineOlderPageRequest,
        handlers: HomeTimelineOlderPageHandlers
    ) async {
        self.request = request
        remoteInput = handlers.prepareRemoteInput(request.account)
        commands.forEach(handlers.perform)
        guard let outcome else { return }
        await handlers.applyRemoteOutcome(
            outcome,
            request.account,
            request.lifecycle
        )
    }
}

@MainActor
private final class LoadOutcomeApplicationSpy: HomeTimelineLoadOutcomeApplying {
    var outcomes: [HomeTimelineRemoteLoadOutcome] = []
    var contexts: [HomeTimelineLoadApplicationContext] = []
    var commands: [HomeTimelineLoadApplicationCommand] = []
    var runsPersistenceEffects = false

    func apply(
        _ outcome: HomeTimelineRemoteLoadOutcome,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async {
        outcomes.append(outcome)
        contexts.append(context)
        commands.forEach(handlers.perform)
        if runsPersistenceEffects {
            await handlers.persistDatabase(context.account)
            await handlers.configureRelayRuntime(context.account)
        }
    }
}

@MainActor
private final class LoadWorkflowProbe {
    var relayAvailabilityReads = 0
    var currentStateReads = 0
    var backfillRequests: [String] = []
    var activityTransitions: [HomeTimelineActivityTransition] = []
    var provisionalAccounts: [NostrAccount] = []
    var configuredAccounts: [NostrAccount] = []
    var restartedAccounts: [NostrAccount] = []
    var backwardDiagnostics: [HomeTimelineBackwardRequestDiagnostic] = []
    var timelineStates: [NostrHomeTimelineState] = []
    var runtimeBootstrapStates: [NostrHomeTimelineState] = []
    var followedPubkeySets: [[String]] = []
    var materializationCount = 0
    var persistedAccounts: [NostrAccount] = []
    var loadDiagnostics: [HomeTimelineLoadDiagnostic] = []
    var phases: [NostrHomeTimelinePhase] = []
}

@MainActor
private struct LoadWorkflowFixture {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let state: NostrHomeTimelineState
    let resolvedRelays = ["wss://relay.example"]
    let activityTransition: HomeTimelineActivityTransition
    let backwardDiagnostic = HomeTimelineBackwardRequestDiagnostic(
        relayURL: "wss://relay.example",
        subscriptionID: "astrenza-home-older",
        message: "older enqueue failed"
    )
    let loadDiagnostic = HomeTimelineLoadDiagnostic(
        relayURL: "wss://relay.example",
        kind: .partialFailure,
        subscriptionID: "astrenza-bootstrap",
        message: "bootstrap refresh failed"
    )
    let initialLoad = InitialLoadRunnerSpy()
    let refresh = RefreshRunnerSpy()
    let olderPage = OlderPageRunnerSpy()
    let outcomeApplication = LoadOutcomeApplicationSpy()
    let probe = LoadWorkflowProbe()
    let workflow: HomeTimelineLoadWorkflow

    init() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        self.account = account
        self.lifecycle = HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 7
        )
        self.state = NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: [account.pubkey],
            noteEvents: [],
            metadataEvents: []
        )
        self.activityTransition = HomeTimelineActivityCoordinator().setPhase(
            .loadingHome
        )
        self.workflow = HomeTimelineLoadWorkflow(
            initialLoad: initialLoad,
            refresh: refresh,
            olderPage: olderPage,
            outcomeApplication: outcomeApplication
        )
    }

    var effects: HomeTimelineLoadEffects {
        HomeTimelineLoadEffects(
            state: HomeTimelineLoadStateProviders(
                hasResolvedRelays: { [probe] in
                    probe.relayAvailabilityReads += 1
                    return true
                },
                currentState: { [probe, state] in
                    probe.currentStateReads += 1
                    return state
                },
                localBackfillEvents: { [probe] account, _ in
                    probe.backfillRequests.append(account.pubkey)
                    return []
                },
                resolvedRelays: { [resolvedRelays] in resolvedRelays }
            ),
            application: HomeTimelineLoadAppEffects(
                applyActivityTransition: { [probe] transition in
                    probe.activityTransitions.append(transition)
                },
                installProvisionalRuntimeBootstrap: { [probe] account in
                    probe.provisionalAccounts.append(account)
                },
                configureRuntime: { [probe] account in
                    probe.configuredAccounts.append(account)
                },
                restartAccount: { [probe] account in
                    probe.restartedAccounts.append(account)
                },
                recordBackwardDiagnostic: { [probe] diagnostic in
                    probe.backwardDiagnostics.append(diagnostic)
                },
                replaceTimelineState: { [probe] state in
                    probe.timelineStates.append(state)
                },
                replaceRuntimeBootstrapState: { [probe] state in
                    probe.runtimeBootstrapStates.append(state)
                },
                replaceFollowedPubkeys: { [probe] pubkeys in
                    probe.followedPubkeySets.append(pubkeys)
                },
                materializeEntries: { [probe] in
                    probe.materializationCount += 1
                },
                persistDatabase: { [probe] account in
                    probe.persistedAccounts.append(account)
                },
                recordLoadDiagnostic: { [probe] diagnostic in
                    probe.loadDiagnostics.append(diagnostic)
                },
                setPhase: { [probe] phase in
                    probe.phases.append(phase)
                }
            )
        )
    }
}
