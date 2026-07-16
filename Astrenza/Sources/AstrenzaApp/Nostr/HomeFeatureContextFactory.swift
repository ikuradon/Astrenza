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
    let applications: HomeTimelineStoreApplicationEffects
    let resolveBackwardDependencies:
        HomeTimelineBackwardInteractionEffects.DependencyEffect
    let didUpdateLinkPreview: HomeLinkPreviewInteractionEffects.UpdateEffect
}

struct HomeTimelineLinkPreviewStoreInteraction: Sendable {
    let state: HomeTimelineLinkPreviewInteractionState
    let effects: HomeLinkPreviewInteractionEffects
}

@MainActor
struct HomeFeatureContextFactory {
    private let snapshot: HomeFeatureInteractionEnvironment.SnapshotProvider
    private let filterEffects: HomeFilterInteractionEffects
    private let syncEffects: HomeTimelineSyncInteractionEffects
    private let localMutationEffects: HomeLocalMutationInteractionEffects
    private let gapBackfillEffects: HomeGapBackfillInteractionEffects
    private let publishEffects: HomeTimelinePublishInteractionEffects
    private let backwardEffects: HomeTimelineBackwardInteractionEffects
    private let linkPreviewEffects: HomeLinkPreviewInteractionEffects

    init(environment: HomeFeatureInteractionEnvironment) {
        snapshot = environment.snapshot

        let snapshot = environment.snapshot
        let router = HomeTimelineStoreApplicationRouter(
            applications: environment.applications
        )
        filterEffects = HomeFilterInteractionEffects(
            apply: { action in
                router.apply(action)
            }
        )
        syncEffects = HomeTimelineSyncInteractionEffects(
            apply: { action in
                router.apply(action)
            }
        )
        localMutationEffects = HomeLocalMutationInteractionEffects(
            apply: { action in
                router.apply(action)
            }
        )
        gapBackfillEffects = HomeGapBackfillInteractionEffects(
            apply: { action in
                router.apply(action)
            }
        )
        publishEffects = HomeTimelinePublishInteractionEffects(
            environment: HomeTimelinePublishEnvironment(
                currentAccountID: {
                    snapshot()?.account?.pubkey
                }
            ),
            apply: { action in
                router.apply(action)
            },
            perform: { action in
                await router.perform(action)
            }
        )
        backwardEffects = HomeTimelineBackwardInteractionEffects(
            apply: { action in
                router.apply(action)
            },
            resolveDependencies: environment.resolveBackwardDependencies
        )
        linkPreviewEffects = HomeLinkPreviewInteractionEffects(
            didUpdate: environment.didUpdateLinkPreview,
            apply: { action in
                router.apply(action)
            }
        )
    }

    func filterContext() -> HomeFilterInteractionContext {
        HomeFilterInteractionContext(
            effects: filterEffects
        )
    }

    func syncContext() -> HomeTimelineSyncInteractionContext {
        HomeTimelineSyncInteractionContext(
            effects: syncEffects
        )
    }

    func localMutationContext() -> HomeLocalMutationInteractionContext {
        HomeLocalMutationInteractionContext(
            state: HomeLocalMutationInteractionState(
                accountID: currentSnapshot().account?.pubkey
            ),
            effects: localMutationEffects
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
            effects: gapBackfillEffects
        )
    }

    func publishContext(
        account: NostrAccount
    ) -> HomeTimelinePublishInteractionContext {
        let snapshot = currentSnapshot()
        return HomeTimelinePublishInteractionContext(
            state: HomeTimelinePublishInteractionState(
                account: account,
                accountWriteRelays: NostrRelayList.parse(
                    from: snapshot.relayListEvent
                ).writeRelays,
                fallbackRelays: snapshot.resolvedRelays
            ),
            effects: publishEffects
        )
    }

    func backwardContext() -> HomeTimelineBackwardInteractionContext {
        let snapshot = currentSnapshot()
        return HomeTimelineBackwardInteractionContext(
            state: HomeTimelineBackwardInteractionState(
                account: snapshot.account,
                resolvedRelays: snapshot.resolvedRelays
            ),
            effects: backwardEffects
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
            effects: linkPreviewEffects
        )
    }

    private func currentSnapshot() -> HomeTimelineFeatureInteractionSnapshot {
        snapshot() ?? .empty
    }
}
