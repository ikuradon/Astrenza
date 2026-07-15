import Testing
@testable import Astrenza

@Suite("Home timeline projection viewport state")
struct ProjectionViewportStateTests {
    @Test("The initial viewport follows the newest window without an anchor")
    func initialStateFollowsNewest() {
        let state = HomeTimelineProjectionViewportState()

        #expect(state.restoreAnchorEventID == nil)
        #expect(state.isAtNewestWindow)
    }

    @Test("Setting a restore anchor atomically detaches from newest")
    func restoreAnchorDetaches() throws {
        let state = HomeTimelineProjectionViewportState()

        let next = try #require(state.applying(.setRestoreAnchor("anchor")))

        #expect(next.restoreAnchorEventID == "anchor")
        #expect(!next.isAtNewestWindow)
    }

    @Test("Clearing a restore anchor preserves the detached window")
    func clearingAnchorPreservesDetach() throws {
        let state = HomeTimelineProjectionViewportState(
            restoreAnchorEventID: "anchor",
            isAtNewestWindow: false
        )

        let next = try #require(state.applying(.setRestoreAnchor(nil)))

        #expect(next.restoreAnchorEventID == nil)
        #expect(!next.isAtNewestWindow)
    }

    @Test("An active restore anchor blocks realtime newest following")
    func restoreAnchorBlocksNewestFollow() {
        let state = HomeTimelineProjectionViewportState(
            restoreAnchorEventID: "anchor",
            isAtNewestWindow: false
        )

        #expect(state.applying(.setNewestWindow(true)) == nil)
        #expect(state.restoreAnchorEventID == "anchor")
        #expect(!state.isAtNewestWindow)
    }

    @Test("A restored nil anchor still stays detached during viewport recovery")
    func restoredNilAnchorStaysDetached() throws {
        let state = HomeTimelineProjectionViewportState()

        let next = try #require(state.applying(.restoreViewport(
            anchorEventID: nil
        )))

        #expect(next.restoreAnchorEventID == nil)
        #expect(!next.isAtNewestWindow)
    }

    @Test("Reset clears restoration and explicitly resumes newest following")
    func resetResumesNewestFollow() throws {
        let state = HomeTimelineProjectionViewportState(
            restoreAnchorEventID: "anchor",
            isAtNewestWindow: false
        )

        let next = try #require(state.applying(.resetToNewest))

        #expect(next.restoreAnchorEventID == nil)
        #expect(next.isAtNewestWindow)
    }
}
