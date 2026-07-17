import AstrenzaCore

typealias HomeTimelineAccountLoadOperation = @MainActor @Sendable () async -> Void

@MainActor
protocol HomeTimelineAccountLifecycleCoordinating: AnyObject {
    var hasCompletedRuntimeBootstrap: Bool { get }

    func begin(accountID: String) -> HomeTimelineLifecycleToken

    func isCurrent(_ token: HomeTimelineLifecycleToken) -> Bool

    @discardableResult
    func setRuntimeBootstrapCompleted(
        _ isCompleted: Bool,
        for token: HomeTimelineLifecycleToken
    ) -> Bool

    func startLoad(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping HomeTimelineAccountLoadOperation
    )
}

extension HomeTimelineLifecycleCoordinator: HomeTimelineAccountLifecycleCoordinating {}

struct HomeTimelineAccountStartRequest: Equatable, Sendable {
    let account: NostrAccount
    let hasRelayRuntime: Bool
}

struct HomeTimelineAccountStartState: Equatable, Sendable {
    let accountID: String?
    let syncPolicy: NostrSyncPolicy
    let restoreProjectionAnchorEventID: String?
    let hasEntries: Bool
    let hasResolvedRelays: Bool
}

struct HomeTimelineRestoredViewport: Equatable, Sendable {
    let anchorEventID: String?
}

enum HomeTimelineAccountStartCommand: Equatable, Sendable {
    case cancelCurrentAccount
    case setAccount(NostrAccount, syncPolicy: NostrSyncPolicy)
    case startRuntimeSession
    case prepareHomeFeedDefinition(NostrAccount)
    case applyRestoredViewport(HomeTimelineRestoredViewport)
    case reloadNewestProjectionWindow(NostrAccount)
    case materializeEntries
    case applyRestoreProjectionAnchor(NostrAccount)
    case installProvisionalRuntimeBootstrap(NostrAccount)
    case setPhase(NostrHomeTimelinePhase)
    case activateOutbox(accountID: String)
}

struct HomeTimelineAccountStartHandlers: Sendable {
    typealias StateProvider = @MainActor @Sendable () -> HomeTimelineAccountStartState
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineAccountStartCommand
    ) -> Void
    typealias CachedSnapshotRestorer = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> HomeTimelineCachedStateRestoreOutcome
    typealias ViewportRestorer = @MainActor @Sendable (
        _ accountID: String
    ) -> HomeTimelineRestoredViewport?
    typealias CachedPresentationWaiter = @MainActor @Sendable () async -> Void
    typealias CachedReadStateRestorer = @MainActor @Sendable (
        _ account: NostrAccount
    ) async -> Void
    typealias LoadHandler = @MainActor @Sendable (
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let state: StateProvider
    let perform: CommandHandler
    let restoreCachedSnapshot: CachedSnapshotRestorer
    let restoredViewport: ViewportRestorer
    let waitForCachedPresentation: CachedPresentationWaiter
    let restoreCachedReadState: CachedReadStateRestorer
    let load: LoadHandler
}

@MainActor
final class HomeTimelineAccountStartCoordinator {
    typealias SyncPolicyResolver = @MainActor @Sendable (
        _ accountID: String,
        _ fallback: NostrSyncPolicy
    ) -> NostrSyncPolicy

    private let lifecycleCoordinator: any HomeTimelineAccountLifecycleCoordinating
    private let startupFailureMessage: String?
    private let resolveSyncPolicy: SyncPolicyResolver

    init(
        lifecycleCoordinator: any HomeTimelineAccountLifecycleCoordinating,
        startupFailureMessage: String? = nil,
        resolveSyncPolicy: @escaping SyncPolicyResolver
    ) {
        self.lifecycleCoordinator = lifecycleCoordinator
        self.startupFailureMessage = startupFailureMessage
        self.resolveSyncPolicy = resolveSyncPolicy
    }

    func start(
        _ request: HomeTimelineAccountStartRequest,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        let initialState = handlers.state()
        if let startupFailureMessage {
            failStartup(
                request.account,
                message: startupFailureMessage,
                initialState: initialState,
                handlers: handlers
            )
            return
        }
        if initialState.accountID == request.account.pubkey {
            handlers.perform(.startRuntimeSession)
            handlers.perform(.activateOutbox(accountID: request.account.pubkey))
            return
        }

        if initialState.accountID != nil {
            handlers.perform(.cancelCurrentAccount)
        }

        let lifecycle = lifecycleCoordinator.begin(accountID: request.account.pubkey)
        let syncPolicy = resolveSyncPolicy(
            request.account.pubkey,
            handlers.state().syncPolicy
        )
        handlers.perform(.setAccount(request.account, syncPolicy: syncPolicy))
        let load = handlers.load
        lifecycleCoordinator.startLoad(for: lifecycle) { [weak self] in
            guard let self else { return }
            let restoreOutcome = await handlers.restoreCachedSnapshot(
                request.account
            )
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            let didRestore: Bool
            switch restoreOutcome {
            case .restored:
                didRestore = true
            case .missing:
                didRestore = false
            case .failed(let message):
                handlers.perform(.setPhase(.failed(message)))
                return
            case .cancelled:
                return
            }
            let phaseAfterCachedPresentation = completeCachedStartup(
                request,
                lifecycle: lifecycle,
                didRestore: didRestore,
                handlers: handlers
            )
            await handlers.waitForCachedPresentation()
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            if let phaseAfterCachedPresentation {
                handlers.perform(.setPhase(phaseAfterCachedPresentation))
            }
            await handlers.restoreCachedReadState(request.account)
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            handlers.perform(.startRuntimeSession)
            await load(request.account, lifecycle)
        }
        handlers.perform(.activateOutbox(accountID: request.account.pubkey))
    }

    private func failStartup(
        _ account: NostrAccount,
        message: String,
        initialState: HomeTimelineAccountStartState,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        if initialState.accountID != account.pubkey {
            if initialState.accountID != nil {
                handlers.perform(.cancelCurrentAccount)
            }
            _ = lifecycleCoordinator.begin(accountID: account.pubkey)
            let syncPolicy = resolveSyncPolicy(
                account.pubkey,
                handlers.state().syncPolicy
            )
            handlers.perform(.setAccount(account, syncPolicy: syncPolicy))
        }
        handlers.perform(.setPhase(.failed(message)))
    }

    private func completeCachedStartup(
        _ request: HomeTimelineAccountStartRequest,
        lifecycle: HomeTimelineLifecycleToken,
        didRestore: Bool,
        handlers: HomeTimelineAccountStartHandlers
    ) -> NostrHomeTimelinePhase? {
        guard lifecycleCoordinator.setRuntimeBootstrapCompleted(
            didRestore,
            for: lifecycle
        ) else { return nil }
        handlers.perform(.prepareHomeFeedDefinition(request.account))
        restoreViewportIfNeeded(
            accountID: request.account.pubkey,
            handlers: handlers
        )
        restoreProjectionWindow(account: request.account, handlers: handlers)
        handlers.perform(.installProvisionalRuntimeBootstrap(request.account))
        if let phase = initialPhase(
            hasRelayRuntime: request.hasRelayRuntime,
            state: handlers.state()
        ) {
            if case .loaded = phase {
                return phase
            }
            handlers.perform(.setPhase(phase))
        }
        return nil
    }

    private func restoreViewportIfNeeded(
        accountID: String,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        guard handlers.state().restoreProjectionAnchorEventID == nil,
              let viewport = handlers.restoredViewport(accountID)
        else { return }
        handlers.perform(.applyRestoredViewport(viewport))
    }

    private func restoreProjectionWindow(
        account: NostrAccount,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        if handlers.state().restoreProjectionAnchorEventID == nil {
            handlers.perform(.reloadNewestProjectionWindow(account))
            handlers.perform(.materializeEntries)
        } else {
            handlers.perform(.applyRestoreProjectionAnchor(account))
        }
    }

    private func initialPhase(
        hasRelayRuntime: Bool,
        state: HomeTimelineAccountStartState
    ) -> NostrHomeTimelinePhase? {
        if hasRelayRuntime,
           lifecycleCoordinator.hasCompletedRuntimeBootstrap,
           state.hasResolvedRelays {
            return .loaded
        }
        if hasRelayRuntime || !state.hasEntries {
            return .resolvingRelays
        }
        return nil
    }
}
