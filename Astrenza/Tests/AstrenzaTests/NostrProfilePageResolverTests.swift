import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Nostr profile page resolver")
struct NostrProfilePageResolverTests {
    @Test("Profile resolution stores metadata, follows, and known followers")
    func resolvesProfileProjectionInputs() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let profile = String(repeating: "a", count: 64)
        let followed = String(repeating: "b", count: 64)
        let follower = String(repeating: "c", count: 64)
        let unrelated = String(repeating: "d", count: 64)
        let metadata = event(
            id: "1",
            pubkey: profile,
            createdAt: 300,
            kind: 0,
            content: #"{"about":"hello","banner":"https://images.example/banner.jpg"}"#
        )
        let contactList = event(
            id: "2",
            pubkey: profile,
            createdAt: 301,
            kind: 3,
            tags: [["p", followed]]
        )
        let followerContactList = event(
            id: "3",
            pubkey: follower,
            createdAt: 302,
            kind: 3,
            tags: [["p", profile]]
        )
        let unrelatedContactList = event(
            id: "4",
            pubkey: unrelated,
            createdAt: 303,
            kind: 3,
            tags: [["p", followed]]
        )
        let relay = ProfileRelayFetchingStub(events: [
            metadata,
            contactList,
            followerContactList,
            unrelatedContactList
        ])
        let resolver = NostrProfilePageResolver(
            eventStore: eventStore,
            relayClient: relay,
            refreshIntervalSeconds: 60,
            now: { 1_000 }
        )

        let resolved = await resolver.resolve(
            pubkey: profile,
            relayURLs: ["wss://profiles.example", "wss://profiles.example/"]
        )
        let throttled = await resolver.resolve(
            pubkey: profile,
            relayURLs: ["wss://profiles.example"]
        )

        #expect(resolved)
        #expect(!throttled)
        #expect(try eventStore.latestReplaceableEvent(
            pubkey: profile,
            kind: 0
        )?.id == metadata.id)
        #expect(try eventStore.latestReplaceableEvent(
            pubkey: profile,
            kind: 3
        )?.id == contactList.id)
        #expect(try eventStore.followerCount(of: profile) == 1)
        #expect(try eventStore.followerPubkeys(of: profile, limit: 9) == [
            follower
        ])
        #expect(try eventStore.event(id: unrelatedContactList.id) == nil)
        #expect(await relay.requestCount() == 1)
    }

    private func event(
        id: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]] = [],
        content: String = ""
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}

private actor ProfileRelayFetchingStub: NostrRelayFetching {
    private let events: [NostrEvent]
    private var requests: [NostrRelayRequest] = []

    init(events: [NostrEvent]) {
        self.events = events
    }

    func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        requests.append(request)
        return events
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }

    func requestCount() -> Int {
        requests.count
    }
}
