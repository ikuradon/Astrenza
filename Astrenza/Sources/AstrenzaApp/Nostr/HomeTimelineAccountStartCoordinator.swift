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
    case restoreHomeFeedReadState(NostrAccount)
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
    ) async -> Bool
    typealias ViewportRestorer = @MainActor @Sendable (
        _ accountID: String
    ) -> HomeTimelineRestoredViewport?
    typealias CachedPresentationWaiter = @MainActor @Sendable () async -> Void
    typealias LoadHandler = @MainActor @Sendable (
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let state: StateProvider
    let perform: CommandHandler
    let restoreCachedSnapshot: CachedSnapshotRestorer
    let restoredViewport: ViewportRestorer
    let waitForCachedPresentation: CachedPresentationWaiter
    let load: LoadHandler
}

@MainActor
final class HomeTimelineAccountStartCoordinator {
    typealias SyncPolicyResolver = @MainActor @Sendable (
        _ accountID: String,
        _ fallback: NostrSyncPolicy
    ) -> NostrSyncPolicy

    private let lifecycleCoordinator: any HomeTimelineAccountLifecycleCoordinating
    private let resolveSyncPolicy: SyncPolicyResolver

    init(
        lifecycleCoordinator: any HomeTimelineAccountLifecycleCoordinating,
        resolveSyncPolicy: @escaping SyncPolicyResolver
    ) {
        self.lifecycleCoordinator = lifecycleCoordinator
        self.resolveSyncPolicy = resolveSyncPolicy
    }

    func start(
        _ request: HomeTimelineAccountStartRequest,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        let initialState = handlers.state()
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
            let didRestore = await handlers.restoreCachedSnapshot(
                request.account
            )
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            completeCachedStartup(
                request,
                lifecycle: lifecycle,
                didRestore: didRestore,
                handlers: handlers
            )
            await handlers.waitForCachedPresentation()
            guard !Task.isCancelled,
                  lifecycleCoordinator.isCurrent(lifecycle)
            else { return }
            handlers.perform(.startRuntimeSession)
            await load(request.account, lifecycle)
        }
        handlers.perform(.activateOutbox(accountID: request.account.pubkey))
    }

    private func completeCachedStartup(
        _ request: HomeTimelineAccountStartRequest,
        lifecycle: HomeTimelineLifecycleToken,
        didRestore: Bool,
        handlers: HomeTimelineAccountStartHandlers
    ) {
        guard lifecycleCoordinator.setRuntimeBootstrapCompleted(
            didRestore,
            for: lifecycle
        ) else { return }
        handlers.perform(.prepareHomeFeedDefinition(request.account))
        restoreViewportIfNeeded(
            accountID: request.account.pubkey,
            handlers: handlers
        )
        restoreProjectionWindow(account: request.account, handlers: handlers)
        handlers.perform(.installProvisionalRuntimeBootstrap(request.account))
        handlers.perform(.restoreHomeFeedReadState(request.account))
        if let phase = initialPhase(
            hasRelayRuntime: request.hasRelayRuntime,
            state: handlers.state()
        ) {
            handlers.perform(.setPhase(phase))
        }
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
