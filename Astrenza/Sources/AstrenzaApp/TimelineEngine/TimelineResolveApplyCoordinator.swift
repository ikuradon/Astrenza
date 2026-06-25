import Foundation
import UIKit

struct TimelineResolveReconfigureIntent: Equatable, Sendable {
    var reason: ResolveApplyReason
    var mutationStyle: TimelineMutationStyle
    var entryIDs: [TimelineEntryID]
    var missingIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]

    var skippedIDs: [TimelineEntryID] {
        missingIDs
    }
}

final class TimelineResolveApplyCoordinator {
    func reconfigureIntent(
        resolvedIDs: [TimelineEntryID],
        existingIDs: [TimelineEntryID],
        reason: ResolveApplyReason
    ) -> TimelineResolveReconfigureIntent {
        let existingSet = Set(existingIDs)
        let uniqueResolvedIDs = Self.uniquePreservingOrder(resolvedIDs)

        return TimelineResolveReconfigureIntent(
            reason: reason,
            mutationStyle: .reconfigure,
            entryIDs: uniqueResolvedIDs.filter { existingSet.contains($0) },
            missingIDs: uniqueResolvedIDs.filter { !existingSet.contains($0) },
            insertedIDs: [],
            deletedIDs: []
        )
    }

    @MainActor
    func applyResolvedUpdates(
        intent: TimelineResolveReconfigureIntent,
        snapshotCoordinator: TimelineSnapshotCoordinator,
        in collectionView: UICollectionView,
        animatingDifferences: Bool = true
    ) {
        snapshotCoordinator.applyReconfigure(
            entryIDs: intent.entryIDs,
            reason: intent.reason,
            in: collectionView,
            animatingDifferences: animatingDifferences
        )
    }

    private static func uniquePreservingOrder(_ ids: [TimelineEntryID]) -> [TimelineEntryID] {
        var seen = Set<TimelineEntryID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
