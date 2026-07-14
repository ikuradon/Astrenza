import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline feed sync coordinator")
struct HomeTimelineFeedSyncCoordinatorTests {
    @Test("Backward requests retain provenance and supersede the previous attempt")
    @MainActor
    func backwardRequestProvenanceAndSupersession() throws {
        let eventStore = try NostrEventStore.inMemory()
        let registry = HomeTimelineBackwardRequestRegistry()
        let coordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: registry,
            now: { 500 }
        )
        let definition = try feedDefinition()
        let context = HomeFeedRuntimeContext(definition: definition)
        try eventStore.saveFeedDefinition(definition)
        let packet = NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [["authors": .strings(Array(context.allowedAuthors)), "kinds": .ints([1, 6])]],
            relayURLs: ["wss://relay.example"],
            groupID: "astrenza-older-notes-test",
            subscriptionID: "astrenza-older-notes-test-req"
        )
        registry.registerOlderPage(
            groupID: packet.groupID,
            context: context,
            anchorEventID: "anchor"
        )
        let registration = try #require(coordinator.registration(for: packet))
        #expect(registration.direction == .backward)
        #expect(registration.purpose == .older)
        #expect(registration.pendingRequestKey == packet.groupID)

        let firstAttempt = NostrRelayRequestAttempt(
            requestID: "request-1",
            relayURL: "wss://relay.example",
            packet: packet,
            startedAt: 10
        )
        let firstStart = coordinator.startRequest(
            firstAttempt,
            isCurrentFeedContext: { $0 == context }
        )
        #expect(firstStart.wasHandled)
        #expect(!firstStart.isRealtime)
        #expect(firstStart.failureMessage == nil)
        coordinator.recordRequestInstalled(requestID: firstAttempt.requestID, installedAt: 11)
        coordinator.record(
            event(idSeed: "1", createdAt: 100),
            relayURL: firstAttempt.relayURL,
            subscriptionID: packet.subscriptionID
        )

        let secondAttempt = NostrRelayRequestAttempt(
            requestID: "request-2",
            relayURL: firstAttempt.relayURL,
            packet: packet,
            startedAt: 20
        )
        let secondStart = coordinator.startRequest(
            secondAttempt,
            isCurrentFeedContext: { $0 == context }
        )
        #expect(secondStart.wasHandled)
        #expect(secondStart.failureMessage == nil)
        coordinator.record(
            event(idSeed: "2", createdAt: 90),
            relayURL: secondAttempt.relayURL,
            subscriptionID: packet.subscriptionID
        )
        let transition = coordinator.handleStreamCompletion(
            relayURL: secondAttempt.relayURL,
            subscriptionID: packet.subscriptionID,
            completion: .timeout(message: "timed out")
        )
        #expect(!transition.isRealtime)
        #expect(transition.diagnostic.kind == .timeout)
        #expect(transition.diagnostic.eventCount == 1)
        #expect(transition.diagnostic.newestCreatedAt == 90)
        #expect(transition.diagnostic.oldestCreatedAt == 90)

        let request = try #require(registry.request(for: packet.groupID))
        #expect(request.sourceRequestIDs == ["request-1", "request-2"])
        let requests = try eventStore.feedSyncRequests(feedID: definition.feedID)
        let first = try #require(requests.first { $0.requestID == firstAttempt.requestID })
        let second = try #require(requests.first { $0.requestID == secondAttempt.requestID })
        #expect(first.endReason == .superseded)
        #expect(first.endedAt == secondAttempt.startedAt)
        #expect(first.installedAt == 11)
        #expect(first.eventCount == 1)
        #expect(second.endReason == .timeout)
        #expect(second.endedAt == 500)
        #expect(second.eventCount == 1)
        #expect(second.endMessage == "timed out")
        #expect(coordinator.activeRequestCount == 0)
        #expect(coordinator.activeContextCount == 0)
    }

    @Test("Realtime requires EOSE from every expected forward subscription")
    @MainActor
    func forwardRealtimeRequiresEveryEOSE() throws {
        let eventStore = try NostrEventStore.inMemory()
        let registry = HomeTimelineBackwardRequestRegistry()
        let coordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: registry,
            now: { 700 }
        )
        let definition = try feedDefinition()
        let context = HomeFeedRuntimeContext(definition: definition)
        try eventStore.saveFeedDefinition(definition)
        let firstPacket = forwardPacket(suffix: "one", since: nil)
        let secondPacket = forwardPacket(suffix: "two", since: 50)
        coordinator.registerForwardContext(context, groupID: firstPacket.groupID)
        coordinator.registerForwardContext(context, groupID: secondPacket.groupID)
        let firstKey = RuntimeSubscriptionKey(
            relayURL: "wss://one.example",
            subscriptionID: firstPacket.subscriptionID
        )
        let secondKey = RuntimeSubscriptionKey(
            relayURL: "wss://two.example",
            subscriptionID: secondPacket.subscriptionID
        )
        coordinator.prepareForwardSubscriptions([firstKey, secondKey])

        let firstRegistration = try #require(coordinator.registration(for: firstPacket))
        let secondRegistration = try #require(coordinator.registration(for: secondPacket))
        #expect(firstRegistration.purpose == .initial)
        #expect(secondRegistration.purpose == .newer)
        let firstAttempt = NostrRelayRequestAttempt(
            requestID: "forward-1",
            relayURL: firstKey.relayURL,
            packet: firstPacket,
            startedAt: 10
        )
        let secondAttempt = NostrRelayRequestAttempt(
            requestID: "forward-2",
            relayURL: secondKey.relayURL,
            packet: secondPacket,
            startedAt: 11
        )
        let firstStart = coordinator.startRequest(
            firstAttempt,
            isCurrentFeedContext: { $0 == context }
        )
        let secondStart = coordinator.startRequest(
            secondAttempt,
            isCurrentFeedContext: { $0 == context }
        )
        #expect(firstStart.wasHandled)
        #expect(secondStart.wasHandled)
        coordinator.record(
            event(idSeed: "3", createdAt: 100),
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID
        )
        let firstEOSE = coordinator.handleStreamCompletion(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID,
            completion: .eose
        )
        #expect(!firstEOSE.isRealtime)
        #expect(firstEOSE.diagnostic.kind == .eose)
        #expect(firstEOSE.diagnostic.eventCount == 1)
        #expect(firstEOSE.diagnostic.newestCreatedAt == 100)
        #expect(firstEOSE.diagnostic.oldestCreatedAt == 100)

        let secondEOSE = coordinator.handleStreamCompletion(
            relayURL: secondKey.relayURL,
            subscriptionID: secondKey.subscriptionID,
            completion: .eose
        )
        #expect(secondEOSE.isRealtime)
        #expect(secondEOSE.diagnostic.eventCount == 0)
        #expect(coordinator.activeRequestCount == 2)
        #expect(coordinator.context(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID
        ) == context)

        let closed = coordinator.handleStreamCompletion(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID,
            completion: .closed(message: "closed")
        )
        #expect(!closed.isRealtime)
        #expect(closed.diagnostic.kind == .closed)
        #expect(coordinator.activeRequestCount == 1)

        let requests = try eventStore.feedSyncRequests(feedID: definition.feedID)
        let first = try #require(requests.first { $0.requestID == firstAttempt.requestID })
        let second = try #require(requests.first { $0.requestID == secondAttempt.requestID })
        #expect(first.eoseAt == 700)
        #expect(first.eventCount == 1)
        #expect(first.endReason == .closed)
        #expect(second.eoseAt == 700)
        #expect(second.eventCount == 0)

        coordinator.reset(finishingActiveRequestsWith: .cancelled)
        #expect(coordinator.activeRequestCount == 0)
        #expect(coordinator.activeContextCount == 0)
        let cancelled = try #require(
            try eventStore.feedSyncRequests(feedID: definition.feedID).first {
                $0.requestID == secondAttempt.requestID
            }
        )
        #expect(cancelled.endReason == .cancelled)
        #expect(cancelled.endedAt == 700)
    }

    @Test("Request start reports persistence failure without activating runtime state")
    @MainActor
    func requestStartReportsPersistenceFailure() throws {
        let eventStore = try NostrEventStore.inMemory()
        let registry = HomeTimelineBackwardRequestRegistry()
        let coordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: registry
        )
        let definition = try feedDefinition()
        let context = HomeFeedRuntimeContext(definition: definition)
        let packet = forwardPacket(suffix: "missing-definition", since: nil)
        coordinator.registerForwardContext(context, groupID: packet.groupID)
        coordinator.prepareForwardSubscriptions([
            RuntimeSubscriptionKey(
                relayURL: "wss://relay.example",
                subscriptionID: packet.subscriptionID
            )
        ])
        let attempt = NostrRelayRequestAttempt(
            requestID: "missing-definition",
            relayURL: "wss://relay.example",
            packet: packet,
            startedAt: 10
        )

        let result = coordinator.startRequest(
            attempt,
            isCurrentFeedContext: { $0 == context }
        )

        #expect(result.wasHandled)
        #expect(!result.isRealtime)
        #expect(result.failureMessage != nil)
        #expect(coordinator.activeRequestCount == 0)
        #expect(coordinator.activeContextCount == 0)
        #expect(try eventStore.feedSyncRequests(feedID: definition.feedID).isEmpty)
    }

    @Test("CLOSED diagnostics distinguish authentication and payment requirements")
    @MainActor
    func classifiesClosedDiagnostics() {
        let coordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: nil,
            backwardRequestRegistry: HomeTimelineBackwardRequestRegistry()
        )

        let authentication = coordinator.handleStreamCompletion(
            relayURL: "wss://relay.example",
            subscriptionID: "auth",
            completion: .closed(message: "auth-required: challenge")
        )
        let payment = coordinator.handleStreamCompletion(
            relayURL: "wss://relay.example",
            subscriptionID: "payment",
            completion: .closed(message: "payment required")
        )
        let ordinary = coordinator.handleStreamCompletion(
            relayURL: "wss://relay.example",
            subscriptionID: "ordinary",
            completion: .closed(message: "rate limited")
        )

        #expect(authentication.diagnostic.kind == .authRequired)
        #expect(payment.diagnostic.kind == .paymentRequired)
        #expect(ordinary.diagnostic.kind == .closed)
    }

    @Test("Current gap request persists its requested boundary and source provenance")
    @MainActor
    func gapRequestPersistsBoundaryAndProvenance() throws {
        let eventStore = try NostrEventStore.inMemory()
        let registry = HomeTimelineBackwardRequestRegistry()
        let coordinator = HomeTimelineFeedSyncCoordinator(
            eventStore: eventStore,
            backwardRequestRegistry: registry
        )
        let definition = try feedDefinition()
        let context = HomeFeedRuntimeContext(definition: definition)
        let newer = event(idSeed: "7", createdAt: 200)
        let older = event(idSeed: "8", createdAt: 100)
        try eventStore.save(events: [newer, older], receivedAt: 5)
        try eventStore.replaceFeedProjection(
            definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [newer, older],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "test",
                insertedAt: 5
            )
        )
        try eventStore.markFeedGap(
            feedID: definition.feedID,
            revision: definition.revision,
            newerEventID: newer.id,
            olderEventID: older.id,
            state: .unresolved,
            at: 6
        )
        let packet = NostrREQPacket.backward(
            purpose: "gap-notes",
            filters: [["authors": .strings(Array(context.allowedAuthors)), "kinds": .ints([1, 6])]],
            relayURLs: ["wss://relay.example"],
            groupID: "astrenza-gap-notes-test",
            subscriptionID: "astrenza-gap-notes-test-req"
        )
        registry.registerGap(
            groupID: packet.groupID,
            context: context,
            newerEventID: newer.id,
            olderEventID: older.id,
            direction: .older
        )
        let attempt = NostrRelayRequestAttempt(
            requestID: "gap-request",
            relayURL: "wss://relay.example",
            packet: packet,
            startedAt: 10
        )

        let result = coordinator.startRequest(
            attempt,
            isCurrentFeedContext: { $0 == context }
        )

        #expect(result.wasHandled)
        #expect(result.failureMessage == nil)
        let gap = try #require(try eventStore.feedGaps(
            feedID: definition.feedID,
            revision: definition.revision
        ).first)
        #expect(gap.state == .requested)
        #expect(gap.sourceRequestID == attempt.requestID)
        #expect(gap.updatedAt == attempt.startedAt)
    }

    private func feedDefinition() throws -> NostrFeedDefinitionRecord {
        let specification = try JSONEncoder().encode(
            HomeFeedSpecification(authors: [String(repeating: "a", count: 64)], kinds: [1, 6])
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:account",
            accountID: "account",
            kind: "home",
            specificationJSON: specification,
            specificationHash: "specification",
            revision: 3,
            createdAt: 1,
            updatedAt: 1
        )
    }

    private func forwardPacket(suffix: String, since: Int?) -> NostrREQPacket {
        var filter: [String: AnySendableJSON] = [
            "authors": .strings([String(repeating: "a", count: 64)]),
            "kinds": .ints([1, 6])
        ]
        if let since {
            filter["since"] = .int(since)
        }
        return .forward(
            subscriptionID: "astrenza-home-forward-\(suffix)",
            filters: [filter]
        )
    }

    private func event(idSeed: String, createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idSeed, count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: idSeed,
            sig: String(repeating: "b", count: 128)
        )
    }
}
