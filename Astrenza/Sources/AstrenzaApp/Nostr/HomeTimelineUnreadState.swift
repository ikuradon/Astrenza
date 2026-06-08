import Foundation

struct HomeTimelineUnreadState: Equatable {
    private(set) var materializedPostIDs: [TimelinePost.ID] = []
    private(set) var readPostIDs = Set<TimelinePost.ID>()
    private(set) var materializedUnreadCount = 0
    private(set) var visibleUnreadBadgeCount = 0

    private var dismissedGeneration: String?
    private var viewportHiddenGeneration: String?

    var canMarkNewestWindowRead: Bool {
        !materializedPostIDs.isEmpty &&
            (materializedUnreadCount > 0 || visibleUnreadBadgeCount > 0)
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
        updateViewportVisibility(readablePostIDs: readableIDs)
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
        viewportHiddenGeneration = nil
        materializedUnreadCount = 0
        visibleUnreadBadgeCount = 0
    }

    private mutating func recompute() {
        let unreadIDs = materializedPostIDs.filter { !readPostIDs.contains($0) }
        materializedUnreadCount = unreadIDs.count

        let generation = unreadGeneration(from: unreadIDs)
        if generation == nil {
            dismissedGeneration = nil
            viewportHiddenGeneration = nil
            visibleUnreadBadgeCount = 0
        } else if dismissedGeneration == generation {
            visibleUnreadBadgeCount = 0
        } else if viewportHiddenGeneration == generation {
            visibleUnreadBadgeCount = 0
        } else {
            visibleUnreadBadgeCount = unreadIDs.count
        }
    }

    private mutating func updateViewportVisibility(readablePostIDs: [TimelinePost.ID]) {
        let unreadIDs = materializedPostIDs.filter { !readPostIDs.contains($0) }
        guard let generation = unreadGeneration(from: unreadIDs),
              let lastUnreadIndex = materializedPostIDs.lastIndex(where: { unreadIDs.contains($0) })
        else {
            viewportHiddenGeneration = nil
            return
        }

        let readableIndexes = readablePostIDs.compactMap { materializedPostIDs.firstIndex(of: $0) }
        guard let newestReadableIndex = readableIndexes.min() else { return }
        let isPastUnreadRange = newestReadableIndex > lastUnreadIndex
        if isPastUnreadRange {
            viewportHiddenGeneration = generation
        } else if viewportHiddenGeneration == generation {
            viewportHiddenGeneration = nil
        }
    }

    private func currentUnreadGeneration() -> String? {
        unreadGeneration(from: materializedPostIDs.filter { !readPostIDs.contains($0) })
    }

    private func unreadGeneration(from unreadIDs: [TimelinePost.ID]) -> String? {
        unreadIDs.isEmpty ? nil : unreadIDs.joined(separator: "|")
    }
}
