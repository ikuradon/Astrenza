import AstrenzaCore

@MainActor
protocol HomeTimelineAccountStartHandling: AnyObject {
    func start(
        _ input: HomeTimelineAccountStartInput,
        effects: HomeTimelineAccountStartEffects
    )
}

extension HomeTimelineAccountStartWorkflow: HomeTimelineAccountStartHandling {}

struct HomeTimelineAccountStartInteractionState: Equatable, Sendable {
    let hasRelayRuntime: Bool
}

struct HomeTimelineAccountStartStoreState: Equatable, Sendable {
    let accountID: String?
    let syncPolicy: NostrSyncPolicy
    let restoreProjectionAnchorEventID: String?
    let hasEntries: Bool
    let hasResolvedRelays: Bool
}

enum HomeTimelineAccountStartStoreAction: Equatable, Sendable {
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
    case setPhase(NostrHomeTimelinePhase)
    case publishOutboxRelayResults
}

struct HomeTimelineAccountStartLoadRequest: Equatable, Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
}

struct HomeTimelineAccountStartEnvironment: Sendable {
    typealias StateProvider = @MainActor @Sendable (
    ) -> HomeTimelineAccountStartStoreState
    typealias CachedSnapshotRestorer = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Bool
    typealias ViewportRestorer = @MainActor @Sendable (
        _ accountID: String
    ) -> HomeTimelineRestoredViewport?
    typealias CachedPresentationWaiter = @MainActor @Sendable () async -> Void
    typealias CachedReadStateRestorer = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void

    let state: StateProvider
    let restoreCachedSnapshot: CachedSnapshotRestorer
    let restoredViewport: ViewportRestorer
    let waitForCachedPresentation: CachedPresentationWaiter
    let restoreCachedReadState: CachedReadStateRestorer
}

struct HomeAccountStartInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineAccountStartStoreAction
    ) -> Void
    typealias LoadEffect = @MainActor @Sendable (
        _ request: HomeTimelineAccountStartLoadRequest
    ) async -> Void

    let environment: HomeTimelineAccountStartEnvironment
    let apply: ApplicationEffect
    let load: LoadEffect
}

struct HomeAccountStartInteractionContext: Sendable {
    let state: HomeTimelineAccountStartInteractionState
    let effects: HomeAccountStartInteractionEffects
}

@MainActor
final class HomeAccountStartInteractionWorkflow {
    private let accountStart: any HomeTimelineAccountStartHandling

    init(accountStart: any HomeTimelineAccountStartHandling) {
        self.accountStart = accountStart
    }

    func start(
        account: NostrAccount,
        context: HomeAccountStartInteractionContext
    ) {
        accountStart.start(
            HomeTimelineAccountStartInput(
                account: account,
                hasRelayRuntime: context.state.hasRelayRuntime
            ),
            effects: accountStartEffects(for: context.effects)
        )
    }

    private func accountStartEffects(
        for effects: HomeAccountStartInteractionEffects
    ) -> HomeTimelineAccountStartEffects {
        HomeTimelineAccountStartEffects(
            state: {
                let state = effects.environment.state()
                return HomeTimelineAccountStartState(
                    accountID: state.accountID,
                    syncPolicy: state.syncPolicy,
                    restoreProjectionAnchorEventID:
                        state.restoreProjectionAnchorEventID,
                    hasEntries: state.hasEntries,
                    hasResolvedRelays: state.hasResolvedRelays
                )
            },
            application: applicationEffects(for: effects),
            restoreCachedSnapshot: effects.environment.restoreCachedSnapshot,
            restoredViewport: effects.environment.restoredViewport,
            waitForCachedPresentation:
                effects.environment.waitForCachedPresentation,
            restoreCachedReadState:
                effects.environment.restoreCachedReadState,
            load: { account, lifecycle in
                await effects.load(HomeTimelineAccountStartLoadRequest(
                    account: account,
                    lifecycle: lifecycle
                ))
            }
        )
    }

    private func applicationEffects(
        for effects: HomeAccountStartInteractionEffects
    ) -> HomeTimelineAccountStartAppEffects {
        HomeTimelineAccountStartAppEffects(
            cancelCurrentAccount: {
                effects.apply(.cancelCurrentAccount)
            },
            applyAccountContextTransition: { transition in
                effects.apply(.applyAccountContextTransition(transition))
            },
            startRuntimeSession: {
                effects.apply(.startRuntimeSession)
            },
            prepareHomeFeedDefinition: { account in
                effects.apply(.prepareHomeFeedDefinition(account))
            },
            applyProjectionViewportTransition: { transition in
                effects.apply(.applyProjectionViewportTransition(transition))
            },
            reloadNewestProjectionWindow: { account in
                effects.apply(.reloadNewestProjectionWindow(account))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            },
            applyRestoreProjectionAnchor: { account in
                effects.apply(.applyRestoreProjectionAnchor(account))
            },
            installProvisionalRuntimeBootstrap: { account in
                effects.apply(.installProvisionalRuntimeBootstrap(account))
            },
            setPhase: { phase in
                effects.apply(.setPhase(phase))
            },
            publishOutboxRelayResults: {
                effects.apply(.publishOutboxRelayResults)
            }
        )
    }
}
