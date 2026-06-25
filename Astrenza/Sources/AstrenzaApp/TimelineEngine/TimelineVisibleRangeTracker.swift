import Foundation
import UIKit

struct TimelineVisibleRangeUpdate: Equatable, Sendable {
    var previousIDs: [TimelineEntryID]
    var currentIDs: [TimelineEntryID]
    var addedIDs: [TimelineEntryID]
    var removedIDs: [TimelineEntryID]

    var advancesReadMarker: Bool {
        false
    }
}

final class TimelineVisibleRangeTracker {
    private(set) var visibleIDs: [TimelineEntryID] = []

    func recordVisibleIDs(_ ids: [TimelineEntryID]) -> TimelineVisibleRangeUpdate {
        let uniqueIDs = Self.uniquePreservingOrder(ids)
        let previousIDs = visibleIDs
        visibleIDs = uniqueIDs

        return TimelineVisibleRangeUpdate(
            previousIDs: previousIDs,
            currentIDs: uniqueIDs,
            addedIDs: uniqueIDs.filter { !previousIDs.contains($0) },
            removedIDs: previousIDs.filter { !uniqueIDs.contains($0) }
        )
    }

    @MainActor
    func recordVisibleIndexPaths(
        in collectionView: UICollectionView,
        entryIDAt: (IndexPath) -> TimelineEntryID?
    ) -> TimelineVisibleRangeUpdate {
        let ids = collectionView.indexPathsForVisibleItems
            .sorted { lhs, rhs in
                if lhs.section == rhs.section {
                    lhs.item < rhs.item
                } else {
                    lhs.section < rhs.section
                }
            }
            .compactMap { indexPath in
                entryIDAt(indexPath)
            }
        return recordVisibleIDs(ids)
    }

    private static func uniquePreservingOrder(_ ids: [TimelineEntryID]) -> [TimelineEntryID] {
        var seen = Set<TimelineEntryID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
