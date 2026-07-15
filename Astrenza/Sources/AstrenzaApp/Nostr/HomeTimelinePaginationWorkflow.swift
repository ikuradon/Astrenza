import AstrenzaCore

@MainActor
protocol HomeTimelinePaginationScheduling: AnyObject {
    typealias Operation = @MainActor @Sendable () async -> Void

    func token(for accountID: String) -> HomeTimelineLifecycleToken?

    func startPagination(
        for token: HomeTimelineLifecycleToken,
        operation: @escaping Operation
    )
}

extension HomeTimelineLifecycleCoordinator: HomeTimelinePaginationScheduling {}

struct HomeTimelinePaginationState: Equatable, Sendable {
    let account: NostrAccount?
    let canBeginLoadingOlder: Bool
    let hasMoreOlder: Bool
    let hasTimelineEvents: Bool
    let hasResolvedRelays: Bool
    let hasFollowedPubkeys: Bool
}

struct HomeTimelinePaginationEffects: Sendable {
    typealias ProjectionViewportTransitionEffect = @MainActor @Sendable (
        _ transition: HomeTimelineProjectionViewportTransition
    ) -> Void
    typealias LoadEffect = @MainActor @Sendable (
        _ account: NostrAccount,
        _ lifecycle: HomeTimelineLifecycleToken
    ) async -> Void

    let applyProjectionViewportTransition: ProjectionViewportTransitionEffect
    let refreshLatest: LoadEffect
    let loadOlder: LoadEffect
}

@MainActor
final class HomeTimelinePaginationWorkflow {
    private let lifecycleCoordinator: any HomeTimelinePaginationScheduling

    init(lifecycleCoordinator: any HomeTimelinePaginationScheduling) {
        self.lifecycleCoordinator = lifecycleCoordinator
    }

    func refresh(
        _ state: HomeTimelinePaginationState,
        effects: HomeTimelinePaginationEffects
    ) {
        guard let context = context(for: state.account) else { return }

        effects.applyProjectionViewportTransition(.resetToNewest)
        lifecycleCoordinator.startPagination(for: context.lifecycle) {
            await effects.refreshLatest(context.account, context.lifecycle)
        }
    }

    func refreshLatest(
        _ state: HomeTimelinePaginationState,
        effects: HomeTimelinePaginationEffects
    ) async {
        guard let context = context(for: state.account) else { return }
        await effects.refreshLatest(context.account, context.lifecycle)
    }

    func loadOlder(
        _ state: HomeTimelinePaginationState,
        effects: HomeTimelinePaginationEffects
    ) {
        guard let context = context(for: state.account),
              state.canBeginLoadingOlder,
              state.hasMoreOlder,
              state.hasTimelineEvents,
              state.hasResolvedRelays,
              state.hasFollowedPubkeys
        else { return }

        lifecycleCoordinator.startPagination(for: context.lifecycle) {
            await effects.loadOlder(context.account, context.lifecycle)
        }
    }

    private func context(
        for account: NostrAccount?
    ) -> HomeTimelinePaginationContext? {
        guard let account,
              let lifecycle = lifecycleCoordinator.token(for: account.pubkey)
        else { return nil }
        return HomeTimelinePaginationContext(
            account: account,
            lifecycle: lifecycle
        )
    }
}

private struct HomeTimelinePaginationContext: Sendable {
    let account: NostrAccount
    let lifecycle: HomeTimelineLifecycleToken
}
