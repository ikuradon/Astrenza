import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline load interaction workflow")
@MainActor
struct HomeTimelineLoadInteractionTests {
    @Test("Load entry points build requests from the current interaction state")
    func buildsRequests() async {
        let fixture = LoadInteractionFixture(
            state: HomeTimelineLoadInteractionState(
                hasRelayRuntime: true,
                hasTimelineEvents: true
            )
        )

        await fixture.workflow.loadInitial(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            context: fixture.context
        )
        await fixture.workflow.refreshLatest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            context: fixture.context
        )
        await fixture.workflow.loadOlder(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            context: fixture.context
        )

        #expect(fixture.router.initialRequest == HomeTimelineInitialLoadRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasRelayRuntime: true
        ))
        #expect(fixture.router.refreshRequest == HomeTimelineRefreshRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasTimelineEvents: true,
            hasRelayRuntime: true
        ))
        #expect(fixture.router.olderRequest == HomeTimelineOlderPageRequest(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            hasRelayRuntime: true
        ))
    }

    @Test("Environment providers remain dynamic behind the routing boundary")
    func forwardsEnvironmentProviders() async {
        let fixture = LoadInteractionFixture()
        fixture.router.readsEnvironment = true

        await fixture.workflow.loadInitial(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            context: fixture.context
        )

        #expect(fixture.router.hasResolvedRelays == true)
        #expect(fixture.router.currentState == fixture.timelineState)
        #expect(fixture.router.localBackfillEvents == [])
        #expect(fixture.router.resolvedRelays == fixture.resolvedRelays)
        #expect(fixture.probe.relayAvailabilityReads == 1)
        #expect(fixture.probe.currentStateReads == 1)
        #expect(fixture.probe.backfillRequests == [fixture.account.pubkey])
        #expect(fixture.probe.resolvedRelayReads == 1)
    }

    @Test("Load applications route through typed sync and async boundaries")
    func routesApplications() async {
        let fixture = LoadInteractionFixture()
        fixture.router.applicationFixture = fixture.applicationFixture

        await fixture.workflow.loadInitial(
            account: fixture.account,
            lifecycle: fixture.lifecycle,
            context: fixture.context
        )

        #expect(fixture.probe.applications == [
            .applyActivityTransition(fixture.activityTransition),
            .installProvisionalRuntimeBootstrap(fixture.account),
            .restartAccount(fixture.account),
            .applyRelayStatusTransition(fixture.relayStatus.transition),
            .replaceTimelineState(fixture.timelineState),
            .replaceRuntimeBootstrapState(fixture.timelineState),
            .replaceFollowedPubkeys([fixture.account.pubkey]),
            .materializeEntries,
            .applyRelayStatusTransition(fixture.relayStatus.transition),
            .setPhase(.loaded)
        ])
        #expect(fixture.relayStatus.records == [
            fixture.backwardDiagnosticRecord,
            fixture.loadDiagnosticRecord
        ])
        #expect(fixture.probe.asyncApplications == [
            .configureRuntime(fixture.account),
            .persistDatabase(fixture.account)
        ])
    }
}

@MainActor
private final class LoadInteractionRouterSpy: HomeTimelineLoadRouting {
    var initialRequest: HomeTimelineInitialLoadRequest?
    var refreshRequest: HomeTimelineRefreshRequest?
    var olderRequest: HomeTimelineOlderPageRequest?
    var readsEnvironment = false
    var applicationFixture: LoadInteractionApplicationFixture?
    var hasResolvedRelays: Bool?
    var currentState: NostrHomeTimelineState?
    var localBackfillEvents: [NostrEvent]?
    var resolvedRelays: [String] = []

    func loadInitial(
        _ request: HomeTimelineInitialLoadRequest,
        effects: HomeTimelineLoadEffects
    ) async {
        initialRequest = request
        if readsEnvironment {
            readEnvironment(from: effects, account: request.account)
        }
        if let applicationFixture {
            await apply(applicationFixture, with: effects)
        }
    }

    func refreshLatest(
        _ request: HomeTimelineRefreshRequest,
        effects _: HomeTimelineLoadEffects
    ) async {
        refreshRequest = request
    }

    func loadOlder(
        _ request: HomeTimelineOlderPageRequest,
        effects _: HomeTimelineLoadEffects
    ) async {
        olderRequest = request
    }

    private func readEnvironment(
        from effects: HomeTimelineLoadEffects,
        account: NostrAccount
    ) {
        hasResolvedRelays = effects.state.hasResolvedRelays()
        currentState = effects.state.currentState()
        if let currentState {
            localBackfillEvents = effects.state.localBackfillEvents(
                account,
                currentState
            )
        }
        resolvedRelays = effects.state.resolvedRelays()
    }

    private func apply(
        _ fixture: LoadInteractionApplicationFixture,
        with effects: HomeTimelineLoadEffects
    ) async {
        effects.application.applyActivityTransition(fixture.activityTransition)
        effects.application.installProvisionalRuntimeBootstrap(fixture.account)
        await effects.application.configureRuntime(fixture.account)
        effects.application.restartAccount(fixture.account)
        effects.application.recordBackwardDiagnostic(fixture.backwardDiagnostic)
        effects.application.replaceTimelineState(fixture.timelineState)
        effects.application.replaceRuntimeBootstrapState(fixture.timelineState)
        effects.application.replaceFollowedPubkeys([fixture.account.pubkey])
        effects.application.materializeEntries()
        await effects.application.persistDatabase(fixture.account)
        effects.application.recordLoadDiagnostic(fixture.loadDiagnostic)
        effects.application.setPhase(.loaded)
    }
}

@MainActor
private final class LoadInteractionProbe {
    var relayAvailabilityReads = 0
    var currentStateReads = 0
    var backfillRequests: [String] = []
    var resolvedRelayReads = 0
    var applications: [HomeTimelineLoadApplication] = []
    var asyncApplications: [HomeTimelineLoadAsyncApplication] = []
}

private struct LoadInteractionApplicationFixture {
    let account: NostrAccount
    let timelineState: NostrHomeTimelineState
    let activityTransition: HomeTimelineActivityTransition
    let backwardDiagnostic: HomeTimelineBackwardRequestDiagnostic
    let loadDiagnostic: HomeTimelineLoadDiagnostic
}

@MainActor
private struct LoadInteractionFixture {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let timelineState: NostrHomeTimelineState
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
    let state: HomeTimelineLoadInteractionState
    let router = LoadInteractionRouterSpy()
    let probe = LoadInteractionProbe()
    let relayStatus = RelayStatusRecordingSpy()
    let workflow: HomeTimelineLoadInteractionWorkflow

    init(
        state: HomeTimelineLoadInteractionState = HomeTimelineLoadInteractionState(
            hasRelayRuntime: false,
            hasTimelineEvents: false
        )
    ) {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "load-interaction",
            readOnly: true
        )
        self.account = account
        self.lifecycle = HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 7
        )
        self.timelineState = NostrHomeTimelineState(
            relays: resolvedRelays,
            followedPubkeys: [account.pubkey],
            noteEvents: [],
            metadataEvents: []
        )
        self.activityTransition = HomeTimelineActivityCoordinator().setPhase(
            .loadingHome
        )
        self.state = state
        self.workflow = HomeTimelineLoadInteractionWorkflow(
            loadWorkflow: router,
            relayStatus: relayStatus
        )
    }

    var applicationFixture: LoadInteractionApplicationFixture {
        LoadInteractionApplicationFixture(
            account: account,
            timelineState: timelineState,
            activityTransition: activityTransition,
            backwardDiagnostic: backwardDiagnostic,
            loadDiagnostic: loadDiagnostic
        )
    }

    var backwardDiagnosticRecord: HomeTimelineRelayStatusRecord {
        relayStatusRecord(
            relayURL: backwardDiagnostic.relayURL,
            kind: .partialFailure,
            subscriptionID: backwardDiagnostic.subscriptionID,
            message: backwardDiagnostic.message
        )
    }

    var loadDiagnosticRecord: HomeTimelineRelayStatusRecord {
        relayStatusRecord(
            relayURL: loadDiagnostic.relayURL,
            kind: loadDiagnostic.kind,
            subscriptionID: loadDiagnostic.subscriptionID,
            message: loadDiagnostic.message
        )
    }

    private func relayStatusRecord(
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        subscriptionID: String?,
        message: String
    ) -> HomeTimelineRelayStatusRecord {
        HomeTimelineRelayStatusRecord(
            accountID: account.pubkey,
            resolvedRelays: resolvedRelays,
            relayURL: relayURL,
            kind: kind,
            subscriptionID: subscriptionID,
            eventCount: 0,
            newestCreatedAt: nil,
            oldestCreatedAt: nil,
            message: message
        )
    }

    var context: HomeTimelineLoadInteractionContext {
        HomeTimelineLoadInteractionContext(
            state: state,
            effects: HomeTimelineLoadInteractionEffects(
                environment: HomeTimelineLoadEnvironment(
                    hasResolvedRelays: { [probe] in
                        probe.relayAvailabilityReads += 1
                        return true
                    },
                    currentState: { [probe, timelineState] in
                        probe.currentStateReads += 1
                        return timelineState
                    },
                    localBackfillEvents: { [probe] account, _ in
                        probe.backfillRequests.append(account.pubkey)
                        return []
                    },
                    resolvedRelays: { [probe, resolvedRelays] in
                        probe.resolvedRelayReads += 1
                        return resolvedRelays
                    }
                ),
                apply: { [probe] application in
                    probe.applications.append(application)
                },
                perform: { [probe] application in
                    probe.asyncApplications.append(application)
                }
            )
        )
    }
}
