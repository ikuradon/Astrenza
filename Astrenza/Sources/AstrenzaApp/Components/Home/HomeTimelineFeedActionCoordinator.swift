import AstrenzaCore

@MainActor
protocol HomeTimelineFeedActionHandling: AnyObject {
    @discardableResult
    func applyPendingNewEvents() async -> Bool

    func loadOlder()

    func backfillGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) async -> Bool

    func setTimelineScrollActive(_ isActive: Bool)

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID]
    )
}

extension NostrHomeTimelineStore: HomeTimelineFeedActionHandling {}

@MainActor
final class HomeTimelineFeedActionCoordinator {
    private let actions: any HomeTimelineFeedActionHandling

    init(actions: any HomeTimelineFeedActionHandling) {
        self.actions = actions
    }

    func refresh(
        context: HomeTimelineInteractionContext,
        prepareViewport: () -> Void
    ) async -> Bool {
        guard context.canMutateLiveHome else { return false }
        prepareViewport()
        return await actions.applyPendingNewEvents()
    }

    func loadOlder(context: HomeTimelineInteractionContext) {
        guard context.canMutateLiveHome else { return }
        actions.loadOlder()
    }

    func backfillGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection,
        context: HomeTimelineInteractionContext
    ) async -> Bool {
        guard context.canMutateLiveHome else { return false }
        return await actions.backfillGap(gap, direction: direction)
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        actions.setTimelineScrollActive(isActive)
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        actions.markMaterializedPostsRead(visiblePostIDs: visiblePostIDs)
    }
}
