import SwiftUI

struct TimelineFeedView: View {
    let entries: [TimelineFeedEntry]
    let sourceIdentity: String
    let sourceRevision: Int
    let viewportIdentity: TimelineFeedViewportIdentity
    let metrics: TimelineFeedCollectionMetrics
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let scrollCommand: TimelineScrollCommand?
    let viewportRestoreProtectionActive: Bool
    let followsRealtimeEntries: Bool
    let layoutCache: TimelineLayoutCache
    let emptyState: TimelineEmptyState
    let onEmptyStatePrimaryAction: () -> Void
    let onEmptyStateSecondaryAction: (() -> Void)?
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
    let onRefresh: (() async -> Bool)?
    let onLoadOlderPost: ((TimelinePost.ID) -> Void)?
    let onBackfillGap:
        ((TimelineGap, TimelineGapFillDirection) async -> Bool)?
    let onScrollOffsetChanged: (CGFloat) -> Void
    let onScrollActivityChanged: (Bool) -> Void
    let onInitialViewportReady: () -> Void
    let onViewportRestoreCompleted: (CGFloat) -> Void
    let onViewportStateChanged: (TimelineViewportState) -> Void
    let onPostsCrossedReadLineTowardNewer: ([TimelinePost.ID]) -> Void
    let unreadCountAnchorPostID: TimelinePost.ID?
    let onUnreadPillPlacementChanged: (HomeUnreadPillPlacement) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void
    @State private var pullRefreshPresentation =
        TimelinePullRefreshPresentation.idle

    init(
        posts: [TimelinePost],
        sourceIdentity: String = "timeline",
        sourceRevision: Int = 0,
        viewportIdentity: TimelineFeedViewportIdentity? = nil,
        metrics: TimelineFeedCollectionMetrics = .home,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        viewportRestoreProtectionActive: Bool = false,
        followsRealtimeEntries: Bool = false,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onPostActionChoice: @escaping (TimelinePost, PostActionChoice) -> Void = { _, _ in },
        onRefresh: (() async -> Bool)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onScrollActivityChanged: @escaping (Bool) -> Void = { _ in },
        onInitialViewportReady: @escaping () -> Void = {},
        onViewportRestoreCompleted: @escaping (CGFloat) -> Void = { _ in },
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onPostsCrossedReadLineTowardNewer: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        unreadCountAnchorPostID: TimelinePost.ID? = nil,
        onUnreadPillPlacementChanged: @escaping (HomeUnreadPillPlacement) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.init(
            entries: posts.map(TimelineFeedEntry.post),
            sourceIdentity: sourceIdentity,
            sourceRevision: sourceRevision,
            viewportIdentity: viewportIdentity,
            metrics: metrics,
            swipeSettings: swipeSettings,
            viewportState: viewportState,
            scrollCommand: scrollCommand,
            viewportRestoreProtectionActive:
                viewportRestoreProtectionActive,
            followsRealtimeEntries: followsRealtimeEntries,
            layoutCache: layoutCache,
            emptyState: emptyState,
            onEmptyStatePrimaryAction: onEmptyStatePrimaryAction,
            onEmptyStateSecondaryAction: onEmptyStateSecondaryAction,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onPostActionChoice: onPostActionChoice,
            onRefresh: onRefresh,
            onLoadOlderPost: onLoadOlderPost,
            onBackfillGap: onBackfillGap,
            onScrollOffsetChanged: onScrollOffsetChanged,
            onScrollActivityChanged: onScrollActivityChanged,
            onInitialViewportReady: onInitialViewportReady,
            onViewportRestoreCompleted: onViewportRestoreCompleted,
            onViewportStateChanged: onViewportStateChanged,
            onPostsCrossedReadLineTowardNewer:
                onPostsCrossedReadLineTowardNewer,
            unreadCountAnchorPostID: unreadCountAnchorPostID,
            onUnreadPillPlacementChanged:
                onUnreadPillPlacementChanged,
            onLayoutCacheChanged: onLayoutCacheChanged
        )
    }

    init(
        entries: [TimelineFeedEntry],
        sourceIdentity: String = "timeline",
        sourceRevision: Int = 0,
        viewportIdentity: TimelineFeedViewportIdentity? = nil,
        metrics: TimelineFeedCollectionMetrics = .home,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        viewportRestoreProtectionActive: Bool = false,
        followsRealtimeEntries: Bool = false,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onPostActionChoice: @escaping (TimelinePost, PostActionChoice) -> Void = { _, _ in },
        onRefresh: (() async -> Bool)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onScrollActivityChanged: @escaping (Bool) -> Void = { _ in },
        onInitialViewportReady: @escaping () -> Void = {},
        onViewportRestoreCompleted: @escaping (CGFloat) -> Void = { _ in },
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onPostsCrossedReadLineTowardNewer: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        unreadCountAnchorPostID: TimelinePost.ID? = nil,
        onUnreadPillPlacementChanged: @escaping (HomeUnreadPillPlacement) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.entries = entries
        self.sourceIdentity = sourceIdentity
        self.sourceRevision = sourceRevision
        self.viewportIdentity = viewportIdentity ?? TimelineFeedViewportIdentity(
            accountID: viewportState?.accountID ?? "mock-account",
            timelineKey: viewportState?.timelineKey ?? "home"
        )
        self.metrics = metrics
        self.swipeSettings = swipeSettings
        self.viewportState = viewportState
        self.scrollCommand = scrollCommand
        self.viewportRestoreProtectionActive =
            viewportRestoreProtectionActive
        self.followsRealtimeEntries = followsRealtimeEntries
        self.layoutCache = layoutCache
        self.emptyState = emptyState
        self.onEmptyStatePrimaryAction = onEmptyStatePrimaryAction
        self.onEmptyStateSecondaryAction = onEmptyStateSecondaryAction
        self.onOpenPost = onOpenPost
        self.onOpenProfile = onOpenProfile
        self.onReplyPost = onReplyPost
        self.onOpenMedia = onOpenMedia
        self.onOpenURL = onOpenURL
        self.onPostActionChoice = onPostActionChoice
        self.onRefresh = onRefresh
        self.onLoadOlderPost = onLoadOlderPost
        self.onBackfillGap = onBackfillGap
        self.onScrollOffsetChanged = onScrollOffsetChanged
        self.onScrollActivityChanged = onScrollActivityChanged
        self.onInitialViewportReady = onInitialViewportReady
        self.onViewportRestoreCompleted = onViewportRestoreCompleted
        self.onViewportStateChanged = onViewportStateChanged
        self.onPostsCrossedReadLineTowardNewer =
            onPostsCrossedReadLineTowardNewer
        self.unreadCountAnchorPostID = unreadCountAnchorPostID
        self.onUnreadPillPlacementChanged = onUnreadPillPlacementChanged
        self.onLayoutCacheChanged = onLayoutCacheChanged
    }

    var body: some View {
        ZStack(alignment: .top) {
            TimelineFeedCollectionView(
                configuration: collectionConfiguration
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if entries.isEmpty {
                TimelineEmptyStateView(
                    state: emptyState,
                    onPrimaryAction: onEmptyStatePrimaryAction,
                    onSecondaryAction: onEmptyStateSecondaryAction
                )
                .padding(.top, 72)
            }

            TimelinePullRefreshIndicator(
                presentation: pullRefreshPresentation
            )
            .padding(.top, 80)
        }
        .background(Color.astrenzaBackground)
    }

    private var collectionConfiguration:
        TimelineFeedCollectionConfiguration {
        TimelineFeedCollectionConfiguration(
            entries: entries,
            leadingContent: nil,
            metrics: metrics,
            sourceIdentity: sourceIdentity,
            sourceRevision: sourceRevision,
            viewportIdentity: viewportIdentity,
            swipeSettings: swipeSettings,
            viewportState: viewportState,
            scrollCommand: scrollCommand,
            viewportRestoreProtectionActive:
                viewportRestoreProtectionActive,
            followsRealtimeEntries: followsRealtimeEntries,
            layoutCache: layoutCache,
            unreadCountAnchorPostID: unreadCountAnchorPostID,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onPostActionChoice: onPostActionChoice,
            onRefresh: onRefresh,
            onLoadOlderPost: onLoadOlderPost,
            onBackfillGap: onBackfillGap,
            onScrollOffsetChanged: onScrollOffsetChanged,
            onScrollActivityChanged: onScrollActivityChanged,
            onInitialViewportReady: onInitialViewportReady,
            onViewportRestoreCompleted: onViewportRestoreCompleted,
            onViewportStateChanged: onViewportStateChanged,
            onPostsCrossedReadLineTowardNewer:
                onPostsCrossedReadLineTowardNewer,
            onUnreadPillPlacementChanged:
                onUnreadPillPlacementChanged,
            onLayoutCacheChanged: onLayoutCacheChanged,
            onPullRefreshPresentationChanged: {
                pullRefreshPresentation = $0
            }
        )
    }
}

private struct TimelinePullRefreshIndicator: View {
    let presentation: TimelinePullRefreshPresentation

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point8) {
            indicator

            Text(title)
                .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AstrenzaSpacing.point12)
        .frame(height: 34)
        .astrenzaGlass(
            tint: Color.white.opacity(0.06),
            in: Capsule()
        )
        .scaleEffect(0.92 + visibleProgress * 0.08)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHidden(!isVisible)
        .animation(
            .spring(duration: AstrenzaMotion.standard, bounce: 0.12),
            value: animationPhase
        )
        .animation(.snappy(duration: AstrenzaMotion.instant), value: visibleProgress)
    }

    @ViewBuilder
    private var indicator: some View {
        switch presentation {
        case .refreshing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(Color.astrenzaAccent)
                .frame(width: 18, height: 18)
        case .completed(let didUpdate):
            Image(systemName: didUpdate ? "checkmark" : "checkmark.circle")
                .font(.astrenza(.point12, weight: .black))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(width: 18, height: 18)
        case .idle, .pulling:
            ProgressView(value: visibleProgress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(Color.astrenzaAccent)
                .frame(width: 18, height: 18)
        }
    }

    private var title: String {
        switch presentation {
        case .idle, .pulling:
            "Pull to update"
        case .refreshing:
            "Updating"
        case .completed(let didUpdate):
            didUpdate ? "Updated" : "Up to date"
        }
    }

    private var visibleProgress: CGFloat {
        switch presentation {
        case .idle:
            0
        case .pulling(let progress):
            progress
        case .refreshing, .completed:
            1
        }
    }

    private var isVisible: Bool {
        switch presentation {
        case .idle:
            false
        case .pulling(let progress):
            progress > 0.08
        case .refreshing, .completed:
            true
        }
    }

    private var animationPhase: Int {
        switch presentation {
        case .idle:
            0
        case .pulling:
            1
        case .refreshing:
            2
        case .completed:
            3
        }
    }
}
