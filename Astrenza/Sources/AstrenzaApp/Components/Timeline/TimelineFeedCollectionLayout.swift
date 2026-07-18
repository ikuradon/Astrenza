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

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes:
            UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes:
            UICollectionViewLayoutAttributes
    ) -> Bool {
        abs(
            preferredAttributes.size.height -
                originalAttributes.size.height
        ) > 0.5
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes:
            UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes:
            UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes
        )
        let indexPath = originalAttributes.indexPath
        guard indexPath.section == 0,
              let delta = layoutIndex.updateHeight(
                preferredAttributes.size.height,
                at: indexPath.item
              )
        else { return context }

        context.invalidateItems(at: [indexPath])
        if let collectionView,
           originalAttributes.frame.maxY <=
            collectionView.contentOffset.y + anchorLineY {
            context.contentOffsetAdjustment.y += delta
        }
        if let entryID = layoutIndex.id(at: indexPath.item),
           let height = layoutIndex.height(at: indexPath.item) {
            onMeasuredHeight?(entryID, height)
        }
        return context
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
