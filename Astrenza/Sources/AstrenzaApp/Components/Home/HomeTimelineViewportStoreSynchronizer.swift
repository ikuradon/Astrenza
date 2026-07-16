import AstrenzaCore

@MainActor
protocol HomeTimelineViewportStoreHandling: AnyObject {
    func setRestoreProjectionAnchor(_ anchorEventID: String?)
    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool)
    func markNewestMaterializedWindowRead()
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
            store.markNewestMaterializedWindowRead()
            // ページング後の先頭Rowは最新とは限らないため、最新windowを先に復元する。
            store.setRestoreProjectionAnchor(nil)
            store.setTimelineAtNewestWindow(true)
        }
    }

    func applyRestoreSnapshot(
        _ snapshot: HomeTimelineViewportRestoreSnapshot,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        store.setRestoreProjectionAnchor(snapshot.viewportState?.anchorPostID)
        store.setTimelineAtNewestWindow(snapshot.viewportState == nil)
    }
}
