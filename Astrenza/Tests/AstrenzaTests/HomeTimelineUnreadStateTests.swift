import Testing
@testable import Astrenza

@MainActor
@Suite("Home timeline unread state")
struct HomeTimelineUnreadStateTests {
    @Test("unread state scopes dismissed badge to the current generation")
    func unreadStateDismissesOnlyCurrentGeneration() {
        var state = HomeTimelineUnreadState()

        state.replaceMaterializedPostIDs(["new-1", "old-1"], marksInitialWindowRead: false)
        state.setReadBoundary(postID: "old-1")
        state.dismissBadge()

        #expect(state.visibleUnreadBadgeCount == 0)

        state.replaceMaterializedPostIDs(["new-2", "new-1", "old-1"], marksInitialWindowRead: false)

        #expect(state.materializedUnreadCount == 2)
        #expect(state.visibleUnreadBadgeCount == 2)
    }

    @Test("materialized unread count ignores unmaterialized new events")
    func materializedUnreadCountIsSeparateFromUnmaterializedEvents() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.testingSetUnmaterializedNewEventIDs(["db-new-1"])

        #expect(store.materializedUnreadCount == 2)
        #expect(store.visibleUnreadBadgeCount == 2)
        #expect(store.unmaterializedNewCount == 1)
    }

    @Test("dismissing badge hides only the current unread generation")
    func unreadBadgeDismissIsGenerationScoped() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.dismissUnreadBadge()
        #expect(store.visibleUnreadBadgeCount == 0)

        store.testingSetMaterializedPostIDs(["new-2", "new-1", "old-1"])
        #expect(store.visibleUnreadBadgeCount == 2)
    }

    @Test("marking visible materialized posts read decreases unread count")
    func markVisiblePostsReadDecreasesCount() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["new-1"])
        #expect(store.materializedUnreadCount == 1)

        store.markMaterializedPostsRead(visiblePostIDs: ["new-2"])
        #expect(store.materializedUnreadCount == 0)
    }

    @Test("read boundary advances with the last counted post")
    func readBoundaryAdvancesWithCountedPost() {
        var state = HomeTimelineUnreadState()

        state.replaceMaterializedPostIDs(
            ["new-1", "new-2", "old-1"],
            marksInitialWindowRead: false
        )
        state.setReadBoundary(postID: "old-1")
        #expect(state.materializedUnreadCount == 2)
        #expect(state.readBoundaryPostID == "old-1")

        state.markVisiblePostsRead(["new-2"])
        #expect(state.materializedUnreadCount == 1)
        #expect(state.readBoundaryPostID == "new-2")
    }

    @Test("marking newest materialized window read clears the badge")
    func markNewestMaterializedWindowReadClearsBadge() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        #expect(store.visibleUnreadBadgeCount == 2)

        store.markNewestMaterializedWindowRead()

        #expect(store.materializedUnreadCount == 0)
        #expect(store.visibleUnreadBadgeCount == 0)
    }

    @Test("unread count is retained when the viewport moves older than its anchor")
    func unreadCountIsRetainedPastAnchor() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1", "old-2"])
        store.testingSetReadBoundary(postID: "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["old-2"])
        #expect(store.materializedUnreadCount == 2)
        #expect(store.visibleUnreadBadgeCount == 2)
        #expect(store.unreadCountAnchorPostID == "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["new-1"])
        #expect(store.visibleUnreadBadgeCount == 1)
    }
}

@MainActor
@Suite("Home unread pill placement")
struct HomeUnreadPillPlacementTests {
    private let postOrder = [
        "new-1": 0,
        "new-2": 1,
        "anchor": 2,
        "old-1": 3,
    ]

    @Test("pill stays pinned at the bottom edge of the top chrome")
    func pillStaysPinnedAtAnchor() {
        let placement = HomeUnreadPillPlacementPolicy.resolve(
            anchorPostID: "anchor",
            anchorMinY: 72,
            postOrderByID: postOrder,
            readablePostIDs: ["anchor"],
            pinLineY: 72
        )

        #expect(placement == .visible(offsetY: 0))
    }

    @Test("pill follows its anchor toward the top")
    func pillFollowsAnchorTowardTop() {
        let placement = HomeUnreadPillPlacementPolicy.resolve(
            anchorPostID: "anchor",
            anchorMinY: 44,
            postOrderByID: postOrder,
            readablePostIDs: ["anchor"],
            pinLineY: 72
        )

        #expect(placement == .visible(offsetY: -28))
    }

    @Test("pill remains offscreen while the viewport is older than its anchor")
    func pillIsHiddenPastAnchor() {
        let placement = HomeUnreadPillPlacementPolicy.resolve(
            anchorPostID: "anchor",
            anchorMinY: nil,
            postOrderByID: postOrder,
            readablePostIDs: ["old-1"],
            pinLineY: 72
        )

        #expect(placement == .hidden)
    }

    @Test("pill resumes when the viewport returns to its anchor")
    func pillResumesAtAnchor() {
        let placement = HomeUnreadPillPlacementPolicy.resolve(
            anchorPostID: "anchor",
            anchorMinY: nil,
            postOrderByID: postOrder,
            readablePostIDs: ["anchor"],
            pinLineY: 72
        )

        #expect(placement == .visible(offsetY: 0))
    }
}
