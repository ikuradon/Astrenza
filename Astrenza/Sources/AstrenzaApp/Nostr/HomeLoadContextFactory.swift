import AstrenzaCore

struct HomeLoadContextSnapshot: Equatable, Sendable {
    let hasRelayRuntime: Bool
    let hasTimelineEvents: Bool
    let syncPolicy: NostrSyncPolicy

    init(
        hasRelayRuntime: Bool,
        hasTimelineEvents: Bool,
        syncPolicy: NostrSyncPolicy = .default()
    ) {
        self.hasRelayRuntime = hasRelayRuntime
        self.hasTimelineEvents = hasTimelineEvents
        self.syncPolicy = syncPolicy
    }

    static var empty: Self {
        HomeLoadContextSnapshot(
            hasRelayRuntime: false,
            hasTimelineEvents: false,
            syncPolicy: .default()
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
                hasTimelineEvents: snapshot.hasTimelineEvents,
                syncPolicy: snapshot.syncPolicy
            ),
            effects: effects
        )
    }
}
