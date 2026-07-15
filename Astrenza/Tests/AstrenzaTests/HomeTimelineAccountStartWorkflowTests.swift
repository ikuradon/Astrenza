import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline account start workflow")
@MainActor
struct HomeTimelineAccountStartWorkflowTests {
    @Test("Input and dependency handlers preserve their values")
    func mapsInputAndDependencies() async throws {
        let account = accountStartWorkflowAccount()
        let lifecycle = HomeTimelineLifecycleToken(
            accountID: account.pubkey,
            generation: 9
        )
        let viewport = HomeTimelineRestoredViewport(anchorEventID: "anchor")
        let probe = AccountStartWorkflowEffectProbe(
            account: account,
            viewport: viewport
        )
        let coordinator = AccountStartWorkflowCoordinatorSpy()
        let workflow = HomeTimelineAccountStartWorkflow(
            coordinator: coordinator,
            outbox: AccountStartWorkflowOutboxSpy()
        )
        let input = HomeTimelineAccountStartInput(
            account: account,
            hasRelayRuntime: true
        )

        workflow.start(input, effects: probe.effects)

        #expect(coordinator.requests == [HomeTimelineAccountStartRequest(
            account: account,
            hasRelayRuntime: true
        )])
        let handlers = try #require(coordinator.handlers)
        #expect(handlers.state() == probe.state)
        #expect(await handlers.restoreCachedSnapshot(account))
        #expect(handlers.restoredViewport(account.pubkey) == viewport)
        await handlers.waitForCachedPresentation()
        await handlers.load(account, lifecycle)
        #expect(probe.dependencies == [
            .restoreCachedSnapshot(account),
            .restoreViewport(account.pubkey),
            .waitForCachedPresentation,
            .load(account, lifecycle)
        ])
    }

    @Test("Every coordinator command routes through its matching effect")
    func routesEveryCommand() {
        let account = accountStartWorkflowAccount()
        let syncPolicy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let viewport = HomeTimelineRestoredViewport(anchorEventID: "restored")
        let commands: [HomeTimelineAccountStartCommand] = [
            .cancelCurrentAccount,
            .setAccount(account, syncPolicy: syncPolicy),
            .startRuntimeSession,
            .prepareHomeFeedDefinition(account),
            .applyRestoredViewport(viewport),
            .reloadNewestProjectionWindow(account),
            .materializeEntries,
            .applyRestoreProjectionAnchor(account),
            .installProvisionalRuntimeBootstrap(account),
            .restoreHomeFeedReadState(account),
            .setPhase(.resolvingRelays),
            .activateOutbox(accountID: account.pubkey)
        ]
        let probe = AccountStartWorkflowEffectProbe(account: account)
        let coordinator = AccountStartWorkflowCoordinatorSpy(commands: commands)
        let outbox = AccountStartWorkflowOutboxSpy()
        let workflow = HomeTimelineAccountStartWorkflow(
            coordinator: coordinator,
            outbox: outbox
        )

        workflow.start(
            HomeTimelineAccountStartInput(
                account: account,
                hasRelayRuntime: false
            ),
            effects: probe.effects
        )

        #expect(probe.applications == accountStartWorkflowApplications(
            account: account,
            syncPolicy: syncPolicy,
            viewport: viewport
        ))
        #expect(outbox.activatedAccountIDs == [account.pubkey])

        outbox.recordRelayResults()

        #expect(probe.applications.last == .publishOutboxRelayResults)
    }
}

@MainActor
private final class AccountStartWorkflowCoordinatorSpy:
    HomeTimelineAccountStartCoordinating {
    private let commands: [HomeTimelineAccountStartCommand]
    private(set) var requests: [HomeTimelineAccountStartRequest] = []
    private(set) var handlers: HomeTimelineAccountStartHandlers?

    init(commands: [HomeTimelineAccountStartCommand] = []) {
        self.commands = commands
    }

    func start(
        _ request: HomeTimelineAccountStartRequest,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        requests.append(request)
        self.handlers = handlers
        commands.forEach(handlers.perform)
    }
}

@MainActor
private final class AccountStartWorkflowEffectProbe {
    let state: HomeTimelineAccountStartState
    private let viewport: HomeTimelineRestoredViewport?
    private(set) var applications: [AccountStartWorkflowApplication] = []
    private(set) var dependencies: [AccountStartWorkflowDependency] = []

    init(
        account: NostrAccount,
        viewport: HomeTimelineRestoredViewport? = nil
    ) {
        state = HomeTimelineAccountStartState(
            accountID: account.pubkey,
            syncPolicy: .default(networkType: .wifi),
            restoreProjectionAnchorEventID: viewport?.anchorEventID,
            hasEntries: true,
            hasResolvedRelays: true
        )
        self.viewport = viewport
    }

    var effects: HomeTimelineAccountStartEffects {
        HomeTimelineAccountStartEffects(
            state: { [self] in state },
            application: applicationEffects,
            restoreCachedSnapshot: { [self] account in
                dependencies.append(.restoreCachedSnapshot(account))
                return true
            },
            restoredViewport: { [self] accountID in
                dependencies.append(.restoreViewport(accountID))
                return viewport
            },
            waitForCachedPresentation: { [self] in
                dependencies.append(.waitForCachedPresentation)
            },
            load: { [self] account, lifecycle in
                dependencies.append(.load(account, lifecycle))
            }
        )
    }

    private var applicationEffects: HomeTimelineAccountStartAppEffects {
        HomeTimelineAccountStartAppEffects(
            cancelCurrentAccount: { [self] in
                applications.append(.cancelCurrentAccount)
            },
            applyAccountContextTransition: { [self] transition in
                applications.append(.applyAccountContextTransition(transition))
            },
            startRuntimeSession: { [self] in
                applications.append(.startRuntimeSession)
            },
            prepareHomeFeedDefinition: { [self] account in
                applications.append(.prepareHomeFeedDefinition(account))
            },
            applyProjectionViewportTransition: { [self] transition in
                applications.append(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { [self] account in
                applications.append(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: { [self] in
                applications.append(.materializeEntries)
            },
            applyRestoreProjectionAnchor: { [self] account in
                applications.append(.applyRestoreProjectionAnchor(account))
            },
            installProvisionalRuntimeBootstrap: { [self] account in
                applications.append(.installProvisionalRuntimeBootstrap(account))
            },
            restoreHomeFeedReadState: { [self] account in
                applications.append(.restoreHomeFeedReadState(account))
            },
            setPhase: { [self] phase in
                applications.append(.setPhase(phase))
            },
            publishOutboxRelayResults: { [self] in
                applications.append(.publishOutboxRelayResults)
            }
        )
    }
}

private enum AccountStartWorkflowApplication: Equatable, Sendable {
    case cancelCurrentAccount
    case applyAccountContextTransition(HomeTimelineAccountContextTransition)
    case startRuntimeSession
    case prepareHomeFeedDefinition(NostrAccount)
    case applyProjectionViewportTransition(
        HomeTimelineProjectionViewportTransition
    )
    case reloadNewestProjectionWindow(NostrAccount)
    case materializeEntries
    case applyRestoreProjectionAnchor(NostrAccount)
    case installProvisionalRuntimeBootstrap(NostrAccount)
    case restoreHomeFeedReadState(NostrAccount)
    case setPhase(NostrHomeTimelinePhase)
    case publishOutboxRelayResults
}

@MainActor
private final class AccountStartWorkflowOutboxSpy:
    HomeTimelineOutboxActivating {
    private(set) var activatedAccountIDs: [String] = []
    private var relayResultsHandler: (@MainActor @Sendable () -> Void)?

    func activate(
        accountID: String,
        onRelayResultsRecorded: @escaping @MainActor @Sendable () -> Void
    ) {
        activatedAccountIDs.append(accountID)
        relayResultsHandler = onRelayResultsRecorded
    }

    func recordRelayResults() {
        relayResultsHandler?()
    }
}

private enum AccountStartWorkflowDependency: Equatable, Sendable {
    case restoreCachedSnapshot(NostrAccount)
    case restoreViewport(String)
    case waitForCachedPresentation
    case load(NostrAccount, HomeTimelineLifecycleToken)
}

private func accountStartWorkflowApplications(
    account: NostrAccount,
    syncPolicy: NostrSyncPolicy,
    viewport: HomeTimelineRestoredViewport
) -> [AccountStartWorkflowApplication] {
    [
        .cancelCurrentAccount,
        .applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        )),
        .startRuntimeSession,
        .prepareHomeFeedDefinition(account),
        .applyProjectionViewportTransition(.restoreViewport(
            anchorEventID: viewport.anchorEventID
        )),
        .reloadNewestProjectionWindow(account),
        .materializeEntries,
        .applyRestoreProjectionAnchor(account),
        .installProvisionalRuntimeBootstrap(account),
        .restoreHomeFeedReadState(account),
        .setPhase(.resolvingRelays)
    ]
}

private func accountStartWorkflowAccount() -> NostrAccount {
    NostrAccount(
        pubkey: String(repeating: "a", count: 64),
        displayIdentifier: "workflow",
        readOnly: true
    )
}
