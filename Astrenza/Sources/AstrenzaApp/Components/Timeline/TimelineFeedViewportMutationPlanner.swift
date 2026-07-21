import Foundation

enum TimelineFeedSnapshotPosition: Equatable {
    case unchanged
    case preserve(TimelineFeedVisibleAnchor)
    case followNewest(fallback: TimelineFeedVisibleAnchor?)
}

struct TimelineFeedViewportMutationInput {
    let oldIDs: [TimelineFeedEntry.ID]
    let newIDs: [TimelineFeedEntry.ID]
    let visibleAnchor: TimelineFeedVisibleAnchor?
    let refreshAnchor: TimelineFeedVisibleAnchor?
    let isPullRefreshing: Bool
    let followsRealtimeEntries: Bool
    let isRestoreProtected: Bool
    let isRestoreBlocked: Bool
}

enum TimelineFeedViewportMutationPlanner {
    static func position(
        for input: TimelineFeedViewportMutationInput
    ) -> TimelineFeedSnapshotPosition {
        if shouldFollowNewest(input) {
            return .followNewest(fallback: input.visibleAnchor)
        }
        if let refreshAnchor = input.refreshAnchor,
           input.newIDs.contains(refreshAnchor.postID) {
            return .preserve(refreshAnchor)
        }
        if let visibleAnchor = input.visibleAnchor,
           input.newIDs.contains(visibleAnchor.postID) {
            return .preserve(visibleAnchor)
        }
        return .unchanged
    }

    static func didPrependNewest(
        oldIDs: [TimelineFeedEntry.ID],
        newIDs: [TimelineFeedEntry.ID]
    ) -> Bool {
        guard let firstOldID = oldIDs.first,
              let firstOldIndex = newIDs.firstIndex(of: firstOldID)
        else { return false }
        return firstOldIndex > 0
    }

    private static func shouldFollowNewest(
        _ input: TimelineFeedViewportMutationInput
    ) -> Bool {
        let isPullRefreshProtected = input.refreshAnchor != nil ||
            input.isPullRefreshing
        return didPrependNewest(
            oldIDs: input.oldIDs,
            newIDs: input.newIDs
        ) && TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: input.followsRealtimeEntries,
            isPullRefreshProtected: isPullRefreshProtected,
            isRestoreProtected: input.isRestoreProtected,
            didRestoreViewport: !input.isRestoreBlocked,
            isRestoringViewport: input.isRestoreBlocked
        )
    }
}

struct TimelineFeedSnapshotPositionCommitInput {
    let plannedPosition: TimelineFeedSnapshotPosition
    let followsRealtimeEntries: Bool
    let isUserInteractionActive: Bool
    let isPullRefreshProtected: Bool
    let isRestoreProtected: Bool
    let isRestoreBlocked: Bool
}

enum TimelineFeedSnapshotPositionCommitPlanner {
    static func position(
        for input: TimelineFeedSnapshotPositionCommitInput
    ) -> TimelineFeedSnapshotPosition {
        guard !input.isUserInteractionActive else { return .unchanged }
        guard case .followNewest(let fallback) = input.plannedPosition else {
            return input.plannedPosition
        }

        let canFollowNewest = input.followsRealtimeEntries &&
            !input.isPullRefreshProtected &&
            !input.isRestoreProtected &&
            !input.isRestoreBlocked
        guard canFollowNewest else {
            return fallback.map(TimelineFeedSnapshotPosition.preserve) ??
                .unchanged
        }
        return input.plannedPosition
    }
}
