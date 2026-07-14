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
        try coordinator.beginRequest(firstAttempt, registration: registration)
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
        try coordinator.beginRequest(secondAttempt, registration: registration)
        coordinator.record(
            event(idSeed: "2", createdAt: 90),
            relayURL: secondAttempt.relayURL,
            subscriptionID: packet.subscriptionID
        )
        let window = coordinator.finishWindow(
            relayURL: secondAttempt.relayURL,
            subscriptionID: packet.subscriptionID
        )
        coordinator.endRequest(
            relayURL: secondAttempt.relayURL,
            subscriptionID: packet.subscriptionID,
            reason: .timeout,
            message: "timed out",
            window: window
        )

        let request = try #require(registry.request(for: packet.groupID))
        #expect(request.sourceRequestIDs == ["request-1", "request-2"])
        let requests = try eventStore.feedSyncRequests(feedID: definition.feedID)
        let first = try #require(requests.first { $0.requestID == firstAttempt.requestID })
        let second = try #require(requests.first { $0.requestID == secondAttempt.requestID })
        #expect(first.endReason == .superseded)
        #expect(first.endedAt == secondAttempt.startedAt)
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
        try coordinator.beginRequest(firstAttempt, registration: firstRegistration)
        try coordinator.beginRequest(secondAttempt, registration: secondRegistration)
        coordinator.record(
            event(idSeed: "3", createdAt: 100),
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID
        )
        let firstWindow = coordinator.finishWindow(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID
        )
        coordinator.recordEOSE(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID,
            window: firstWindow
        )
        #expect(!coordinator.isRealtime)

        let secondWindow = coordinator.finishWindow(
            relayURL: secondKey.relayURL,
            subscriptionID: secondKey.subscriptionID
        )
        coordinator.recordEOSE(
            relayURL: secondKey.relayURL,
            subscriptionID: secondKey.subscriptionID,
            window: secondWindow
        )
        #expect(coordinator.isRealtime)
        #expect(coordinator.activeRequestCount == 2)
        #expect(coordinator.context(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID
        ) == context)

        coordinator.endRequest(
            relayURL: firstKey.relayURL,
            subscriptionID: firstKey.subscriptionID,
            reason: .closed,
            message: "closed",
            window: RuntimeSyncWindow()
        )
        #expect(!coordinator.isRealtime)
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
