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
    ) {
        guard
            let indexPath = indexPathForEntryID(TimelineEntryID(rawValue: anchor.anchorItemKey)),
            let attributes = collectionView.layoutAttributesForItem(at: indexPath)
        else {
            return
        }

        let restoredY = attributes.frame.minY
            - CGFloat(anchor.cellTopDeltaFromViewportTop)
            - collectionView.adjustedContentInset.top
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: restoredY),
            animated: false
        )
    }

    static func anchorDelta(before: TimelineVisualAnchor?, after: TimelineVisualAnchor?) -> Double? {
        guard
            let before,
            let after,
            before.anchorItemKey == after.anchorItemKey
        else {
            return nil
        }

        return after.cellTopDeltaFromViewportTop - before.cellTopDeltaFromViewportTop
    }

    static func currentTimeMilliseconds(date: Date = Date()) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
