import AstrenzaCore

@MainActor
protocol HomeTimelineBackwardCompletionRouting: AnyObject {
    func handle(
        _ completion: NostrBackwardREQCompletion,
        accountID: String?
    ) -> [HomeTimelineBackwardCompletionCommand]
}

extension HomeTimelineBackwardCompletionApplicationCoordinator:
    HomeTimelineBackwardCompletionRouting {}

@MainActor
protocol HomeTimelineGapReconciliationApplying: AnyObject {
    @discardableResult
    func start(
        _ gap: PendingGapBackfill,
        feedContext: HomeFeedRuntimeContext,
        account: NostrAccount,
        handlers: HomeTimelineGapReconciliationApplicationHandlers
    ) -> Bool

    func cancel()
}

extension HomeTimelineGapReconciliationApplicationCoordinator:
    HomeTimelineGapReconciliationApplying {}

struct HomeTimelineBackwardCompletionInput: Equatable, Sendable {
    let completion: NostrBackwardREQCompletion
    let account: NostrAccount?
}

struct HomeTimelineBackwardCompletionEffects: Sendable {
    typealias ContentSnapshotHandler = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias DiagnosticHandler = @MainActor @Sendable (
        _ relayURL: String,
        _ subscriptionID: String?,
        _ message: String
    ) -> Void
    typealias ProjectionReloader = @MainActor @Sendable (
        _ account: NostrAccount,
        _ anchorEventID: String?,
        _ mergingWithCurrentWindow: Bool
    ) -> Void
    typealias RelayStatusRevisionHandler = @MainActor @Sendable () -> Void
    typealias DependencyResolver = @MainActor @Sendable (
        _ event: NostrEvent,
        _ context: HomeTimelineGapReconciliationApplicationContext
    ) async -> Bool

    let applyContentSnapshot: ContentSnapshotHandler
    let recordDiagnostic: DiagnosticHandler
    let reloadProjection: ProjectionReloader
    let incrementRelayStatusRevision: RelayStatusRevisionHandler
    let resolveDependencies: DependencyResolver
}

@MainActor
final class HomeTimelineBackwardCompletionWorkflow {
    private let completionCoordinator: any HomeTimelineBackwardCompletionRouting
    private let gapReconciliation: any HomeTimelineGapReconciliationApplying

    init(
        completionCoordinator: any HomeTimelineBackwardCompletionRouting,
        gapReconciliation: any HomeTimelineGapReconciliationApplying
    ) {
        self.completionCoordinator = completionCoordinator
        self.gapReconciliation = gapReconciliation
    }

    func handle(
        _ input: HomeTimelineBackwardCompletionInput,
        effects: HomeTimelineBackwardCompletionEffects
    ) {
        let commands = completionCoordinator.handle(
            input.completion,
            accountID: input.account?.pubkey
        )
        for command in commands {
            apply(command, account: input.account, effects: effects)
        }
    }

    func cancel() {
        gapReconciliation.cancel()
    }

    private func apply(
        _ command: HomeTimelineBackwardCompletionCommand,
        account: NostrAccount?,
        effects: HomeTimelineBackwardCompletionEffects
    ) {
        switch command {
        case .applyContentSnapshot(let snapshot):
            effects.applyContentSnapshot(snapshot)
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(diagnostic.relayURL, nil, diagnostic.message)
        case .reloadProjection(let anchorEventID, let mergingWithCurrentWindow):
            guard let account else { return }
            effects.reloadProjection(
                account,
                anchorEventID,
                mergingWithCurrentWindow
            )
        case .reconcileGap(let gap, let context):
            guard let account else { return }
            gapReconciliation.start(
                gap,
                feedContext: context,
                account: account,
                handlers: gapHandlers(account: account, effects: effects)
            )
        case .incrementRelayStatusRevision:
            effects.incrementRelayStatusRevision()
        }
    }

    private func gapHandlers(
        account: NostrAccount,
        effects: HomeTimelineBackwardCompletionEffects
    ) -> HomeTimelineGapReconciliationApplicationHandlers {
        HomeTimelineGapReconciliationApplicationHandlers(
            perform: { [weak self] command in
                self?.apply(command, account: account, effects: effects)
            },
            resolveDependencies: effects.resolveDependencies
        )
    }

    private func apply(
        _ command: HomeTimelineGapReconciliationApplicationCommand,
        account: NostrAccount,
        effects: HomeTimelineBackwardCompletionEffects
    ) {
        switch command {
        case .incrementRelayStatusRevision:
            effects.incrementRelayStatusRevision()
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(
                diagnostic.relayURL,
                diagnostic.subscriptionID,
                diagnostic.message
            )
        case .reloadProjection(let anchorEventID):
            effects.reloadProjection(account, anchorEventID, false)
        }
    }
}
