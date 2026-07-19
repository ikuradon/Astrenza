import AstrenzaCore
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
    @Test("Repeated fitting of a timeline post row is idempotent")
    func repeatedTimelinePostFittingDoesNotGrowRowHeight() throws {
        let (collectionView, dataSource) = makeCollectionView(
            contents: [.timelinePost(makeTimelinePost())]
        )
        _ = dataSource

        let indexPath = IndexPath(item: 0, section: 0)
        let cell = try #require(
            collectionView.cellForItem(at: indexPath)
                as? TimelineFeedHostingCollectionCell
        )
        let initialAttributes = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.copy() as? UICollectionViewLayoutAttributes
        )
        var attributes = initialAttributes
        let initialHeight = initialAttributes.size.height

        for _ in 0 ..< 32 {
            attributes = cell.preferredLayoutAttributesFitting(attributes)
            cell.apply(attributes)
            cell.frame.size = attributes.size
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }

        #expect(abs(attributes.size.height - initialHeight) <= 0.5)
    }

    @MainActor
    @Test("Repeated reconfiguration does not grow a timeline post row")
    func repeatedReconfigurationDoesNotGrowRowHeight() throws {
        let post = makeTimelinePost()
        let collectionView = makeBareCollectionView()
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, _ in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "cell",
                for: indexPath
            ) as? TimelineFeedHostingCollectionCell else { return nil }
            let hostedConfiguration = UIHostingConfiguration {
                TimelinePostRow(
                    post: post,
                    isActionMenuPresented: false,
                    swipeSettings: TimelineSwipeSettings(),
                    onActionEvent: { _ in },
                    onOpenPost: { _ in },
                    onOpenProfile: { _ in },
                    onReplyPost: { _ in },
                    onOpenMedia: { _, _ in },
                    onOpenURL: { _ in },
                    onDismissActionMenu: {}
                )
            }
            .margins(.all, 0)
            .background { Color.astrenzaBackground }
            cell.configure(
                contentConfiguration: hostedConfiguration,
                sizingIdentity: TimelineFeedCellSizingIdentity(
                    entryID: "post-0",
                    renderFingerprint: 0,
                    swipeSettings: TimelineSwipeSettings(),
                    isActionMenuPresented: false,
                    gapDirection: .older,
                    isFetchingGap: false
                )
            )
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let initialHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.size.height
        )

        for _ in 0 ..< 32 {
            snapshot = dataSource.snapshot()
            snapshot.reconfigureItems([0])
            dataSource.apply(snapshot, animatingDifferences: false)
            collectionView.layoutIfNeeded()
        }

        let finalHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.size.height
        )
        #expect(abs(finalHeight - initialHeight) <= 0.5)
    }

    @MainActor
    @Test("A changed sizing identity remeasures the row")
    func changedSizingIdentityRemeasuresRow() throws {
        var configuredHeight: CGFloat = 80
        let collectionView = makeBareCollectionView()
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, _ in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "cell",
                for: indexPath
            ) as? TimelineFeedHostingCollectionCell else { return nil }
            let hostedConfiguration = UIHostingConfiguration {
                Color.clear.frame(height: configuredHeight)
            }
            .margins(.all, 0)
            cell.configure(
                contentConfiguration: hostedConfiguration,
                sizingIdentity: TimelineFeedCellSizingIdentity(
                    entryID: "resizing-post",
                    renderFingerprint: configuredHeight.hashValue,
                    swipeSettings: TimelineSwipeSettings(),
                    isActionMenuPresented: false,
                    gapDirection: .older,
                    isFetchingGap: false
                )
            )
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let initialHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.size.height
        )

        configuredHeight = 240
        snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.layoutIfNeeded()

        let finalHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: indexPath
            )?.size.height
        )
        #expect(initialHeight >= 80)
        #expect(finalHeight >= 240)
        #expect(finalHeight > initialHeight)
    }

    @MainActor
    @Test("Cell reuse across different content heights does not grow rows")
    func reuseAcrossDifferentHeightsDoesNotGrowRows() throws {
        let contents = (0 ..< 120).map { index in
            HostedCellContent.fixedHeight(index.isMultiple(of: 2) ? 80 : 320)
        }
        let (collectionView, dataSource) = makeCollectionView(
            contents: contents
        )
        _ = dataSource

        let firstIndexPath = IndexPath(item: 0, section: 0)
        let initialHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: firstIndexPath
            )?.size.height
        )

        for _ in 0 ..< 16 {
            collectionView.contentOffset.y = max(
                0,
                collectionView.collectionViewLayout.collectionViewContentSize.height -
                    collectionView.bounds.height
            )
            collectionView.layoutIfNeeded()
            collectionView.contentOffset.y = 0
            collectionView.layoutIfNeeded()
        }

        let finalHeight = try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: firstIndexPath
            )?.size.height
        )
        #expect(abs(finalHeight - initialHeight) <= 0.5)
    }

    private func makeTimelinePost() -> TimelinePost {
        TimelinePost(
            id: "self-sizing-post",
            authorName: "Astrenza",
            handle: "astrenza@example.com",
            avatar: AvatarStyle(
                primary: .cyan,
                secondary: .indigo,
                symbolName: "sparkles"
            ),
            body: String(
                repeating: "Hosted timeline post content ",
                count: 16
            ),
            richBody: NostrRichContent(
                displayText: String(
                    repeating: "Hosted :astrenza: content ",
                    count: 16
                ),
                tokens: [
                    .text(
                        String(
                            repeating: "Hosted timeline content ",
                            count: 8
                        )
                    ),
                    .customEmoji(
                        shortcode: "astrenza",
                        url: URL(string: "https://example.invalid/emoji.png")!
                    ),
                    .text(
                        String(
                            repeating: " trailing timeline content",
                            count: 8
                        )
                    ),
                ],
                references: []
            ),
            createdAt: 1_718_000_000,
            replyCount: 2,
            boostCount: 4,
            favoriteCount: 8,
            isLocked: false,
            media: .gallery([
                MediaTile(
                    title: "Portrait",
                    colors: [.indigo, .cyan],
                    symbolName: "rectangle.portrait",
                    width: 900,
                    height: 1_600
                ),
            ]),
            context: nil
        )
    }

    @MainActor
    private func makeCollectionView(
        contents: [HostedCellContent]
    ) -> (UICollectionView, HostedCellDataSource) {
        let collectionView = makeBareCollectionView()
        let dataSource = HostedCellDataSource(contents: contents)
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        return (collectionView, dataSource)
    }

    @MainActor
    private func makeBareCollectionView() -> UICollectionView {
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
        return collectionView
    }
}

private enum HostedCellContent {
    case fixedHeight(CGFloat)
    case text(String)
    case timelinePost(TimelinePost)

    var renderFingerprint: Int {
        switch self {
        case let .fixedHeight(height):
            height.hashValue
        case let .text(text):
            text.hashValue
        case let .timelinePost(post):
            TimelineRenderFingerprint.entry(.post(post))
        }
    }
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
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell",
            for: indexPath
        ) as? TimelineFeedHostingCollectionCell else {
            return UICollectionViewCell()
        }
        let content = contents[indexPath.item]
        let hostedConfiguration = UIHostingConfiguration {
            switch content {
            case let .fixedHeight(height):
                Color.clear.frame(height: height)
            case let .text(text):
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case let .timelinePost(post):
                TimelinePostRow(
                    post: post,
                    isActionMenuPresented: false,
                    swipeSettings: TimelineSwipeSettings(),
                    onActionEvent: { _ in },
                    onOpenPost: { _ in },
                    onOpenProfile: { _ in },
                    onReplyPost: { _ in },
                    onOpenMedia: { _, _ in },
                    onOpenURL: { _ in },
                    onDismissActionMenu: {}
                )
            }
        }
        .margins(.all, 0)
        .background { Color.astrenzaBackground }
        cell.configure(
            contentConfiguration: hostedConfiguration,
            sizingIdentity: TimelineFeedCellSizingIdentity(
                entryID: "test-\(indexPath.item)",
                renderFingerprint: content.renderFingerprint,
                swipeSettings: TimelineSwipeSettings(),
                isActionMenuPresented: false,
                gapDirection: .older,
                isFetchingGap: false
            )
        )
        return cell
    }
}
