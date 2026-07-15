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
}

enum HomeTimelineBackwardStoreAction: Equatable, Sendable {
    case applyContentSnapshot(HomeTimelineContentSnapshot)
    case recordDiagnostic(HomeTimelineBackwardAppDiagnostic)
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

    init(backward: any HomeTimelineBackwardCompletionHandling) {
        self.backward = backward
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
            effects: completionEffects(for: context.effects)
        )
    }

    func cancel() {
        backward.cancel()
    }

    private func completionEffects(
        for effects: HomeTimelineBackwardInteractionEffects
    ) -> HomeTimelineBackwardCompletionAppEffects {
        HomeTimelineBackwardCompletionAppEffects(
            applyContentSnapshot: { snapshot in
                effects.apply(.applyContentSnapshot(snapshot))
            },
            recordDiagnostic: { diagnostic in
                effects.apply(.recordDiagnostic(diagnostic))
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
