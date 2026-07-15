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
    let applyStart: HomeAccountStartInteractionEffects.ApplicationEffect
    let load: HomeAccountStartInteractionEffects.LoadEffect
    let applyReset: HomeAccountResetInteractionEffects.ApplicationEffect
    let performReset:
        HomeAccountResetInteractionEffects.AsyncApplicationEffect
}

@MainActor
struct HomeAccountContextFactory {
    private let environment: HomeAccountLifecycleEnvironment

    init(environment: HomeAccountLifecycleEnvironment) {
        self.environment = environment
    }

    func startContext() -> HomeAccountStartInteractionContext {
        let snapshot = currentSnapshot()
        let snapshotProvider = environment.snapshot
        return HomeAccountStartInteractionContext(
            state: HomeTimelineAccountStartInteractionState(
                hasRelayRuntime: snapshot.hasRelayRuntime
            ),
            effects: HomeAccountStartInteractionEffects(
                environment: HomeTimelineAccountStartEnvironment(
                    state: {
                        Self.startState(
                            from: snapshotProvider() ?? .empty
                        )
                    },
                    restoreCachedSnapshot:
                        environment.restoreCachedSnapshot,
                    restoredViewport: environment.restoredViewport,
                    waitForCachedPresentation:
                        environment.waitForCachedPresentation,
                    restoreCachedReadState:
                        environment.restoreCachedReadState
                ),
                apply: environment.applyStart,
                load: environment.load
            )
        )
    }

    func resetContext() -> HomeAccountResetInteractionContext {
        let snapshot = currentSnapshot()
        let snapshotProvider = environment.snapshot
        return HomeAccountResetInteractionContext(
            state: HomeTimelineAccountResetInteractionState(
                readBoundaryWrite: environment.readBoundaryWrite(),
                resolvedRelays: snapshot.resolvedRelays
            ),
            effects: HomeAccountResetInteractionEffects(
                environment: HomeTimelineAccountResetEnvironment(
                    currentAccount: {
                        snapshotProvider()?.account
                    }
                ),
                apply: environment.applyReset,
                perform: environment.performReset
            )
        )
    }

    private func currentSnapshot() -> HomeAccountLifecycleSnapshot {
        environment.snapshot() ?? .empty
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
