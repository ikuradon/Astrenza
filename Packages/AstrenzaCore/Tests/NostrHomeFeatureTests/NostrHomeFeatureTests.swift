import NostrHomeFeature
import NostrProtocol
import NostrRelay
import NostrSync
import Testing

@Suite("home feature contract")
struct NostrHomeFeatureTests {
    @Test("account bootstrap resolves kind 3 and kind 10002 concurrently")
    func accountBootstrapResolvesReplaceableStateConcurrently() async throws {
        let pubkey = String(repeating: "1", count: 64)
        let followedPubkey = String(repeating: "2", count: 64)
        let relayURL = "wss://bootstrap.example"
        let relayList = testEvent(
            idCharacter: "a",
            pubkey: pubkey,
            createdAt: 100,
            kind: 10_002,
            tags: [["r", relayURL, "read"]]
        )
        let contacts = testEvent(
            idCharacter: "b",
            pubkey: pubkey,
            createdAt: 101,
            kind: 3,
            tags: [["p", followedPubkey]]
        )
        let relayClient = ConcurrentBootstrapRelayClient(
            relayList: relayList,
            contacts: contacts
        )
        let loader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: [relayURL],
            discoveryPolicy: NostrHomeTimelineDiscoveryPolicy(
                settlementMilliseconds: 5,
                absoluteTimeoutMilliseconds: 100
            )
        )

        let state = try await loader.bootstrapState(
            account: NostrAccount(
                pubkey: pubkey,
                displayIdentifier: "npub-bootstrap",
                readOnly: true
            )
        )

        #expect(state.relays == [relayURL])
        #expect(state.followedPubkeys == [followedPubkey])
        #expect(state.relayListEvent?.id == relayList.id)
        #expect(state.contactListEvent?.id == contacts.id)
        #expect(await relayClient.startedSubscriptionIDs() == [
            "astrenza-kind3",
            "astrenza-nip65"
        ])
    }

    @Test("account bootstrap falls back after an absolute discovery deadline")
    func accountBootstrapHasAbsoluteDiscoveryDeadline() async throws {
        let pubkey = String(repeating: "1", count: 64)
        let relayURL = "wss://bootstrap.example"
        let loader = NostrHomeTimelineLoader(
            relayClient: HangingBootstrapRelayClient(),
            bootstrapRelays: [relayURL],
            discoveryPolicy: NostrHomeTimelineDiscoveryPolicy(
                settlementMilliseconds: 5,
                absoluteTimeoutMilliseconds: 20
            )
        )

        let state = try await loader.bootstrapState(
            account: NostrAccount(
                pubkey: pubkey,
                displayIdentifier: "npub-bootstrap",
                readOnly: true
            )
        )

        #expect(state.relays == [relayURL])
        #expect(state.followedPubkeys.isEmpty)
        #expect(state.relaySyncEvents.contains {
            $0.subscriptionID == "astrenza-nip65" && $0.kind == .timeout
        })
        #expect(state.relaySyncEvents.contains {
            $0.subscriptionID == "astrenza-kind3" && $0.kind == .timeout
        })
    }

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

private actor ConcurrentBootstrapRelayClient: NostrRelayFetching {
    private let relayList: NostrEvent
    private let contacts: NostrEvent
    private var startedIDs: Set<String> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(relayList: NostrEvent, contacts: NostrEvent) {
        self.relayList = relayList
        self.contacts = contacts
    }

    func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        startedIDs.insert(request.subscriptionID)
        if startedIDs.isSuperset(of: ["astrenza-nip65", "astrenza-kind3"]) {
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        switch request.subscriptionID {
        case "astrenza-nip65":
            return [relayList]
        case "astrenza-kind3":
            return [contacts]
        default:
            return []
        }
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }

    func startedSubscriptionIDs() -> [String] {
        startedIDs.sorted()
    }
}

private struct HangingBootstrapRelayClient: NostrRelayFetching {
    func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }
}

private func testEvent(
    idCharacter: Character,
    pubkey: String,
    createdAt: Int,
    kind: Int,
    tags: [[String]] = []
) -> NostrEvent {
    NostrEvent(
        id: String(repeating: idCharacter, count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: "",
        sig: String(repeating: "0", count: 128)
    )
}
