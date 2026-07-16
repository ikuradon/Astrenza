import Testing
@testable import AstrenzaCore

@Suite("Nostr relay work scheduler")
struct NostrRelayWorkSchedulerTests {
    @Test("Queued relay work respects capacity and priority")
    func queuesByPriority() async throws {
        let relayURL = try #require(NostrRelayURL("wss://relay.example"))
        let scheduler = NostrRelayWorkScheduler(policy: NostrRelayWorkSchedulerPolicy(
            fallbackMaxSubscriptions: 1,
            queueTimeoutMilliseconds: 500
        ))
        let blocker = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "active",
            priority: .realtime
        )
        try await scheduler.waitUntilActive(blocker)
        let backfill = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "backfill",
            priority: .backfill
        )
        let visible = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "visible",
            priority: .visibleDependency
        )

        var snapshot = await scheduler.snapshot(for: relayURL)
        #expect(snapshot.activeSubscriptionIDs == ["active"])
        #expect(snapshot.queuedSubscriptionIDs == ["visible", "backfill"])

        await scheduler.release(blocker)
        try await scheduler.waitUntilActiveWithPolicyTimeout(visible)
        snapshot = await scheduler.snapshot(for: relayURL)
        #expect(snapshot.activeSubscriptionIDs == ["visible"])
        #expect(snapshot.queuedSubscriptionIDs == ["backfill"])

        await scheduler.release(visible)
        try await scheduler.waitUntilActiveWithPolicyTimeout(backfill)
        #expect(await scheduler.snapshot(for: relayURL).activeSubscriptionIDs == ["backfill"])
    }

    @Test("A lower NIP-11 capacity waits for existing work to drain")
    func appliesPublishedCapacityWithoutRevokingActiveWork() async throws {
        let relayURL = try #require(NostrRelayURL("wss://relay.example"))
        let scheduler = NostrRelayWorkScheduler(policy: NostrRelayWorkSchedulerPolicy(
            fallbackMaxSubscriptions: 3,
            queueTimeoutMilliseconds: 500
        ))
        let active = await (0..<3).asyncMap { index in
            await scheduler.enqueue(
                relayURL: relayURL,
                subscriptionID: "active-\(index)",
                priority: .userInitiated
            )
        }
        for ticket in active {
            try await scheduler.waitUntilActive(ticket)
        }

        await scheduler.setPublishedMaxSubscriptions(1, for: relayURL)
        let queued = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "queued",
            priority: .visibleDependency
        )
        await scheduler.release(active[0])
        await scheduler.release(active[1])
        #expect(await scheduler.snapshot(for: relayURL).queuedSubscriptionIDs == ["queued"])

        await scheduler.release(active[2])
        try await scheduler.waitUntilActiveWithPolicyTimeout(queued)
        let snapshot = await scheduler.snapshot(for: relayURL)
        #expect(snapshot.maxSubscriptions == 1)
        #expect(snapshot.activeSubscriptionIDs == ["queued"])
    }

    @Test("Queue timeout removes work that cannot acquire relay capacity")
    func queueTimeoutReleasesTicket() async throws {
        let relayURL = try #require(NostrRelayURL("wss://relay.example"))
        let scheduler = NostrRelayWorkScheduler(policy: NostrRelayWorkSchedulerPolicy(
            fallbackMaxSubscriptions: 1,
            queueTimeoutMilliseconds: 10
        ))
        let blocker = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "active",
            priority: .realtime
        )
        try await scheduler.waitUntilActive(blocker)
        let queued = await scheduler.enqueue(
            relayURL: relayURL,
            subscriptionID: "queued",
            priority: .maintenance
        )

        await #expect(throws: NostrRelayWorkSchedulerError.self) {
            try await scheduler.waitUntilActiveWithPolicyTimeout(queued)
        }
        #expect(await scheduler.snapshot(for: relayURL).queuedCount == 0)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}
