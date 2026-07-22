import CoreGraphics
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline viewport state")
struct HomeTimelineViewportStateTests {
    @Test("Restored viewport starts protected and detached from the live edge")
    func restoredViewportStartsProtectedAndDetached() {
        let restoredViewport = makeViewport(postID: "restored")
        let layoutCache = TimelineLayoutCache(measuredHeights: ["restored": 180])

        let state = HomeTimelineViewportState(
            restoredViewportState: restoredViewport,
            layoutCache: layoutCache
        )

        #expect(state.viewportState == restoredViewport)
        #expect(state.layoutCache == layoutCache)
        #expect(state.isRestoreProtectionActive)
        #expect(state.isDetachedFromLiveEdge)
        #expect(!state.isAtNewestWindow)
        #expect(!state.isHomeReturnMode)
    }

    @Test("Chrome offset keeps the existing update threshold and clamping")
    func chromeOffsetKeepsThresholdAndClamping() {
        var state = makeState()

        #expect(!state.shouldDismissFloatingMenus(for: 1))
        #expect(state.shouldDismissFloatingMenus(for: 1.1))

        recordScrollOffset(1, on: &state)
        #expect(state.scrollOffset == 0)

        recordScrollOffset(40, on: &state)
        #expect(state.scrollOffset == 40)
        #expect(state.topChromeCollapseProgress == CGFloat(40) / 72)

        recordScrollOffset(100, on: &state)
        #expect(state.scrollOffset == 72)
        #expect(state.topChromeCollapseProgress == 1)
    }

    @Test("Completing restore unlocks writes but keeps the restored window detached")
    func completingRestoreKeepsRestoredWindowDetached() {
        var state = makeState(restoredViewportState: makeViewport(postID: "anchor"))

        let didCompleteRestore = state.completeRestore()
        let update = state.updateNewestWindow(for: 0, forceStoreSync: true)
        let didCompleteRestoreAgain = state.completeRestore()

        #expect(didCompleteRestore)
        #expect(!state.isRestoreProtectionActive)
        #expect(state.isDetachedFromLiveEdge)
        #expect(!state.isAtNewestWindow)
        #expect(update == .init(
            isAtNewestWindow: false,
            shouldUpdateState: false,
            shouldPublishToStore: true
        ))
        #expect(!didCompleteRestoreAgain)
    }

    @Test("Newest-window updates publish only on change unless forced")
    func newestWindowUpdatesPublishOnlyWhenRequired() {
        var state = makeState()

        let detachedUpdate = state.updateNewestWindow(for: 24)
        let unchangedUpdate = state.updateNewestWindow(for: 32)
        let newestUpdate = state.updateNewestWindow(for: 0)
        let forcedUpdate = state.updateNewestWindow(
            for: 0,
            forceStoreSync: true
        )

        #expect(detachedUpdate == .init(
            isAtNewestWindow: false,
            shouldUpdateState: true,
            shouldPublishToStore: true
        ))
        #expect(unchangedUpdate == .init(
            isAtNewestWindow: false,
            shouldUpdateState: false,
            shouldPublishToStore: false
        ))
        #expect(newestUpdate == .init(
            isAtNewestWindow: true,
            shouldUpdateState: true,
            shouldPublishToStore: true
        ))
        #expect(forcedUpdate == .init(
            isAtNewestWindow: true,
            shouldUpdateState: false,
            shouldPublishToStore: true
        ))
    }

    @Test("Home retap round trip preserves the original viewport anchor")
    func homeRetapRoundTripPreservesViewportAnchor() {
        let restoredViewport = makeViewport(postID: "return-anchor")
        var state = makeState(restoredViewportState: restoredViewport)

        let showNewestAction = state.prepareHomeRetap(latestSavedViewportState: nil)

        #expect(showNewestAction == .showNewest)
        #expect(state.returnAnchor == restoredViewport)
        #expect(state.viewportState == nil)
        #expect(!state.isRestoreProtectionActive)
        #expect(state.isDetachedFromLiveEdge)
        #expect(!state.isAtNewestWindow)
        #expect(state.scrollCommand?.target == .top)

        let restoreAction = state.prepareHomeRetap(latestSavedViewportState: nil)

        #expect(restoreAction == .restore(restoredViewport))
        #expect(state.returnAnchor == nil)
        #expect(state.isDetachedFromLiveEdge)
        #expect(!state.isAtNewestWindow)
        #expect(state.scrollCommand?.target == .viewport(restoredViewport))
    }

    @Test("Refresh clears restore state and recalculates the live edge from the current offset")
    func refreshClearsRestoreStateAndRecalculatesLiveEdge() {
        let restoredViewport = makeViewport(postID: "refresh-anchor")
        var state = makeState(restoredViewportState: restoredViewport)
        recordScrollOffset(24, on: &state)
        _ = state.prepareHomeRetap(latestSavedViewportState: nil)

        let update = state.prepareRefresh()

        #expect(state.returnAnchor == nil)
        #expect(state.viewportState == nil)
        #expect(!state.isRestoreProtectionActive)
        #expect(!state.isDetachedFromLiveEdge)
        #expect(!state.isAtNewestWindow)
        #expect(update == .init(
            isAtNewestWindow: false,
            shouldUpdateState: false,
            shouldPublishToStore: true
        ))
    }

    @Test("Live mode is exposed only for a realtime Home live edge")
    func liveModeRequiresRealtimeHomeLiveEdge() {
        #expect(HomeTimelineLiveModePolicy.isEnabled(
            selectedTimeline: .home,
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: false
        ))
        #expect(!HomeTimelineLiveModePolicy.isEnabled(
            selectedTimeline: .lists,
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: false
        ))
        #expect(!HomeTimelineLiveModePolicy.isEnabled(
            selectedTimeline: .home,
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: true
        ))
    }

    @Test("LIVE requires the applied collection head to be the visible head")
    func liveRequiresActualCollectionHead() {
        var state = makeState()
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: true,
            pendingEventCount: 0
        ))

        let liveUpdate = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "newest"
        ))

        #expect(state.mode == .live)
        #expect(state.isRealtimeModeEnabled)
        #expect(liveUpdate.isAtNewestWindow)

        let browsingUpdate = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "anchor"
        ))

        #expect(state.mode == .browsing)
        #expect(!state.isRealtimeModeEnabled)
        #expect(!browsingUpdate.isAtNewestWindow)
    }

    @Test("Pending events keep the physical head out of LIVE")
    func pendingEventsDisableLiveAtPhysicalHead() {
        var state = makeState()
        _ = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "newest"
        ))
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: true,
            pendingEventCount: 4
        ))

        #expect(state.mode == .browsing)
        #expect(!state.isAtNewestWindow)
        #expect(!state.isRealtimeModeEnabled)
    }

    @Test("Vertical interaction exits LIVE before the content offset changes")
    func scrollActivityExitsLiveImmediately() {
        var state = makeLiveState()

        let update = state.setUserScrollActive(true)

        #expect(state.mode == .browsing)
        #expect(!update.isAtNewestWindow)
        #expect(update.shouldPublishToStore)
    }

    @Test("UIKit pull-refresh protection cannot briefly re-enter LIVE")
    func pullRefreshObservationDisablesLive() {
        var state = makeLiveState()

        _ = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "newest",
            isUserScrollActive: false,
            isPullRefreshing: true
        ))

        #expect(state.mode == .browsing)
        #expect(!state.isRealtimeModeEnabled)
        #expect(!state.isAtNewestWindow)
    }

    @Test("Refresh stays protected until its revision reaches UICollectionView")
    func refreshWaitsForAppliedSourceRevision() {
        var state = makeLiveState(sourceRevision: 10)

        _ = state.beginRefresh()
        _ = state.completeRefresh(didUpdate: true, sourceRevision: 11)

        #expect(state.mode == .refreshing(expectedSourceRevision: 11))
        #expect(!state.isRealtimeModeEnabled)

        _ = state.observeViewport(observation(
            collectionHead: "new",
            visibleHead: "old",
            sourceRevision: 11
        ))

        #expect(state.mode == .browsing)
        #expect(!state.isRealtimeModeEnabled)
    }

    @Test("Applying a pending stack never flashes LIVE before the anchor is committed")
    func pendingRefreshNeverFlashesLive() {
        var state = makeLiveState(sourceRevision: 10)
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: true,
            pendingEventCount: 3
        ))
        #expect(state.mode == .browsing)

        _ = state.beginRefresh()
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: true,
            pendingEventCount: 0
        ))
        _ = state.completeRefresh(
            didUpdate: true,
            sourceRevision: 12
        )
        _ = state.observeViewport(observation(
            collectionHead: "old",
            visibleHead: "old",
            sourceRevision: 11
        ))

        #expect(state.mode == .refreshing(expectedSourceRevision: 12))
        #expect(!state.isRealtimeModeEnabled)

        _ = state.observeViewport(observation(
            collectionHead: "new",
            visibleHead: "old",
            isAtContentStart: false,
            sourceRevision: 12
        ))

        #expect(state.mode == .browsing)
        #expect(!state.isRealtimeModeEnabled)
    }

    @Test("A physical head waits for forward EOSE before showing LIVE")
    func physicalHeadWaitsForRealtimeReadiness() {
        var state = makeState()
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: false,
            pendingEventCount: 0
        ))
        _ = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "newest"
        ))

        #expect(state.mode == .head)
        #expect(state.isAtNewestWindow)
        #expect(!state.isRealtimeModeEnabled)
    }

    private func makeState(
        restoredViewportState: TimelineViewportState? = nil
    ) -> HomeTimelineViewportState {
        HomeTimelineViewportState(
            restoredViewportState: restoredViewportState,
            layoutCache: TimelineLayoutCache()
        )
    }

    private func makeLiveState(
        sourceRevision: Int = 1
    ) -> HomeTimelineViewportState {
        var state = makeState()
        _ = state.synchronizeLiveContext(.init(
            selectedTimeline: .home,
            isRealtimeAvailable: true,
            pendingEventCount: 0
        ))
        _ = state.observeViewport(observation(
            collectionHead: "newest",
            visibleHead: "newest",
            sourceRevision: sourceRevision
        ))
        return state
    }

    private func observation(
        collectionHead: TimelinePost.ID?,
        visibleHead: TimelinePost.ID?,
        isAtContentStart: Bool = true,
        isUserScrollActive: Bool = false,
        isPullRefreshing: Bool = false,
        sourceRevision: Int = 1
    ) -> TimelineFeedViewportObservation {
        TimelineFeedViewportObservation(
            collectionHeadPostID: collectionHead,
            visibleHeadPostID: visibleHead,
            isAtContentStart: isAtContentStart,
            isUserScrollActive: isUserScrollActive,
            isPullRefreshing: isPullRefreshing,
            sourceRevision: sourceRevision
        )
    }

    private func makeViewport(postID: TimelinePost.ID) -> TimelineViewportState {
        TimelineViewportState(
            accountID: "account",
            timelineKey: TimelineKind.home.id,
            anchorPostID: postID,
            anchorOffset: 18,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func recordScrollOffset(
        _ offset: CGFloat,
        on state: inout HomeTimelineViewportState
    ) {
        guard let newChromeOffset = state.scrollOffsetUpdate(for: offset) else { return }
        state.applyScrollOffset(newChromeOffset)
    }
}
