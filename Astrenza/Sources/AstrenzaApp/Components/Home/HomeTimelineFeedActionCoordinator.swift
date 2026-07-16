import AstrenzaCore

struct HomeTimelineFeedInteractionContext {
    let hasLiveAccount: Bool
    let timeline: TimelineKind

    var canMutateLiveHome: Bool {
        hasLiveAccount && timeline == .home
    }
}

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
        context: HomeTimelineFeedInteractionContext,
        prepareViewport: () -> Void
    ) async -> Bool {
        guard context.canMutateLiveHome else { return false }
        prepareViewport()
        return await actions.applyPendingNewEvents()
    }

    func loadOlder(context: HomeTimelineFeedInteractionContext) {
        guard context.canMutateLiveHome else { return }
        actions.loadOlder()
    }

    func backfillGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection,
        context: HomeTimelineFeedInteractionContext
    ) async -> Bool {
        guard context.canMutateLiveHome else { return false }
        return await actions.backfillGap(gap, direction: direction)
    }

    func setTimelineScrollActive(
        _ isActive: Bool,
        context: HomeTimelineFeedInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        actions.setTimelineScrollActive(isActive)
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID],
        context: HomeTimelineFeedInteractionContext
    ) {
        guard context.canMutateLiveHome else { return }
        actions.markMaterializedPostsRead(visiblePostIDs: visiblePostIDs)
    }
}
