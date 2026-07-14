import Foundation

struct TimelineFilterStatus: Equatable {
    var activeRuleCount = 0
    var warningMatchCount = 0
    var hiddenMatchCount = 0
    var isSuspended = false

    var matchedPostCount: Int {
        warningMatchCount + hiddenMatchCount
    }

    var isVisible: Bool {
        activeRuleCount > 0 || isSuspended
    }
}

struct HomeTimelinePresentationSnapshot {
    let entries: [TimelineFeedEntry]
    let filterStatus: TimelineFilterStatus
    let materializedUnreadCount: Int
    let visibleUnreadBadgeCount: Int
    let resolvedContentRevision: Int
    let realtimeFollowSourceRevision: Int?
}

struct HomeTimelinePresentationChanges: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let entries = HomeTimelinePresentationChanges(rawValue: 1 << 0)
    static let filterStatus = HomeTimelinePresentationChanges(rawValue: 1 << 1)
    static let unreadCounts = HomeTimelinePresentationChanges(rawValue: 1 << 2)
    static let resolvedContentRevision = HomeTimelinePresentationChanges(rawValue: 1 << 3)
    static let realtimeFollowSourceRevision = HomeTimelinePresentationChanges(rawValue: 1 << 4)
}

struct HomeTimelinePresentationTransition {
    let snapshot: HomeTimelinePresentationSnapshot
    let changes: HomeTimelinePresentationChanges
    let didChangeReadState: Bool
}

@MainActor
final class HomeTimelinePresentationCoordinator {
    typealias MaterializeHandler = HomeTimelineMaterializationScheduler.MaterializeHandler

    private let scheduler: HomeTimelineMaterializationScheduler
    private var entries: [TimelineFeedEntry] = []
    private var filterStatus = TimelineFilterStatus()
    private var unreadState = HomeTimelineUnreadState()
    private var resolvedContentRevision = 0
    private var realtimeFollowSourceRevision: Int?

    init(scheduler: HomeTimelineMaterializationScheduler = HomeTimelineMaterializationScheduler()) {
        self.scheduler = scheduler
    }

    var snapshot: HomeTimelinePresentationSnapshot {
        HomeTimelinePresentationSnapshot(
            entries: entries,
            filterStatus: filterStatus,
            materializedUnreadCount: unreadState.materializedUnreadCount,
            visibleUnreadBadgeCount: unreadState.visibleUnreadBadgeCount,
            resolvedContentRevision: resolvedContentRevision,
            realtimeFollowSourceRevision: realtimeFollowSourceRevision
        )
    }

    var defaultDelayNanoseconds: UInt64 {
        scheduler.defaultDelayNanoseconds
    }

    var hasPendingNewestProjectionReload: Bool {
        scheduler.hasPendingNewestProjectionReload
    }

    var hasPendingMaterialization: Bool {
        scheduler.hasPendingMaterialization
    }

    var readBoundaryPostID: TimelinePost.ID? {
        unreadState.readBoundaryPostID
    }

    func reset() -> HomeTimelinePresentationTransition {
        var changes: HomeTimelinePresentationChanges = []
        if !entries.isEmpty {
            entries = []
            changes.insert(.entries)
        }
        if filterStatus != TimelineFilterStatus() {
            filterStatus = TimelineFilterStatus()
            changes.insert(.filterStatus)
        }
        let previousUnreadCounts = unreadCounts
        unreadState.reset()
        changes.formUnion(unreadChanges(from: previousUnreadCounts))
        scheduler.reset()
        if realtimeFollowSourceRevision != nil {
            realtimeFollowSourceRevision = nil
            changes.insert(.realtimeFollowSourceRevision)
        }
        return transition(changes: changes)
    }

    func setScrollActive(
        _ isActive: Bool,
        materialize: @escaping MaterializeHandler
    ) {
        scheduler.setScrollActive(isActive, materialize: materialize)
    }

    func requestNewestProjectionReload() {
        scheduler.requestNewestProjectionReload()
    }

    func clearNewestProjectionReload() {
        scheduler.clearNewestProjectionReload()
    }

    func beginMaterialization(
        allowsRealtimeFollow: Bool
    ) -> HomeTimelineMaterializationPass? {
        scheduler.beginMaterialization(allowsRealtimeFollow: allowsRealtimeFollow)
    }

    func schedule(
        delayNanoseconds: UInt64? = nil,
        allowsRealtimeFollow: Bool? = nil,
        materialize: @escaping MaterializeHandler
    ) {
        scheduler.schedule(
            delayNanoseconds: delayNanoseconds,
            allowsRealtimeFollow: allowsRealtimeFollow,
            materialize: materialize
        )
    }

    func apply(
        _ materialized: HomeTimelineMaterializedSnapshot,
        pass: HomeTimelineMaterializationPass
    ) -> HomeTimelinePresentationTransition {
        var changes: HomeTimelinePresentationChanges = []
        var didChangePublishedContent = false
        if scheduler.shouldPublish(renderFingerprint: materialized.renderFingerprint) {
            entries = materialized.entries
            changes.insert(.entries)
            didChangePublishedContent = true
        }

        let previousUnreadCounts = unreadCounts
        unreadState.replaceMaterializedPostIDs(entries.compactMap(\.post?.id))
        changes.formUnion(unreadChanges(from: previousUnreadCounts))

        if materialized.filterStatus != filterStatus {
            filterStatus = materialized.filterStatus
            changes.insert(.filterStatus)
            didChangePublishedContent = true
        }
        if didChangePublishedContent {
            resolvedContentRevision &+= 1
            changes.insert(.resolvedContentRevision)
            scheduler.didPublish(
                revision: resolvedContentRevision,
                allowsRealtimeFollow: pass.allowsRealtimeFollow
            )
            let nextFollowRevision = scheduler.realtimeFollowSourceRevision
            if realtimeFollowSourceRevision != nextFollowRevision {
                realtimeFollowSourceRevision = nextFollowRevision
                changes.insert(.realtimeFollowSourceRevision)
            }
        }
        return transition(changes: changes)
    }

    func dismissUnreadBadge() -> HomeTimelinePresentationTransition {
        let previousUnreadCounts = unreadCounts
        unreadState.dismissBadge()
        return transition(changes: unreadChanges(from: previousUnreadCounts))
    }

    func markVisiblePostsRead(
        _ visiblePostIDs: [TimelinePost.ID]
    ) -> HomeTimelinePresentationTransition? {
        let previousState = unreadState
        let previousUnreadCounts = unreadCounts
        unreadState.markVisiblePostsRead(visiblePostIDs)
        guard unreadState != previousState else { return nil }
        return transition(
            changes: unreadChanges(from: previousUnreadCounts),
            didChangeReadState: true
        )
    }

    func markNewestWindowRead() -> HomeTimelinePresentationTransition? {
        guard unreadState.canMarkNewestWindowRead else { return nil }
        let previousUnreadCounts = unreadCounts
        unreadState.markNewestWindowRead()
        return transition(
            changes: unreadChanges(from: previousUnreadCounts),
            didChangeReadState: true
        )
    }

    func restoreReadBoundary(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        let previousUnreadCounts = unreadCounts
        unreadState.setReadBoundary(postID: postID)
        return transition(changes: unreadChanges(from: previousUnreadCounts))
    }

    private var unreadCounts: (materialized: Int, visible: Int) {
        (
            materialized: unreadState.materializedUnreadCount,
            visible: unreadState.visibleUnreadBadgeCount
        )
    }

    private func unreadChanges(
        from previous: (materialized: Int, visible: Int)
    ) -> HomeTimelinePresentationChanges {
        guard previous.materialized != unreadState.materializedUnreadCount ||
                previous.visible != unreadState.visibleUnreadBadgeCount
        else { return [] }
        return .unreadCounts
    }

    private func transition(
        changes: HomeTimelinePresentationChanges,
        didChangeReadState: Bool = false
    ) -> HomeTimelinePresentationTransition {
        HomeTimelinePresentationTransition(
            snapshot: snapshot,
            changes: changes,
            didChangeReadState: didChangeReadState
        )
    }
}

#if DEBUG
extension HomeTimelinePresentationCoordinator {
    func replaceEntriesForTesting(
        _ entries: [TimelineFeedEntry],
        renderFingerprint: [Int]
    ) -> HomeTimelinePresentationTransition {
        let previousUnreadCounts = unreadCounts
        self.entries = entries
        scheduler.replaceRenderFingerprint(renderFingerprint)
        unreadState.replaceMaterializedPostIDs(
            entries.compactMap(\.post?.id),
            marksInitialWindowRead: false
        )
        return transition(
            changes: [.entries, unreadChanges(from: previousUnreadCounts)]
        )
    }

    func setReadBoundaryForTesting(
        postID: TimelinePost.ID
    ) -> HomeTimelinePresentationTransition {
        restoreReadBoundary(postID: postID)
    }
}
#endif
