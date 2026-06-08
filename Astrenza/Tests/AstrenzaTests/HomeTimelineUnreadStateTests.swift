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
        let store = NostrHomeTimelineStore(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.testingSetUnmaterializedNewEventIDs(["db-new-1"])

        #expect(store.materializedUnreadCount == 2)
        #expect(store.visibleUnreadBadgeCount == 2)
        #expect(store.unmaterializedNewCount == 1)
    }

    @Test("dismissing badge hides only the current unread generation")
    func unreadBadgeDismissIsGenerationScoped() {
        let store = NostrHomeTimelineStore(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.dismissUnreadBadge()
        #expect(store.visibleUnreadBadgeCount == 0)

        store.testingSetMaterializedPostIDs(["new-2", "new-1", "old-1"])
        #expect(store.visibleUnreadBadgeCount == 2)
    }

    @Test("marking visible materialized posts read decreases unread count")
    func markVisiblePostsReadDecreasesCount() {
        let store = NostrHomeTimelineStore(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["new-1"])
        #expect(store.materializedUnreadCount == 1)

        store.markMaterializedPostsRead(visiblePostIDs: ["new-2"])
        #expect(store.materializedUnreadCount == 0)
    }

    @Test("marking newest materialized window read clears the badge")
    func markNewestMaterializedWindowReadClearsBadge() {
        let store = NostrHomeTimelineStore(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        #expect(store.visibleUnreadBadgeCount == 2)

        store.markNewestMaterializedWindowRead()

        #expect(store.materializedUnreadCount == 0)
        #expect(store.visibleUnreadBadgeCount == 0)
    }

    @Test("badge hides when the viewport moves older than the unread range")
    func badgeHidesPastUnreadRange() {
        let store = NostrHomeTimelineStore(eventStore: nil)

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1", "old-2"])
        store.testingSetReadBoundary(postID: "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["old-2"])
        #expect(store.materializedUnreadCount == 2)
        #expect(store.visibleUnreadBadgeCount == 0)

        store.markMaterializedPostsRead(visiblePostIDs: ["new-1"])
        #expect(store.visibleUnreadBadgeCount == 1)
    }
}
