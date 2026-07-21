import CoreGraphics
import Testing
@testable import Astrenza

@Suite("Timeline feed viewport mutation planner")
struct TimelineFeedViewportMutationPlannerTests {
    private let visibleAnchor = TimelineFeedVisibleAnchor(
        postID: "visible",
        offset: 18
    )
    private let refreshAnchor = TimelineFeedVisibleAnchor(
        postID: "refresh",
        offset: 24
    )

    @Test("Realtime prepend follows newest only when unprotected")
    func realtimePrependFollowsNewest() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(followsRealtimeEntries: true)
        )

        #expect(position == .followNewest(fallback: visibleAnchor))
    }

    @Test("Pull refresh preserves its original anchor over realtime")
    func pullRefreshPreservesOriginalAnchor() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(
                refreshAnchor: refreshAnchor,
                followsRealtimeEntries: true
            )
        )

        #expect(position == .preserve(refreshAnchor))
    }

    @Test("Restore protection preserves the visible anchor")
    func restoreProtectionPreservesVisibleAnchor() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(
                followsRealtimeEntries: true,
                isRestoreProtected: true,
                isRestoreBlocked: true
            )
        )

        #expect(position == .preserve(visibleAnchor))
    }

    @Test("Non-realtime prepend preserves the visible anchor")
    func nonRealtimePrependPreservesVisibleAnchor() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(followsRealtimeEntries: false)
        )

        #expect(position == .preserve(visibleAnchor))
    }

    @Test("Missing anchors leave the collection position unchanged")
    func missingAnchorsLeavePositionUnchanged() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(
                newIDs: ["new", "other"],
                followsRealtimeEntries: false
            )
        )

        #expect(position == .unchanged)
    }

    @Test("Appending older entries never counts as newest prepend")
    func appendingOlderEntriesDoesNotFollowNewest() {
        let position = TimelineFeedViewportMutationPlanner.position(
            for: input(
                newIDs: ["visible", "refresh", "older"],
                followsRealtimeEntries: true
            )
        )

        #expect(position == .preserve(visibleAnchor))
    }

    @Test("Realtime follow commits only while idle at the live edge")
    func realtimeFollowCommitRequiresIdleLiveEdge() {
        let planned = TimelineFeedSnapshotPosition.followNewest(
            fallback: visibleAnchor
        )

        #expect(committedPosition(planned: planned) == planned)
        #expect(committedPosition(
            planned: planned,
            isUserInteractionActive: true
        ) == .unchanged)
        #expect(committedPosition(
            planned: planned,
            contentOffset: 24
        ) == .preserve(visibleAnchor))
        #expect(committedPosition(
            planned: planned,
            followsRealtimeEntries: false
        ) == .preserve(visibleAnchor))
    }

    @Test("An interaction never receives a programmatic anchor correction")
    func activeInteractionLeavesPlannedPreservationUnchanged() {
        let committed = committedPosition(
            planned: .preserve(visibleAnchor),
            isUserInteractionActive: true
        )

        #expect(committed == .unchanged)
    }

    private func input(
        newIDs: [TimelineFeedEntry.ID] = ["new", "visible", "refresh"],
        refreshAnchor: TimelineFeedVisibleAnchor? = nil,
        followsRealtimeEntries: Bool,
        isRestoreProtected: Bool = false,
        isRestoreBlocked: Bool = false
    ) -> TimelineFeedViewportMutationInput {
        TimelineFeedViewportMutationInput(
            oldIDs: ["visible", "refresh"],
            newIDs: newIDs,
            visibleAnchor: visibleAnchor,
            refreshAnchor: refreshAnchor,
            isPullRefreshing: false,
            followsRealtimeEntries: followsRealtimeEntries,
            isRestoreProtected: isRestoreProtected,
            isRestoreBlocked: isRestoreBlocked
        )
    }

    private func committedPosition(
        planned: TimelineFeedSnapshotPosition,
        followsRealtimeEntries: Bool = true,
        isUserInteractionActive: Bool = false,
        contentOffset: CGFloat = 0
    ) -> TimelineFeedSnapshotPosition {
        TimelineFeedSnapshotPositionCommitPlanner.position(
            for: TimelineFeedSnapshotPositionCommitInput(
                plannedPosition: planned,
                followsRealtimeEntries: followsRealtimeEntries,
                isUserInteractionActive: isUserInteractionActive,
                isPullRefreshProtected: false,
                isRestoreProtected: false,
                isRestoreBlocked: false,
                contentOffset: contentOffset
            )
        )
    }
}
