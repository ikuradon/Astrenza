import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline backward completion planner")
struct HomeTimelineBackwardCompletionPlannerTests {
    @Test("A stale feed context rejects timeline completion work")
    func rejectsStaleTimelineContext() throws {
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: olderRequest(context: try context()),
            completion: completion(eventCount: 1),
            fallbackBottomEventID: "bottom",
            isCurrentFeedContext: false
        ))

        #expect(!plan.acceptsTimelineRequest)
        #expect(!plan.marksOlderEnd)
        #expect(plan.olderPageUpdate == nil)
        #expect(plan.gapUpdate == nil)
    }

    @Test("A completed empty older page marks the end without reloading")
    func marksCompletedEmptyOlderPageEnd() throws {
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: olderRequest(context: try context()),
            completion: completion(),
            fallbackBottomEventID: "bottom",
            isCurrentFeedContext: true
        ))

        #expect(plan.acceptsTimelineRequest)
        #expect(plan.marksOlderEnd)
        #expect(plan.olderPageUpdate == nil)
    }

    @Test("A primary candidate EOSE does not mark older history exhausted")
    func primaryCandidateDoesNotMarkOlderEnd() throws {
        let request = PendingBackwardRequest(
            feedContext: try context(),
            isOlderPage: true,
            olderAnchorPostID: "anchor",
            requestedLimit: 100,
            hasRemainingRelayCandidates: true
        )
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: request,
            completion: completion(),
            fallbackBottomEventID: "bottom",
            isCurrentFeedContext: true
        ))

        #expect(plan.acceptsTimelineRequest)
        #expect(!plan.marksOlderEnd)
        #expect(plan.olderPageUpdate == nil)
    }

    @Test("A completed older page with events reloads without creating a boundary gap")
    func reloadsCompletedOlderPage() throws {
        let request = olderRequest(context: try context(), anchorEventID: nil)
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: request,
            completion: completion(eventCount: 1),
            fallbackBottomEventID: "bottom",
            isCurrentFeedContext: true
        ))

        #expect(!plan.marksOlderEnd)
        #expect(plan.olderPageUpdate == .init(
            request: request,
            anchorEventID: "bottom",
            marksBoundaryGap: false
        ))
    }

    @Test("A partial older page uses registry progress and creates a boundary gap")
    func plansPartialOlderPageBoundary() throws {
        let request = PendingBackwardRequest(
            feedContext: try context(),
            isOlderPage: true,
            olderAnchorPostID: "anchor",
            receivedTimelineEventCount: 1,
            receivedTimelineEventIDs: ["received"]
        )
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: request,
            completion: completion(eoseCount: 1, closedCount: 1),
            fallbackBottomEventID: "bottom",
            isCurrentFeedContext: true
        ))

        #expect(plan.olderPageUpdate == .init(
            request: request,
            anchorEventID: "anchor",
            marksBoundaryGap: true
        ))
    }

    @Test("A completed gap starts reconciliation")
    func reconcilesCompletedGap() throws {
        let context = try context()
        let gap = gap()
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: PendingBackwardRequest(feedContext: context, gap: gap),
            completion: completion(),
            fallbackBottomEventID: nil,
            isCurrentFeedContext: true
        ))

        #expect(plan.gapUpdate == .reconcile(gap: gap, context: context))
    }

    @Test("A primary candidate gap EOSE waits for remaining candidates")
    func primaryCandidateGapWaitsForHedge() throws {
        let context = try context()
        let request = PendingBackwardRequest(
            feedContext: context,
            gap: gap(),
            requestedLimit: 10,
            hasRemainingRelayCandidates: true
        )
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: request,
            completion: completion(),
            fallbackBottomEventID: nil,
            isCurrentFeedContext: true
        ))

        #expect(plan.gapUpdate == nil)
    }

    @Test("A partial gap is restored as unresolved")
    func restoresPartialGapAsUnresolved() throws {
        let context = try context()
        let gap = gap()
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: PendingBackwardRequest(feedContext: context, gap: gap),
            completion: completion(eventCount: 1, eoseCount: 1, closedCount: 1),
            fallbackBottomEventID: nil,
            isCurrentFeedContext: true
        ))

        #expect(plan.gapUpdate == .restore(
            gap: gap,
            context: context,
            marksUnresolved: true
        ))
    }

    @Test("A timed out empty gap is restored without overwriting its persisted state")
    func restoresEmptyTimedOutGapWithoutMarking() throws {
        let context = try context()
        let gap = gap()
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: PendingBackwardRequest(feedContext: context, gap: gap),
            completion: completion(eoseCount: 0, timeoutCount: 1),
            fallbackBottomEventID: nil,
            isCurrentFeedContext: true
        ))

        #expect(plan.gapUpdate == .restore(
            gap: gap,
            context: context,
            marksUnresolved: false
        ))
    }

    @Test("A closed gap with registry progress is restored as unresolved")
    func restoresClosedGapWithProgressAsUnresolved() throws {
        let context = try context()
        let gap = gap()
        let request = PendingBackwardRequest(
            feedContext: context,
            gap: gap,
            receivedTimelineEventIDs: ["received"]
        )
        let plan = HomeTimelineBackwardCompletionPlanner().plan(.init(
            request: request,
            completion: completion(eoseCount: 0, closedCount: 1),
            fallbackBottomEventID: nil,
            isCurrentFeedContext: true
        ))

        #expect(plan.gapUpdate == .restore(
            gap: gap,
            context: context,
            marksUnresolved: true
        ))
    }

    private func olderRequest(
        context: HomeFeedRuntimeContext,
        anchorEventID: String? = "anchor"
    ) -> PendingBackwardRequest {
        PendingBackwardRequest(
            feedContext: context,
            isOlderPage: true,
            olderAnchorPostID: anchorEventID
        )
    }

    private func gap() -> PendingGapBackfill {
        PendingGapBackfill(
            newerPostID: "newer",
            olderPostID: "older",
            direction: .older
        )
    }

    private func completion(
        eventCount: Int = 0,
        eoseCount: Int = 1,
        closedCount: Int = 0,
        timeoutCount: Int = 0
    ) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: "request",
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: ["request-relay"],
            eventCount: eventCount,
            eoseCount: eoseCount,
            closedCount: closedCount,
            timeoutCount: timeoutCount
        )
    }

    private func context() throws -> HomeFeedRuntimeContext {
        HomeFeedRuntimeContext(definition: try definition())
    }

    private func definition() throws -> NostrFeedDefinitionRecord {
        let accountID = String(repeating: "a", count: 64)
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [accountID], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 3,
            createdAt: 1,
            updatedAt: 1
        )
    }
}
