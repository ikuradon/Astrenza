import AstrenzaCore

@MainActor
protocol HomeTimelineRefreshRemoteLoading: Sendable {
    func refreshState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome
}

extension HomeTimelineRemoteLoadCoordinator: HomeTimelineRefreshRemoteLoading {
    func refreshState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome {
        await load(
            .refresh(
                account: account,
                current: current,
                policy: policy
            ),
            isCurrent: isCurrent
        )
    }
}

struct HomeTimelineRefreshRequest: Equatable, Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let hasTimelineEvents: Bool
    let hasRelayRuntime: Bool
    let syncPolicy: NostrSyncPolicy

    init(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        hasTimelineEvents: Bool,
        hasRelayRuntime: Bool,
        syncPolicy: NostrSyncPolicy = .default()
    ) {
        self.account = account
        self.lifecycle = lifecycle
        self.hasTimelineEvents = hasTimelineEvents
        self.hasRelayRuntime = hasRelayRuntime
        self.syncPolicy = syncPolicy
    }
}

struct HomeTimelineRefreshRemoteInput: Equatable, Sendable {
    let current: NostrHomeTimelineState
}

enum HomeTimelineRefreshCommand: Equatable, Sendable {
    case applyActivityTransition(HomeTimelineActivityTransition)
    case restartAccount(NostrAccount)
}

struct HomeTimelineRefreshHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineRefreshCommand
    ) -> Void
    typealias RemoteInputProvider = @MainActor @Sendable (
        _ account: NostrAccount
    ) -> HomeTimelineRefreshRemoteInput?
    typealias RuntimeConfigurator = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias RemoteOutcomeHandler = @MainActor @Sendable (
        _ outcome: HomeTimelineRemoteLoadOutcome,
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let perform: CommandHandler
    let prepareRemoteInput: RemoteInputProvider
    let configureRuntime: RuntimeConfigurator
    let applyRemoteOutcome: RemoteOutcomeHandler
}

@MainActor
final class HomeTimelineRefreshWorkflow {
    private let remoteLoader: any HomeTimelineRefreshRemoteLoading
    private let activityCoordinator: HomeTimelineActivityCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        remoteLoader: any HomeTimelineRefreshRemoteLoading,
        activityCoordinator: HomeTimelineActivityCoordinator,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.remoteLoader = remoteLoader
        self.activityCoordinator = activityCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func refresh(
        _ request: HomeTimelineRefreshRequest,
        handlers: HomeTimelineRefreshHandlers
    ) async {
        guard lifecycleCoordinator.isCurrent(request.lifecycle) else { return }
        guard request.hasTimelineEvents else {
            handlers.perform(.restartAccount(request.account))
            return
        }
        guard let transition = activityCoordinator.beginRefresh() else { return }
        handlers.perform(.applyActivityTransition(transition))
        defer {
            if lifecycleCoordinator.isCurrent(request.lifecycle) {
                handlers.perform(.applyActivityTransition(
                    activityCoordinator.endRefresh()
                ))
            }
        }

        if request.hasRelayRuntime {
            await refreshRuntime(request, handlers: handlers)
            return
        }

        guard let input = handlers.prepareRemoteInput(request.account) else {
            return
        }
        let outcome = await remoteLoader.refreshState(
            account: request.account,
            current: input.current,
            policy: request.syncPolicy,
            isCurrent: { [lifecycleCoordinator] in
                lifecycleCoordinator.isCurrent(request.lifecycle)
            }
        )
        await handlers.applyRemoteOutcome(
            outcome,
            request.account,
            request.lifecycle
        )
    }

    private func refreshRuntime(
        _ request: HomeTimelineRefreshRequest,
        handlers: HomeTimelineRefreshHandlers
    ) async {
        await handlers.configureRuntime(request.account)
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(request.lifecycle)
        else { return }
        handlers.perform(.applyActivityTransition(
            activityCoordinator.setPhase(.loaded)
        ))
    }
}
