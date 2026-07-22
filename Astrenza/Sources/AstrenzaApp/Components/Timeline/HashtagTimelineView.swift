import SwiftUI

struct HashtagTimelineView: View {
    @Environment(\.dismiss) private var dismiss

    let route: HomeTimelineHashtagRoute
    let accountID: String
    let timelineStore: NostrHomeTimelineStore
    let swipeSettings: TimelineSwipeSettings
    let actions: HomeTimelineNavigationDestinationActions

    @State private var store: HashtagTimelineStore?
    @State private var viewport: HomeTimelineViewportState
    @State private var viewportPersistence: HomeViewportPersistenceCoordinator

    init(
        route: HomeTimelineHashtagRoute,
        accountID: String,
        timelineStore: NostrHomeTimelineStore,
        swipeSettings: TimelineSwipeSettings,
        actions: HomeTimelineNavigationDestinationActions
    ) {
        self.route = route
        self.accountID = accountID
        self.timelineStore = timelineStore
        self.swipeSettings = swipeSettings
        self.actions = actions

        let identity = HashtagFeedIdentity(hashtag: route.hashtag)
        let timelineKey = identity?.timelineKey(accountID: accountID) ??
            "hashtag:invalid"
        let persistence = HomeViewportPersistenceCoordinator(
            persistence: TimelineRestoreStore(),
            fallbackViewportLoader: { _, _ in nil }
        )
        let snapshot = persistence.restoreSnapshot(
            accountID: accountID,
            timelineKey: timelineKey
        )
        _viewportPersistence = State(initialValue: persistence)
        _viewport = State(initialValue: HomeTimelineViewportState(
            restoredViewportState: snapshot.viewportState,
            layoutCache: snapshot.layoutCache
        ))
        _store = State(initialValue: timelineStore.makeHashtagTimelineStore(
            accountID: accountID,
            hashtag: route.hashtag,
            restoreAnchorEventID: snapshot.viewportState?.anchorPostID
        ))
    }

    var body: some View {
        Group {
            if let store {
                timeline(store)
            } else {
                TimelineEmptyStateView(
                    state: TimelineEmptyState(
                        title: "Tag timeline unavailable",
                        message: "A persistent account database is required to open this timeline.",
                        systemName: "exclamationmark.triangle",
                        primaryActionTitle: "Back",
                        secondaryActionTitle: nil
                    ),
                    onPrimaryAction: { dismiss() },
                    onSecondaryAction: nil
                )
            }
        }
        .background(Color.astrenzaBackground)
        .navigationTitle("#\(route.hashtag)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.astrenzaBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await store?.start()
        }
        .onChange(of: timelineStore.profileMetadataRevision) { _, _ in
            store?.refreshPresentationForDependencyChange()
        }
        .onChange(of: timelineStore.resolvedContentRevision) { _, _ in
            store?.refreshPresentationForDependencyChange()
        }
        .onDisappear {
            store?.stop()
            viewportPersistence.flushPendingSaves()
        }
    }

    private func timeline(_ store: HashtagTimelineStore) -> some View {
        TimelineFeedView(
            entries: store.entries,
            sourceIdentity: "\(accountID)/\(store.timelineKey)",
            sourceRevision: store.contentRevision,
            viewportIdentity: TimelineFeedViewportIdentity(
                accountID: accountID,
                timelineKey: store.timelineKey
            ),
            metrics: .navigation,
            swipeSettings: swipeSettings,
            viewportState: viewport.viewportState,
            scrollCommand: viewport.scrollCommand,
            viewportRestoreProtectionActive:
                viewport.isRestoreProtectionActive,
            followsRealtimeEntries:
                HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
                    isRealtime: store.isRealtime,
                    isAtNewestWindow: viewport.isAtNewestWindow,
                    isRestoreProtected:
                        viewport.isRestoreProtectionActive,
                    isDetachedFromLiveEdge:
                        viewport.isDetachedFromLiveEdge
                ),
            layoutCache: viewport.layoutCache,
            emptyState: store.emptyState,
            onEmptyStatePrimaryAction: {
                Task { _ = await store.refresh() }
            },
            onOpenPost: actions.onOpenPost,
            onOpenProfile: actions.onOpenProfile,
            onReplyPost: actions.onReply,
            onOpenMedia: actions.onOpenMedia,
            onOpenURL: actions.onOpenURL,
            onPostActionChoice: actions.onPostActionChoice,
            onRefresh: { _ in
                _ = viewport.prepareRefresh()
                let didUpdate = await store.refresh()
                return TimelineFeedRefreshResult(
                    didUpdate: didUpdate,
                    sourceRevision: store.contentRevision
                )
            },
            onLoadOlderPost: { _ in store.loadOlder() },
            onScrollOffsetChanged: { offset in
                if let nextOffset = viewport.scrollOffsetUpdate(for: offset) {
                    viewport.applyScrollOffset(nextOffset)
                }
                _ = viewport.updateNewestWindow(for: offset)
            },
            onViewportObservationChanged: { _ in },
            onViewportRestoreCompleted: { offset in
                _ = viewport.completeRestore()
                _ = viewport.updateNewestWindow(
                    for: offset,
                    forceStoreSync: true
                )
            },
            onViewportStateChanged: { state in
                viewportPersistence.scheduleViewportStateSave(
                    state,
                    accountID: accountID,
                    timelineKey: store.timelineKey
                )
            },
            onLayoutCacheChanged: { cache in
                guard viewport.shouldUpdateLayoutCache(cache) else {
                    return
                }
                viewport.applyLayoutCache(cache)
                viewportPersistence.scheduleLayoutCacheSave(
                    cache,
                    accountID: accountID,
                    timelineKey: store.timelineKey
                )
            }
        )
    }
}
