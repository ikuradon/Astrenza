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

    @Test("A complete fresh catalog is served without relay requests")
    func completeFreshCatalogUsesPersistentCache() async throws {
        let accountID = String(repeating: "a", count: 64)
        let setAuthor = String(repeating: "b", count: 64)
        let list = emojiList(accountID: accountID, setAuthor: setAuthor)
        let set = emojiSet(author: setAuthor, dTag: "party")
        let store = try NostrEventStore.inMemory()
        try store.ingest(
            events: [list, set],
            eventSources: [list, set].map {
                NostrEventSourceRecord(
                    eventID: $0.id,
                    relayURL: "wss://cache.example",
                    firstSeenAt: 950,
                    lastSeenAt: 950
                )
            },
            feedMemberships: [],
            receivedAt: 950
        )
        let relayClient = ComposeEmojiRelayFetchingStub(eventsByRelay: [:])
        let resolver = NostrComposeEmojiResolver(
            eventStore: store,
            relayClient: relayClient,
            refreshIntervalSeconds: 0,
            cacheRefreshIntervalSeconds: 60,
            now: { 1_000 }
        )

        #expect(!(await resolver.resolve(
            accountID: accountID,
            relayURLs: ["wss://base.example"]
        )))
        #expect(await relayClient.requestedRelayURLs().isEmpty)
    }

    @Test("Only missing emoji sets are requested from their hints")
    func resolverFetchesOnlyMissingSets() async throws {
        let accountID = String(repeating: "a", count: 64)
        let existingAuthor = String(repeating: "b", count: 64)
        let missingAuthor = String(repeating: "c", count: 64)
        let existingRelay = "wss://existing.example"
        let missingRelay = "wss://missing.example"
        let list = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: accountID,
            createdAt: 100,
            kind: 10_030,
            tags: [
                ["a", "30030:\(existingAuthor):party", existingRelay],
                ["a", "30030:\(missingAuthor):animals", missingRelay]
            ],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
        let existingSet = emojiSet(author: existingAuthor, dTag: "party")
        let missingSet = emojiSet(author: missingAuthor, dTag: "animals", id: "3")
        let store = try NostrEventStore.inMemory()
        try store.ingest(
            events: [list, existingSet],
            eventSources: [list, existingSet].map {
                NostrEventSourceRecord(
                    eventID: $0.id,
                    relayURL: "wss://cache.example",
                    firstSeenAt: 950,
                    lastSeenAt: 950
                )
            },
            feedMemberships: [],
            receivedAt: 950
        )
        let relayClient = ComposeEmojiRelayFetchingStub(eventsByRelay: [
            missingRelay: [missingSet]
        ])
        let resolver = NostrComposeEmojiResolver(
            eventStore: store,
            relayClient: relayClient,
            refreshIntervalSeconds: 0,
            cacheRefreshIntervalSeconds: 60,
            now: { 1_000 }
        )

        #expect(await resolver.resolve(
            accountID: accountID,
            relayURLs: ["wss://base.example"]
        ))
        let requestedRelays = await relayClient.requestedRelayURLs()
        #expect(requestedRelays.contains(missingRelay))
        #expect(!requestedRelays.contains(existingRelay))
        #expect(try store.latestAddressableEvent(
            kind: 30_030,
            pubkey: missingAuthor,
            dTag: "animals"
        )?.id == missingSet.id)
    }

    @Test("Compose treats a fully cached catalog as resolved")
    func completeCatalogDoesNotRequireResolvingPresentation() {
        let accountID = String(repeating: "a", count: 64)
        let setAuthor = String(repeating: "b", count: 64)
        let list = emojiList(accountID: accountID, setAuthor: setAuthor)
        let set = emojiSet(author: setAuthor, dTag: "party")

        #expect(ComposeSuggestionSource(
            profiles: [],
            recentNotes: [],
            emojiListEvent: list,
            emojiSetEvents: [set]
        ).hasCompleteEmojiCatalog)
        #expect(!ComposeSuggestionSource(
            profiles: [],
            recentNotes: [],
            emojiListEvent: list,
            emojiSetEvents: []
        ).hasCompleteEmojiCatalog)
    }

    private func emojiList(accountID: String, setAuthor: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: accountID,
            createdAt: 100,
            kind: 10_030,
            tags: [[
                "a",
                "30030:\(setAuthor):party",
                "wss://emoji.example"
            ]],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
    }

    private func emojiSet(
        author: String,
        dTag: String,
        id: Character = "2"
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: id, count: 64),
            pubkey: author,
            createdAt: 200,
            kind: 30_030,
            tags: [
                ["d", dTag],
                ["title", dTag.capitalized],
                ["emoji", dTag, "https://emoji.example/\(dTag).png"]
            ],
            content: "",
            sig: String(repeating: "0", count: 128)
        )
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
