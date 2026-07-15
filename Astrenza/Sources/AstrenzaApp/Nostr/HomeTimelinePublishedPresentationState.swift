struct HomeTimelinePublishedPresentationState {
    private(set) var entries: [TimelineFeedEntry]
    private(set) var filterStatus: TimelineFilterStatus
    private(set) var materializedUnreadCount: Int
    private(set) var visibleUnreadBadgeCount: Int
    private(set) var resolvedContentRevision: Int
    private(set) var realtimeFollowSourceRevision: Int?

    init(
        entries: [TimelineFeedEntry] = [],
        filterStatus: TimelineFilterStatus = TimelineFilterStatus(),
        materializedUnreadCount: Int = 0,
        visibleUnreadBadgeCount: Int = 0,
        resolvedContentRevision: Int = 0,
        realtimeFollowSourceRevision: Int? = nil
    ) {
        self.entries = entries
        self.filterStatus = filterStatus
        self.materializedUnreadCount = materializedUnreadCount
        self.visibleUnreadBadgeCount = visibleUnreadBadgeCount
        self.resolvedContentRevision = resolvedContentRevision
        self.realtimeFollowSourceRevision = realtimeFollowSourceRevision
    }

    func applying(
        _ transition: HomeTimelinePresentationTransition
    ) -> HomeTimelinePublishedPresentationState? {
        let changes = transition.changes
        let snapshot = transition.snapshot
        var next = self
        var didMutate = false

        if changes.contains(.entries) {
            next.entries = snapshot.entries
            didMutate = true
        }
        if changes.contains(.unreadCounts) {
            if next.materializedUnreadCount != snapshot.materializedUnreadCount {
                next.materializedUnreadCount = snapshot.materializedUnreadCount
                didMutate = true
            }
            if next.visibleUnreadBadgeCount != snapshot.visibleUnreadBadgeCount {
                next.visibleUnreadBadgeCount = snapshot.visibleUnreadBadgeCount
                didMutate = true
            }
        }
        if changes.contains(.filterStatus) {
            next.filterStatus = snapshot.filterStatus
            didMutate = true
        }
        if changes.contains(.resolvedContentRevision) {
            next.resolvedContentRevision = snapshot.resolvedContentRevision
            didMutate = true
        }
        if changes.contains(.realtimeFollowSourceRevision) {
            next.realtimeFollowSourceRevision = snapshot.realtimeFollowSourceRevision
            didMutate = true
        }
        return didMutate ? next : nil
    }
}
