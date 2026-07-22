import AstrenzaCore

@MainActor
protocol HomeTimelineViewportStoreHandling: AnyObject {
    func setRestoreProjectionAnchor(_ anchorEventID: String?)
    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool)
    func markNewestMaterializedWindowRead()
    func clearRestoreProjectionAnchorWithoutReload()
}

extension NostrHomeTimelineStore: HomeTimelineViewportStoreHandling {}

@MainActor
final class HomeTimelineViewportStoreSynchronizer {
    private let store: any HomeTimelineViewportStoreHandling

    init(store: any HomeTimelineViewportStoreHandling) {
        self.store = store
    }

    func applyNewestWindowUpdate(
        _ update: HomeTimelineViewportState.NewestWindowUpdate,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        if update.isAtNewestWindow {
            store.markNewestMaterializedWindowRead()
        }
        guard update.shouldPublishToStore else { return }
        store.setTimelineAtNewestWindow(update.isAtNewestWindow)
    }

    func applyHomeRetap(
        _ action: HomeTimelineViewportState.HomeRetapAction,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        switch action {
        case .restore(let returnAnchor):
            // DBの表示windowを復元対象へ切り替えてからSwiftUIへscrollを指示する。
            store.setTimelineAtNewestWindow(false)
            store.setRestoreProjectionAnchor(returnAnchor.anchorPostID)
        case .showNewest:
            store.clearRestoreProjectionAnchorWithoutReload()
            store.setTimelineAtNewestWindow(false)
        }
    }

    func applyRefreshPreparation(
        _ update: HomeTimelineViewportState.NewestWindowUpdate,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        store.clearRestoreProjectionAnchorWithoutReload()
        applyNewestWindowUpdate(update, context: context)
    }

    func applyRestoreSnapshot(
        _ snapshot: HomeTimelineViewportRestoreSnapshot,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        store.setRestoreProjectionAnchor(snapshot.viewportState?.anchorPostID)
        store.setTimelineAtNewestWindow(false)
    }
}
