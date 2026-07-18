import CoreGraphics
import Foundation

struct TimelineFeedLayoutItem: Equatable {
    let id: TimelineFeedEntry.ID
    let estimatedHeight: CGFloat
}

struct TimelineFeedLayoutIndex {
    private let itemIDs: [TimelineFeedEntry.ID]
    private let itemIndexByID: [TimelineFeedEntry.ID: Int]
    private var heights: TimelineFeedHeightIndex
    let topPadding: CGFloat

    init(
        items: [TimelineFeedLayoutItem] = [],
        topPadding: CGFloat = 0
    ) {
        itemIDs = items.map(\.id)
        itemIndexByID = Dictionary(
            uniqueKeysWithValues: itemIDs.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        heights = TimelineFeedHeightIndex(
            items.map { max(1, $0.estimatedHeight) }
        )
        self.topPadding = topPadding
    }

    var count: Int {
        itemIDs.count
    }

    var contentHeight: CGFloat {
        topPadding + heights.total
    }

    func id(at index: Int) -> TimelineFeedEntry.ID? {
        guard itemIDs.indices.contains(index) else { return nil }
        return itemIDs[index]
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

    func frame(
        for id: TimelineFeedEntry.ID,
        width: CGFloat
    ) -> CGRect? {
        guard let index = itemIndexByID[id] else { return nil }
        return frame(at: index, width: width)
    }

    func itemIndexes(intersecting rect: CGRect) -> Range<Int> {
        guard !itemIDs.isEmpty, rect.maxY > topPadding else {
            return 0..<0
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
        return first..<end
    }

    func height(at index: Int) -> CGFloat? {
        guard itemIDs.indices.contains(index) else { return nil }
        return heights.value(at: index)
    }

    @discardableResult
    mutating func updateHeight(
        _ height: CGFloat,
        at index: Int,
        threshold: CGFloat = 0.5
    ) -> CGFloat? {
        guard itemIDs.indices.contains(index), height > 0 else { return nil }
        let delta = height - heights.value(at: index)
        guard abs(delta) > threshold else { return nil }
        heights.update(to: height, at: index)
        return delta
    }
}

private struct TimelineFeedHeightIndex {
    private var values: [CGFloat]
    private var tree: [CGFloat]

    init(_ values: [CGFloat]) {
        self.values = values
        tree = Array(repeating: 0, count: values.count + 1)
        for (index, value) in values.enumerated() {
            add(value, at: index)
        }
    }

    var total: CGFloat {
        prefixSum(count: values.count)
    }

    func value(at index: Int) -> CGFloat {
        values[index]
    }

    func prefixSum(before index: Int) -> CGFloat {
        prefixSum(count: index)
    }

    func prefixSum(through index: Int) -> CGFloat {
        prefixSum(count: index + 1)
    }

    mutating func update(to value: CGFloat, at index: Int) {
        let delta = value - values[index]
        values[index] = value
        add(delta, at: index)
    }

    private mutating func add(_ delta: CGFloat, at index: Int) {
        var treeIndex = index + 1
        while treeIndex < tree.count {
            tree[treeIndex] += delta
            treeIndex += treeIndex & -treeIndex
        }
    }

    private func prefixSum(count: Int) -> CGFloat {
        var total: CGFloat = 0
        var treeIndex = min(max(count, 0), tree.count - 1)
        while treeIndex > 0 {
            total += tree[treeIndex]
            treeIndex -= treeIndex & -treeIndex
        }
        return total
    }
}
