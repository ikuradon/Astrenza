import AstrenzaCore

@MainActor
protocol HomeTimelineOlderPageRequesting: Sendable {
    func requestOlder(
        account: NostrAccount
    ) async -> HomeTimelineBackwardRequestOutcome
}

extension HomeTimelineBackwardRequestCoordinator: HomeTimelineOlderPageRequesting {}

@MainActor
protocol HomeTimelineOlderPageRemoteLoading: Sendable {
    func loadOlderPage(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome
}

extension HomeTimelineRemoteLoadCoordinator: HomeTimelineOlderPageRemoteLoading {
    func loadOlderPage(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]?,
        isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) async -> HomeTimelineRemoteLoadOutcome {
        await load(
            .older(
                account: account,
                current: current,
                localBackfillEvents: localBackfillEvents
            ),
            isCurrent: isCurrent
        )
    }
}

struct HomeTimelineOlderPageRequest: Equatable, Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
    let hasRelayRuntime: Bool
}

struct HomeTimelineOlderPageRemoteInput: Equatable, Sendable {
    let current: NostrHomeTimelineState
    let localBackfillEvents: [NostrEvent]?
}

enum HomeTimelineOlderPageCommand: Equatable, Sendable {
    case applyActivityTransition(HomeTimelineActivityTransition)
    case recordDiagnostic(HomeTimelineBackwardRequestDiagnostic)
}

struct HomeTimelineOlderPageHandlers: Sendable {
    typealias CommandHandler = @MainActor @Sendable (
        _ command: HomeTimelineOlderPageCommand
    ) -> Void
    typealias RemoteInputProvider = @MainActor @Sendable (
        _ account: NostrAccount
    ) -> HomeTimelineOlderPageRemoteInput?
    typealias RemoteOutcomeHandler = @MainActor @Sendable (
        _ outcome: HomeTimelineRemoteLoadOutcome,
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let perform: CommandHandler
    let prepareRemoteInput: RemoteInputProvider
    let applyRemoteOutcome: RemoteOutcomeHandler
}

@MainActor
final class HomeTimelineOlderPageWorkflow {
    private let requester: any HomeTimelineOlderPageRequesting
    private let remoteLoader: any HomeTimelineOlderPageRemoteLoading
    private let activityCoordinator: HomeTimelineActivityCoordinator
    private let lifecycleCoordinator: HomeTimelineLifecycleCoordinator

    init(
        requester: any HomeTimelineOlderPageRequesting,
        remoteLoader: any HomeTimelineOlderPageRemoteLoading,
        activityCoordinator: HomeTimelineActivityCoordinator,
        lifecycleCoordinator: HomeTimelineLifecycleCoordinator
    ) {
        self.requester = requester
        self.remoteLoader = remoteLoader
        self.activityCoordinator = activityCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func load(
        _ request: HomeTimelineOlderPageRequest,
        handlers: HomeTimelineOlderPageHandlers
    ) async {
        guard lifecycleCoordinator.isCurrent(request.lifecycle),
              let transition = activityCoordinator.beginLoadingOlder()
        else { return }
        handlers.perform(.applyActivityTransition(transition))
        defer {
            if lifecycleCoordinator.isCurrent(request.lifecycle) {
                handlers.perform(.applyActivityTransition(
                    activityCoordinator.endLoadingOlder()
                ))
            }
        }

        if request.hasRelayRuntime {
            await loadFromRuntime(request, handlers: handlers)
            return
        }

        guard let input = handlers.prepareRemoteInput(request.account) else {
            return
        }
        let outcome = await remoteLoader.loadOlderPage(
            account: request.account,
            current: input.current,
            localBackfillEvents: input.localBackfillEvents,
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

    private func loadFromRuntime(
        _ request: HomeTimelineOlderPageRequest,
        handlers: HomeTimelineOlderPageHandlers
    ) async {
        let outcome = await requester.requestOlder(account: request.account)
        if case .failed(let diagnostic) = outcome {
            handlers.perform(.recordDiagnostic(diagnostic))
        }
        guard !Task.isCancelled,
              lifecycleCoordinator.isCurrent(request.lifecycle)
        else { return }
        handlers.perform(.applyActivityTransition(
            activityCoordinator.setPhase(.loaded)
        ))
    }
}
