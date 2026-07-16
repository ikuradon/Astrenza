import Testing
@testable import Astrenza

@Suite("Home timeline published presentation state")
@MainActor
struct PublishedPresentationStateTests {
    @Test("The change mask updates only its selected presentation fields")
    func changeMaskPreservesUnselectedFields() throws {
        let initialFilter = TimelineFilterStatus(activeRuleCount: 1)
        let state = HomeTimelinePublishedPresentationState(
            entries: [.deleted(TimelineDeletedEntry(id: "initial"))],
            filterStatus: initialFilter,
            materializedUnreadCount: 1,
            visibleUnreadBadgeCount: 1,
            resolvedContentRevision: 2,
            realtimeFollowSourceRevision: 2
        )
        let transition = publishedPresentationTransition(
            entries: [.deleted(TimelineDeletedEntry(id: "next"))],
            filterStatus: TimelineFilterStatus(activeRuleCount: 9),
            materializedUnreadCount: 3,
            visibleUnreadBadgeCount: 2,
            resolvedContentRevision: 10,
            realtimeFollowSourceRevision: 10,
            changes: [.entries, .unreadCounts]
        )

        let next = try #require(state.applying(transition))

        #expect(next.entries.map(\.id) == ["next"])
        #expect(next.materializedUnreadCount == 3)
        #expect(next.visibleUnreadBadgeCount == 2)
        #expect(next.filterStatus == initialFilter)
        #expect(next.resolvedContentRevision == 2)
        #expect(next.realtimeFollowSourceRevision == 2)
    }

    @Test("Filter and revision changes copy their canonical snapshot values")
    func filterAndRevisionChangesApply() throws {
        let state = HomeTimelinePublishedPresentationState()
        let nextFilter = TimelineFilterStatus(
            activeRuleCount: 2,
            warningMatchCount: 1,
            hiddenMatchCount: 1,
            isSuspended: true
        )
        let transition = publishedPresentationTransition(
            filterStatus: nextFilter,
            resolvedContentRevision: 7,
            realtimeFollowSourceRevision: 6,
            changes: [
                .filterStatus,
                .resolvedContentRevision,
                .realtimeFollowSourceRevision
            ]
        )

        let next = try #require(state.applying(transition))

        #expect(next.filterStatus == nextFilter)
        #expect(next.resolvedContentRevision == 7)
        #expect(next.realtimeFollowSourceRevision == 6)
    }

    @Test("Empty and equal unread transitions avoid redundant publication state")
    func noMutationReturnsNil() {
        let state = HomeTimelinePublishedPresentationState(
            materializedUnreadCount: 2,
            visibleUnreadBadgeCount: 1
        )
        let empty = publishedPresentationTransition(
            materializedUnreadCount: 9,
            visibleUnreadBadgeCount: 9,
            changes: []
        )
        let equalUnread = publishedPresentationTransition(
            materializedUnreadCount: 2,
            visibleUnreadBadgeCount: 1,
            changes: [.unreadCounts]
        )

        #expect(state.applying(empty) == nil)
        #expect(state.applying(equalUnread) == nil)
    }

    @Test("A selected presentation field notifies its observer once")
    func selectedPresentationFieldNotifiesOnce() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)
        store.testingSetMaterializedPostIDs(["old"])
        store.testingSetReadBoundary(postID: "old")
        let observation = observePublishedState(store.entries)

        store.testingSetMaterializedPostIDs(["new", "old"])

        #expect(observation.count == 1)
        #expect(store.entries.map(\.id) == ["new", "old"])
        #expect(store.materializedUnreadCount == 1)
        #expect(store.visibleUnreadBadgeCount == 1)
    }
}

@MainActor
private func publishedPresentationTransition(
    entries: [TimelineFeedEntry] = [],
    filterStatus: TimelineFilterStatus = TimelineFilterStatus(),
    materializedUnreadCount: Int = 0,
    visibleUnreadBadgeCount: Int = 0,
    resolvedContentRevision: Int = 0,
    realtimeFollowSourceRevision: Int? = nil,
    changes: HomeTimelinePresentationChanges
) -> HomeTimelinePresentationTransition {
    HomeTimelinePresentationTransition(
        snapshot: HomeTimelinePresentationSnapshot(
            entries: entries,
            filterStatus: filterStatus,
            materializedUnreadCount: materializedUnreadCount,
            visibleUnreadBadgeCount: visibleUnreadBadgeCount,
            resolvedContentRevision: resolvedContentRevision,
            realtimeFollowSourceRevision: realtimeFollowSourceRevision
        ),
        changes: changes,
        didChangeReadState: false
    )
}
