import AstrenzaCore

struct HomeLoadContextSnapshot: Equatable, Sendable {
    let hasRelayRuntime: Bool
    let hasTimelineEvents: Bool

    static var empty: Self {
        HomeLoadContextSnapshot(
            hasRelayRuntime: false,
            hasTimelineEvents: false
        )
    }
}

struct HomeLoadContextEnvironment: Sendable {
    typealias SnapshotProvider = @MainActor @Sendable (
    ) -> HomeLoadContextSnapshot?

    let snapshot: SnapshotProvider
    let providers: HomeTimelineLoadEnvironment
    let applications: HomeTimelineLoadApplicationEffects
}

@MainActor
struct HomeLoadContextFactory {
    private let snapshot: HomeLoadContextEnvironment.SnapshotProvider
    private let effects: HomeTimelineLoadInteractionEffects

    init(environment: HomeLoadContextEnvironment) {
        snapshot = environment.snapshot

        let dispatcher = HomeTimelineLoadDispatcher()
        effects = HomeTimelineLoadInteractionEffects(
            environment: environment.providers,
            apply: { application in
                dispatcher.apply(
                    application,
                    effects: environment.applications
                )
            },
            perform: { application in
                await dispatcher.perform(
                    application,
                    effects: environment.applications
                )
            }
        )
    }

    func context() -> HomeTimelineLoadInteractionContext {
        let snapshot = snapshot() ?? .empty
        return HomeTimelineLoadInteractionContext(
            state: HomeTimelineLoadInteractionState(
                hasRelayRuntime: snapshot.hasRelayRuntime,
                hasTimelineEvents: snapshot.hasTimelineEvents
            ),
            effects: effects
        )
    }
}
