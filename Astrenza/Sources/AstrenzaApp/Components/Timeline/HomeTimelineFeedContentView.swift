import SwiftUI

struct HomeTimelineFeedContentView: View {
    let store: NostrHomeTimelineStore
    let hasLiveAccount: Bool
    let selectedTimeline: TimelineKind
    let sourceIdentity: String
    let actionMenuTopClearance: CGFloat
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let scrollCommand: TimelineScrollCommand?
    let viewportRestoreProtectionActive: Bool
    let isTimelineAtNewestWindow: Bool
    let isTimelineDetachedFromLiveEdge: Bool
    let layoutCache: TimelineLayoutCache
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
    let onViewportRestoreCompleted: (CGFloat) -> Void
    let onViewportStateChanged: (TimelineViewportState) -> Void
    let onReadablePostIDsChanged: ([TimelinePost.ID]) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void

    var body: some View {
        TimelineFeedView(
            entries: entries,
            sourceIdentity: sourceIdentity,
            sourceRevision: sourceRevision,
            actionMenuTopClearance: actionMenuTopClearance,
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
            onViewportRestoreCompleted: onViewportRestoreCompleted,
            onViewportStateChanged: onViewportStateChanged,
            onReadablePostIDsChanged: onReadablePostIDsChanged,
            onLayoutCacheChanged: onLayoutCacheChanged
        )
    }

    private var entries: [TimelineFeedEntry] {
        guard hasLiveAccount else {
            return MockTimelineData.entries(for: selectedTimeline)
        }
        return HomeTimelineLiveEntryPolicy.entries(
            for: selectedTimeline,
            home: store.entries,
            lists: store.listEntries()
        )
    }

    private var sourceRevision: Int {
        switch selectedTimeline {
        case .home:
            store.resolvedContentRevision
        case .relays:
            0
        case .lists:
            store.listContentRevision
        }
    }

    private var followsRealtimeEntries: Bool {
        guard selectedTimeline == .home else { return false }
        return HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: store.isHomeTimelineRealtime &&
                store.realtimeFollowSourceRevision == sourceRevision,
            isAtNewestWindow: isTimelineAtNewestWindow,
            isRestoreProtected: viewportRestoreProtectionActive,
            isDetachedFromLiveEdge: isTimelineDetachedFromLiveEdge
        )
    }

    private var emptyStateContext: HomeTimelineEmptyStateContext {
        let interaction = HomeTimelineInteractionContext(
            hasLiveAccount: hasLiveAccount,
            timeline: selectedTimeline
        )
        guard interaction.canMutateLiveHome else {
            return HomeTimelineEmptyStateContext(
                interaction: interaction,
                phase: .idle,
                hasFollowedPubkeys: false
            )
        }
        return HomeTimelineEmptyStateContext(
            interaction: interaction,
            phase: store.phase,
            hasFollowedPubkeys: !store.followedPubkeys.isEmpty
        )
    }

    private var emptyState: TimelineEmptyState {
        HomeTimelineEmptyStatePolicy.resolve(emptyStateContext).emptyState
    }
}

enum HomeTimelineLiveEntryPolicy {
    static func entries(
        for timeline: TimelineKind,
        home: @autoclosure () -> [TimelineFeedEntry],
        lists: @autoclosure () -> [TimelineFeedEntry]
    ) -> [TimelineFeedEntry] {
        switch timeline {
        case .home:
            home()
        case .relays:
            []
        case .lists:
            lists()
        }
    }
}
