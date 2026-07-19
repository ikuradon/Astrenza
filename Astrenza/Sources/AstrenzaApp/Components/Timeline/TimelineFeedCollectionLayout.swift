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
    func updateProjectedHeights(
        _ heightsByEntryID: [TimelineFeedEntry.ID: CGFloat]
    ) -> Bool {
        guard !heightsByEntryID.isEmpty else { return false }
        let absoluteAnchorY = (collectionView?.contentOffset.y ?? 0) +
            anchorLineY
        let updates = heightsByEntryID.compactMap {
            entryID, height -> (
                index: Int,
                height: CGFloat,
                preservesAnchor: Bool
            )? in
            guard let itemIndex = layoutIndex.index(for: entryID),
                  let originalFrame = layoutIndex.frame(
                    at: itemIndex,
                    width: layoutWidth
                  )
            else { return nil }
            return (
                itemIndex,
                height,
                originalFrame.maxY <= absoluteAnchorY
            )
        }
        .sorted { $0.index < $1.index }
        guard !updates.isEmpty else { return false }

        var changedIndexPaths: [IndexPath] = []
        var contentOffsetAdjustment: CGFloat = 0
        for update in updates {
            guard let delta = layoutIndex.updateHeight(
                update.height,
                at: update.index
            ) else { continue }
            changedIndexPaths.append(
                IndexPath(item: update.index, section: 0)
            )
            if update.preservesAnchor {
                contentOffsetAdjustment += delta
            }
        }
        guard !changedIndexPaths.isEmpty else { return false }

        let context = UICollectionViewLayoutInvalidationContext()
        let visibleIndexPaths = collectionView?.indexPathsForVisibleItems ?? []
        context.invalidateItems(
            at: Array(Set(changedIndexPaths + visibleIndexPaths))
        )
        if contentOffsetAdjustment != 0 {
            context.contentOffsetAdjustment.y = contentOffsetAdjustment
        }
        invalidateLayout(with: context)
        return true
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
