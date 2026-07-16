import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr relay runtime client")
struct NostrRelayRuntimeClientTests {
    @Test("Bootstrap reuses one physical connection until default relay handoff")
    func bootstrapReusesConnectionThroughDefaultHandoff() async throws {
        let relayURL = "wss://relay.example"
        let signer = try NostrPrivateKeySigner(
            privateKeyHex: String(repeating: "61", count: 32)
        )
        let followed = String(repeating: "2", count: 64)
        let relayList = try await signer.sign(NostrUnsignedEvent(
            pubkey: signer.pubkey,
            createdAt: 100,
            kind: 10_002,
            tags: [["r", relayURL, "read"]],
            content: ""
        ))
        let contacts = try await signer.sign(NostrUnsignedEvent(
            pubkey: signer.pubkey,
            createdAt: 101,
            kind: 3,
            tags: [["p", followed]],
            content: ""
        ))
        let connection = RuntimeFetchTestConnection(
            eventsByKind: [10_002: [relayList], 3: [contacts]]
        )
        let transport = RuntimeFetchTestTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            heartbeatPolicy: .disabled
        )
        let loader = NostrHomeTimelineLoader(
            relayClient: NostrRelayRuntimeClient(runtime: runtime),
            bootstrapRelays: [relayURL]
        )
        let account = NostrAccount(
            pubkey: signer.pubkey,
            displayIdentifier: "npub-runtime-fetch",
            readOnly: true
        )

        let state = try await loader.bootstrapState(account: account)

        #expect(state.relays == [relayURL])
        #expect(state.followedPubkeys == [followed])
        #expect(await transport.connectCallCount() == 1)
        #expect(await connection.connectionCloseCallCount() == 0)
        #expect(await runtime.temporaryRelayURLs() == [relayURL])

        try await runtime.setDefaultRelays(state.relays)

        #expect(await transport.connectCallCount() == 1)
        #expect(await connection.connectionCloseCallCount() == 0)
        #expect(await runtime.temporaryRelayURLs().isEmpty)
        await runtime.terminate()
    }

    @Test("Cancelling fetch closes its REQ and releases a temporary relay immediately")
    func cancellationReleasesTemporaryRelay() async throws {
        let relayURL = "wss://relay.example"
        let connection = RuntimeFetchTestConnection(respondsToRequests: false)
        let transport = RuntimeFetchTestTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            heartbeatPolicy: .disabled
        )
        let client = NostrRelayRuntimeClient(runtime: runtime)
        let fetchTask = Task {
            try await client.fetch(
                relayURL: relayURL,
                request: NostrRelayRequest(
                    subscriptionID: "astrenza-kind0",
                    filters: [["kinds": .ints([0]), "authors": .strings([
                        String(repeating: "3", count: 64)
                    ])]]
                )
            )
        }

        try await connection.waitForREQCount(1)
        fetchTask.cancel()
        var wasCancelled = false
        do {
            _ = try await fetchTask.value
        } catch is CancellationError {
            wasCancelled = true
        }
        try await connection.waitForCLOSECount(1)
        try await connection.waitForConnectionCloseCount(1)

        #expect(wasCancelled)
        #expect(await runtime.temporaryRelayURLs().isEmpty)
        let snapshot = try #require(await runtime.relayWorkSnapshot(relayURL: relayURL))
        #expect(snapshot.activeSubscriptionIDs.isEmpty)
        #expect(snapshot.queuedCount == 0)
        await runtime.terminate()
    }

    @Test("Fetch keeps EOSE that arrives before REQ send returns")
    func keepsEOSEBeforeSendReturns() async throws {
        let relayURL = "wss://relay.example"
        let connection = RuntimeFetchTestConnection(gateNextREQSend: true)
        let transport = RuntimeFetchTestTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            heartbeatPolicy: .disabled
        )
        try await runtime.setDefaultRelays([relayURL])
        let client = NostrRelayRuntimeClient(runtime: runtime)
        let fetchTask = Task {
            try await client.fetch(
                relayURL: relayURL,
                request: NostrRelayRequest(
                    subscriptionID: "astrenza-kind0",
                    filters: [["kinds": .ints([0]), "authors": .strings([
                        String(repeating: "4", count: 64)
                    ])]]
                )
            )
        }

        await connection.waitUntilREQSendIsGated()
        try await connection.waitForCLOSECount(1)
        await connection.releaseREQSend()
        let events = try await fetchTask.value

        #expect(events.isEmpty)
        #expect(await transport.connectCallCount() == 1)
        #expect(await connection.connectionCloseCallCount() == 0)
        await runtime.terminate()
    }
}

private actor RuntimeFetchTestTransport: NostrRelayTransport {
    private let connection: RuntimeFetchTestConnection
    private var connectCalls = 0

    init(connection: RuntimeFetchTestConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        connectCalls += 1
        return connection
    }

    func connectCallCount() -> Int {
        connectCalls
    }
}

private actor RuntimeFetchTestConnection: NostrRelayTransportConnection {
    private let eventsByKind: [Int: [NostrEvent]]
    private let respondsToRequests: Bool
    private var shouldGateNextREQSend: Bool
    private var inboundFrames: [String] = []
    private var sentFrames: [String] = []
    private var receiveContinuation: CheckedContinuation<String, any Error>?
    private var gatedREQSendContinuation: CheckedContinuation<Void, Never>?
    private var gatedREQSendWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeCalls = 0

    init(
        eventsByKind: [Int: [NostrEvent]] = [:],
        respondsToRequests: Bool = true,
        gateNextREQSend: Bool = false
    ) {
        self.eventsByKind = eventsByKind
        self.respondsToRequests = respondsToRequests
        shouldGateNextREQSend = gateNextREQSend
    }

    func send(_ textFrame: String) async throws {
        sentFrames.append(textFrame)
        guard let frame = Self.frame(from: textFrame),
              frame.first as? String == "REQ",
              let subscriptionID = frame.dropFirst().first as? String
        else { return }

        if respondsToRequests {
            let requestedKinds = Set(
                frame.dropFirst(2)
                    .compactMap { $0 as? [String: Any] }
                    .flatMap { $0["kinds"] as? [Int] ?? [] }
            )
            for event in requestedKinds.sorted().flatMap({ eventsByKind[$0] ?? [] }) {
                try enqueue(Self.eventFrame(subscriptionID: subscriptionID, event: event))
            }
            enqueue(Self.eoseFrame(subscriptionID: subscriptionID))
        }

        guard shouldGateNextREQSend else { return }
        shouldGateNextREQSend = false
        for waiter in gatedREQSendWaiters {
            waiter.resume()
        }
        gatedREQSendWaiters = []
        await withCheckedContinuation { continuation in
            gatedREQSendContinuation = continuation
        }
    }

    func receive() async throws -> String {
        if !inboundFrames.isEmpty {
            return inboundFrames.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveContinuation = continuation
        }
    }

    func close() async {
        closeCalls += 1
        receiveContinuation?.resume(throwing: CancellationError())
        receiveContinuation = nil
    }

    func waitForREQCount(_ expectedCount: Int) async throws {
        try await waitUntil {
            sentFrames.filter { Self.messageType(from: $0) == "REQ" }.count >= expectedCount
        }
    }

    func waitForCLOSECount(_ expectedCount: Int) async throws {
        try await waitUntil {
            sentFrames.filter { Self.messageType(from: $0) == "CLOSE" }.count >= expectedCount
        }
    }

    func waitForConnectionCloseCount(_ expectedCount: Int) async throws {
        try await waitUntil { closeCalls >= expectedCount }
    }

    func waitUntilREQSendIsGated() async {
        guard shouldGateNextREQSend || gatedREQSendContinuation == nil else { return }
        if gatedREQSendContinuation != nil { return }
        await withCheckedContinuation { continuation in
            gatedREQSendWaiters.append(continuation)
        }
    }

    func releaseREQSend() {
        gatedREQSendContinuation?.resume()
        gatedREQSendContinuation = nil
    }

    func connectionCloseCallCount() -> Int {
        closeCalls
    }

    private func enqueue(_ frame: String) {
        if let receiveContinuation {
            self.receiveContinuation = nil
            receiveContinuation.resume(returning: frame)
        } else {
            inboundFrames.append(frame)
        }
    }

    private func waitUntil(
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw RuntimeFetchTestError.conditionTimedOut
    }

    private static func frame(from textFrame: String) -> [Any]? {
        guard let data = textFrame.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    private static func messageType(from textFrame: String) -> String? {
        frame(from: textFrame)?.first as? String
    }

    private static func eventFrame(
        subscriptionID: String,
        event: NostrEvent
    ) throws -> String {
        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let data = try JSONSerialization.data(withJSONObject: [
            "EVENT",
            subscriptionID,
            eventObject
        ])
        return String(decoding: data, as: UTF8.self)
    }

    private static func eoseFrame(subscriptionID: String) -> String {
        #"["EOSE","\#(subscriptionID)"]"#
    }
}

private enum RuntimeFetchTestError: Error {
    case conditionTimedOut
}
