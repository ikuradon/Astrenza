import UIKit

struct TimelineFeedProjectedLayoutItem: Equatable {
    let id: TimelineFeedEntry.ID
    let height: CGFloat
}

final class TimelineFeedStableLayout: UICollectionViewLayout {
    private var activeIndex = TimelineFeedStableLayoutIndex()
    private var pendingIndex: TimelineFeedStableLayoutIndex?
    private var layoutWidth: CGFloat = 0

    func configure(
        items: [TimelineFeedProjectedLayoutItem],
        topPadding: CGFloat
    ) {
        pendingIndex = TimelineFeedStableLayoutIndex(
            items: items,
            topPadding: topPadding
        )
        activatePendingIndexIfCompatible()
        invalidateLayout()
    }

    override func prepare() {
        super.prepare()
        layoutWidth = collectionView?.bounds.width ?? 0
        activatePendingIndexIfCompatible()
    }

    override var collectionViewContentSize: CGSize {
        CGSize(
            width: layoutWidth,
            height: activeIndex.contentHeight
        )
    }

    override func layoutAttributesForElements(
        in rect: CGRect
    ) -> [UICollectionViewLayoutAttributes]? {
        activeIndex.itemIndexes(intersecting: rect).compactMap {
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

    private func activatePendingIndexIfCompatible() {
        guard let pendingIndex,
              let collectionView,
              collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) == pendingIndex.count
        else { return }
        activeIndex = pendingIndex
        self.pendingIndex = nil
    }

    private func layoutAttributes(
        at itemIndex: Int
    ) -> UICollectionViewLayoutAttributes? {
        guard let frame = activeIndex.frame(
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

private struct TimelineFeedStableLayoutIndex {
    private let itemIDs: [TimelineFeedEntry.ID]
    private let heights: TimelineFeedStableHeightIndex
    let topPadding: CGFloat

    init(
        items: [TimelineFeedProjectedLayoutItem] = [],
        topPadding: CGFloat = 0
    ) {
        itemIDs = items.map(\.id)
        heights = TimelineFeedStableHeightIndex(
            items.map { max(1, $0.height) }
        )
        self.topPadding = topPadding
    }

    var count: Int {
        itemIDs.count
    }

    var contentHeight: CGFloat {
        topPadding + heights.total
    }

    func frame(at index: Int, width: CGFloat) -> CGRect? {
        guard itemIDs.indices.contains(index) else { return nil }
        return CGRect(
            x: 0,
            y: topPadding + heights.prefixSum(before: index),
            width: max(0, width),
            height: heights.value(at: index)
        )
    }

    func itemIndexes(intersecting rect: CGRect) -> Range<Int> {
        guard !itemIDs.isEmpty, rect.maxY > topPadding else {
            return 0 ..< 0
        }

        var lowerBound = 0
        var upperBound = itemIDs.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let maxY = topPadding + heights.prefixSum(through: middle)
            if maxY <= rect.minY {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let first = lowerBound
        var end = first
        while end < itemIDs.count {
            let minY = topPadding + heights.prefixSum(before: end)
            guard minY < rect.maxY else { break }
            end += 1
        }
        return first ..< end
    }
}

private struct TimelineFeedStableHeightIndex {
    private let values: [CGFloat]
    private let prefixSums: [CGFloat]

    init(_ values: [CGFloat]) {
        self.values = values
        var nextPrefixSums: [CGFloat] = [0]
        nextPrefixSums.reserveCapacity(values.count + 1)
        for value in values {
            nextPrefixSums.append((nextPrefixSums.last ?? 0) + value)
        }
        prefixSums = nextPrefixSums
    }

    var total: CGFloat {
        prefixSums.last ?? 0
    }

    func value(at index: Int) -> CGFloat {
        values[index]
    }

    func prefixSum(before index: Int) -> CGFloat {
        prefixSums[index]
    }

    func prefixSum(through index: Int) -> CGFloat {
        prefixSums[index + 1]
    }
}
