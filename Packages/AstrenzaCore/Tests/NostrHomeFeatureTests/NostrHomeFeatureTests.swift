import NostrHomeFeature
import NostrRelay
import Testing

@Suite("home feature contract")
struct NostrHomeFeatureTests {
    @Test("dependency queue keeps relay hints scoped by dependency type")
    func batchesDependenciesByRelayHint() {
        let profile = String(repeating: "a", count: 64)
        let eventID = String(repeating: "b", count: 64)
        var queue = NostrDependencyFetchQueue()

        let enqueued = queue.enqueue(
            dependencies: NostrEventDependencies(
                profilePubkeys: [profile],
                sourceEventIDs: [eventID],
                profileRelayURLsByPubkey: [profile: ["wss://profiles.example"]],
                sourceRelayURLsByEventID: [eventID: ["wss://events.example"]]
            ),
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://fallback.example"],
            now: 100
        )
        let batch = queue.drain()

        #expect(enqueued)
        #expect(batch.profileGroups == [
            NostrDependencyFetchGroup(
                relayURLs: ["wss://profiles.example"],
                values: [profile]
            )
        ])
        #expect(batch.sourceGroups == [
            NostrDependencyFetchGroup(
                relayURLs: ["wss://events.example"],
                values: [eventID]
            )
        ])
    }
}
