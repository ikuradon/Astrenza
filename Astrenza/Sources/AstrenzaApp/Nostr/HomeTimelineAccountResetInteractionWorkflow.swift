import AstrenzaCore

@MainActor
protocol HomeTimelineAccountResetHandling: AnyObject {
    var isRuntimeTerminating: Bool { get }

    func reset(
        _ input: HomeTimelineAccountResetInput,
        effects: HomeTimelineAccountResetEffects
    )
}

extension HomeTimelineAccountResetWorkflow: HomeTimelineAccountResetHandling {}

struct HomeTimelineAccountResetInteractionState: Sendable {
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    let resolvedRelays: [String]
}

enum HomeTimelineAccountResetStoreAction {
    case applyPresentationTransition(HomeTimelinePresentationTransition)
    case clearPendingEvents
    case applyActivityTransition(HomeTimelineActivityTransition)
    case invalidateListEntries
    case resetRealtimeState
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case applyRelayStatusSnapshot(HomeTimelineRelayStatusSnapshot)
    case applyProjectionViewportTransition(
        HomeTimelineProjectionViewportTransition
    )
    case publishRelayStatusChange
    case applyAccountContextTransition(HomeTimelineAccountContextTransition)
}

enum HomeTimelineAccountResetAsyncAction: Equatable, Sendable {
    case resetRuntimeState
    case startRuntimeSession
    case configureRuntime(account: NostrAccount, forceInstall: Bool)
}

struct HomeTimelineAccountResetEnvironment: Sendable {
    typealias AccountProvider = @MainActor @Sendable () -> NostrAccount?

    let currentAccount: AccountProvider
}

struct HomeAccountResetInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineAccountResetStoreAction
    ) -> Void
    typealias AsyncApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineAccountResetAsyncAction
    ) async -> Void

    let environment: HomeTimelineAccountResetEnvironment
    let apply: ApplicationEffect
    let perform: AsyncApplicationEffect
}

struct HomeAccountResetInteractionContext: Sendable {
    let state: HomeTimelineAccountResetInteractionState
    let effects: HomeAccountResetInteractionEffects
}

@MainActor
final class HomeAccountResetInteractionWorkflow {
    private let accountReset: any HomeTimelineAccountResetHandling

    var isRuntimeTerminating: Bool {
        accountReset.isRuntimeTerminating
    }

    init(accountReset: any HomeTimelineAccountResetHandling) {
        self.accountReset = accountReset
    }

    func reset(context: HomeAccountResetInteractionContext) {
        accountReset.reset(
            HomeTimelineAccountResetInput(
                readBoundaryWrite: context.state.readBoundaryWrite,
                resolvedRelays: context.state.resolvedRelays
            ),
            effects: accountResetEffects(for: context.effects)
        )
    }

    private func accountResetEffects(
        for effects: HomeAccountResetInteractionEffects
    ) -> HomeTimelineAccountResetEffects {
        HomeTimelineAccountResetEffects(
            application: applicationEffects(for: effects),
            runtimeShutdown: runtimeShutdownEffects(for: effects)
        )
    }

    private func applicationEffects(
        for effects: HomeAccountResetInteractionEffects
    ) -> HomeTimelineAccountResetAppEffects {
        HomeTimelineAccountResetAppEffects(
            applyPresentationTransition: { transition in
                effects.apply(.applyPresentationTransition(transition))
            },
            clearPendingEvents: {
                effects.apply(.clearPendingEvents)
            },
            applyActivityTransition: { transition in
                effects.apply(.applyActivityTransition(transition))
            },
            invalidateListEntries: {
                effects.apply(.invalidateListEntries)
            },
            resetRealtimeState: {
                effects.apply(.resetRealtimeState)
            },
            applyContentSnapshot: { snapshot in
                effects.apply(.applyContentSnapshot(snapshot))
            },
            applyRelayStatusSnapshot: { snapshot in
                effects.apply(.applyRelayStatusSnapshot(snapshot))
            },
            applyProjectionViewportTransition: { transition in
                effects.apply(.applyProjectionViewportTransition(transition))
            },
            publishRelayStatusChange: {
                effects.apply(.publishRelayStatusChange)
            },
            applyAccountContextTransition: { transition in
                effects.apply(.applyAccountContextTransition(transition))
            }
        )
    }

    private func runtimeShutdownEffects(
        for effects: HomeAccountResetInteractionEffects
    ) -> HomeTimelineRuntimeShutdownEffects {
        HomeTimelineRuntimeShutdownEffects(
            currentAccount: effects.environment.currentAccount,
            resetRuntimeState: {
                await effects.perform(.resetRuntimeState)
            },
            startRuntimeSession: {
                await effects.perform(.startRuntimeSession)
            },
            configureRuntime: { account, forceInstall in
                await effects.perform(.configureRuntime(
                    account: account,
                    forceInstall: forceInstall
                ))
            }
        )
    }
}
