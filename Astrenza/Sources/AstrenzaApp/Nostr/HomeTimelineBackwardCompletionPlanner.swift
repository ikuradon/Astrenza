import AstrenzaCore

struct HomeTimelineBackwardCompletionPlan: Equatable, Sendable {
    struct OlderPageUpdate: Equatable, Sendable {
        let request: PendingBackwardRequest
        let anchorEventID: String?
        let marksBoundaryGap: Bool
    }

    enum GapUpdate: Equatable, Sendable {
        case reconcile(
            gap: PendingGapBackfill,
            context: HomeFeedRuntimeContext
        )
        case restore(
            gap: PendingGapBackfill,
            context: HomeFeedRuntimeContext,
            marksUnresolved: Bool
        )
    }

    let acceptsTimelineRequest: Bool
    let marksOlderEnd: Bool
    let olderPageUpdate: OlderPageUpdate?
    let gapUpdate: GapUpdate?
}

struct HomeTimelineBackwardCompletionPlanner: Sendable {
    struct Input: Sendable {
        let request: PendingBackwardRequest
        let completion: NostrBackwardREQCompletion
        let fallbackBottomEventID: String?
        let isCurrentFeedContext: Bool
    }

    func plan(_ input: Input) -> HomeTimelineBackwardCompletionPlan {
        let request = input.request
        let isTimelineBackfill = request.isOlderPage || request.gap != nil
        guard !isTimelineBackfill || input.isCurrentFeedContext else {
            return HomeTimelineBackwardCompletionPlan(
                acceptsTimelineRequest: false,
                marksOlderEnd: false,
                olderPageUpdate: nil,
                gapUpdate: nil
            )
        }

        let didReceiveTimelineEvents = input.completion.eventCount > 0 ||
            request.receivedTimelineEventCount > 0 ||
            !request.receivedTimelineEventIDs.isEmpty
        let completesCandidateCoverage = request.completesCandidateCoverage(
            with: input.completion
        )
        let olderPageUpdate: HomeTimelineBackwardCompletionPlan.OlderPageUpdate?
        if request.isOlderPage, didReceiveTimelineEvents {
            olderPageUpdate = HomeTimelineBackwardCompletionPlan.OlderPageUpdate(
                request: request,
                anchorEventID: request.olderAnchorPostID ?? input.fallbackBottomEventID,
                marksBoundaryGap: completesCandidateCoverage &&
                    input.completion.status != .completed
            )
        } else {
            olderPageUpdate = nil
        }

        let gapUpdate: HomeTimelineBackwardCompletionPlan.GapUpdate?
        if completesCandidateCoverage,
           let gap = request.gap,
           let context = request.feedContext {
            if input.completion.status == .completed {
                gapUpdate = .reconcile(gap: gap, context: context)
            } else {
                gapUpdate = .restore(
                    gap: gap,
                    context: context,
                    marksUnresolved: input.completion.status == .partial || didReceiveTimelineEvents
                )
            }
        } else {
            gapUpdate = nil
        }

        return HomeTimelineBackwardCompletionPlan(
            acceptsTimelineRequest: true,
            marksOlderEnd: completesCandidateCoverage &&
                request.isOlderPage &&
                input.completion.status == .completed &&
                !didReceiveTimelineEvents,
            olderPageUpdate: olderPageUpdate,
            gapUpdate: gapUpdate
        )
    }
}
