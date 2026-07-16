import AstrenzaCore

@MainActor
protocol HomeTimelineInitialLoadRemoteLoading: Sendable {
    func loadInitialState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome

    func loadRuntimeBootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome
}

extension HomeTimelineRemoteLoadCoordinator: HomeTimelineInitialLoadRemoteLoading {
    func loadInitialState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome {
        await load(
            .initial(account: account, policy: policy),
            isCurrent: isCurrent,
            didReceiveStage: didReceiveStage,
            didFetch: didFetch
        )
    }

    func loadRuntimeBootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        isCurrent: @escaping @MainActor @Sendable () -> Bool,
        didReceiveStage: @escaping @MainActor @Sendable (
            NostrHomeTimelineLoadStage
        ) -> Void,
        didFetch: @escaping @MainActor @Sendable () -> Void
    ) async -> HomeTimelineRemoteLoadOutcome {
        await load(
            .runtimeBootstrap(account: account, policy: policy),
            isCurrent: isCurrent,
            didReceiveStage: didReceiveStage,
            didFetch: didFetch
        )
    }
}

struct HomeTimelineInitialLoadRequest: Equatable, Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let hasRelayRuntime: Bool
    let syncPolicy: NostrSyncPolicy

    init(
        account: NostrAccount,
        lifecycle: HomeTimelineLifecycleToken,
        hasRelayRuntime: Bool,
        syncPolicy: NostrSyncPolicy = .default()
    ) {
        self.account = account
        self.lifecycle = lifecycle
        self.hasRelayRuntime = hasRelayRuntime
        self.syncPolicy = syncPolicy
    }
}

enum HomeTimelineInitialLoadCommand: Equatable, Sendable {
    case applyActivityTransition(HomeTimelineActivityTransition)
    case installProvisionalRuntimeBootstrap(NostrAccount)
}

struct HomeTimelineInitialLoadHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineInitialLoadCommand
    ) -> Void
    typealias RelayAvailabilityProvider = @MainActor @Sendable () -> Bool
    typealias RuntimeConfigurator = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias OutcomeHandler = @MainActor @Sendable (
        _ outcome: HomeTimelineRemoteLoadOutcome,
        _ operation: HomeTimelineLoadOperation,
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let perform: CommandHandler
    let hasResolvedRelays: RelayAvailabilityProvider
    let configureRuntime: RuntimeConfigurator
    let applyOutcome: OutcomeHandler
}

@MainActor
final class HomeTimelineInitialLoadWorkflow {
    private let remoteLoader: any HomeTimelineInitialLoadRemoteLoading
    private let activityCoordinator: HomeTimelineActivityCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        remoteLoader: any HomeTimelineInitialLoadRemoteLoading,
        activityCoordinator: HomeTimelineActivityCoordinator,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.remoteLoader = remoteLoader
        self.activityCoordinator = activityCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func load(
        _ request: HomeTimelineInitialLoadRequest,
        handlers: HomeTimelineInitialLoadHandlers
    ) async {
        guard lifecycleCoordinator.isCurrent(request.lifecycle) else { return }
        if request.hasRelayRuntime {
            await loadRuntimeBootstrap(request, handlers: handlers)
            return
        }

        let outcome = await remoteLoader.loadInitialState(
            account: request.account,
            policy: request.syncPolicy,
            isCurrent: currentLifecycleHandler(for: request.lifecycle),
            didReceiveStage: stageHandler(
                lifecycle: request.lifecycle,
                handlers: handlers
            ),
            didFetch: fetchHandler(
                lifecycle: request.lifecycle,
                handlers: handlers
            )
        )
        await handlers.applyOutcome(
            outcome,
            .initial,
            request.account,
            request.lifecycle
        )
    }

    private func loadRuntimeBootstrap(
        _ request: HomeTimelineInitialLoadRequest,
        handlers: HomeTimelineInitialLoadHandlers
    ) async {
        guard lifecycleCoordinator.isCurrent(request.lifecycle) else { return }
        handlers.perform(.installProvisionalRuntimeBootstrap(request.account))
        let hadCachedBootstrap = lifecycleCoordinator.hasCompletedRuntimeBootstrap
        if hadCachedBootstrap, handlers.hasResolvedRelays() {
            await handlers.configureRuntime(request.account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(request.lifecycle)
            else { return }
        } else {
            setPhase(.resolvingRelays, handlers: handlers)
        }

        let outcome = await remoteLoader.loadRuntimeBootstrapState(
            account: request.account,
            policy: request.syncPolicy,
            isCurrent: currentLifecycleHandler(for: request.lifecycle),
            didReceiveStage: stageHandler(
                lifecycle: request.lifecycle,
                handlers: handlers
            ),
            didFetch: fetchHandler(
                lifecycle: request.lifecycle,
                handlers: handlers
            )
        )
        await handlers.applyOutcome(
            outcome,
            .runtimeBootstrap(hadCachedBootstrap: hadCachedBootstrap),
            request.account,
            request.lifecycle
        )
    }

    private func currentLifecycleHandler(
        for lifecycle: HomeTimelineLifecycleToken
    ) -> @MainActor @Sendable () -> Bool {
        { [lifecycleCoordinator] in
            lifecycleCoordinator.isCurrent(lifecycle)
        }
    }

    private func stageHandler(
        lifecycle: HomeTimelineLifecycleToken,
        handlers: HomeTimelineInitialLoadHandlers
    ) -> @MainActor @Sendable (NostrHomeTimelineLoadStage) -> Void {
        { [weak self] stage in
            self?.handleStage(stage, lifecycle: lifecycle, handlers: handlers)
        }
    }

    private func fetchHandler(
        lifecycle: HomeTimelineLifecycleToken,
        handlers: HomeTimelineInitialLoadHandlers
    ) -> @MainActor @Sendable () -> Void {
        { [weak self] in
            self?.handleStage(
                .loadingTimeline,
                lifecycle: lifecycle,
                handlers: handlers
            )
        }
    }

    private func handleStage(
        _ stage: NostrHomeTimelineLoadStage,
        lifecycle: HomeTimelineLifecycleToken,
        handlers: HomeTimelineInitialLoadHandlers
    ) {
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(lifecycle)
        else { return }
        switch stage {
        case .resolvingRelayList:
            setPhase(.resolvingRelays, handlers: handlers)
        case .resolvingContactList:
            setPhase(.resolvingContacts, handlers: handlers)
        case .resolvingOutboxRelayLists:
            setPhase(.resolvingRelays, handlers: handlers)
        case .loadingTimeline:
            setPhase(.loadingHome, handlers: handlers)
        }
    }

    private func setPhase(
        _ phase: NostrHomeTimelinePhase,
        handlers: HomeTimelineInitialLoadHandlers
    ) {
        handlers.perform(.applyActivityTransition(
            activityCoordinator.setPhase(phase)
        ))
    }
}
