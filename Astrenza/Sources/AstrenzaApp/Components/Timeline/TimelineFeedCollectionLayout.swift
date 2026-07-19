import UIKit

@MainActor
final class TimelineFeedCollectionLayout: UICollectionViewLayout {
    var onMeasuredHeight:
        ((TimelineFeedEntry.ID, CGFloat) -> Void)?

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
        guard let itemIndex = layoutIndex.index(for: entryID),
              let originalFrame = layoutIndex.frame(
                at: itemIndex,
                width: layoutWidth
              ),
              let delta = layoutIndex.updateHeight(
                height,
                at: itemIndex
              )
        else { return false }

        let indexPath = IndexPath(item: itemIndex, section: 0)
        let context = UICollectionViewLayoutInvalidationContext()
        let visibleDownstreamIndexPaths = collectionView?
            .indexPathsForVisibleItems
            .filter {
                $0.section == indexPath.section &&
                    $0.item > indexPath.item
            } ?? []
        context.invalidateItems(
            at: [indexPath] + visibleDownstreamIndexPaths
        )
        if let collectionView,
           originalFrame.maxY <=
            collectionView.contentOffset.y + anchorLineY {
            context.contentOffsetAdjustment.y = delta
        }
        invalidateLayout(with: context)
        onMeasuredHeight?(entryID, height)
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
