import Foundation

enum TimelineFeedSnapshotPosition: Equatable {
    case unchanged
    case preserve(TimelineFeedVisibleAnchor)
    case newest
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
            return .newest
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
