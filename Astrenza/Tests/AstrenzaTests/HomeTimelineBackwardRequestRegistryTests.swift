import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline backward request registry")
struct HomeTimelineBackwardRequestRegistryTests {
    @Test("Subscription IDs resolve exact, relay-suffixed, and strategy fallback requests")
    @MainActor
    func resolvesSubscriptionIDs() throws {
        let registry = HomeTimelineBackwardRequestRegistry()
        let context = try feedContext()
        registry.registerOlderPage(
            groupID: "older-group",
            context: context,
            anchorEventID: "anchor"
        )
        registry.registerGap(
            groupID: "gap-group",
            context: context,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .older
        )

        #expect(registry.requestState == HomeTimelineBackwardRequestState(
            requestCount: 2,
            hasOlderPageRequest: true,
            hasGapWork: true,
            hasRequests: true
        ))
        #expect(registry.key(for: "older-group") == "older-group")
        #expect(registry.key(for: "older-group-relay-1") == "older-group")
        #expect(registry.key(for: "astrenza-older-notes-relay-1") == "older-group")
        #expect(registry.key(for: "astrenza-gap-notes-relay-1") == "gap-group")
        #expect(registry.key(for: "unrelated") == nil)
    }

    @Test("Request progress is accumulated and removed as one value")
    @MainActor
    func accumulatesAndRemovesRequestProgress() throws {
        let registry = HomeTimelineBackwardRequestRegistry()
        let context = try feedContext()
        registry.registerOlderPage(
            groupID: "older-group",
            context: context,
            anchorEventID: "anchor"
        )

        registry.appendSourceRequestID("source-1", for: "older-group")
        registry.appendSourceRequestID("source-2", for: "older-group")
        registry.recordTimelineEvent("event-1", for: "older-group")
        registry.recordTimelineEvent("event-1", for: "older-group")
        registry.recordTimelineEvent("event-2", for: "older-group")

        let request = try #require(registry.remove(groupID: "older-group"))
        #expect(request.receivedTimelineEventCount == 3)
        #expect(request.receivedTimelineEventIDs == ["event-1", "event-2"])
        #expect(request.sourceRequestIDs == ["source-1", "source-2"])
        #expect(request.olderAnchorPostID == "anchor")
        #expect(registry.requestCount == 0)
        #expect(!registry.hasRequests)
    }

    @Test("Gap activity covers queued requests and active reconciliation")
    @MainActor
    func tracksGapActivityAcrossPhases() throws {
        let registry = HomeTimelineBackwardRequestRegistry()
        let context = try feedContext()
        registry.registerGap(
            groupID: "gap-group",
            context: context,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .newer
        )

        #expect(registry.hasGapWork)
        let request = try #require(registry.remove(groupID: "gap-group"))
        let gap = try #require(request.gap)
        #expect(!registry.hasGapWork)

        let reconciliationID = registry.beginGapReconciliation(gap: gap, context: context)
        let duplicateID = registry.beginGapReconciliation(gap: gap, context: context)
        #expect(reconciliationID == duplicateID)
        #expect(registry.hasGapWork)
        #expect(registry.activeGapReconciliationCount == 1)

        registry.endGapReconciliation(reconciliationID)
        #expect(!registry.hasGapWork)

        registry.registerOlderPage(
            groupID: "older-group",
            context: context,
            anchorEventID: nil
        )
        #expect(registry.hasOlderPageRequest)
        registry.reset()
        #expect(registry.requestState == .idle)
    }

    @Test("Completion resumes a terminal waiter and preserves early completion")
    @MainActor
    func deliversTerminalCompletion() async throws {
        let registry = HomeTimelineBackwardRequestRegistry()
        let context = try feedContext()
        registry.registerOlderPage(
            groupID: "waiting",
            context: context,
            anchorEventID: "anchor"
        )
        let waiter = Task {
            await registry.waitForCompletion(groupID: "waiting")
        }
        await Task.yield()
        let waitingCompletion = completion(groupID: "waiting")

        let request = registry.complete(waitingCompletion)
        let received = await waiter.value

        #expect(request?.isOlderPage == true)
        #expect(received == waitingCompletion)

        registry.registerGap(
            groupID: "early",
            context: context,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .newer
        )
        let earlyCompletion = completion(groupID: "early", timeoutCount: 1)
        registry.complete(earlyCompletion)
        let receivedEarly = await registry.waitForCompletion(groupID: "early")

        #expect(receivedEarly == earlyCompletion)
    }

    @Test("Reset releases a terminal waiter without a false completion")
    @MainActor
    func resetReleasesWaiter() async throws {
        let registry = HomeTimelineBackwardRequestRegistry()
        registry.registerOlderPage(
            groupID: "waiting",
            context: try feedContext(),
            anchorEventID: nil
        )
        let waiter = Task {
            await registry.waitForCompletion(groupID: "waiting")
        }
        await Task.yield()

        registry.reset()
        let received = await waiter.value

        #expect(received == nil)
        #expect(registry.requestState == .idle)
    }

    private func completion(
        groupID: String,
        timeoutCount: Int = 0
    ) -> NostrBackwardREQCompletion {
        NostrBackwardREQCompletion(
            groupID: groupID,
            relayURLs: ["wss://relay.example"],
            subscriptionIDs: ["\(groupID)-relay"],
            eventCount: 0,
            eoseCount: timeoutCount == 0 ? 1 : 0,
            closedCount: 0,
            timeoutCount: timeoutCount
        )
    }

    private func feedContext() throws -> HomeFeedRuntimeContext {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [String(repeating: "a", count: 64)], kinds: [1, 6])
        )
        return HomeFeedRuntimeContext(
            definition: NostrFeedDefinitionRecord(
                feedID: "feed:home:account",
                accountID: "account",
                kind: "home",
                specificationJSON: specification,
                specificationHash: "specification",
                revision: 3,
                createdAt: 1,
                updatedAt: 1
            )
        )
    }
}
