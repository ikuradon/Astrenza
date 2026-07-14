import AstrenzaCore

typealias HomeTimelineRuntimeTermination = @MainActor @Sendable () async -> Void
typealias HomeTimelineRuntimeTerminationCompletion = @MainActor @Sendable () async -> Void

@MainActor
protocol HomeTimelineRuntimeTerminationScheduling: AnyObject {
    var isTerminating: Bool { get }

    func schedule(
        termination: @escaping HomeTimelineRuntimeTermination,
        onLatestCompletion: @escaping HomeTimelineRuntimeTerminationCompletion
    )
}

extension HomeTimelineRelayRuntimeTerminator: HomeTimelineRuntimeTerminationScheduling {}

@MainActor
protocol HomeTimelineRuntimeSessionStopping: AnyObject {
    func cancelRuntimeEvents()
    func stopProfileUpdates() async
}

extension HomeTimelineRuntimeSessionCoordinator: HomeTimelineRuntimeSessionStopping {}

enum HomeTimelineRuntimeShutdownCommand: Equatable, Sendable {
    case resetRuntimeState
    case startRuntimeSession
    case configureRuntime(account: NostrAccount, forceInstall: Bool)
}

struct HomeTimelineRuntimeShutdownHandlers: Sendable {
    typealias CurrentAccount = @MainActor @Sendable () -> NostrAccount?
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRuntimeShutdownCommand
    ) async -> Void

    let currentAccount: CurrentAccount
    let perform: CommandHandler
}

@MainActor
final class HomeTimelineRuntimeShutdownCoordinator {
    typealias RuntimeTermination = HomeTimelineRuntimeTermination

    private let scheduler: any HomeTimelineRuntimeTerminationScheduling
    private let runtimeSession: any HomeTimelineRuntimeSessionStopping
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    private let terminateRuntime: RuntimeTermination?

    var isTerminating: Bool {
        scheduler.isTerminating
    }

    init(
        scheduler: any HomeTimelineRuntimeTerminationScheduling,
        runtimeSession: any HomeTimelineRuntimeSessionStopping,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator,
        terminateRuntime: RuntimeTermination?
    ) {
        self.scheduler = scheduler
        self.runtimeSession = runtimeSession
        self.lifecycleCoordinator = lifecycleCoordinator
        self.terminateRuntime = terminateRuntime
    }

    @discardableResult
    func schedule(
        cancellationGeneration: UInt64,
        handlers: HomeTimelineRuntimeShutdownHandlers
    ) -> Bool {
        guard let terminateRuntime else { return false }

        let runtimeSession = runtimeSession
        scheduler.schedule(
            termination: {
                await runtimeSession.stopProfileUpdates()
                await terminateRuntime()
            },
            onLatestCompletion: { [weak self] in
                await self?.restartIfNeeded(
                    after: cancellationGeneration,
                    handlers: handlers
                )
            }
        )
        return true
    }

    private func restartIfNeeded(
        after cancellationGeneration: UInt64,
        handlers: HomeTimelineRuntimeShutdownHandlers
    ) async {
        guard let lifecycle = lifecycleCoordinator.currentToken,
              lifecycle.generation != cancellationGeneration,
              let account = handlers.currentAccount(),
              lifecycle.accountID == account.pubkey
        else { return }

        runtimeSession.cancelRuntimeEvents()
        await handlers.perform(.resetRuntimeState)
        await handlers.perform(.startRuntimeSession)
        await handlers.perform(.configureRuntime(account: account, forceInstall: true))
    }
}
