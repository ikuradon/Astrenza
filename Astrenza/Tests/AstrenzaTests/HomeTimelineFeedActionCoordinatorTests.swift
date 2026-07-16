import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline feed action coordinator")
@MainActor
struct HomeTimelineFeedActionCoordinatorTests {
    @Test("Refresh prepares the viewport before applying pending events")
    func refreshPreservesEffectOrder() async {
        let actions = FeedActionHandlerSpy()
        actions.applyPendingResult = true
        let coordinator = HomeTimelineFeedActionCoordinator(actions: actions)
        var calls: [FeedActionCall] = []
        actions.onCall = { calls.append($0) }

        let didRefresh = await coordinator.refresh(context: .liveHome) {
            calls.append(.prepareViewport)
        }

        #expect(didRefresh)
        #expect(calls == [.prepareViewport, .applyPendingEvents])
    }

    @Test("Feed mutations require an account on the Home timeline")
    func feedMutationsRequireLiveHome() async {
        let actions = FeedActionHandlerSpy()
        actions.applyPendingResult = true
        actions.backfillResult = true
        let coordinator = HomeTimelineFeedActionCoordinator(actions: actions)
        let gap = makeGap()
        var prepareCount = 0

        for context in [
            HomeTimelineFeedInteractionContext(
                hasLiveAccount: false,
                timeline: .home
            ),
            HomeTimelineFeedInteractionContext(
                hasLiveAccount: true,
                timeline: .relays
            )
        ] {
            let didRefresh = await coordinator.refresh(context: context) {
                prepareCount += 1
            }
            coordinator.loadOlder(context: context)
            let didBackfill = await coordinator.backfillGap(
                gap,
                direction: .older,
                context: context
            )
            coordinator.setTimelineScrollActive(true, context: context)
            coordinator.markMaterializedPostsRead(
                visiblePostIDs: ["post"],
                context: context
            )

            #expect(!didRefresh)
            #expect(!didBackfill)
        }

        #expect(prepareCount == 0)
        #expect(actions.calls.isEmpty)
    }

    @Test("Live Home forwards pagination and presentation actions")
    func liveHomeForwardsFeedActions() async {
        let actions = FeedActionHandlerSpy()
        actions.backfillResult = true
        let coordinator = HomeTimelineFeedActionCoordinator(actions: actions)
        let gap = makeGap()

        coordinator.loadOlder(context: .liveHome)
        let didBackfill = await coordinator.backfillGap(
            gap,
            direction: .newer,
            context: .liveHome
        )
        coordinator.setTimelineScrollActive(true, context: .liveHome)
        coordinator.markMaterializedPostsRead(
            visiblePostIDs: ["one", "two"],
            context: .liveHome
        )

        #expect(didBackfill)
        #expect(actions.calls == [
            .loadOlder,
            .backfillGap(gap.id, .newer),
            .setScrollActive(true),
            .markPostsRead(["one", "two"])
        ])
    }

    private func makeGap() -> TimelineGap {
        TimelineGap(
            id: "gap",
            newerPostID: "newer",
            olderPostID: "older",
            missingEstimate: 3,
            relayCount: 2,
            state: .needsBackfill,
            backfilledPosts: []
        )
    }
}

private extension HomeTimelineFeedInteractionContext {
    static let liveHome = HomeTimelineFeedInteractionContext(
        hasLiveAccount: true,
        timeline: .home
    )
}

private enum FeedActionCall: Equatable {
    case prepareViewport
    case applyPendingEvents
    case loadOlder
    case backfillGap(String, TimelineGapFillDirection)
    case setScrollActive(Bool)
    case markPostsRead([TimelinePost.ID])
}

@MainActor
private final class FeedActionHandlerSpy: HomeTimelineFeedActionHandling {
    var applyPendingResult = false
    var backfillResult = false
    var onCall: ((FeedActionCall) -> Void)?
    private(set) var calls: [FeedActionCall] = []

    func applyPendingNewEvents() async -> Bool {
        record(.applyPendingEvents)
        return applyPendingResult
    }

    func loadOlder() {
        record(.loadOlder)
    }

    func backfillGap(
        _ gap: TimelineGap,
        direction: TimelineGapFillDirection
    ) async -> Bool {
        record(.backfillGap(gap.id, direction))
        return backfillResult
    }

    func setTimelineScrollActive(_ isActive: Bool) {
        record(.setScrollActive(isActive))
    }

    func markMaterializedPostsRead(
        visiblePostIDs: [TimelinePost.ID]
    ) {
        record(.markPostsRead(visiblePostIDs))
    }

    private func record(_ call: FeedActionCall) {
        calls.append(call)
        onCall?(call)
    }
}
