import SwiftUI
import UIKit

enum TimelinePullRefreshPresentation: Equatable {
    case idle
    case pulling(progress: CGFloat)
    case refreshing
    case completed(didUpdate: Bool)
}

struct TimelineFeedCollectionMetrics: Equatable {
    let topContentPadding: CGFloat
    let bottomContentPadding: CGFloat

    static let home = TimelineFeedCollectionMetrics(
        topContentPadding: 72,
        bottomContentPadding: 124
    )

    static let profile = TimelineFeedCollectionMetrics(
        topContentPadding: 0,
        bottomContentPadding: 132
    )
}

@MainActor
struct TimelineFeedLeadingContent {
    let renderRevision: Int
    let geometryRevision: Int
    let rootView: AnyView
}

@MainActor
struct TimelineFeedCollectionConfiguration {
    let entries: [TimelineFeedEntry]
    let leadingContent: TimelineFeedLeadingContent?
    let metrics: TimelineFeedCollectionMetrics
    let sourceIdentity: String
    let sourceRevision: Int
    let viewportIdentity: TimelineFeedViewportIdentity
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let scrollCommand: TimelineScrollCommand?
    let viewportRestoreProtectionActive: Bool
    let followsRealtimeEntries: Bool
    let layoutCache: TimelineLayoutCache
    let unreadCountAnchorPostID: TimelinePost.ID?
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
    let onUnreadPillPlacementChanged: (HomeUnreadPillPlacement) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void
    let onPullRefreshPresentationChanged:
        (TimelinePullRefreshPresentation) -> Void
}

struct TimelineFeedCollectionView: UIViewControllerRepresentable {
    let configuration: TimelineFeedCollectionConfiguration

    func makeUIViewController(context: Context) -> TimelineFeedViewController {
        let controller = TimelineFeedViewController()
        controller.apply(configuration)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: TimelineFeedViewController,
        context: Context
    ) {
        uiViewController.apply(configuration)
    }

    static func dismantleUIViewController(
        _ uiViewController: TimelineFeedViewController,
        coordinator: Void
    ) {
        uiViewController.prepareForRemoval()
    }
}
