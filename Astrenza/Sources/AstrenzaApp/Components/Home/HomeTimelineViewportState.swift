import CoreGraphics

struct HomeTimelineViewportState {
    struct NewestWindowUpdate: Equatable {
        let isAtNewestWindow: Bool
        let shouldUpdateState: Bool
        let shouldPublishToStore: Bool
    }

    enum HomeRetapAction: Equatable {
        case restore(TimelineViewportState)
        case showNewest
    }

    private(set) var scrollOffset: CGFloat = 0
    private(set) var isAtNewestWindow: Bool
    private(set) var isRestoreProtectionActive: Bool
    private(set) var isDetachedFromLiveEdge: Bool
    private(set) var returnAnchor: TimelineViewportState?
    private(set) var scrollCommand: TimelineScrollCommand?
    private(set) var viewportState: TimelineViewportState?
    private(set) var layoutCache: TimelineLayoutCache

    init(
        restoredViewportState: TimelineViewportState?,
        layoutCache: TimelineLayoutCache
    ) {
        viewportState = restoredViewportState
        self.layoutCache = layoutCache
        isAtNewestWindow = restoredViewportState == nil
        isRestoreProtectionActive = restoredViewportState != nil
        isDetachedFromLiveEdge = restoredViewportState != nil
    }

    var topChromeCollapseProgress: CGFloat {
        min(max(scrollOffset / 72, 0), 1)
    }

    var isHomeReturnMode: Bool {
        returnAnchor != nil
    }

    func shouldDismissFloatingMenus(for offset: CGFloat) -> Bool {
        abs(offset - scrollOffset) > 1
    }

    func scrollOffsetUpdate(for offset: CGFloat) -> CGFloat? {
        let oldChromeOffset = min(max(scrollOffset, 0), 72)
        let newChromeOffset = min(max(offset, 0), 72)
        let crossedCollapseBoundary = (scrollOffset <= 72) != (offset <= 72)
        guard abs(newChromeOffset - oldChromeOffset) >= 2 || crossedCollapseBoundary else { return nil }
        return newChromeOffset
    }

    mutating func applyScrollOffset(_ newChromeOffset: CGFloat) {
        scrollOffset = newChromeOffset
    }

    mutating func completeRestore() -> Bool {
        guard isRestoreProtectionActive else { return false }
        isRestoreProtectionActive = false
        return true
    }

    func newestWindowUpdate(
        for offset: CGFloat,
        forceStoreSync: Bool = false
    ) -> NewestWindowUpdate {
        let nextIsAtNewestWindow = HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: offset,
            isRestoreProtected: isRestoreProtectionActive,
            isDetachedFromLiveEdge: isDetachedFromLiveEdge
        )
        let shouldUpdateState = isAtNewestWindow != nextIsAtNewestWindow
        return NewestWindowUpdate(
            isAtNewestWindow: nextIsAtNewestWindow,
            shouldUpdateState: shouldUpdateState,
            shouldPublishToStore: forceStoreSync || shouldUpdateState
        )
    }

    mutating func applyNewestWindowUpdate(_ update: NewestWindowUpdate) {
        isAtNewestWindow = update.isAtNewestWindow
    }

    mutating func prepareHomeRetap(
        latestSavedViewportState: TimelineViewportState?
    ) -> HomeRetapAction {
        let currentViewportState = viewportState
        releaseRestoreProtection(clearViewportState: true)

        if let returnAnchor {
            isDetachedFromLiveEdge = true
            isAtNewestWindow = false
            scrollCommand = TimelineScrollCommand(target: .viewport(returnAnchor))
            self.returnAnchor = nil
            return .restore(returnAnchor)
        }

        isDetachedFromLiveEdge = false
        returnAnchor = latestSavedViewportState ?? currentViewportState
        isAtNewestWindow = true
        scrollCommand = TimelineScrollCommand(target: .top)
        return .showNewest
    }

    mutating func prepareRefresh() -> NewestWindowUpdate {
        clearReturnAnchor()
        releaseRestoreProtection(clearViewportState: true)
        isDetachedFromLiveEdge = false
        let update = newestWindowUpdate(for: scrollOffset, forceStoreSync: true)
        if update.shouldUpdateState {
            applyNewestWindowUpdate(update)
        }
        return update
    }

    mutating func clearReturnAnchor() {
        returnAnchor = nil
    }

    mutating func load(
        restoredViewportState: TimelineViewportState?,
        layoutCache: TimelineLayoutCache
    ) {
        viewportState = restoredViewportState
        isRestoreProtectionActive = restoredViewportState != nil
        isDetachedFromLiveEdge = restoredViewportState != nil
        isAtNewestWindow = restoredViewportState == nil
        self.layoutCache = layoutCache
    }

    mutating func releaseRestoreProtection(clearViewportState: Bool) {
        isRestoreProtectionActive = false
        if clearViewportState {
            viewportState = nil
        }
    }

    func shouldUpdateLayoutCache(_ cache: TimelineLayoutCache) -> Bool {
        layoutCache != cache
    }

    mutating func applyLayoutCache(_ cache: TimelineLayoutCache) {
        layoutCache = cache
    }
}

enum HomeTimelineViewportRestorePolicy {
    static func isAtNewestWindow(
        offset: CGFloat,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        !isRestoreProtected && !isDetachedFromLiveEdge && offset <= 6
    }

    static func followsRealtimeEntries(
        isRealtime: Bool,
        isAtNewestWindow: Bool,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        isRealtime && !isRestoreProtected && !isDetachedFromLiveEdge && isAtNewestWindow
    }
}
