import Foundation

struct HomeTimelineUnreadState: Equatable {
    private(set) var materializedPostIDs: [TimelinePost.ID] = []
    private(set) var readPostIDs = Set<TimelinePost.ID>()
    private(set) var materializedUnreadCount = 0
    private(set) var visibleUnreadBadgeCount = 0

    private var dismissedGeneration: String?

    var canMarkNewestWindowRead: Bool {
        !materializedPostIDs.isEmpty &&
            (materializedUnreadCount > 0 || visibleUnreadBadgeCount > 0)
    }

    var readBoundaryPostID: TimelinePost.ID? {
        guard !materializedPostIDs.isEmpty else { return nil }
        guard let oldestUnreadIndex = materializedPostIDs.lastIndex(where: { !readPostIDs.contains($0) }) else {
            return materializedPostIDs.first
        }
        let boundaryIndex = materializedPostIDs.index(after: oldestUnreadIndex)
        guard boundaryIndex < materializedPostIDs.endIndex else { return nil }
        return materializedPostIDs[boundaryIndex]
    }

    mutating func replaceMaterializedPostIDs(
        _ ids: [TimelinePost.ID],
        marksInitialWindowRead: Bool = true
    ) {
        if marksInitialWindowRead && materializedPostIDs.isEmpty {
            readPostIDs.formUnion(ids)
        }
        materializedPostIDs = ids
        readPostIDs = readPostIDs.intersection(Set(ids))
        recompute()
    }

    mutating func dismissBadge() {
        dismissedGeneration = currentUnreadGeneration()
        recompute()
    }

    mutating func markVisiblePostsRead(_ visiblePostIDs: [TimelinePost.ID]) {
        let knownPostIDs = Set(materializedPostIDs)
        let readableIDs = visiblePostIDs.filter { knownPostIDs.contains($0) }
        guard !readableIDs.isEmpty else { return }
        readPostIDs.formUnion(readableIDs)
        recompute()
    }

    mutating func markNewestWindowRead() {
        guard canMarkNewestWindowRead else { return }
        readPostIDs.formUnion(materializedPostIDs)
        recompute()
    }

    mutating func setReadBoundary(postID: TimelinePost.ID) {
        guard let boundaryIndex = materializedPostIDs.firstIndex(of: postID) else { return }
        readPostIDs = Set(materializedPostIDs[boundaryIndex...])
        recompute()
    }

    mutating func reset() {
        materializedPostIDs = []
        readPostIDs.removeAll()
        dismissedGeneration = nil
        materializedUnreadCount = 0
        visibleUnreadBadgeCount = 0
    }

    private mutating func recompute() {
        let unreadIDs = materializedPostIDs.filter { !readPostIDs.contains($0) }
        materializedUnreadCount = unreadIDs.count

        let generation = unreadGeneration(from: unreadIDs)
        if generation == nil {
            dismissedGeneration = nil
            visibleUnreadBadgeCount = 0
        } else if dismissedGeneration == generation {
            visibleUnreadBadgeCount = 0
        } else {
            visibleUnreadBadgeCount = unreadIDs.count
        }
    }

    private func currentUnreadGeneration() -> String? {
        unreadGeneration(from: materializedPostIDs.filter { !readPostIDs.contains($0) })
    }

    private func unreadGeneration(from unreadIDs: [TimelinePost.ID]) -> String? {
        unreadIDs.isEmpty ? nil : unreadIDs.joined(separator: "|")
    }
}
