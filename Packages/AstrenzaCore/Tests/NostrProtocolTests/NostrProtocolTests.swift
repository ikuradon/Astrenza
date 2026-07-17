import Testing
@testable import NostrProtocol

@Suite("Nostr protocol")
struct NostrProtocolTests {
    @Test("Canonical event identifiers are stable")
    func canonicalEventIdentifiersAreStable() {
        let event = NostrEvent(
            id: String(repeating: "0", count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: 1_700_000_000,
            kind: 1,
            tags: [["p", String(repeating: "b", count: 64)]],
            content: "hello",
            sig: String(repeating: "0", count: 128)
        )

        #expect(event.computedID == "97fb4824e47a52bbca4eb5fc028f65dd67a0a0c6e506a5e0312ce5d5a04c7ddf")
    }

    @Test(
        "Malformed Unicode Bech32 prefixes throw instead of trapping",
        arguments: ["日本語1qqqqqq", "emoji😀1qqqqqq"]
    )
    func malformedUnicodeBech32PrefixesThrow(input: String) {
        #expect {
            try NostrNIP19.eventReference(from: input)
        } throws: { error in
            error as? NostrNIP19Error == .invalidEncoding
        }
    }
}
