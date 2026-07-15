import AstrenzaCore

@MainActor
protocol HomeTimelineAccountStartCoordinating: AnyObject {
    func start(
        _ request: HomeTimelineAccountStartRequest,
        handlers: HomeTimelineAccountStartHandlers
    )
}

extension HomeTimelineAccountStartCoordinator: HomeTimelineAccountStartCoordinating {}

struct HomeTimelineAccountStartInput: Equatable, Sendable {
    let account: NostrAccount
    let hasRelayRuntime: Bool
}

struct HomeTimelineAccountStartAppEffects: Sendable {
    typealias VoidEffect = @MainActor @Sendable () -> Void
    typealias AccountEffect = @MainActor @Sendable (_ account: NostrAccount) -> Void
    typealias AccountContextTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelineAccountContextTransition
    ) -> Void
    typealias ProjectionViewportTransitionHandler = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias PhaseEffect = @MainActor @Sendable (
        _ phase: NostrHomeTimelinePhase
    ) -> Void
    typealias OutboxActivator = @MainActor @Sendable (_ accountID: String) -> Void

    let cancelCurrentAccount: VoidEffect
    let applyAccountContextTransition: AccountContextTransitionHandler
    let startRuntimeSession: VoidEffect
    let ensureHomeFeedDefinition: AccountEffect
    let applyProjectionViewportTransition: ProjectionViewportTransitionHandler
    let reloadNewestProjectionWindow: AccountEffect
    let materializeEntries: VoidEffect
    let applyRestoreProjectionAnchor: AccountEffect
    let installProvisionalRuntimeBootstrap: AccountEffect
    let restoreHomeFeedReadState: AccountEffect
    let setPhase: PhaseEffect
    let activateOutbox: OutboxActivator
}

struct HomeTimelineAccountStartEffects: Sendable {
    let state: HomeTimelineAccountStartHandlers.StateProvider
    let application: HomeTimelineAccountStartAppEffects
    let restoreCachedSnapshot: HomeTimelineAccountStartHandlers.CachedSnapshotRestorer
    let restoredViewport: HomeTimelineAccountStartHandlers.ViewportRestorer
    let load: HomeTimelineAccountStartHandlers.LoadHandler
}

@MainActor
final class HomeTimelineAccountStartWorkflow {
    private let coordinator: any HomeTimelineAccountStartCoordinating

    init(coordinator: any HomeTimelineAccountStartCoordinating) {
        self.coordinator = coordinator
    }

    func start(
        _ input: HomeTimelineAccountStartInput,
        effects: HomeTimelineAccountStartEffects
    ) {
        coordinator.start(
            HomeTimelineAccountStartRequest(
                account: input.account,
                hasRelayRuntime: input.hasRelayRuntime
            ),
            handlers: handlers(effects: effects)
        )
    }

    private func handlers(
        effects: HomeTimelineAccountStartEffects
    ) -> HomeTimelineAccountStartHandlers {
        HomeTimelineAccountStartHandlers(
            state: effects.state,
            perform: { [weak self] command in
                self?.apply(command, effects: effects.application)
            },
            restoreCachedSnapshot: effects.restoreCachedSnapshot,
            restoredViewport: effects.restoredViewport,
            load: effects.load
        )
    }

    private func apply(
        _ command: HomeTimelineAccountStartCommand,
        effects: HomeTimelineAccountStartAppEffects
    ) {
        switch command {
        case .applyRestoredViewport,
             .reloadNewestProjectionWindow,
             .materializeEntries,
             .applyRestoreProjectionAnchor:
            applyProjectionCommand(command, effects: effects)
        default:
            applyAccountCommand(command, effects: effects)
        }
    }

    private func applyAccountCommand(
        _ command: HomeTimelineAccountStartCommand,
        effects: HomeTimelineAccountStartAppEffects
    ) {
        switch command {
        case .cancelCurrentAccount:
            effects.cancelCurrentAccount()
        case .setAccount(let account, let syncPolicy):
            effects.applyAccountContextTransition(.activate(
                account,
                syncPolicy: syncPolicy
            ))
        case .startRuntimeSession:
            effects.startRuntimeSession()
        case .ensureHomeFeedDefinition(let account):
            effects.ensureHomeFeedDefinition(account)
        case .installProvisionalRuntimeBootstrap(let account):
            effects.installProvisionalRuntimeBootstrap(account)
        case .restoreHomeFeedReadState(let account):
            effects.restoreHomeFeedReadState(account)
        case .setPhase(let phase):
            effects.setPhase(phase)
        case .activateOutbox(let accountID):
            effects.activateOutbox(accountID)
        case .applyRestoredViewport,
             .reloadNewestProjectionWindow,
             .materializeEntries,
             .applyRestoreProjectionAnchor:
            assertionFailure("Projection command reached the account command router")
        }
    }

    private func applyProjectionCommand(
        _ command: HomeTimelineAccountStartCommand,
        effects: HomeTimelineAccountStartAppEffects
    ) {
        switch command {
        case .applyRestoredViewport(let viewport):
            effects.applyProjectionViewportTransition(.restoreViewport(
                anchorEventID: viewport.anchorEventID
            ))
        case .reloadNewestProjectionWindow(let account):
            effects.reloadNewestProjectionWindow(account)
        case .materializeEntries:
            effects.materializeEntries()
        case .applyRestoreProjectionAnchor(let account):
            effects.applyRestoreProjectionAnchor(account)
        case .cancelCurrentAccount,
             .setAccount,
             .startRuntimeSession,
             .ensureHomeFeedDefinition,
             .installProvisionalRuntimeBootstrap,
             .restoreHomeFeedReadState,
             .setPhase,
             .activateOutbox:
            assertionFailure("Account command reached the projection command router")
        }
    }
}
