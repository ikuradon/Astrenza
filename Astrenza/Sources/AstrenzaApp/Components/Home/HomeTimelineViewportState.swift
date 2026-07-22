import CoreGraphics

struct TimelineFeedViewportObservation: Equatable {
    let collectionHeadPostID: TimelinePost.ID?
    let visibleHeadPostID: TimelinePost.ID?
    let isAtContentStart: Bool
    let isUserScrollActive: Bool
    let isPullRefreshing: Bool
    let sourceRevision: Int
}

struct HomeTimelineViewportLiveContext: Equatable {
    let selectedTimeline: TimelineKind
    let isRealtimeAvailable: Bool
    let pendingEventCount: Int

    static let inactive = HomeTimelineViewportLiveContext(
        selectedTimeline: .home,
        isRealtimeAvailable: false,
        pendingEventCount: 0
    )
}

enum HomeTimelineViewportMode: Equatable {
    case restoring
    case refreshing(expectedSourceRevision: Int?)
    case browsing
    case head
    case live

    var isAtNewestWindow: Bool {
        self == .head || self == .live
    }

    var isLive: Bool {
        self == .live
    }
}

private struct HomeTimelineViewportMachine {
    enum Intent {
        case contextChanged(HomeTimelineViewportLiveContext)
        case viewportObserved(TimelineFeedViewportObservation)
        case scrollActivityChanged(Bool)
        case restoreCompleted
        case refreshBegan
        case refreshCompleted(didUpdate: Bool, sourceRevision: Int)
        case reset(isRestoring: Bool)
        case invalidatePosition
    }

    private(set) var mode: HomeTimelineViewportMode
    private var context = HomeTimelineViewportLiveContext.inactive
    private var observation: TimelineFeedViewportObservation?
    private var isRestoreActive: Bool
    private var isScrollActive = false
    private var refreshExpectedSourceRevision: Int?
    private var isRefreshActive = false

    init(isRestoring: Bool) {
        isRestoreActive = isRestoring
        mode = isRestoring ? .restoring : .browsing
    }

    mutating func reduce(_ intent: Intent) {
        switch intent {
        case .contextChanged(let context):
            self.context = context
        case .viewportObserved(let observation):
            self.observation = observation
            isScrollActive = observation.isUserScrollActive
        case .scrollActivityChanged(let isActive):
            isScrollActive = isActive
        case .restoreCompleted:
            isRestoreActive = false
        case .refreshBegan:
            isRefreshActive = true
            refreshExpectedSourceRevision = nil
        case .refreshCompleted(let didUpdate, let sourceRevision):
            if didUpdate {
                refreshExpectedSourceRevision = sourceRevision
            } else {
                isRefreshActive = false
                refreshExpectedSourceRevision = nil
            }
        case .reset(let isRestoring):
            observation = nil
            isRestoreActive = isRestoring
            isScrollActive = false
            isRefreshActive = false
            refreshExpectedSourceRevision = nil
        case .invalidatePosition:
            observation = nil
            isScrollActive = false
        }
        reevaluate()
    }

    private mutating func reevaluate() {
        if isRestoreActive {
            mode = .restoring
            return
        }

        if isRefreshActive {
            if let expectedRevision = refreshExpectedSourceRevision,
               let observation,
               observation.sourceRevision >= expectedRevision {
                isRefreshActive = false
                refreshExpectedSourceRevision = nil
            } else {
                mode = .refreshing(
                    expectedSourceRevision: refreshExpectedSourceRevision
                )
                return
            }
        }

        guard !isScrollActive,
              context.pendingEventCount == 0,
              let observation,
              !observation.isPullRefreshing,
              observation.isAtContentStart,
              let collectionHeadPostID = observation.collectionHeadPostID,
              collectionHeadPostID == observation.visibleHeadPostID
        else {
            mode = .browsing
            return
        }

        mode = context.selectedTimeline == .home &&
            context.isRealtimeAvailable
            ? .live
            : .head
    }
}

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
    private var machine: HomeTimelineViewportMachine

    init(
        restoredViewportState: TimelineViewportState?,
        layoutCache: TimelineLayoutCache
    ) {
        viewportState = restoredViewportState
        self.layoutCache = layoutCache
        isAtNewestWindow = restoredViewportState == nil
        isRestoreProtectionActive = restoredViewportState != nil
        isDetachedFromLiveEdge = restoredViewportState != nil
        machine = HomeTimelineViewportMachine(
            isRestoring: restoredViewportState != nil
        )
    }

    var topChromeCollapseProgress: CGFloat {
        min(max(scrollOffset / 72, 0), 1)
    }

    var isHomeReturnMode: Bool {
        returnAnchor != nil
    }

    var mode: HomeTimelineViewportMode {
        machine.mode
    }

    var isRealtimeModeEnabled: Bool {
        machine.mode.isLive
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
        _ = applyMachineIntent(.restoreCompleted)
        return true
    }

    mutating func synchronizeLiveContext(
        _ context: HomeTimelineViewportLiveContext,
        forceStoreSync: Bool = false
    ) -> NewestWindowUpdate {
        applyMachineIntent(
            .contextChanged(context),
            forceStoreSync: forceStoreSync
        )
    }

    mutating func observeViewport(
        _ observation: TimelineFeedViewportObservation,
        forceStoreSync: Bool = false
    ) -> NewestWindowUpdate {
        applyMachineIntent(
            .viewportObserved(observation),
            forceStoreSync: forceStoreSync
        )
    }

    mutating func setUserScrollActive(
        _ isActive: Bool
    ) -> NewestWindowUpdate {
        applyMachineIntent(.scrollActivityChanged(isActive))
    }

    mutating func beginRefresh() -> NewestWindowUpdate {
        clearReturnAnchor()
        releaseRestoreProtection(clearViewportState: true)
        return applyMachineIntent(.refreshBegan, forceStoreSync: true)
    }

    mutating func completeRefresh(
        didUpdate: Bool,
        sourceRevision: Int
    ) -> NewestWindowUpdate {
        applyMachineIntent(
            .refreshCompleted(
                didUpdate: didUpdate,
                sourceRevision: sourceRevision
            ),
            forceStoreSync: !didUpdate
        )
    }

    mutating func updateNewestWindow(
        for offset: CGFloat,
        forceStoreSync: Bool = false
    ) -> NewestWindowUpdate {
        let nextIsAtNewestWindow = HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: offset,
            isRestoreProtected: isRestoreProtectionActive,
            isDetachedFromLiveEdge: isDetachedFromLiveEdge
        )
        let shouldUpdateState = isAtNewestWindow != nextIsAtNewestWindow
        let update = NewestWindowUpdate(
            isAtNewestWindow: nextIsAtNewestWindow,
            shouldUpdateState: shouldUpdateState,
            shouldPublishToStore: forceStoreSync || shouldUpdateState
        )
        if update.shouldUpdateState {
            applyNewestWindowUpdate(update)
        }
        return update
    }

    private mutating func applyNewestWindowUpdate(_ update: NewestWindowUpdate) {
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
            _ = applyMachineIntent(.invalidatePosition)
            scrollCommand = TimelineScrollCommand(target: .viewport(returnAnchor))
            self.returnAnchor = nil
            return .restore(returnAnchor)
        }

        returnAnchor = latestSavedViewportState ?? currentViewportState
        _ = applyMachineIntent(.invalidatePosition)
        scrollCommand = TimelineScrollCommand(target: .top)
        return .showNewest
    }

    mutating func prepareRefresh() -> NewestWindowUpdate {
        clearReturnAnchor()
        releaseRestoreProtection(clearViewportState: true)
        isDetachedFromLiveEdge = false
        return updateNewestWindow(for: scrollOffset, forceStoreSync: true)
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
        _ = applyMachineIntent(
            .reset(isRestoring: restoredViewportState != nil),
            forceStoreSync: true
        )
    }

    mutating func releaseRestoreProtection(clearViewportState: Bool) {
        let wasRestoreProtected = isRestoreProtectionActive
        isRestoreProtectionActive = false
        if wasRestoreProtected {
            _ = applyMachineIntent(.restoreCompleted)
        }
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

    private mutating func applyMachineIntent(
        _ intent: HomeTimelineViewportMachine.Intent,
        forceStoreSync: Bool = false
    ) -> NewestWindowUpdate {
        let previousIsAtNewestWindow = isAtNewestWindow
        machine.reduce(intent)
        isAtNewestWindow = machine.mode.isAtNewestWindow
        isDetachedFromLiveEdge = !isAtNewestWindow
        let didChange = previousIsAtNewestWindow != isAtNewestWindow
        return NewestWindowUpdate(
            isAtNewestWindow: isAtNewestWindow,
            shouldUpdateState: didChange,
            shouldPublishToStore: forceStoreSync || didChange
        )
    }
}

enum HomeTimelineViewportRestorePolicy {
    static let newestWindowMaximumOffset: CGFloat = 6

    static func isAtNewestWindow(
        offset: CGFloat,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        !isRestoreProtected &&
            !isDetachedFromLiveEdge &&
            offset <= newestWindowMaximumOffset
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

enum HomeTimelineLiveModePolicy {
    static func isEnabled(
        selectedTimeline: TimelineKind,
        isRealtime: Bool,
        isAtNewestWindow: Bool,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        guard selectedTimeline == .home else { return false }
        return HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: isRealtime,
            isAtNewestWindow: isAtNewestWindow,
            isRestoreProtected: isRestoreProtected,
            isDetachedFromLiveEdge: isDetachedFromLiveEdge
        )
    }
}
