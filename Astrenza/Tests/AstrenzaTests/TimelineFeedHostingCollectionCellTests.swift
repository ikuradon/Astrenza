import AstrenzaCore
import SwiftUI
import Testing
import UIKit
@testable import Astrenza

@Suite("Timeline hosted collection cell geometry")
struct TimelineFeedHostingCollectionCellTests {
    @MainActor
    @Test("Stable layout gives adjacent hosted rows disjoint frames")
    func stableLayoutKeepsAdjacentRowsDisjoint() throws {
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
        let cell = try #require(
            collectionView.cellForItem(at: indexPath)
                as? TimelineFeedHostingCollectionCell
        )
        let fittedHeight = cell.measuredHeight(fittingWidth: first.width)

        #expect(first.width == 390)
        #expect(abs(first.height - fittedHeight) <= 0.5)
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
    @Test("Projected height matches an unconstrained hosting measurement")
    func projectedHeightMatchesHostingControllerMeasurement() {
        let post = makeYouTubeTimelinePost()
        let content = HostedCellContent.timelinePost(post)
        let measurementCell = TimelineFeedHostingCollectionCell(frame: .zero)
        HostedCellDataSource.configure(
            cell: measurementCell,
            content: content,
            entryID: post.id
        )
        let projectedHeight = measurementCell.measuredHeight(fittingWidth: 390)
        let hostingController = UIHostingController(
            rootView: TimelinePostRow(
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        )
        let hostingHeight = hostingController.sizeThatFits(
            in: CGSize(
                width: 390,
                height: CGFloat.greatestFiniteMagnitude
            )
        ).height

        #expect(abs(projectedHeight - hostingHeight) <= 0.5)
    }

    @MainActor
    @Test("Mounted content keeps the projected intrinsic height")
    func mountedContentKeepsProjectedIntrinsicHeight() throws {
        for content in [
            HostedCellContent.timelinePost(makeTimelinePost()),
            HostedCellContent.timelinePost(makeYouTubeTimelinePost()),
        ] {
            let (collectionView, dataSource) = makeCollectionView(
                contents: [content]
            )
            _ = dataSource
            let indexPath = IndexPath(item: 0, section: 0)
            let projectedHeight = try #require(
                collectionView.collectionViewLayout
                    .layoutAttributesForItem(at: indexPath)?.size.height
            )
            let cell = try #require(
                collectionView.cellForItem(at: indexPath)
                    as? TimelineFeedHostingCollectionCell
            )
            cell.layoutIfNeeded()
            let measuredHeight = cell.measuredHeight(
                fittingWidth: collectionView.bounds.width
            )

            #expect(abs(projectedHeight - measuredHeight) <= 0.5)
            #expect(abs(cell.hostedContentFrame.minX) <= 0.5)
            #expect(abs(cell.hostedContentFrame.minY) <= 0.5)
            #expect(
                abs(cell.hostedContentFrame.height - projectedHeight) <= 0.5
            )
        }
    }

    @MainActor
    @Test("Hosted content is clipped at the projected row boundary")
    func hostedContentIsContainedByProjectedRowBounds() throws {
        let contents: [HostedCellContent] = [
            .text(String(repeating: "Mounted timeline text ", count: 24)),
            .timelinePost(makeTimelinePost()),
        ]
        for content in contents {
            let (collectionView, dataSource) = makeCollectionView(
                contents: [content]
            )
            _ = dataSource
            let indexPath = IndexPath(item: 0, section: 0)
            _ = try #require(
                collectionView.collectionViewLayout
                    .layoutAttributesForItem(at: indexPath)?.frame
            )
            let cell = try #require(
                collectionView.cellForItem(at: indexPath)
                    as? TimelineFeedHostingCollectionCell
            )
            cell.layoutIfNeeded()
            #expect(cell.clipsToBounds)
            #expect(cell.contentView.clipsToBounds)
            #expect(cell.hostedContentFrame == cell.contentView.bounds)
            #expect(cell.hostedSafeAreaIsDisabled)
        }
    }

    @MainActor
    @Test("Repeated reconfiguration does not grow a timeline post row")
    func repeatedReconfigurationDoesNotGrowRowHeight() throws {
        let post = makeTimelinePost()
        let content = HostedCellContent.timelinePost(post)
        let collectionView = makeBareCollectionView(
            projectedItems: projectedItems(for: [content])
        )
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, _ in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "cell",
                for: indexPath
            ) as? TimelineFeedHostingCollectionCell else { return nil }
            cell.configure(
                rootView: content.makeContentView(),
                parentViewController: nil,
                sizingIdentity: TimelineFeedCellSizingIdentity(
                    entryID: "post-0",
                    geometryFingerprint: 0,
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
        let collectionView = makeBareCollectionView(
            projectedItems: [
                TimelineFeedProjectedLayoutItem(
                    id: "resizing-post",
                    height: configuredHeight
                ),
            ]
        )
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, _ in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "cell",
                for: indexPath
            ) as? TimelineFeedHostingCollectionCell else { return nil }
            cell.configure(
                rootView: AnyView(
                    Color.clear
                        .frame(height: configuredHeight)
                        .fixedSize(horizontal: false, vertical: true)
                ),
                parentViewController: nil,
                sizingIdentity: TimelineFeedCellSizingIdentity(
                    entryID: "resizing-post",
                    geometryFingerprint: configuredHeight.hashValue,
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
        let layout = try #require(
            collectionView.collectionViewLayout as? TimelineFeedStableLayout
        )
        layout.configure(
            items: [
                TimelineFeedProjectedLayoutItem(
                    id: "resizing-post",
                    height: configuredHeight
                ),
            ],
            topPadding: 72
        )
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

    @MainActor
    @Test("Bidirectional scrolling keeps the complete content geometry fixed")
    func bidirectionalScrollingKeepsContentGeometryFixed() {
        let contents = (0 ..< 120).map { index in
            HostedCellContent.fixedHeight(index.isMultiple(of: 2) ? 80 : 320)
        }
        let (collectionView, dataSource) = makeCollectionView(
            contents: contents
        )
        _ = dataSource
        let initialContentHeight = collectionView
            .collectionViewLayout
            .collectionViewContentSize
            .height

        var offset: CGFloat = 0
        while offset < collectionView.collectionViewLayout
            .collectionViewContentSize.height {
            collectionView.contentOffset.y = offset
            collectionView.layoutIfNeeded()
            offset += collectionView.bounds.height * 0.75
        }
        while offset > 0 {
            offset = max(0, offset - collectionView.bounds.height * 0.75)
            collectionView.contentOffset.y = offset
            collectionView.layoutIfNeeded()
        }

        let finalContentHeight = collectionView
            .collectionViewLayout
            .collectionViewContentSize
            .height
        #expect(abs(finalContentHeight - initialContentHeight) <= 0.5)
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

    private func makeYouTubeTimelinePost() -> TimelinePost {
        TimelinePost(
            id: "youtube-row",
            authorName: "YouTube Author",
            handle: "youtube@example.com",
            avatar: AvatarStyle(
                primary: .cyan,
                secondary: .indigo,
                symbolName: "play.rectangle.fill"
            ),
            body: "正解が知りたい。",
            richBody: NostrRichContent(
                displayText: "正解が知りたい。",
                tokens: [.text("正解が知りたい。")],
                references: []
            ),
            createdAt: 1_784_455_666,
            replyCount: 0,
            boostCount: 0,
            favoriteCount: 0,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "7年分のそうめんちゅるちゅるASMRを比較してみた！【ホロライブ切り抜き/大神ミオ】",
                subtitle: "YouTube でお気に入りの動画や音楽を楽しみ、オリジナルのコンテンツを共有しましょう。",
                host: "www.youtube.com",
                url: "https://www.youtube.com/shorts/XyvI2U2XZTs",
                imageURL: URL(string: "https://i.ytimg.com/vi/XyvI2U2XZTs/oardefault.jpg"),
                style: .youtube
            )),
            context: nil,
            linkSummary: TimelineLinkSummary(
                totalCount: 1,
                visibleHosts: ["www.youtube.com"],
                unresolvedCount: 0
            )
        )
    }

    @MainActor
    private func makeCollectionView(
        contents: [HostedCellContent]
    ) -> (UICollectionView, HostedCellDataSource) {
        let collectionView = makeBareCollectionView(
            projectedItems: projectedItems(for: contents)
        )
        let dataSource = HostedCellDataSource(contents: contents)
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        return (collectionView, dataSource)
    }

    @MainActor
    private func makeBareCollectionView(
        projectedItems: [TimelineFeedProjectedLayoutItem]
    ) -> UICollectionView {
        let layout = TimelineFeedStableLayout()
        layout.configure(items: projectedItems, topPadding: 72)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            collectionViewLayout: layout
        )
        collectionView.register(
            TimelineFeedHostingCollectionCell.self,
            forCellWithReuseIdentifier: "cell"
        )
        return collectionView
    }

    @MainActor
    private func projectedItems(
        for contents: [HostedCellContent]
    ) -> [TimelineFeedProjectedLayoutItem] {
        let measurementCell = TimelineFeedHostingCollectionCell(frame: .zero)
        return contents.enumerated().map { index, content in
            HostedCellDataSource.configure(
                cell: measurementCell,
                content: content,
                entryID: "test-\(index)"
            )
            return TimelineFeedProjectedLayoutItem(
                id: "test-\(index)",
                height: measurementCell.measuredHeight(fittingWidth: 390)
            )
        }
    }
}

private enum HostedCellContent {
    case fixedHeight(CGFloat)
    case text(String)
    case timelinePost(TimelinePost)

    var geometryFingerprint: Int {
        switch self {
        case let .fixedHeight(height):
            height.hashValue
        case let .text(text):
            text.hashValue
        case let .timelinePost(post):
            TimelineRenderFingerprint.entry(.post(post))
        }
    }

    @MainActor
    func makeContentView() -> AnyView {
        AnyView(
            Group {
                switch self {
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .id(geometryFingerprint)
            .background(Color.astrenzaBackground)
        )
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
        Self.configure(
            cell: cell,
            content: content,
            entryID: "test-\(indexPath.item)"
        )
        return cell
    }

    static func configure(
        cell: TimelineFeedHostingCollectionCell,
        content: HostedCellContent,
        entryID: String
    ) {
        cell.configure(
            rootView: content.makeContentView(),
            parentViewController: nil,
            sizingIdentity: TimelineFeedCellSizingIdentity(
                entryID: entryID,
                geometryFingerprint: content.geometryFingerprint,
                swipeSettings: TimelineSwipeSettings(),
                isActionMenuPresented: false,
                gapDirection: .older,
                isFetchingGap: false
            )
        )
    }
}
