import UIKit

@MainActor
final class TimelineFeedCollectionLayout: UICollectionViewLayout {
    private var layoutIndex = TimelineFeedLayoutIndex()
    private var layoutWidth: CGFloat = 0
    private let anchorLineY: CGFloat

    init(anchorLineY: CGFloat) {
        self.anchorLineY = anchorLineY
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        items: [TimelineFeedLayoutItem],
        topPadding: CGFloat
    ) {
        layoutIndex = TimelineFeedLayoutIndex(
            items: items,
            topPadding: topPadding
        )
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        layoutWidth = collectionView?.bounds.width ?? 0
    }

    override var collectionViewContentSize: CGSize {
        CGSize(
            width: layoutWidth,
            height: layoutIndex.contentHeight
        )
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        layoutIndex.itemIndexes(intersecting: rect).compactMap {
            layoutAttributes(at: $0)
        }
    }

    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0 else { return nil }
        return layoutAttributes(at: indexPath.item)
    }

    override func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        abs(newBounds.width - layoutWidth) > 0.5
    }

    @discardableResult
    func updateMeasuredHeight(
        _ height: CGFloat,
        for entryID: TimelineFeedEntry.ID
    ) -> Bool {
        updateMeasuredHeights([entryID: height]).contains(entryID)
    }

    @discardableResult
    func updateMeasuredHeights(
        _ heightsByEntryID: [TimelineFeedEntry.ID: CGFloat]
    ) -> Set<TimelineFeedEntry.ID> {
        let candidates = heightsByEntryID.compactMap {
            entryID,
            height -> (
                entryID: TimelineFeedEntry.ID,
                itemIndex: Int,
                height: CGFloat,
                originalFrame: CGRect
            )? in
            guard let itemIndex = layoutIndex.index(for: entryID),
                  let originalFrame = layoutIndex.frame(
                    at: itemIndex,
                    width: layoutWidth
                  )
            else { return nil }
            return (entryID, itemIndex, height, originalFrame)
        }
        .sorted { $0.itemIndex < $1.itemIndex }

        var changes: [(
            entryID: TimelineFeedEntry.ID,
            itemIndex: Int,
            delta: CGFloat,
            originalFrame: CGRect
        )] = []
        changes.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard let delta = layoutIndex.updateHeight(
                candidate.height,
                at: candidate.itemIndex
            ) else { continue }
            changes.append(
                (
                    candidate.entryID,
                    candidate.itemIndex,
                    delta,
                    candidate.originalFrame
                )
            )
        }
        guard let firstChangedIndex = changes.first?.itemIndex else {
            return []
        }

        let context = UICollectionViewLayoutInvalidationContext()
        let visibleDownstreamIndexPaths = collectionView?
            .indexPathsForVisibleItems
            .filter {
                $0.section == 0 && $0.item >= firstChangedIndex
            } ?? []
        let changedIndexPaths = changes.map {
            IndexPath(item: $0.itemIndex, section: 0)
        }
        context.invalidateItems(at: Array(Set(
            changedIndexPaths + visibleDownstreamIndexPaths
        )))
        if let collectionView {
            let anchorLineInContent =
                collectionView.contentOffset.y + anchorLineY
            context.contentOffsetAdjustment.y = changes.reduce(0) {
                adjustment,
                change in
                change.originalFrame.maxY <= anchorLineInContent
                    ? adjustment + change.delta
                    : adjustment
            }
        }
        invalidateLayout(with: context)
        return Set(changes.map(\.entryID))
    }

    func frame(for entryID: TimelineFeedEntry.ID) -> CGRect? {
        layoutIndex.frame(for: entryID, width: layoutWidth)
    }

    func entryIDs(intersecting rect: CGRect) -> [TimelineFeedEntry.ID] {
        layoutIndex.itemIndexes(intersecting: rect).compactMap {
            layoutIndex.id(at: $0)
        }
    }

    private func layoutAttributes(
        at itemIndex: Int
    ) -> UICollectionViewLayoutAttributes? {
        guard let frame = layoutIndex.frame(
            at: itemIndex,
            width: layoutWidth
        ) else { return nil }
        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: itemIndex, section: 0)
        )
        attributes.frame = frame
        return attributes
    }
}
