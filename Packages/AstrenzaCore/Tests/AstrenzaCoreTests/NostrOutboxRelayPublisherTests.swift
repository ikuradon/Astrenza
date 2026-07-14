import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr outbox relay publisher")
struct NostrOutboxRelayPublisherTests {
    @Test("EVENT frame waits for matching relay OK")
    func acceptsMatchingOK() async throws {
        let event = makeEvent(id: String(repeating: "a", count: 64))
        let connection = PublishTestConnection(responses: [
            #"["OK","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",true,"other"]"#,
            #"["OK","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",true,"saved"]"#
        ])
        let publisher = NostrOutboxRelayPublisher(
            transportFactory: { _ in PublishTestTransport(connection: connection) },
            timeoutNanoseconds: 1_000_000_000
        )

        let result = await publisher.publish(event: event, relayURL: "wss://relay.example")
        let frames = await connection.sentFrames()

        #expect(result == NostrOutboxRelayPublishResult(
            relayURL: "wss://relay.example",
            accepted: true,
            message: "saved"
        ))
        #expect(frames.count == 1)
        let frame = try #require(frames.first)
        let data = try #require(frame.data(using: .utf8))
        let array = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(array.first as? String == "EVENT")
        let object = try #require(array[1] as? [String: Any])
        #expect(object["id"] as? String == event.id)
    }

    @Test("Relay rejection is returned without losing its message")
    func returnsRelayRejection() async {
        let event = makeEvent(id: String(repeating: "c", count: 64))
        let connection = PublishTestConnection(responses: [
            #"["OK","cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",false,"blocked"]"#
        ])
        let publisher = NostrOutboxRelayPublisher(
            transportFactory: { _ in PublishTestTransport(connection: connection) }
        )

        let result = await publisher.publish(event: event, relayURL: "wss://relay.example")

        #expect(result.accepted == false)
        #expect(result.message == "blocked")
    }

    @Test("Publish timeout closes the connection and returns a durable failure")
    func timesOut() async {
        let event = makeEvent(id: String(repeating: "d", count: 64))
        let connection = PublishTestConnection(responses: [], suspendsWhenEmpty: true)
        let publisher = NostrOutboxRelayPublisher(
            transportFactory: { _ in PublishTestTransport(connection: connection) },
            timeoutNanoseconds: 1_000_000
        )

        let result = await publisher.publish(event: event, relayURL: "wss://relay.example")

        #expect(result.accepted == false)
        #expect(result.message == "publish timed out")
        #expect(await connection.wasClosed())
    }

    private func makeEvent(id: String) -> NostrEvent {
        NostrEvent(
            id: id,
            pubkey: String(repeating: "1", count: 64),
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "hello",
            sig: String(repeating: "2", count: 128)
        )
    }
}

private struct PublishTestTransport: NostrRelayTransport {
    let connection: PublishTestConnection

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        connection
    }
}

private actor PublishTestConnection: NostrRelayTransportConnection {
    private var responses: [String]
    private var frames: [String] = []
    private var closed = false
    private let suspendsWhenEmpty: Bool

    init(responses: [String], suspendsWhenEmpty: Bool = false) {
        self.responses = responses
        self.suspendsWhenEmpty = suspendsWhenEmpty
    }

    func send(_ textFrame: String) async throws {
        frames.append(textFrame)
    }

    func receive() async throws -> String {
        if !responses.isEmpty {
            return responses.removeFirst()
        }
        if suspendsWhenEmpty {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        throw PublishTestError.noResponse
    }

    func close() async {
        closed = true
    }

    func sentFrames() -> [String] {
        frames
    }

    func wasClosed() -> Bool {
        closed
    }
}

private enum PublishTestError: Error {
    case noResponse
}
