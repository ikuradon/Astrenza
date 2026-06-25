import UIKit

@MainActor
final class TimelineSnapshotCoordinator {
    typealias DataSource = UICollectionViewDiffableDataSource<TimelineSection, TimelineEntryID>

    private let dataSource: DataSource
    private let positionRecorder: TimelinePositionRecorder
    private let visibleRangeTracker: TimelineVisibleRangeTracker
    private let diagnosticsRecorder: TimelineDiagnosticsRecorder

    init(
        dataSource: DataSource,
        positionRecorder: TimelinePositionRecorder,
        visibleRangeTracker: TimelineVisibleRangeTracker,
        diagnosticsRecorder: TimelineDiagnosticsRecorder
    ) {
        self.dataSource = dataSource
        self.positionRecorder = positionRecorder
        self.visibleRangeTracker = visibleRangeTracker
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    var currentItemIDs: [TimelineEntryID] {
        dataSource.snapshot().itemIdentifiers
    }

    nonisolated static func makeMutationPlan(
        currentIDs: [TimelineEntryID],
        proposedIDs: [TimelineEntryID],
        reconfigureIDs: [TimelineEntryID] = [],
        reason: TimelineSnapshotReason
    ) -> TimelineSnapshotMutationPlan {
        let itemIDs = uniquePreservingOrder(proposedIDs)
        let currentSet = Set(currentIDs)
        let proposedSet = Set(itemIDs)
        let filteredReconfigureIDs = uniquePreservingOrder(reconfigureIDs)
            .filter { currentSet.contains($0) && proposedSet.contains($0) }

        return TimelineSnapshotMutationPlan(
            reason: reason,
            mutationStyle: filteredReconfigureIDs.isEmpty ? .snapshot : .reconfigure,
            itemIDs: itemIDs,
            reconfigureIDs: filteredReconfigureIDs,
            insertedIDs: itemIDs.filter { !currentSet.contains($0) },
            deletedIDs: currentIDs.filter { !proposedSet.contains($0) }
        )
    }

    func applyPreservingPosition(
        itemIDs: [TimelineEntryID],
        reason: TimelineSnapshotReason,
        in collectionView: UICollectionView,
        reconfigureIDs: [TimelineEntryID] = [],
        animatingDifferences: Bool = true
    ) {
        let beforeVisibleIDs = visibleIDs(in: collectionView)
        let beforeAnchor = positionRecorder.capture(in: collectionView) { [dataSource] indexPath in
            dataSource.itemIdentifier(for: indexPath)
        }
        let plan = Self.makeMutationPlan(
            currentIDs: currentItemIDs,
            proposedIDs: itemIDs,
            reconfigureIDs: reconfigureIDs,
            reason: reason
        )

        if reason == .initialRestore {
            diagnosticsRecorder.recordRestoreGate(.localSnapshotApplying)
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineEntryID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(plan.itemIDs, toSection: .main)
        if !plan.reconfigureIDs.isEmpty {
            snapshot.reconfigureItems(plan.reconfigureIDs)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        collectionView.layoutIfNeeded()

        if let beforeAnchor {
            diagnosticsRecorder.recordRestoreGate(.anchorRestoring)
            positionRecorder.restore(anchor: beforeAnchor, in: collectionView) { [dataSource] entryID in
                dataSource.indexPath(for: entryID)
            }
        }

        collectionView.layoutIfNeeded()
        let afterAnchor = positionRecorder.capture(in: collectionView) { [dataSource] indexPath in
            dataSource.itemIdentifier(for: indexPath)
        }
        let afterVisibleIDs = visibleIDs(in: collectionView)
        _ = visibleRangeTracker.recordVisibleIDs(afterVisibleIDs)

        diagnosticsRecorder.recordMutation(
            reason: reason,
            anchorBefore: beforeAnchor,
            anchorAfter: afterAnchor,
            visibleIDsBefore: beforeVisibleIDs,
            visibleIDsAfter: afterVisibleIDs,
            restoreGate: reason == .initialRestore ? .firstInteractiveScrollReady : nil
        )
    }

    func applyReconfigure(
        entryIDs: [TimelineEntryID],
        reason: ResolveApplyReason,
        in collectionView: UICollectionView,
        animatingDifferences: Bool = true
    ) {
        applyPreservingPosition(
            itemIDs: currentItemIDs,
            reason: reason.snapshotReason,
            in: collectionView,
            reconfigureIDs: entryIDs,
            animatingDifferences: animatingDifferences
        )
    }

    private func visibleIDs(in collectionView: UICollectionView) -> [TimelineEntryID] {
        collectionView.indexPathsForVisibleItems
            .sorted { lhs, rhs in
                if lhs.section == rhs.section {
                    lhs.item < rhs.item
                } else {
                    lhs.section < rhs.section
                }
            }
            .compactMap { dataSource.itemIdentifier(for: $0) }
    }

    private nonisolated static func uniquePreservingOrder(_ ids: [TimelineEntryID]) -> [TimelineEntryID] {
        var seen = Set<TimelineEntryID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
