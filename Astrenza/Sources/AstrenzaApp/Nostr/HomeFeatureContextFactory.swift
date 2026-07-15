import AstrenzaCore

struct HomeTimelineFeatureInteractionSnapshot: Sendable {
    let account: NostrAccount?
    let resolvedRelays: [String]
    let relayListEvent: NostrEvent?
    let syncPolicy: NostrSyncPolicy
    let hasRelayRuntime: Bool

    static var empty: Self {
        HomeTimelineFeatureInteractionSnapshot(
            account: nil,
            resolvedRelays: [],
            relayListEvent: nil,
            syncPolicy: .default(),
            hasRelayRuntime: false
        )
    }
}

struct HomeFeatureInteractionEnvironment: Sendable {
    typealias SnapshotProvider = @MainActor @Sendable (
    ) -> HomeTimelineFeatureInteractionSnapshot?

    let snapshot: SnapshotProvider
    let applyFilter: HomeFilterInteractionEffects.ApplicationEffect
    let applySync: HomeTimelineSyncInteractionEffects.ApplicationEffect
    let applyLocalMutation:
        HomeLocalMutationInteractionEffects.ApplicationEffect
    let applyGapBackfill: HomeGapBackfillInteractionEffects.ApplicationEffect
    let applyPublish: HomeTimelinePublishInteractionEffects.ApplicationEffect
    let performPublish:
        HomeTimelinePublishInteractionEffects.AsyncApplicationEffect
    let applyBackward:
        HomeTimelineBackwardInteractionEffects.ApplicationEffect
    let resolveBackwardDependencies:
        HomeTimelineBackwardInteractionEffects.DependencyEffect
    let didUpdateLinkPreview: HomeLinkPreviewInteractionEffects.UpdateEffect
    let applyLinkPreview: HomeLinkPreviewInteractionEffects.ApplicationEffect
}

struct HomeTimelineLinkPreviewStoreInteraction: Sendable {
    let state: HomeTimelineLinkPreviewInteractionState
    let effects: HomeLinkPreviewInteractionEffects
}

@MainActor
struct HomeFeatureContextFactory {
    private let environment: HomeFeatureInteractionEnvironment

    init(environment: HomeFeatureInteractionEnvironment) {
        self.environment = environment
    }

    func filterContext() -> HomeFilterInteractionContext {
        HomeFilterInteractionContext(
            effects: HomeFilterInteractionEffects(
                apply: environment.applyFilter
            )
        )
    }

    func syncContext() -> HomeTimelineSyncInteractionContext {
        HomeTimelineSyncInteractionContext(
            effects: HomeTimelineSyncInteractionEffects(
                apply: environment.applySync
            )
        )
    }

    func localMutationContext() -> HomeLocalMutationInteractionContext {
        HomeLocalMutationInteractionContext(
            state: HomeLocalMutationInteractionState(
                accountID: currentSnapshot().account?.pubkey
            ),
            effects: HomeLocalMutationInteractionEffects(
                apply: environment.applyLocalMutation
            )
        )
    }

    func gapBackfillContext() -> HomeGapBackfillInteractionContext {
        let snapshot = currentSnapshot()
        return HomeGapBackfillInteractionContext(
            state: HomeTimelineGapBackfillInteractionState(
                account: snapshot.account,
                hasRelayRuntime: snapshot.hasRelayRuntime,
                resolvedRelays: snapshot.resolvedRelays
            ),
            effects: HomeGapBackfillInteractionEffects(
                apply: environment.applyGapBackfill
            )
        )
    }

    func publishContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext {
        let snapshot = currentSnapshot()
        let snapshotProvider = environment.snapshot
        return HomeTimelinePublishInteractionContext(
            state: HomeTimelinePublishInteractionState(
                account: account,
                accountWriteRelays: NostrRelayList.parse(
                    from: snapshot.relayListEvent
                ).writeRelays,
                fallbackRelays: snapshot.resolvedRelays
            ),
            effects: HomeTimelinePublishInteractionEffects(
                environment: HomeTimelinePublishEnvironment(
                    currentAccountID: {
                        snapshotProvider()?.account?.pubkey
                    }
                ),
                apply: environment.applyPublish,
                perform: environment.performPublish
            )
        )
    }

    func backwardContext() -> HomeTimelineBackwardInteractionContext {
        let snapshot = currentSnapshot()
        return HomeTimelineBackwardInteractionContext(
            state: HomeTimelineBackwardInteractionState(
                account: snapshot.account,
                resolvedRelays: snapshot.resolvedRelays
            ),
            effects: HomeTimelineBackwardInteractionEffects(
                apply: environment.applyBackward,
                resolveDependencies: environment.resolveBackwardDependencies
            )
        )
    }

    func linkPreviewInteraction(
    ) -> HomeTimelineLinkPreviewStoreInteraction {
        let snapshot = currentSnapshot()
        return HomeTimelineLinkPreviewStoreInteraction(
            state: HomeTimelineLinkPreviewInteractionState(
                accountID: snapshot.account?.pubkey,
                resolvedRelays: snapshot.resolvedRelays,
                policy: snapshot.syncPolicy
            ),
            effects: HomeLinkPreviewInteractionEffects(
                didUpdate: environment.didUpdateLinkPreview,
                apply: environment.applyLinkPreview
            )
        )
    }

    private func currentSnapshot() -> HomeTimelineFeatureInteractionSnapshot {
        environment.snapshot() ?? .empty
    }
}
