import NostrRelay
import Testing

@Suite("relay wire contract")
struct NostrRelayTests {
    @Test("relay message parser decodes lifecycle frames")
    func parsesLifecycleFrames() {
        #expect(NostrRelayMessage.parse(#"["EOSE","home"]"#) == .eose(subscriptionID: "home"))
        #expect(NostrRelayMessage.parse(#"["AUTH","challenge"]"#) == .auth("challenge"))
        #expect(NostrRelayMessage.parse(#"["NOTICE","slow down"]"#) == .notice("slow down"))
    }

    @Test("relay request serializes a NIP-01 REQ frame")
    func serializesRequest() throws {
        let request = NostrRelayRequest(
            subscriptionID: "home",
            filters: [["kinds": .ints([1]), "limit": .int(50)]]
        )

        let frame = try request.textFrame()

        #expect(frame.contains(#""REQ""#))
        #expect(frame.contains(#""home""#))
        #expect(frame.contains(#""limit":50"#))
    }
}
