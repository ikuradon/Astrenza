import Foundation
import UIKit

struct TimelineVisibleItemFrame: Equatable, Sendable {
    var entryID: TimelineEntryID
    var minY: Double
    var maxY: Double

    init(entryID: TimelineEntryID, minY: Double, maxY: Double) {
        self.entryID = entryID
        self.minY = minY
        self.maxY = maxY
    }
}

struct TimelineAnchorSelection: Equatable, Sendable {
    var anchorItemKey: String
    var anchorEntryID: TimelineEntryID
    var cellTopDeltaFromViewportTop: Double
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?
}

final class TimelinePositionRecorder {
    private let accountID: AccountID
    private let feedID: FeedID
    private let timelineKey: TimelineKey

    init(accountID: AccountID, feedID: FeedID, timelineKey: TimelineKey) {
        self.accountID = accountID
        self.feedID = feedID
        self.timelineKey = timelineKey
    }

    static func anchorSelection(
        visibleFrames: [TimelineVisibleItemFrame],
        viewportTop: Double
    ) -> TimelineAnchorSelection? {
        chooseAnchorCandidate(visibleFrames: visibleFrames, viewportTop: viewportTop)
    }

    static func chooseAnchorCandidate(
        visibleFrames: [TimelineVisibleItemFrame],
        viewportTop: Double
    ) -> TimelineAnchorSelection? {
        let sortedFrames = visibleFrames.sorted { lhs, rhs in
            if lhs.minY == rhs.minY {
                lhs.entryID.rawValue < rhs.entryID.rawValue
            } else {
                lhs.minY < rhs.minY
            }
        }
        let candidates = sortedFrames.filter { $0.maxY >= viewportTop }
        guard let anchorFrame = candidates.first ?? sortedFrames.first else {
            return nil
        }

        return TimelineAnchorSelection(
            anchorItemKey: anchorFrame.entryID.rawValue,
            anchorEntryID: anchorFrame.entryID,
            cellTopDeltaFromViewportTop: anchorFrame.minY - viewportTop,
            lastVisibleTopItemKey: candidates.first?.entryID.rawValue ?? sortedFrames.first?.entryID.rawValue,
            lastVisibleBottomItemKey: candidates.last?.entryID.rawValue ?? sortedFrames.last?.entryID.rawValue
        )
    }

    static func computeContentOffsetTarget(
        anchorFrameMinY: Double,
        savedCellTopDeltaFromViewportTop: Double,
        adjustedContentInsetTop: Double,
        boundsHeight: Double,
        contentHeight: Double,
        adjustedContentInsetBottom: Double
    ) -> Double {
        let target = anchorFrameMinY - savedCellTopDeltaFromViewportTop - adjustedContentInsetTop
        return clampContentOffsetTarget(
            target,
            adjustedContentInsetTop: adjustedContentInsetTop,
            boundsHeight: boundsHeight,
            contentHeight: contentHeight,
            adjustedContentInsetBottom: adjustedContentInsetBottom
        )
    }

    static func clampContentOffsetTarget(
        _ target: Double,
        adjustedContentInsetTop: Double,
        boundsHeight: Double,
        contentHeight: Double,
        adjustedContentInsetBottom: Double
    ) -> Double {
        let minimumOffsetY = -adjustedContentInsetTop
        let maximumOffsetY = max(
            minimumOffsetY,
            contentHeight + adjustedContentInsetBottom - boundsHeight
        )

        return min(max(target, minimumOffsetY), maximumOffsetY)
    }

    @MainActor
    func capture(
        in collectionView: UICollectionView,
        entryIDAt: (IndexPath) -> TimelineEntryID?
    ) -> TimelineVisualAnchor? {
        let viewportTop = Double(collectionView.contentOffset.y + collectionView.adjustedContentInset.top)
        let frames = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> TimelineVisibleItemFrame? in
            guard
                let entryID = entryIDAt(indexPath),
                let attributes = collectionView.layoutAttributesForItem(at: indexPath)
            else {
                return nil
            }

            return TimelineVisibleItemFrame(
                entryID: entryID,
                minY: Double(attributes.frame.minY),
                maxY: Double(attributes.frame.maxY)
            )
        }

        guard let selection = Self.anchorSelection(visibleFrames: frames, viewportTop: viewportTop) else {
            return nil
        }

        let anchorID = selection.anchorEntryID
        return TimelineVisualAnchor(
            accountID: accountID,
            feedID: feedID,
            timelineKey: timelineKey,
            anchorItemKey: selection.anchorItemKey,
            anchorEventID: anchorID.sourceEventID,
            anchorSortAt: anchorID.sortAt ?? 0,
            anchorTieBreakID: anchorID.tieBreakID ?? anchorID.rawValue,
            cellTopDeltaFromViewportTop: selection.cellTopDeltaFromViewportTop,
            viewportHeight: Double(collectionView.bounds.height),
            viewportWidth: Double(collectionView.bounds.width),
            contentInsetTop: Double(collectionView.adjustedContentInset.top),
            contentInsetBottom: Double(collectionView.adjustedContentInset.bottom),
            lastVisibleTopItemKey: selection.lastVisibleTopItemKey,
            lastVisibleBottomItemKey: selection.lastVisibleBottomItemKey,
            markerEventID: nil,
            markerSortAt: nil,
            capturedAtMS: Self.currentTimeMilliseconds(),
            schemaVersion: 1
        )
    }

    @MainActor
    func restore(
        anchor: TimelineVisualAnchor,
        in collectionView: UICollectionView,
        indexPathForEntryID: (TimelineEntryID) -> IndexPath?
    ) -> TimelineRestoreResult {
        guard !anchor.anchorItemKey.isEmpty else {
            return .skipped(reason: TimelineRestoreFallbackReason(
                kind: .invalidAnchorItemKey,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        let entryID = TimelineEntryID(rawValue: anchor.anchorItemKey)
        guard let indexPath = indexPathForEntryID(entryID) else {
            return .skipped(reason: TimelineRestoreFallbackReason(
                kind: .anchorItemMissing,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        var attemptedLayoutAttributesFallback = false
        var attributes = collectionView.layoutAttributesForItem(at: indexPath)
        if attributes == nil {
            attemptedLayoutAttributesFallback = true
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            collectionView.layoutIfNeeded()
            attributes = collectionView.layoutAttributesForItem(at: indexPath)
        }

        guard let attributes else {
            return .failed(reason: TimelineRestoreFallbackReason(
                kind: .layoutAttributesMissing,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        let boundsHeight = Double(collectionView.bounds.height)
        let contentHeight = Double(collectionView.contentSize.height)
        guard boundsHeight.isFinite, boundsHeight > 0, contentHeight.isFinite else {
            return .failed(reason: TimelineRestoreFallbackReason(
                kind: .contentSizeUnavailable,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        let adjustedContentInsetTop = Double(collectionView.adjustedContentInset.top)
        let adjustedContentInsetBottom = Double(collectionView.adjustedContentInset.bottom)
        let targetY = Double(attributes.frame.minY)
            - anchor.cellTopDeltaFromViewportTop
            - adjustedContentInsetTop
        let restoredY = Self.clampContentOffsetTarget(
            targetY,
            adjustedContentInsetTop: adjustedContentInsetTop,
            boundsHeight: boundsHeight,
            contentHeight: contentHeight,
            adjustedContentInsetBottom: adjustedContentInsetBottom
        )
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: CGFloat(restoredY)),
            animated: false
        )

        guard restoredY == targetY else {
            return .attemptedFallback(reason: TimelineRestoreFallbackReason(
                kind: .targetOffsetClamped,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        guard !attemptedLayoutAttributesFallback else {
            return .attemptedFallback(reason: TimelineRestoreFallbackReason(
                kind: .layoutAttributesMissing,
                anchorItemKey: anchor.anchorItemKey
            ))
        }

        return .restored
    }

    static func anchorDelta(before: TimelineVisualAnchor?, after: TimelineVisualAnchor?) -> Double? {
        computeAnchorDelta(before: before, after: after)?.deltaPoints
    }

    static func computeAnchorDelta(
        before: TimelineVisualAnchor?,
        after: TimelineVisualAnchor?
    ) -> TimelineAnchorDelta? {
        guard
            let before,
            let after,
            before.anchorItemKey == after.anchorItemKey
        else {
            return nil
        }

        return TimelineAnchorDelta(
            anchorItemKey: before.anchorItemKey,
            beforeCellTopDeltaFromViewportTop: before.cellTopDeltaFromViewportTop,
            afterCellTopDeltaFromViewportTop: after.cellTopDeltaFromViewportTop,
            deltaPoints: after.cellTopDeltaFromViewportTop - before.cellTopDeltaFromViewportTop
        )
    }

    static func currentTimeMilliseconds(date: Date = Date()) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
