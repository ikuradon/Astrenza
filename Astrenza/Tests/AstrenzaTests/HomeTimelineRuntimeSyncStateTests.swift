import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline runtime sync state")
struct HomeTimelineRuntimeSyncStateTests {
    @Test("Realtime begins only after every expected relay subscription reaches EOSE")
    func realtimeRequiresEveryExpectedSubscription() {
        let first = RuntimeSubscriptionKey(
            relayURL: "wss://relay-one.example",
            subscriptionID: "home-0"
        )
        let second = RuntimeSubscriptionKey(
            relayURL: "wss://relay-two.example",
            subscriptionID: "home-0"
        )
        var state = HomeTimelineRuntimeSyncState()

        state.prepareForwardSubscriptions([first, second])
        #expect(!state.isRealtime)

        state.markForwardEOSE(first)
        #expect(!state.isRealtime)

        state.markForwardEOSE(second)
        #expect(state.isRealtime)

        state.invalidateForwardSubscriptions(relayURL: first.relayURL)
        #expect(!state.isRealtime)
    }

    @Test("Request lifecycle keeps provenance context and event window atomic")
    func requestLifecycleIsAtomic() throws {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [String(repeating: "a", count: 64)], kinds: [1, 6])
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:account",
            accountID: "account",
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 3,
            createdAt: 1,
            updatedAt: 1
        )
        let context = HomeFeedRuntimeContext(definition: definition)
        let key = RuntimeSubscriptionKey(
            relayURL: "wss://relay.example",
            subscriptionID: "home-0"
        )
        var state = HomeTimelineRuntimeSyncState()

        state.registerForwardContext(context, groupID: "home-group")
        state.activateRequest(key: key, requestID: "request-1", context: context)
        state.record(event(id: "2", createdAt: 20), for: key)
        state.record(event(id: "1", createdAt: 10), for: key)

        #expect(state.forwardContext(groupID: "home-group") == context)
        #expect(state.requestID(for: key) == "request-1")
        #expect(state.context(for: key) == context)
        #expect(state.activeRequestCount == 1)
        let staleRequest = state.takeRequest(for: key, matching: "stale-request")
        #expect(staleRequest == nil)

        let matchingRequest = state.takeRequest(for: key, matching: "request-1")
        let request = try #require(matchingRequest)
        #expect(request.requestID == "request-1")
        #expect(request.context == context)
        #expect(request.window.eventCount == 2)
        #expect(request.window.newestCreatedAt == 20)
        #expect(request.window.oldestCreatedAt == 10)
        #expect(state.activeRequestCount == 0)
        #expect(state.activeContextCount == 0)
    }

    @Test("Materialization permission is conservative across coalesced updates")
    func materializationPermissionMergesConservatively() {
        var state = HomeTimelineMaterializationFollowState()

        state.enqueue(allowsRealtimeFollow: true)
        state.enqueue(allowsRealtimeFollow: true)
        let firstPermission = state.consumePendingPermission()
        let consumedPermission = state.consumePendingPermission()
        #expect(firstPermission)
        #expect(!consumedPermission)

        state.enqueue(allowsRealtimeFollow: true)
        state.enqueue(allowsRealtimeFollow: false)
        state.enqueue(allowsRealtimeFollow: true)
        let mixedPermission = state.consumePendingPermission()
        #expect(!mixedPermission)

        state.didPublish(revision: 4, allowsRealtimeFollow: true)
        #expect(state.sourceRevision == 4)
        state.didPublish(revision: 5, allowsRealtimeFollow: false)
        #expect(state.sourceRevision == nil)
    }

    private func event(id: String, createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: String(repeating: id, count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: "event \(id)",
            sig: String(repeating: "b", count: 128)
        )
    }
}
