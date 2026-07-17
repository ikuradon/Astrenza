import AstrenzaCore

@MainActor
protocol HomeTimelineInitialLoadRunning: AnyObject {
    func load(
        _ request: HomeTimelineInitialLoadRequest,
        handlers: HomeTimelineInitialLoadHandlers
    ) async
}

extension HomeTimelineInitialLoadWorkflow: HomeTimelineInitialLoadRunning {}

@MainActor
protocol HomeTimelineRefreshRunning: AnyObject {
    func refresh(
        _ request: HomeTimelineRefreshRequest,
        handlers: HomeTimelineRefreshHandlers
    ) async
}

extension HomeTimelineRefreshWorkflow: HomeTimelineRefreshRunning {}

@MainActor
protocol HomeTimelineOlderPageRunning: AnyObject {
    func load(
        _ request: HomeTimelineOlderPageRequest,
        handlers: HomeTimelineOlderPageHandlers
    ) async
}

extension HomeTimelineOlderPageWorkflow: HomeTimelineOlderPageRunning {}

@MainActor
protocol HomeTimelineLoadOutcomeApplying: AnyObject {
    func apply(
        _ outcome: HomeTimelineRemoteLoadOutcome,
        context: HomeTimelineLoadApplicationContext,
        handlers: HomeTimelineLoadApplicationHandlers
    ) async
}

extension HomeTimelineLoadApplicationCoordinator: HomeTimelineLoadOutcomeApplying {}

struct HomeTimelineLoadStateProviders: Sendable {
    typealias BooleanProvider = @MainActor @Sendable () -> Bool
    typealias StateProvider = @MainActor @Sendable () -> NostrHomeTimelineState?
    typealias BackfillProvider = @MainActor @Sendable (
        _ account: NostrAccount,
        _ current: NostrHomeTimelineState
    ) -> [NostrEvent]?
    typealias RelayProvider = @MainActor @Sendable () -> [String]
    typealias OptionalStringProvider = @MainActor @Sendable () -> String?

    let hasResolvedRelays: BooleanProvider
    let currentState: StateProvider
    let localBackfillEvents: BackfillProvider
    let resolvedRelays: RelayProvider
    let restoreProjectionAnchorEventID: OptionalStringProvider

    init(
        hasResolvedRelays: @escaping BooleanProvider,
        currentState: @escaping StateProvider,
        localBackfillEvents: @escaping BackfillProvider,
        resolvedRelays: @escaping RelayProvider,
        restoreProjectionAnchorEventID:
            @escaping OptionalStringProvider = { nil }
    ) {
        self.hasResolvedRelays = hasResolvedRelays
        self.currentState = currentState
        self.localBackfillEvents = localBackfillEvents
        self.resolvedRelays = resolvedRelays
        self.restoreProjectionAnchorEventID =
            restoreProjectionAnchorEventID
    }
}

struct HomeTimelineLoadAppEffects: Sendable {
    typealias ActivityEffect = @MainActor @Sendable (
        _ transition: HomeTimelineActivityTransition
    ) -> Void
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias AsyncAccountEffect = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias StateEffect = @MainActor @Sendable (
        _ state: NostrHomeTimelineState
    ) -> Void
    typealias PubkeysEffect = @MainActor @Sendable (_ pubkeys: [String]) -> Void
    typealias Action = @MainActor @Sendable () -> Void
    typealias BackwardDiagnosticEffect = @MainActor @Sendable (
        _ diagnostic: HomeTimelineBackwardRequestDiagnostic
    ) -> Void
    typealias LoadDiagnosticEffect = @MainActor @Sendable (
        _ diagnostic: HomeTimelineLoadDiagnostic
    ) -> Void
    typealias PhaseEffect = @MainActor @Sendable (
        _ phase: NostrHomeTimelinePhase
    ) -> Void

    let applyActivityTransition: ActivityEffect
    let installProvisionalRuntimeBootstrap: AccountEffect
    let configureRuntime: AsyncAccountEffect
    let restartAccount: AccountEffect
    let recordBackwardDiagnostic: BackwardDiagnosticEffect
    let replaceTimelineState: StateEffect
    let replaceRuntimeBootstrapState: StateEffect
    let replaceFollowedPubkeys: PubkeysEffect
    let applyRestoreProjectionAnchor: AccountEffect
    let materializeEntries: Action
    let persistDatabase: AsyncAccountEffect
    let recordLoadDiagnostic: LoadDiagnosticEffect
    let setPhase: PhaseEffect
}

struct HomeTimelineLoadEffects: Sendable {
    let state: HomeTimelineLoadStateProviders
    let application: HomeTimelineLoadAppEffects
}

@MainActor
final class HomeTimelineLoadWorkflow {
    private let initialLoad: any HomeTimelineInitialLoadRunning
    private let refresh: any HomeTimelineRefreshRunning
    private let olderPage: any HomeTimelineOlderPageRunning
    private let outcomeApplication: any HomeTimelineLoadOutcomeApplying

    init(
        initialLoad: any HomeTimelineInitialLoadRunning,
        refresh: any HomeTimelineRefreshRunning,
        olderPage: any HomeTimelineOlderPageRunning,
        outcomeApplication: any HomeTimelineLoadOutcomeApplying
    ) {
        self.initialLoad = initialLoad
        self.refresh = refresh
        self.olderPage = olderPage
        self.outcomeApplication = outcomeApplication
    }

    func loadInitial(
        _ request: HomeTimelineInitialLoadRequest,
        effects: HomeTimelineLoadEffects
    ) async {
        await initialLoad.load(
            request,
            handlers: initialLoadHandlers(effects: effects)
        )
    }

    func refreshLatest(
        _ request: HomeTimelineRefreshRequest,
        effects: HomeTimelineLoadEffects
    ) async {
        await refresh.refresh(
            request,
            handlers: refreshHandlers(effects: effects)
        )
    }

    func loadOlder(
        _ request: HomeTimelineOlderPageRequest,
        effects: HomeTimelineLoadEffects
    ) async {
        await olderPage.load(
            request,
            handlers: olderPageHandlers(effects: effects)
        )
    }

    private func initialLoadHandlers(
        effects: HomeTimelineLoadEffects
    ) -> HomeTimelineInitialLoadHandlers {
        HomeTimelineInitialLoadHandlers(
            perform: { [weak self] command in
                self?.apply(command, effects: effects.application)
            },
            hasResolvedRelays: effects.state.hasResolvedRelays,
            configureRuntime: effects.application.configureRuntime,
            applyOutcome: { [weak self] outcome, operation, account, lifecycle in
                await self?.apply(
                    outcome,
                    operation: operation,
                    account: account,
                    lifecycle: lifecycle,
                    effects: effects
                )
            }
        )
    }

    private func refreshHandlers(
        effects: HomeTimelineLoadEffects
    ) -> HomeTimelineRefreshHandlers {
        HomeTimelineRefreshHandlers(
            perform: { [weak self] command in
                self?.apply(command, effects: effects.application)
            },
            prepareRemoteInput: { _ in
                effects.state.currentState().map(HomeTimelineRefreshRemoteInput.init)
            },
            configureRuntime: effects.application.configureRuntime,
            applyRemoteOutcome: { [weak self] outcome, account, lifecycle in
                await self?.apply(
                    outcome,
                    operation: .refresh,
                    account: account,
                    lifecycle: lifecycle,
                    effects: effects
                )
            }
        )
    }

    private func olderPageHandlers(
        effects: HomeTimelineLoadEffects
    ) -> HomeTimelineOlderPageHandlers {
        HomeTimelineOlderPageHandlers(
            perform: { [weak self] command in
                self?.apply(command, effects: effects.application)
            },
            prepareRemoteInput: { account in
                guard let current = effects.state.currentState() else { return nil }
                return HomeTimelineOlderPageRemoteInput(
                    current: current,
                    localBackfillEvents: effects.state.localBackfillEvents(
                        account,
                        current
                    )
                )
            },
            applyRemoteOutcome: { [weak self] outcome, account, lifecycle in
                await self?.apply(
                    outcome,
                    operation: .older,
                    account: account,
                    lifecycle: lifecycle,
                    effects: effects
                )
            }
        )
    }

    private func apply(
        _ outcome: HomeTimelineRemoteLoadOutcome,
        operation: HomeTimelineLoadOperation,
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        effects: HomeTimelineLoadEffects
    ) async {
        await outcomeApplication.apply(
            outcome,
            context: HomeTimelineLoadApplicationContext(
                account: account,
                lifecycle: lifecycle,
                operation: operation,
                resolvedRelays: effects.state.resolvedRelays(),
                restoreProjectionAnchorEventID:
                    effects.state.restoreProjectionAnchorEventID()
            ),
            handlers: applicationHandlers(effects: effects.application)
        )
    }

    private func applicationHandlers(
        effects: HomeTimelineLoadAppEffects
    ) -> HomeTimelineLoadApplicationHandlers {
        HomeTimelineLoadApplicationHandlers(
            perform: { [weak self] command in
                self?.apply(command, effects: effects)
            },
            persistDatabase: effects.persistDatabase,
            configureRelayRuntime: effects.configureRuntime
        )
    }

    private func apply(
        _ command: HomeTimelineInitialLoadCommand,
        effects: HomeTimelineLoadAppEffects
    ) {
        switch command {
        case .applyActivityTransition(let transition):
            effects.applyActivityTransition(transition)
        case .installProvisionalRuntimeBootstrap(let account):
            effects.installProvisionalRuntimeBootstrap(account)
        }
    }

    private func apply(
        _ command: HomeTimelineRefreshCommand,
        effects: HomeTimelineLoadAppEffects
    ) {
        switch command {
        case .applyActivityTransition(let transition):
            effects.applyActivityTransition(transition)
        case .restartAccount(let account):
            effects.restartAccount(account)
        }
    }

    private func apply(
        _ command: HomeTimelineOlderPageCommand,
        effects: HomeTimelineLoadAppEffects
    ) {
        switch command {
        case .applyActivityTransition(let transition):
            effects.applyActivityTransition(transition)
        case .recordDiagnostic(let diagnostic):
            effects.recordBackwardDiagnostic(diagnostic)
        }
    }

    private func apply(
        _ command: HomeTimelineLoadApplicationCommand,
        effects: HomeTimelineLoadAppEffects
    ) {
        switch command {
        case .replaceState(let state, let replacement):
            apply(state, replacement: replacement, effects: effects)
        case .replaceFollowedPubkeys(let pubkeys):
            effects.replaceFollowedPubkeys(pubkeys)
        case .applyRestoreProjectionAnchor(let account):
            effects.applyRestoreProjectionAnchor(account)
        case .materializeEntries:
            effects.materializeEntries()
        case .recordDiagnostic(let diagnostic):
            effects.recordLoadDiagnostic(diagnostic)
        case .setPhase(let phase):
            effects.setPhase(phase)
        }
    }

    private func apply(
        _ state: NostrHomeTimelineState,
        replacement: HomeTimelineLoadStateReplacement,
        effects: HomeTimelineLoadAppEffects
    ) {
        switch replacement {
        case .complete:
            effects.replaceTimelineState(state)
        case .runtimeBootstrap:
            effects.replaceRuntimeBootstrapState(state)
        }
    }
}
