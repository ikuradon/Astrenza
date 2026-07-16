import Testing
@testable import AstrenzaCore

@Suite("Nostr outbox relay routing")
struct NostrOutboxRoutingTests {
    @Test("最新の kind 10002 の write relay を kind 3 hint より優先する")
    func prefersLatestWriteRelays() {
        let author = String(repeating: "a", count: 64)
        let old = event(
            id: "old",
            author: author,
            createdAt: 100,
            tags: [["r", "wss://old.example", "write"]]
        )
        let latest = event(
            id: "latest",
            author: author,
            createdAt: 200,
            tags: [
                ["r", "https://write.example", "write"],
                ["r", "wss://read.example", "read"]
            ]
        )

        let routes = NostrOutboxRelayRouting().relayURLsByAuthor(
            authors: [author],
            relayListEvents: [old, latest],
            contactItems: [
                NostrContactListItem(
                    pubkey: author,
                    relayHints: ["wss://hint.example"]
                )
            ],
            fallbackRelayURLs: ["wss://own.example"]
        )

        #expect(routes[author] == ["wss://write.example"])
    }

    @Test("kind 10002 が無い著者は kind 3 hint、さらに無ければ自分の relay を使う")
    func fallsBackToHintsThenOwnRelays() {
        let hinted = String(repeating: "b", count: 64)
        let unhinted = String(repeating: "c", count: 64)

        let routes = NostrOutboxRelayRouting().relayURLsByAuthor(
            authors: [hinted, unhinted],
            relayListEvents: [],
            contactItems: [
                NostrContactListItem(
                    pubkey: hinted,
                    relayHints: ["wss://hint.example"]
                )
            ],
            fallbackRelayURLs: ["wss://own.example"]
        )

        #expect(routes[hinted] == ["wss://hint.example"])
        #expect(routes[unhinted] == ["wss://own.example"])
        #expect(NostrOutboxRelayRouting().authorsByRelay(
            relayURLsByAuthor: routes
        ) == [
            "wss://hint.example": [hinted],
            "wss://own.example": [unhinted]
        ])
    }

    private func event(
        id: String,
        author: String,
        createdAt: Int,
        tags: [[String]]
    ) -> NostrEvent {
        NostrEvent(
            id: id,
            pubkey: author,
            createdAt: createdAt,
            kind: 10_002,
            tags: tags,
            content: "",
            sig: ""
        )
    }
}
