import AstrenzaCore

@MainActor
protocol HomeTimelineAccountResetCoordinating: AnyObject {
    func reset(
        context: HomeTimelineAccountResetContext,
        handlers: HomeTimelineAccountResetHandlers
    )
}

extension HomeTimelineAccountResetCoordinator: HomeTimelineAccountResetCoordinating {}

@MainActor
protocol HomeTimelineRuntimeShutdownCoordinating: AnyObject {
    var isTerminating: Bool { get }

    @discardableResult
    func schedule(
        cancellationGeneration: UInt64,
        handlers: HomeTimelineRuntimeShutdownHandlers
    ) -> Bool
}

extension HomeTimelineRuntimeShutdownCoordinator: HomeTimelineRuntimeShutdownCoordinating {}

struct HomeTimelineAccountResetInput: Sendable {
    let readBoundaryWrite: HomeTimelineReadBoundaryWrite?
    let resolvedRelays: [String]
}

struct HomeTimelineAccountResetAppEffects: Sendable {
    let applyPresentationTransition:
        HomeTimelineAccountResetHandlers.PresentationTransitionHandler
    let clearPendingEvents: HomeTimelineAccountResetHandlers.Action
    let applyActivityTransition:
        HomeTimelineAccountResetHandlers.ActivityTransitionHandler
    let invalidateListEntries: HomeTimelineAccountResetHandlers.Action
    let resetRealtimeState: HomeTimelineAccountResetHandlers.Action
    let applyContentSnapshot: HomeTimelineAccountResetHandlers.ContentSnapshotHandler
    let applyRelayStatusSnapshot:
        HomeTimelineAccountResetHandlers.RelayStatusSnapshotHandler
    let resetProjectionRestoreState: HomeTimelineAccountResetHandlers.Action
    let clearPublishedAccountState: HomeTimelineAccountResetHandlers.Action
}

struct HomeTimelineRuntimeShutdownEffects: Sendable {
    typealias Action = @MainActor @Sendable () async -> Void
    typealias RuntimeConfigurator = @MainActor @Sendable (
        _ account: NostrAccount,
        _ forceInstall: Bool
    ) async -> Void

    let currentAccount: HomeTimelineRuntimeShutdownHandlers.CurrentAccount
    let resetRuntimeState: Action
    let startRuntimeSession: Action
    let configureRuntime: RuntimeConfigurator
}

struct HomeTimelineAccountResetEffects: Sendable {
    let application: HomeTimelineAccountResetAppEffects
    let runtimeShutdown: HomeTimelineRuntimeShutdownEffects
}

@MainActor
final class HomeTimelineAccountResetWorkflow {
    private let resetCoordinator: any HomeTimelineAccountResetCoordinating
    private let runtimeShutdownCoordinator: any HomeTimelineRuntimeShutdownCoordinating

    var isRuntimeTerminating: Bool {
        runtimeShutdownCoordinator.isTerminating
    }

    init(
        resetCoordinator: any HomeTimelineAccountResetCoordinating,
        runtimeShutdownCoordinator: any HomeTimelineRuntimeShutdownCoordinating
    ) {
        self.resetCoordinator = resetCoordinator
        self.runtimeShutdownCoordinator = runtimeShutdownCoordinator
    }

    func reset(
        _ input: HomeTimelineAccountResetInput,
        effects: HomeTimelineAccountResetEffects
    ) {
        resetCoordinator.reset(
            context: HomeTimelineAccountResetContext(
                readBoundaryWrite: input.readBoundaryWrite,
                resolvedRelays: input.resolvedRelays
            ),
            handlers: resetHandlers(effects: effects)
        )
    }

    private func resetHandlers(
        effects: HomeTimelineAccountResetEffects
    ) -> HomeTimelineAccountResetHandlers {
        let application = effects.application
        return HomeTimelineAccountResetHandlers(
            applyPresentationTransition: application.applyPresentationTransition,
            clearPendingEvents: application.clearPendingEvents,
            applyActivityTransition: application.applyActivityTransition,
            invalidateListEntries: application.invalidateListEntries,
            resetRealtimeState: application.resetRealtimeState,
            applyContentSnapshot: application.applyContentSnapshot,
            applyRelayStatusSnapshot: application.applyRelayStatusSnapshot,
            resetProjectionRestoreState: application.resetProjectionRestoreState,
            clearPublishedAccountState: application.clearPublishedAccountState,
            scheduleRuntimeShutdown: { [weak self] cancellationGeneration in
                self?.scheduleRuntimeShutdown(
                    cancellationGeneration: cancellationGeneration,
                    effects: effects.runtimeShutdown
                )
            }
        )
    }

    private func scheduleRuntimeShutdown(
        cancellationGeneration: UInt64,
        effects: HomeTimelineRuntimeShutdownEffects
    ) {
        runtimeShutdownCoordinator.schedule(
            cancellationGeneration: cancellationGeneration,
            handlers: HomeTimelineRuntimeShutdownHandlers(
                currentAccount: effects.currentAccount,
                perform: { [weak self] command in
                    await self?.apply(command, effects: effects)
                }
            )
        )
    }

    private func apply(
        _ command: HomeTimelineRuntimeShutdownCommand,
        effects: HomeTimelineRuntimeShutdownEffects
    ) async {
        switch command {
        case .resetRuntimeState:
            await effects.resetRuntimeState()
        case .startRuntimeSession:
            await effects.startRuntimeSession()
        case .configureRuntime(let account, let forceInstall):
            await effects.configureRuntime(account, forceInstall)
        }
    }
}
