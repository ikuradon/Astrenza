import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr forward reconnect tracker")
struct NostrForwardReconnectTrackerTests {
    @Test("Reconnect filters advance only after EOSE and retain overlap")
    func reconnectCursorRequiresEOSE() throws {
        let relayURL = "wss://relay.example"
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [[
                "kinds": .ints([1]),
                "authors": .strings([String(repeating: "a", count: 64)]),
                "since": .int(100),
                "limit": .int(250)
            ]],
            relayURLs: [relayURL]
        )
        let first = event(createdAt: 300)
        let second = event(createdAt: 500)
        var tracker = NostrForwardReconnectTracker()

        tracker.record(event: first, relayURL: relayURL, packet: packet)
        let partialReconnect = try #require(tracker.prepareReconnectPackets(
            relayURL: relayURL,
            packets: [packet],
            overlapSeconds: 10
        )[packet.subscriptionID])
        #expect(partialReconnect.filters == packet.filters)

        tracker.record(event: first, relayURL: relayURL, packet: packet)
        tracker.reachedEOSE(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        let completedReconnect = try #require(tracker.prepareReconnectPackets(
            relayURL: relayURL,
            packets: [packet],
            overlapSeconds: 10
        )[packet.subscriptionID])
        #expect(completedReconnect.filters.first?["since"] == .int(290))
        #expect(completedReconnect.filters.first?["limit"] == nil)

        tracker.record(event: second, relayURL: relayURL, packet: packet)
        let interruptedReconnect = try #require(tracker.prepareReconnectPackets(
            relayURL: relayURL,
            packets: [packet],
            overlapSeconds: 10
        )[packet.subscriptionID])
        #expect(interruptedReconnect.filters.first?["since"] == .int(290))

        tracker.record(event: second, relayURL: relayURL, packet: packet)
        tracker.reachedEOSE(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        let nextCompletedReconnect = try #require(tracker.prepareReconnectPackets(
            relayURL: relayURL,
            packets: [packet],
            overlapSeconds: 10
        )[packet.subscriptionID])
        #expect(nextCompletedReconnect.filters.first?["since"] == .int(490))
    }

    @Test("Retry policy uses exponential delay and bounded jitter")
    func retryPolicyUsesExponentialJitter() {
        let policy = NostrRelayRuntimeRetryPolicy(
            maxAttempts: 5,
            initialDelayMilliseconds: 1_000,
            delayStepMilliseconds: 2_000,
            maximumDelayMilliseconds: 30_000,
            jitterPercentage: 20
        )

        #expect(policy.delayNanoseconds(forAttempt: 1, jitterUnit: 0.5) == 1_000_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 2, jitterUnit: 0.5) == 3_000_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 3, jitterUnit: 0.5) == 7_000_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 2, jitterUnit: 0) == 2_400_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 2, jitterUnit: 1) == 3_600_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 20, jitterUnit: 0.5) == 30_000_000_000)
        #expect(policy.delayNanoseconds(forAttempt: 20, jitterUnit: 1) == 30_000_000_000)
    }

    private func event(createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: String(format: "%064x", createdAt),
            pubkey: String(repeating: "a", count: 64),
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: "event \(createdAt)",
            sig: String(repeating: "b", count: 128)
        )
    }
}
