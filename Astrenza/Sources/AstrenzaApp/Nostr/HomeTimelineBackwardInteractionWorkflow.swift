import AstrenzaCore

@MainActor
protocol HomeTimelineBackwardCompletionHandling: AnyObject {
    func handle(
        _ input: HomeTimelineBackwardCompletionInput,
        effects: HomeTimelineBackwardCompletionAppEffects
    )

    func cancel()
}

extension HomeTimelineBackwardCompletionWorkflow:
    HomeTimelineBackwardCompletionHandling {}

struct HomeTimelineBackwardInteractionState: Equatable, Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
}

enum HomeTimelineBackwardStoreAction: Equatable, Sendable {
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case applyRelayStatusTransition(HomeTimelineRelayStatusTransition)
    case reloadProjection(
        account: NostrAccount,
        anchorEventID: String?,
        mergingWithCurrentWindow: Bool
    )
    case materializeEntries
    case scheduleLinkPreviewResolution
    case incrementRelayStatusRevision
}

struct HomeTimelineBackwardDependencyRequest: Equatable, Sendable {
    let event: NostrEvent
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
}

struct HomeTimelineBackwardInteractionEffects: Sendable {
    typealias ApplicationEffect = @MainActor @Sendable (
        _ action: HomeTimelineBackwardStoreAction
    ) -> Void
    typealias DependencyEffect = @MainActor @Sendable (
        _ request: HomeTimelineBackwardDependencyRequest
    ) async -> Bool

    let apply: ApplicationEffect
    let resolveDependencies: DependencyEffect
}

struct HomeTimelineBackwardInteractionContext: Sendable {
    let state: HomeTimelineBackwardInteractionState
    let effects: HomeTimelineBackwardInteractionEffects
}

@MainActor
final class HomeTimelineBackwardInteractionWorkflow {
    private let backward: any HomeTimelineBackwardCompletionHandling
    private let relayStatus: any HomeTimelineRelayStatusRecording

    init(
        backward: any HomeTimelineBackwardCompletionHandling,
        relayStatus: any HomeTimelineRelayStatusRecording
    ) {
        self.backward = backward
        self.relayStatus = relayStatus
    }

    func handle(
        _ completion: NostrBackwardREQCompletion,
        context: HomeTimelineBackwardInteractionContext
    ) {
        backward.handle(
            HomeTimelineBackwardCompletionInput(
                completion: completion,
                account: context.state.account
            ),
            effects: completionEffects(for: context)
        )
    }

    func cancel() {
        backward.cancel()
    }

    private func completionEffects(
        for context: HomeTimelineBackwardInteractionContext
    ) -> HomeTimelineBackwardCompletionAppEffects {
        let effects = context.effects
        return HomeTimelineBackwardCompletionAppEffects(
            applyContentSnapshot: { snapshot in
                effects.apply(.applyContentSnapshot(snapshot))
            },
            recordDiagnostic: { diagnostic in
                guard let transition = self.relayStatus.recordDiagnostic(
                    diagnostic,
                    accountID: context.state.account?.pubkey,
                    resolvedRelays: context.state.resolvedRelays
                ) else { return }
                effects.apply(.applyRelayStatusTransition(transition))
            },
            reloadProjection: { account, anchorEventID, merging in
                effects.apply(.reloadProjection(
                    account: account,
                    anchorEventID: anchorEventID,
                    mergingWithCurrentWindow: merging
                ))
            },
            materializeEntries: {
                effects.apply(.materializeEntries)
            },
            scheduleLinkPreviewResolution: {
                effects.apply(.scheduleLinkPreviewResolution)
            },
            incrementRelayStatusRevision: {
                effects.apply(.incrementRelayStatusRevision)
            },
            resolveDependencies: { event, account, lifecycle in
                await effects.resolveDependencies(
                    HomeTimelineBackwardDependencyRequest(
                        event: event,
                        account: account,
                        lifecycle: lifecycle
                    )
                )
            }
        )
    }
}
