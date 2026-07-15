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

struct HomeTimelineBackwardAppDiagnostic: Equatable, Sendable {
    let relayURL: String
    let subscriptionID: String?
    let message: String
}

struct HomeTimelineBackwardCompletionAppEffects: Sendable {
    typealias ContentSnapshotEffect = @MainActor @Sendable (
        _ snapshot: HomeTimelineContentSnapshot
    ) -> Void
    typealias DiagnosticEffect = @MainActor @Sendable (
        _ diagnostic: HomeTimelineBackwardAppDiagnostic
    ) -> Void
    typealias ProjectionEffect = @MainActor @Sendable (
        _ account: NostrAccount,
        _ anchorEventID: String?,
        _ mergingWithCurrentWindow: Bool
    ) -> Void
    typealias VoidEffect = @MainActor @Sendable () -> Void
    typealias DependencyEffect = @MainActor @Sendable (
        _ event: NostrEvent,
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Bool

    let applyContentSnapshot: ContentSnapshotEffect
    let recordDiagnostic: DiagnosticEffect
    let reloadProjection: ProjectionEffect
    let materializeEntries: VoidEffect
    let scheduleLinkPreviewResolution: VoidEffect
    let incrementRelayStatusRevision: VoidEffect
    let resolveDependencies: DependencyEffect
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
        effects: HomeTimelineBackwardCompletionAppEffects
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
        effects: HomeTimelineBackwardCompletionAppEffects
    ) {
        switch command {
        case .applyContentSnapshot(let snapshot):
            effects.applyContentSnapshot(snapshot)
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(
                HomeTimelineBackwardAppDiagnostic(
                    relayURL: diagnostic.relayURL,
                    subscriptionID: nil,
                    message: diagnostic.message
                )
            )
        case .reloadProjection(let anchorEventID, let mergingWithCurrentWindow):
            guard let account else { return }
            applyProjectionReload(
                account,
                anchorEventID,
                mergingWithCurrentWindow,
                effects: effects
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
        effects: HomeTimelineBackwardCompletionAppEffects
    ) -> HomeTimelineGapReconciliationApplicationHandlers {
        HomeTimelineGapReconciliationApplicationHandlers(
            perform: { [weak self] command in
                self?.apply(command, account: account, effects: effects)
            },
            resolveDependencies: { event, context in
                await effects.resolveDependencies(
                    event,
                    context.account,
                    context.lifecycle
                )
            }
        )
    }

    private func apply(
        _ command: HomeTimelineGapReconciliationApplicationCommand,
        account: NostrAccount,
        effects: HomeTimelineBackwardCompletionAppEffects
    ) {
        switch command {
        case .incrementRelayStatusRevision:
            effects.incrementRelayStatusRevision()
        case .recordDiagnostic(let diagnostic):
            effects.recordDiagnostic(
                HomeTimelineBackwardAppDiagnostic(
                    relayURL: diagnostic.relayURL,
                    subscriptionID: diagnostic.subscriptionID,
                    message: diagnostic.message
                )
            )
        case .reloadProjection(let anchorEventID):
            applyProjectionReload(
                account,
                anchorEventID,
                false,
                effects: effects
            )
        }
    }

    private func applyProjectionReload(
        _ account: NostrAccount,
        _ anchorEventID: String?,
        _ mergingWithCurrentWindow: Bool,
        effects: HomeTimelineBackwardCompletionAppEffects
    ) {
        effects.reloadProjection(
            account,
            anchorEventID,
            mergingWithCurrentWindow
        )
        effects.materializeEntries()
        effects.scheduleLinkPreviewResolution()
    }
}
