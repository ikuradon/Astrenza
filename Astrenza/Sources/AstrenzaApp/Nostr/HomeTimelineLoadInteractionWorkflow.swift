import AstrenzaCore

@MainActor
protocol HomeTimelineLoadRouting: AnyObject {
    func loadInitial(
        _ request: HomeTimelineInitialLoadRequest,
        effects: HomeTimelineLoadEffects
    ) async

    func refreshLatest(
        _ request: HomeTimelineRefreshRequest,
        effects: HomeTimelineLoadEffects
    ) async

    func loadOlder(
        _ request: HomeTimelineOlderPageRequest,
        effects: HomeTimelineLoadEffects
    ) async
}

extension HomeTimelineLoadWorkflow: HomeTimelineLoadRouting {}

struct HomeTimelineLoadInteractionState: Equatable, Sendable {
    let hasRelayRuntime: Bool
    let hasTimelineEvents: Bool
    let syncPolicy: NostrSyncPolicy

    init(
        hasRelayRuntime: Bool,
        hasTimelineEvents: Bool,
        syncPolicy: NostrSyncPolicy = .default()
    ) {
        self.hasRelayRuntime = hasRelayRuntime
        self.hasTimelineEvents = hasTimelineEvents
        self.syncPolicy = syncPolicy
    }
}

struct HomeTimelineLoadEnvironment: Sendable {
    typealias BooleanProvider = @MainActor @Sendable () -> Bool
    typealias StateProvider = @MainActor @Sendable () -> NostrHomeTimelineState?
    typealias BackfillProvider = @MainActor @Sendable (
        _ account: NostrAccount,
        _ current: NostrHomeTimelineState
    ) -> [NostrEvent]?
    typealias RelayProvider = @MainActor @Sendable () -> [String]

    let hasResolvedRelays: BooleanProvider
    let currentState: StateProvider
    let localBackfillEvents: BackfillProvider
    let resolvedRelays: RelayProvider
}

enum HomeTimelineLoadApplication: Equatable, Sendable {
    case applyActivityTransition(HomeTimelineActivityTransition)
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition)
    case installProvisionalRuntimeBootstrap(NostrAccount)
    case restartAccount(NostrAccount)
    case replaceTimelineState(NostrHomeTimelineState)
    case replaceRuntimeBootstrapState(NostrHomeTimelineState)
    case replaceFollowedPubkeys([String])
    case materializeEntries
    case setPhase(NostrHomeTimelinePhase)
}

enum HomeTimelineLoadAsyncApplication: Equatable, Sendable {
    case configureRuntime(NostrAccount)
    case persistDatabase(NostrAccount)
}

struct HomeTimelineLoadInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineLoadApplication
    ) -> Void
    typealias AsyncApplicationEffect = @MainActor @Sendable (
        _ application: HomeTimelineLoadAsyncApplication
    ) async -> Void

    let environment: HomeTimelineLoadEnvironment
    let apply: ApplicationEffect
    let perform: AsyncApplicationEffect
}

struct HomeTimelineLoadInteractionContext: Sendable {
    let state: HomeTimelineLoadInteractionState
    let effects: HomeTimelineLoadInteractionEffects
}

@MainActor
final class HomeTimelineLoadInteractionWorkflow {
    private let loadWorkflow: any HomeTimelineLoadRouting
    private let relayStatus: any HomeTimelineRelayStatusRecording

    init(
        loadWorkflow: any HomeTimelineLoadRouting,
        relayStatus: any HomeTimelineRelayStatusRecording
    ) {
        self.loadWorkflow = loadWorkflow
        self.relayStatus = relayStatus
    }

    func loadInitial(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async {
        await loadWorkflow.loadInitial(
            HomeTimelineInitialLoadRequest(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: context.state.hasRelayRuntime,
                syncPolicy: context.state.syncPolicy
            ),
            effects: loadEffects(account: account, for: context.effects)
        )
    }

    func refreshLatest(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async {
        await loadWorkflow.refreshLatest(
            HomeTimelineRefreshRequest(
                account: account,
                lifecycle: lifecycle,
                hasTimelineEvents: context.state.hasTimelineEvents,
                hasRelayRuntime: context.state.hasRelayRuntime,
                syncPolicy: context.state.syncPolicy
            ),
            effects: loadEffects(account: account, for: context.effects)
        )
    }

    func loadOlder(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        context: HomeTimelineLoadInteractionContext
    ) async {
        await loadWorkflow.loadOlder(
            HomeTimelineOlderPageRequest(
                account: account,
                lifecycle: lifecycle,
                hasRelayRuntime: context.state.hasRelayRuntime,
                syncPolicy: context.state.syncPolicy
            ),
            effects: loadEffects(account: account, for: context.effects)
        )
    }

    private func loadEffects(
        account: NostrAccount,
        for effects: HomeTimelineLoadInteractionEffects
    ) -> HomeTimelineLoadEffects {
        HomeTimelineLoadEffects(
            state: HomeTimelineLoadStateProviders(
                hasResolvedRelays: effects.environment.hasResolvedRelays,
                currentState: effects.environment.currentState,
                localBackfillEvents: effects.environment.localBackfillEvents,
                resolvedRelays: effects.environment.resolvedRelays
            ),
            application: applicationEffects(
                accountID: account.pubkey,
                for: effects
            )
        )
    }

    private func applicationEffects(
        accountID: String,
        for effects: HomeTimelineLoadInteractionEffects
    ) -> HomeTimelineLoadAppEffects {
        HomeTimelineLoadAppEffects(
            applyActivityTransition: { transition in
                effects.apply(.applyActivityTransition(transition))
            },
            installProvisionalRuntimeBootstrap: { account in
                effects.apply(.installProvisionalRuntimeBootstrap(account))
            },
            configureRuntime: { account in
                await effects.perform(.configureRuntime(account))
            },
            restartAccount: { account in
                effects.apply(.restartAccount(account))
            },
            recordBackwardDiagnostic: { diagnostic in
                self.recordDiagnostic(
                    diagnostic,
                    accountID: accountID,
                    effects: effects
                )
            },
            replaceTimelineState: { state in
                effects.apply(.replaceTimelineState(state))
            },
            replaceRuntimeBootstrapState: { state in
                effects.apply(.replaceRuntimeBootstrapState(state))
            },
            replaceFollowedPubkeys: { pubkeys in
                effects.apply(.replaceFollowedPubkeys(pubkeys))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            },
            persistDatabase: { account in
                await effects.perform(.persistDatabase(account))
            },
            recordLoadDiagnostic: { diagnostic in
                self.recordDiagnostic(
                    diagnostic,
                    accountID: accountID,
                    effects: effects
                )
            },
            setPhase: { phase in
                effects.apply(.setPhase(phase))
            }
        )
    }

    private func recordDiagnostic<Diagnostic>(
        _ diagnostic: Diagnostic,
        accountID: String,
        effects: HomeTimelineLoadInteractionEffects
    ) where Diagnostic: HomeTimelineRelayStatusDiagnostic {
        guard let transition = relayStatus.recordDiagnostic(
            diagnostic,
            accountID: accountID,
            resolvedRelays: effects.environment.resolvedRelays()
        ) else { return }
        effects.apply(.applyRelayStatusTransition(transition))
    }
}
