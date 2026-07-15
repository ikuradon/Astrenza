import AstrenzaCore

struct HomeRuntimeContextEnvironment: Sendable {
    typealias SnapshotProvider = @MainActor @Sendable (
    ) -> HomeTimelineRuntimeStoreSnapshot?
    typealias FeedContextValidity = @MainActor @Sendable (
        _ context: HomeFeedRuntimeContext
    ) -> Bool

    let snapshot: SnapshotProvider
    let isCurrentFeedContext: FeedContextValidity
    let runtimeApplication: HomeTimelineRuntimeApplicationEffects
    let apply: HomeTimelineRuntimeInteractionEffects.ApplicationEffect
    let perform: HomeTimelineRuntimeInteractionEffects.AsyncApplicationEffect
}

@MainActor
struct HomeRuntimeContextFactory {
    private let snapshot: HomeRuntimeContextEnvironment.SnapshotProvider
    private let projector: HomeTimelineRuntimeContextProjector
    private let interactionEffects: HomeTimelineRuntimeInteractionEffects
    private let eventEffects: HomeTimelineRuntimeEventStoreEffects

    init(environment: HomeRuntimeContextEnvironment) {
        snapshot = environment.snapshot

        let snapshot = environment.snapshot
        let projector = HomeTimelineRuntimeContextProjector()
        let isCurrentFeedContext = environment.isCurrentFeedContext
        let isAccountCurrent:
            HomeTimelineRuntimeStoreEnvironment.AccountValidity = { accountID in
                guard let current = snapshot() else { return false }
                return projector.isAccountCurrent(accountID, in: current)
            }

        self.projector = projector
        interactionEffects = HomeTimelineRuntimeInteractionEffects(
            environment: HomeTimelineRuntimeStoreEnvironment(
                packetContext: { isActive in
                    guard let current = snapshot() else { return nil }
                    return projector.packetContext(
                        from: current,
                        isActive: isActive,
                        isCurrentFeedContext: isCurrentFeedContext
                    )
                },
                isAccountCurrent: isAccountCurrent
            ),
            runtimeApplication: environment.runtimeApplication,
            apply: environment.apply,
            perform: environment.perform
        )
        eventEffects = HomeTimelineRuntimeEventStoreEffects(
            environment: HomeTimelineRuntimeEventEnvironment(
                presentationState: { receivedWhileRealtime in
                    projector.eventPresentationState(
                        from: snapshot() ?? .empty,
                        receivedWhileRealtime: receivedWhileRealtime
                    )
                },
                isAccountCurrent: isAccountCurrent
            ),
            runtimeApplication: environment.runtimeApplication,
            apply: environment.apply
        )
    }

    func interactionContext() -> HomeTimelineRuntimeInteractionContext {
        HomeTimelineRuntimeInteractionContext(
            state: interactionState(),
            effects: interactionEffects
        )
    }

    func eventContext() -> HomeTimelineRuntimeEventContext {
        HomeTimelineRuntimeEventContext(
            state: projector.eventState(from: currentSnapshot()),
            effects: eventEffects
        )
    }

    func interactionState() -> HomeTimelineRuntimeInteractionState {
        projector.interactionState(from: currentSnapshot())
    }

    func dependencyState() -> HomeTimelineRuntimeDependencyState {
        projector.dependencyState(from: currentSnapshot())
    }

    private func currentSnapshot() -> HomeTimelineRuntimeStoreSnapshot {
        snapshot() ?? .empty
    }
}
