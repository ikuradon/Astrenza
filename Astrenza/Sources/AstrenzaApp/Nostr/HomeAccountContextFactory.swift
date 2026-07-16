import AstrenzaCore

struct HomeAccountLifecycleSnapshot: Sendable {
    let account: NostrAccount?
    let syncPolicy: NostrSyncPolicy
    let restoreProjectionAnchorEventID: String?
    let hasEntries: Bool
    let resolvedRelays: [String]
    let hasRelayRuntime: Bool

    static var empty: Self {
        HomeAccountLifecycleSnapshot(
            account: nil,
            syncPolicy: .default(),
            restoreProjectionAnchorEventID: nil,
            hasEntries: false,
            resolvedRelays: [],
            hasRelayRuntime: false
        )
    }
}

struct HomeAccountLifecycleEnvironment: Sendable {
    typealias SnapshotProvider = @MainActor @Sendable (
    ) -> HomeAccountLifecycleSnapshot?
    typealias ReadBoundaryProvider = @MainActor @Sendable (
    ) -> HomeTimelineReadBoundaryWrite?

    let snapshot: SnapshotProvider
    let readBoundaryWrite: ReadBoundaryProvider
    let restoreCachedSnapshot:
        HomeTimelineAccountStartEnvironment.CachedSnapshotRestorer
    let restoredViewport: HomeTimelineAccountStartEnvironment.ViewportRestorer
    let waitForCachedPresentation:
        HomeTimelineAccountStartEnvironment.CachedPresentationWaiter
    let restoreCachedReadState:
        HomeTimelineAccountStartEnvironment.CachedReadStateRestorer
    let load: HomeAccountStartInteractionEffects.LoadEffect
    let applications: HomeTimelineAccountApplicationEffects
}

@MainActor
struct HomeAccountContextFactory {
    private let snapshot: HomeAccountLifecycleEnvironment.SnapshotProvider
    private let readBoundaryWrite:
        HomeAccountLifecycleEnvironment.ReadBoundaryProvider
    private let startEffects: HomeAccountStartInteractionEffects
    private let resetEffects: HomeAccountResetInteractionEffects

    init(environment: HomeAccountLifecycleEnvironment) {
        snapshot = environment.snapshot
        readBoundaryWrite = environment.readBoundaryWrite

        let snapshot = environment.snapshot
        let dispatcher = HomeTimelineAccountApplicationDispatcher()
        startEffects = HomeAccountStartInteractionEffects(
            environment: HomeTimelineAccountStartEnvironment(
                state: {
                    Self.startState(from: snapshot() ?? .empty)
                },
                restoreCachedSnapshot: environment.restoreCachedSnapshot,
                restoredViewport: environment.restoredViewport,
                waitForCachedPresentation:
                    environment.waitForCachedPresentation,
                restoreCachedReadState: environment.restoreCachedReadState
            ),
            apply: { action in
                dispatcher.apply(
                    action,
                    effects: environment.applications
                )
            },
            load: environment.load
        )
        resetEffects = HomeAccountResetInteractionEffects(
            environment: HomeTimelineAccountResetEnvironment(
                currentAccount: {
                    snapshot()?.account
                }
            ),
            apply: { action in
                dispatcher.apply(
                    action,
                    effects: environment.applications
                )
            },
            perform: { action in
                await dispatcher.perform(
                    action,
                    effects: environment.applications
                )
            }
        )
    }

    func startContext() -> HomeAccountStartInteractionContext {
        let snapshot = currentSnapshot()
        return HomeAccountStartInteractionContext(
            state: HomeTimelineAccountStartInteractionState(
                hasRelayRuntime: snapshot.hasRelayRuntime
            ),
            effects: startEffects
        )
    }

    func resetContext() -> HomeAccountResetInteractionContext {
        let snapshot = currentSnapshot()
        return HomeAccountResetInteractionContext(
            state: HomeTimelineAccountResetInteractionState(
                readBoundaryWrite: readBoundaryWrite(),
                resolvedRelays: snapshot.resolvedRelays
            ),
            effects: resetEffects
        )
    }

    private func currentSnapshot() -> HomeAccountLifecycleSnapshot {
        snapshot() ?? .empty
    }

    private static func startState(
        from snapshot: HomeAccountLifecycleSnapshot
    ) -> HomeTimelineAccountStartStoreState {
        HomeTimelineAccountStartStoreState(
            accountID: snapshot.account?.pubkey,
            syncPolicy: snapshot.syncPolicy,
            restoreProjectionAnchorEventID:
                snapshot.restoreProjectionAnchorEventID,
            hasEntries: snapshot.hasEntries,
            hasResolvedRelays: !snapshot.resolvedRelays.isEmpty
        )
    }
}
