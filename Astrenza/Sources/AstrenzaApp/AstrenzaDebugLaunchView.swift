#if DEBUG
import AstrenzaCore
import Combine
import SwiftUI

struct AstrenzaDebugLaunchView: View {
    let route: AstrenzaDebugLaunchRoute

    var body: some View {
        switch route {
        case .timelineSnapshot(let snapshotCase):
            AstrenzaDebugTimelineSnapshotView(snapshotCase: snapshotCase)
        case .timelinePerformance(let postCount):
            AstrenzaDebugTimelinePerformanceView(postCount: postCount)
        case .settingsNavigation:
            AstrenzaDebugSettingsNavigationView()
        }
    }
}

private enum AstrenzaDebugTimelineAccessibility {
    static let snapshotCapture = "astrenza.debug.timeline.snapshot.capture"
    static let snapshotResolve = "astrenza.debug.timeline.snapshot.resolve"
    static let snapshotResolved = "astrenza.debug.timeline.snapshot.resolved"
    static let performanceFeed = "astrenza.debug.timeline.performance.feed"
    static let performanceLastOpenedPost =
        "astrenza.debug.timeline.performance.last-opened-post"
}

private struct AstrenzaDebugTimelineSnapshotView: View {
    let snapshotCase: AstrenzaDebugTimelineSnapshotCase
    @StateObject private var feedModel: AstrenzaDebugTimelineFeedModel
    @State private var isResolved = false

    init(snapshotCase: AstrenzaDebugTimelineSnapshotCase) {
        self.snapshotCase = snapshotCase
        _feedModel = StateObject(
            wrappedValue: AstrenzaDebugTimelineFeedModel(
                target: AstrenzaDebugTimelineFixtures.initialPost(for: snapshotCase)
            )
        )
    }

    var body: some View {
        Group {
            if snapshotCase.supportsLateArrival {
                lateArrivalContent
            } else {
                isolatedRowContent
            }
        }
        .background(Color.astrenzaBackground)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.dynamicTypeSize, .large)
        .preferredColorScheme(.dark)
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }

    private var isolatedRowContent: some View {
        VStack(spacing: 0) {
            snapshotRow(post: AstrenzaDebugTimelineFixtures.initialPost(for: snapshotCase))
                .frame(maxWidth: .infinity, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timeline snapshot capture")
                .accessibilityIdentifier(AstrenzaDebugTimelineAccessibility.snapshotCapture)

            Spacer(minLength: 0)
        }
    }

    private var lateArrivalContent: some View {
        VStack(spacing: 0) {
            snapshotFeed
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timeline snapshot capture")
                .accessibilityIdentifier(AstrenzaDebugTimelineAccessibility.snapshotCapture)

            Button(action: resolveLateArrival) {
                Text(isResolved ? "Resolved" : "Resolve Fixture")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.astrenzaAccent)
            .frame(height: 64)
            .disabled(isResolved)
            .accessibilityIdentifier(
                isResolved
                    ? AstrenzaDebugTimelineAccessibility.snapshotResolved
                    : AstrenzaDebugTimelineAccessibility.snapshotResolve
            )
        }
    }

    private var snapshotFeed: some View {
        TimelineFeedView(
            entries: feedModel.entries,
            sourceIdentity: "debug/snapshot/\(snapshotCase.rawValue)",
            sourceRevision: feedModel.revision,
            actionMenuTopClearance: 96,
            swipeSettings: TimelineSwipeSettings(),
            viewportState: nil,
            layoutCache: TimelineLayoutCache(),
            onOpenPost: { _ in },
            onOpenProfile: { _ in },
            onReplyPost: { _ in },
            onOpenMedia: { _, _ in },
            onOpenURL: { _ in },
            onScrollOffsetChanged: { _ in },
            onViewportStateChanged: { _ in },
            onLayoutCacheChanged: { _ in }
        )
        .background(Color.astrenzaBackground)
    }

    private func snapshotRow(post: TimelinePost) -> some View {
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
        .background(Color.astrenzaBackground)
    }

    private func resolveLateArrival() {
        guard !isResolved,
              let resolvedPost = AstrenzaDebugTimelineFixtures.resolvedPost(for: snapshotCase)
        else { return }
        feedModel.replaceTarget(with: resolvedPost)
        isResolved = true
    }
}

private struct AstrenzaDebugTimelinePerformanceView: View {
    let postCount: Int
    private let entries: [TimelineFeedEntry]
    @State private var lastOpenedPostID: TimelinePost.ID?

    init(postCount: Int) {
        self.postCount = postCount
        entries = AstrenzaDebugTimelineFixtures.performanceEntries(count: postCount)
    }

    var body: some View {
        TimelineFeedView(
            entries: entries,
            sourceIdentity: "debug/performance/\(postCount)",
            actionMenuTopClearance: 96,
            swipeSettings: TimelineSwipeSettings(),
            viewportState: nil,
            layoutCache: TimelineLayoutCache(),
            onOpenPost: { post in
                lastOpenedPostID = post.id
            },
            onOpenProfile: { _ in },
            onReplyPost: { _ in },
            onOpenMedia: { _, _ in },
            onOpenURL: { _ in },
            onScrollOffsetChanged: { _ in },
            onViewportStateChanged: { _ in },
            onLayoutCacheChanged: { _ in }
        )
        .background(Color.astrenzaBackground)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.dynamicTypeSize, .large)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(AstrenzaDebugTimelineAccessibility.performanceFeed)
        .overlay(alignment: .topLeading) {
            if let lastOpenedPostID {
                Text(lastOpenedPostID)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier(
                        AstrenzaDebugTimelineAccessibility.performanceLastOpenedPost
                    )
            }
        }
    }
}

private struct AstrenzaDebugSettingsNavigationView: View {
    private let accountID = String(repeating: "a", count: 64)
    private let eventStore: NostrEventStore?
    @State private var swipeSettings = TimelineSwipeSettings()

    init() {
        eventStore = try? NostrEventStore.inMemory()
    }

    var body: some View {
        SettingsView(
            onClose: {},
            swipeSettings: $swipeSettings,
            accountID: accountID,
            eventStore: eventStore,
            accountSummaries: [accountSummary]
        )
        .preferredColorScheme(.dark)
    }

    private var accountSummary: NostrAccountSummary {
        NostrAccountSummary(
            id: accountID,
            account: NostrAccount(
                pubkey: accountID,
                displayIdentifier: "debug@astrenza.local",
                readOnly: true
            ),
            title: "Debug Account",
            subtitle: "debug@astrenza.local",
            npub: "npub1debug",
            avatarStyle: AvatarStyle(
                primary: .black,
                secondary: .cyan,
                symbolName: "person.crop.circle.fill"
            ),
            isSelected: true,
            isReadOnly: true
        )
    }
}

@MainActor
private final class AstrenzaDebugTimelineFeedModel: ObservableObject {
    @Published private(set) var entries: [TimelineFeedEntry]
    @Published private(set) var revision = 0

    init(target: TimelinePost) {
        entries = [
            .post(target),
            .post(AstrenzaDebugTimelineFixtures.sentinel())
        ]
    }

    func replaceTarget(with post: TimelinePost) {
        entries[0] = .post(post)
        revision += 1
    }
}

private enum AstrenzaDebugTimelineFixtures {
    static func initialPost(for snapshotCase: AstrenzaDebugTimelineSnapshotCase) -> TimelinePost {
        switch snapshotCase {
        case .singlePortrait:
            return post(
                id: "snapshot-single-portrait",
                body: "縦長の1枚画像でも、本文・画像・アクションの間隔を変えずに表示する。",
                media: .gallery([
                    MediaTile(
                        title: "Portrait",
                        colors: [.indigo, .cyan],
                        symbolName: "rectangle.portrait",
                        width: 900,
                        height: 1_600
                    )
                ])
            )
        case .singleLandscape:
            return post(
                id: "snapshot-single-landscape",
                body: "横長の1枚画像は、タイムラインの密度を保つ幅と高さで表示する。",
                media: .gallery([
                    MediaTile(
                        title: "Landscape",
                        colors: [.blue, .purple],
                        symbolName: "rectangle",
                        width: 2_400,
                        height: 900
                    )
                ])
            )
        case .gallery2:
            return post(
                id: "snapshot-gallery-2",
                body: "2枚のメディアを同じ比率で横に並べる。",
                media: .gallery([
                    MediaTile(title: "Relay", colors: [.blue, .purple], symbolName: "network"),
                    MediaTile(title: "Keys", colors: [.orange, .red], symbolName: "key.fill")
                ])
            )
        case .gallery3:
            return post(
                id: "snapshot-gallery-3",
                body: "3枚は上に2枚、下に1枚の構成で表示する。",
                media: .gallery([
                    MediaTile(title: "Sky", colors: [.cyan, .blue], symbolName: "cloud.fill"),
                    MediaTile(title: "Relay", colors: [.purple, .indigo], symbolName: "network"),
                    MediaTile(title: "Note", colors: [.orange, .yellow], symbolName: "text.bubble.fill")
                ])
            )
        case .gallery4:
            return post(
                id: "snapshot-gallery-4",
                body: "4枚は2行2列の構成で表示する。",
                media: .gallery([
                    MediaTile(title: "Home", colors: [.blue, .purple], symbolName: "house.fill"),
                    MediaTile(title: "Keys", colors: [.orange, .red], symbolName: "key.fill"),
                    MediaTile(title: "Relay", colors: [.green, .mint], symbolName: "antenna.radiowaves.left.and.right"),
                    MediaTile(title: "Post", colors: [.pink, .purple], symbolName: "square.and.pencil")
                ])
            )
        case .metadataLateArrival:
            return metadataLateArrival().pending
        case .ogpLateArrival:
            return ogpLateArrival().pending
        }
    }

    static func resolvedPost(for snapshotCase: AstrenzaDebugTimelineSnapshotCase) -> TimelinePost? {
        switch snapshotCase {
        case .metadataLateArrival:
            return metadataLateArrival().resolved
        case .ogpLateArrival:
            return ogpLateArrival().resolved
        case .singlePortrait, .singleLandscape, .gallery2, .gallery3, .gallery4:
            return nil
        }
    }

    static func sentinel() -> TimelinePost {
        post(
            id: "snapshot-sentinel",
            body: "後続Rowとの境界が重ならず、Dividerが正しい位置へ移動する。",
            media: nil
        )
    }

    static func performanceEntries(count: Int) -> [TimelineFeedEntry] {
        (0..<count).map { index in
            let body = switch index % 5 {
            case 0:
                "Short performance fixture #\(index)"
            case 1:
                "Two-line performance fixture #\(index)\nThe second line keeps the projected height variable."
            case 2:
                "A medium performance fixture #\(index) verifies wrapping across several lines while scrolling quickly in both directions."
            case 3:
                "Variable-height performance fixture #\(index). This deliberately contains enough text to wrap repeatedly so the collection layout must preserve exact prefix sums without changing already-projected row frames during a scroll session."
            default:
                "Five-line fixture #\(index)\nLine two\nLine three\nLine four\nLine five"
            }
            return .post(post(
                id: "performance-\(index)",
                body: body,
                media: nil,
                createdAt: snapshotCreatedAt() - index
            ))
        }
    }

    private static func metadataLateArrival() -> (pending: TimelinePost, resolved: TimelinePost) {
        let pubkey = TimelineAuthor.mockPubkey(for: "snapshot-metadata-author")
        let createdAt = snapshotCreatedAt()
        let pending = TimelinePost(
            id: "snapshot-metadata-late-arrival",
            author: .unresolved(pubkey: pubkey, state: .fetching),
            avatar: AvatarStyle(
                primary: .indigo,
                secondary: .blue,
                symbolName: "person.fill",
                pictureState: .metadataPending,
                placeholderSeed: pubkey
            ),
            body: "kind:0 metadataが後から到着しても、同じ投稿として自然に更新する。",
            createdAt: createdAt,
            replyCount: 2,
            boostCount: 5,
            favoriteCount: 18,
            isLocked: false,
            media: nil,
            context: nil
        )
        let resolved = TimelinePost(
            id: pending.id,
            author: .resolved(
                displayName: "User Metadata",
                nip05: "metadata@mock.example",
                pubkey: pubkey
            ),
            avatar: AvatarStyle(
                primary: .cyan,
                secondary: .indigo,
                symbolName: "sparkles",
                pictureState: .resolved,
                placeholderSeed: pubkey
            ),
            body: pending.body,
            createdAt: createdAt,
            replyCount: pending.replyCount,
            boostCount: pending.boostCount,
            favoriteCount: pending.favoriteCount,
            isLocked: pending.isLocked,
            media: pending.media,
            context: pending.context
        )
        return (pending, resolved)
    }

    private static func ogpLateArrival() -> (pending: TimelinePost, resolved: TimelinePost) {
        let createdAt = snapshotCreatedAt()
        let pending = post(
            id: "snapshot-ogp-late-arrival",
            body: "OGP metadataが後から到着した時のRow高とカード表示を固定する。",
            media: .unresolvedLink(UnresolvedLinkPreview(
                host: "design.mock.example",
                url: "https://design.mock.example/timeline-layout"
            )),
            createdAt: createdAt
        )
        let resolved = post(
            id: pending.id,
            body: pending.body,
            media: .linkPreview(LinkPreview(
                title: "Timeline Layout Notes",
                subtitle: "可変高Rowとスクロール位置を安定させるための表示ルール",
                host: "design.mock.example",
                url: "https://design.mock.example/timeline-layout",
                imageURL: nil
            )),
            createdAt: createdAt
        )
        return (pending, resolved)
    }

    private static func post(
        id: String,
        body: String,
        media: TimelineMedia?,
        createdAt: Int = snapshotCreatedAt()
    ) -> TimelinePost {
        TimelinePost(
            id: id,
            author: .resolved(
                displayName: "User Snapshot",
                nip05: "snapshot@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "snapshot-author")
            ),
            avatar: AvatarStyle(
                primary: .cyan,
                secondary: .indigo,
                symbolName: "sparkles",
                pictureState: .resolved,
                placeholderSeed: "snapshot-author"
            ),
            body: body,
            createdAt: createdAt,
            replyCount: 3,
            boostCount: 8,
            favoriteCount: 21,
            isLocked: false,
            media: media,
            context: nil,
            actionState: TimelinePostActionState(
                didReply: false,
                didRepost: true,
                didFavorite: false,
                didZap: true
            )
        )
    }

    private static func snapshotCreatedAt() -> Int {
        TimelineMockClock.referenceNow - 8 * 60
    }
}

private extension AstrenzaDebugTimelineSnapshotCase {
    var supportsLateArrival: Bool {
        switch self {
        case .metadataLateArrival, .ogpLateArrival:
            return true
        case .singlePortrait, .singleLandscape, .gallery2, .gallery3, .gallery4:
            return false
        }
    }
}
#endif
