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

    nonisolated static func isReconfigureOnlyMutation(_ plan: TimelineSnapshotMutationPlan) -> Bool {
        plan.mutationStyle == .reconfigure
            && !plan.reconfigureIDs.isEmpty
            && plan.insertedIDs.isEmpty
            && plan.deletedIDs.isEmpty
            && plan.itemIDs.count > 0
    }

    nonisolated static func pendingNewInsertionDecision(
        pendingNewIDs: [TimelineEntryID],
        reason: TimelineSnapshotReason
    ) -> TimelinePendingNewInsertionDecision {
        guard !pendingNewIDs.isEmpty else {
            return .allowed
        }

        return reason == .userInsertedPendingNew ? .allowed : .blocked
    }

    nonisolated static func makeMutationRecord(
        reason: TimelineSnapshotReason,
        anchorBefore: TimelineVisualAnchor?,
        anchorAfter: TimelineVisualAnchor?,
        visibleIDsBefore: [TimelineEntryID],
        visibleIDsAfter: [TimelineEntryID],
        timestampMS: Int64,
        fallbackReason: TimelineRestoreFallbackReason? = nil,
        readMarkerChanged: Bool = false
    ) -> TimelineSnapshotMutationRecord {
        TimelineSnapshotMutationRecord(
            mutationReason: reason,
            anchorBefore: anchorBefore.map { TimelineAnchorSnapshot(anchor: $0) },
            anchorAfter: anchorAfter.map { TimelineAnchorSnapshot(anchor: $0) },
            anchorDelta: TimelinePositionRecorder.computeAnchorDelta(before: anchorBefore, after: anchorAfter),
            visibleIDsBefore: visibleIDsBefore,
            visibleIDsAfter: visibleIDsAfter,
            timestampMS: timestampMS,
            fallbackReason: fallbackReason,
            readMarkerChanged: readMarkerChanged
        )
    }

    @discardableResult
    func applyPreservingPosition(
        itemIDs: [TimelineEntryID],
        reason: TimelineSnapshotReason,
        in collectionView: UICollectionView,
        reconfigureIDs: [TimelineEntryID] = [],
        animatingDifferences: Bool = true
    ) -> TimelineSnapshotMutationRecord {
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

        var restoreResult = TimelineRestoreResult.skipped(reason: TimelineRestoreFallbackReason(
            kind: beforeVisibleIDs.isEmpty ? .noVisibleItems : .noSavedAnchor,
            anchorItemKey: nil
        ))
        if let beforeAnchor {
            diagnosticsRecorder.recordRestoreGate(.anchorRestoring)
            restoreResult = positionRecorder.restore(anchor: beforeAnchor, in: collectionView) { [dataSource] entryID in
                dataSource.indexPath(for: entryID)
            }
        }

        collectionView.layoutIfNeeded()
        let afterAnchor = positionRecorder.capture(in: collectionView) { [dataSource] indexPath in
            dataSource.itemIdentifier(for: indexPath)
        }
        let afterVisibleIDs = visibleIDs(in: collectionView)
        _ = visibleRangeTracker.recordVisibleIDs(afterVisibleIDs)
        if reason == .initialRestore {
            diagnosticsRecorder.recordRestoreGate(.firstInteractiveScrollReady)
        }

        return diagnosticsRecorder.recordMutation(
            reason: reason,
            anchorBefore: beforeAnchor,
            anchorAfter: afterAnchor,
            visibleIDsBefore: beforeVisibleIDs,
            visibleIDsAfter: afterVisibleIDs,
            fallbackReason: restoreResult.fallbackReason
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
