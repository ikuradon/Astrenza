import SwiftUI
import Testing
import UIKit
@testable import Astrenza

@Suite("Timeline hosted collection cell geometry")
struct TimelineFeedHostingCollectionCellTests {
    @MainActor
    @Test("Self-sizing layout gives adjacent hosted rows disjoint frames")
    func selfSizingLayoutKeepsAdjacentRowsDisjoint() throws {
        let (collectionView, dataSource) = makeCollectionView(
            contents: [.fixedHeight(240), .fixedHeight(120)]
        )
        _ = dataSource

        let first = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )?.frame
        )
        let second = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 1, section: 0)
            )?.frame
        )

        #expect(first.minY == 72)
        #expect(first.height >= 240)
        #expect(second.height >= 120)
        #expect(first.maxY <= second.minY)
        #expect(abs(first.maxY - second.minY) <= 0.5)
    }

    @MainActor
    @Test("Multiline hosted content is fitted at the collection width")
    func multilineContentUsesCollectionWidth() throws {
        let (collectionView, dataSource) = makeCollectionView(
            contents: [
                .text(
                    String(
                        repeating: "Astrenza timeline content ",
                        count: 16
                    )
                ),
                .fixedHeight(80),
            ]
        )
        _ = dataSource

        let indexPath = IndexPath(item: 0, section: 0)
        let first = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.frame
        )
        let second = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 1, section: 0)
            )?.frame
        )
        let cell = try #require(collectionView.cellForItem(at: indexPath))
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(
                width: first.width,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(first.width == 390)
        #expect(abs(first.height - fitted.height) <= 0.5)
        #expect(first.maxY <= second.minY)
        #expect(abs(first.maxY - second.minY) <= 0.5)
    }

    @MainActor
    private func makeCollectionView(
        contents: [HostedCellContent]
    ) -> (UICollectionView, HostedCellDataSource) {
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: TimelineFeedSelfSizingLayout.make(
                topContentPadding: 72,
                estimatedRowHeight: 60
            )
        )
        collectionView.selfSizingInvalidation = .disabled
        collectionView.register(
            TimelineFeedHostingCollectionCell.self,
            forCellWithReuseIdentifier: "cell"
        )
        let dataSource = HostedCellDataSource(contents: contents)
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        return (collectionView, dataSource)
    }
}

private enum HostedCellContent {
    case fixedHeight(CGFloat)
    case text(String)
}

@MainActor
private final class HostedCellDataSource:
    NSObject,
    UICollectionViewDataSource
{
    private let contents: [HostedCellContent]

    init(contents: [HostedCellContent]) {
        self.contents = contents
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        contents.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell",
            for: indexPath
        )
        let content = contents[indexPath.item]
        cell.contentConfiguration = UIHostingConfiguration {
            switch content {
            case let .fixedHeight(height):
                Color.clear.frame(height: height)
            case let .text(text):
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .margins(.all, 0)
        return cell
    }
}
