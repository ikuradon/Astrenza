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
        let update = state.newestWindowUpdate(for: 0, forceStoreSync: true)
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

        let detachedUpdate = applyNewestWindowUpdate(to: &state, offset: 24)
        let unchangedUpdate = applyNewestWindowUpdate(to: &state, offset: 32)
        let newestUpdate = applyNewestWindowUpdate(to: &state, offset: 0)
        let forcedUpdate = applyNewestWindowUpdate(
            to: &state,
            offset: 0,
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
        #expect(!state.isDetachedFromLiveEdge)
        #expect(state.isAtNewestWindow)
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
            shouldUpdateState: true,
            shouldPublishToStore: true
        ))
    }

    private func makeState(
        restoredViewportState: TimelineViewportState? = nil
    ) -> HomeTimelineViewportState {
        HomeTimelineViewportState(
            restoredViewportState: restoredViewportState,
            layoutCache: TimelineLayoutCache()
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

    private func applyNewestWindowUpdate(
        to state: inout HomeTimelineViewportState,
        offset: CGFloat,
        forceStoreSync: Bool = false
    ) -> HomeTimelineViewportState.NewestWindowUpdate {
        let update = state.newestWindowUpdate(
            for: offset,
            forceStoreSync: forceStoreSync
        )
        if update.shouldUpdateState {
            state.applyNewestWindowUpdate(update)
        }
        return update
    }
}
