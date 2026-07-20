import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Compose emoji resolver")
struct NostrComposeEmojiResolverTests {
    @Test("Resolver follows kind 10030 relay hints and stores kind 30030")
    func resolverUsesEmojiSetRelayHint() async throws {
        let accountID = String(repeating: "a", count: 64)
        let setAuthor = String(repeating: "b", count: 64)
        let baseRelay = "wss://base.example"
        let hintRelay = "wss://emoji.example"
        let list = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: accountID,
            createdAt: 100,
            kind: 10_030,
            tags: [[
                "a",
                "30030:\(setAuthor):party",
                hintRelay
            ]],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
        let set = NostrEvent(
            id: String(repeating: "2", count: 64),
            pubkey: setAuthor,
            createdAt: 200,
            kind: 30_030,
            tags: [
                ["d", "party"],
                ["title", "Party"],
                ["emoji", "party", "https://emoji.example/party.png"]
            ],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
        let relayClient = ComposeEmojiRelayFetchingStub(eventsByRelay: [
            baseRelay: [list],
            hintRelay: [set]
        ])
        let store = try NostrEventStore.inMemory()
        let resolver = NostrComposeEmojiResolver(
            eventStore: store,
            relayClient: relayClient,
            refreshIntervalSeconds: 0,
            now: { 1_000 }
        )

        #expect(await resolver.resolve(
            accountID: accountID,
            relayURLs: [baseRelay]
        ))
        #expect(try store.latestReplaceableEvent(
            pubkey: accountID,
            kind: 10_030
        )?.id == list.id)
        #expect(try store.latestAddressableEvent(
            kind: 30_030,
            pubkey: setAuthor,
            dTag: "party"
        )?.id == set.id)
        #expect(await relayClient.requestedRelayURLs().contains(hintRelay))
    }
}

private actor ComposeEmojiRelayFetchingStub: NostrRelayFetching {
    private let eventsByRelay: [String: [NostrEvent]]
    private var relayURLs: [String] = []

    init(eventsByRelay: [String: [NostrEvent]]) {
        self.eventsByRelay = eventsByRelay
    }

    func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        _ = request
        relayURLs.append(relayURL)
        return eventsByRelay[relayURL] ?? []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        _ = (relayURL, filter, localEvents, subscriptionID)
        return []
    }

    func requestedRelayURLs() -> [String] {
        relayURLs
    }
}
