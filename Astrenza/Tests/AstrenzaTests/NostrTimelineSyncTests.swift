import CryptoKit
import Foundation
import Testing
import AstrenzaCore
import secp256k1
@testable import Astrenza

@Suite("Nostr timeline sync")
struct NostrTimelineSyncTests {
    @Test("BIP340 verifier accepts signed events and rejects tampering")
    func bip340SignatureVerification() throws {
        let event = try signedEvent(
            kind: 1,
            createdAt: 1_707_409_439,
            tags: [["-"]],
            content: "hello members of the secret group"
        )

        #expect(NostrEventValidator().isValid(event))

        let tampered = NostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: "changed",
            sig: event.sig
        )
        #expect(!NostrEventValidator().isValid(tampered))

        let badSignature = NostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: String(repeating: "1", count: 128)
        )
        #expect(!NostrEventValidator().isValid(badSignature))
    }

    @Test("Home fetch planner creates initial, newer, and older NIP-01 filters")
    func homeFetchPlanner() throws {
        let pubkeys = [
            String(repeating: "a", count: 64),
            String(repeating: "b", count: 64)
        ]
        let planner = NostrHomeFetchPlanner(authors: pubkeys, pageLimit: 50)

        let initial = try #require(planner.initialRequest(subscriptionID: "home").filters.first)
        #expect(initial["authors"] == .strings(pubkeys))
        #expect(initial["kinds"] == .ints([1]))
        #expect(initial["limit"] == .int(50))
        #expect(initial["since"] == nil)
        #expect(initial["until"] == nil)

        let newer = try #require(planner.newerRequest(subscriptionID: "home-new", after: 100).filters.first)
        #expect(newer["since"] == .int(101))
        #expect(newer["limit"] == .int(50))

        let older = try #require(planner.olderRequest(subscriptionID: "home-old", before: 100).filters.first)
        #expect(older["until"] == .int(99))
        #expect(older["limit"] == .int(50))
    }

    @Test("Home timeline sync planner keeps all followed authors before runtime chunking")
    func homeTimelinePlannerKeepsAllFollowedAuthors() throws {
        let account = NostrAccount(pubkey: String(repeating: "f", count: 64), displayIdentifier: "account", readOnly: true)
        let authors = (0..<753).map { String(format: "%064x", $0) }
        let packet = HomeTimelineSyncPlanner().forwardPacket(
            account: account,
            followedPubkeys: authors,
            newestCreatedAt: nil,
            relayURLs: ["wss://relay.example"]
        )

        #expect(authorCount(in: packet) == 753)
    }

    @Test("Own relay list mode sends all authors only to account read relays")
    func ownRelayListPlannerUsesAccountReadRelays() throws {
        let authors = (0..<300).map { String(format: "%064x", $0) }
        let relays = ["wss://read1.example", "wss://read2.example"]
        let plan = HomeTimelineSyncPlanner().forwardPlan(
            account: NostrAccount(pubkey: String(repeating: "a", count: 64), displayIdentifier: "account", readOnly: true),
            followedPubkeys: authors,
            newestCreatedAt: nil,
            relayURLs: relays,
            policy: .default(networkType: .wifi)
        )

        #expect(plan.packets.allSatisfy { $0.relayURLs == relays })
        #expect(plan.totalAuthorCount == 300)
        #expect(plan.mode == .ownRelayList)
    }

    @Test("Full outbox mode groups authors by contact relay hints")
    func fullOutboxPlannerGroupsAuthorsByRelayHints() throws {
        let account = NostrAccount(pubkey: String(repeating: "a", count: 64), displayIdentifier: "account", readOnly: true)
        let hinted = String(repeating: "b", count: 64)
        let fallback = String(repeating: "c", count: 64)
        let missingHint = String(repeating: "d", count: 64)
        let plan = HomeTimelineSyncPlanner().forwardPlan(
            account: account,
            followedPubkeys: [hinted, fallback, missingHint],
            contactItems: [
                NostrContactListItem(pubkey: hinted, relayHints: ["wss://hint.example"]),
                NostrContactListItem(pubkey: fallback, relayHints: []),
                NostrContactListItem(pubkey: missingHint, relayHints: ["wss://offline.example"])
            ],
            newestCreatedAt: nil,
            relayURLs: ["wss://own.example", "wss://hint.example"],
            policy: NostrSyncPolicy(
                mode: .fullOutbox,
                networkType: .wifi,
                lowPowerMode: false,
                tapToLoadMedia: false,
                queueOGPPreviews: true,
                disableOGPOnCellular: false,
                reduceFullOutboxOnCellular: true
            )
        )

        #expect(plan.mode == .fullOutbox)
        #expect(plan.totalAuthorCount == 3)
        #expect(plan.packets.map(\.subscriptionID) == [
            "astrenza-home-forward-outbox-1",
            "astrenza-home-forward-outbox-2"
        ])
        #expect(authorsByRelay(in: plan)["wss://hint.example"] == [hinted])
        #expect(authorsByRelay(in: plan)["wss://own.example"] == [fallback, missingHint])
    }

    @Test("NIP-77 client messages encode relay frames")
    func nip77ClientFrames() throws {
        let filter = NostrRelayFilter(kinds: [1], authors: [String(repeating: "a", count: 64)], since: 100, limit: 20)
        let open = NIP77ClientMessage.negOpen(subscriptionID: "neg-home", filter: filter, initialMessageHex: "0a0b")
        #expect(try open.textFrame() == #"["NEG-OPEN","neg-home",{"authors":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"kinds":[1],"limit":20,"since":100},"0a0b"]"#)

        let message = try #require(NIP77RelayMessage.parse(#"["NEG-MSG","neg-home","0c0d"]"#))
        #expect(message == .negMsg(subscriptionID: "neg-home", messageHex: "0c0d"))
    }

    @Test("NIP-77 sync session builds a negentropy open frame from local events")
    func nip77SyncSessionOpenFrame() throws {
        let localEvent = signedShapeOnlyEvent(
            kind: 1,
            pubkey: String(repeating: "d", count: 64),
            createdAt: 200,
            content: "cached"
        )
        let filter = NostrRelayFilter(kinds: [1], authors: [localEvent.pubkey], since: 100, limit: 100)
        let session = try NIP77SyncSession(localEvents: [localEvent])
        let open = try session.openMessage(subscriptionID: "neg-gap", filter: filter)
        let frame = try open.textFrame()

        #expect(frame.contains(#""NEG-OPEN""#))
        #expect(frame.contains(#""neg-gap""#))
        #expect(frame.contains(#""61"#))
    }

    @Test("Launch mode can route Maestro to the mock timeline")
    func mockLaunchMode() throws {
        let suiteName = "AstrenzaLaunchModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "AstrenzaMockTimeline")

        #expect(AstrenzaLaunchMode(arguments: ["Astrenza", "-AstrenzaMockTimeline"]).usesMockTimeline)
        #expect(AstrenzaLaunchMode(arguments: ["Astrenza", "AstrenzaMockTimeline=true"]).usesMockTimeline)
        #expect(AstrenzaLaunchMode(environment: ["ASTRENZA_MOCK_TIMELINE": "1"]).usesMockTimeline)
        #expect(AstrenzaLaunchMode(arguments: ["Astrenza"], environment: [:], userDefaults: defaults).usesMockTimeline)
        #expect(!AstrenzaLaunchMode(arguments: ["Astrenza"], environment: [:]).usesMockTimeline)
    }

    @Test("Live npub can resolve follows and signed home notes from relays")
    func liveNpubHomeFetch() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ASTRENZA_LIVE_NOSTR_TEST"] == "1"
                || environment["TEST_RUNNER_ASTRENZA_LIVE_NOSTR_TEST"] == "1"
        else {
            return
        }

        let account = try await NostrLoginResolver().resolve("npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m")
        let relayClient = NostrRelayClient(timeoutNanoseconds: 12_000_000_000)
        let bootstrapRelays = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.primal.net",
            "wss://relay.nostr.band",
            "wss://nostr.wine"
        ]

        let relayListEvents = try await liveMergedEvents(
            relays: bootstrapRelays,
            request: NostrRelayRequest(
                subscriptionID: "test-live-nip65",
                filters: [[
                    "authors": .strings([account.pubkey]),
                    "kinds": .ints([10002]),
                    "limit": .int(1)
                ]]
            ),
            relayClient: relayClient
        )
        let relayList = NostrRelayList.parse(from: relayListEvents.first)
        let readRelays = relayList.readRelays.isEmpty ? bootstrapRelays : Array(relayList.readRelays.prefix(5))

        let contactEvents = try await liveMergedEvents(
            relays: Array(Set(readRelays + bootstrapRelays)),
            request: NostrRelayRequest(
                subscriptionID: "test-live-kind3",
                filters: [[
                    "authors": .strings([account.pubkey]),
                    "kinds": .ints([3]),
                    "limit": .int(1)
                ]]
            ),
            relayClient: relayClient
        )
        let contacts = NostrContactList.pubkeys(from: contactEvents.first)
        #expect(!contacts.isEmpty)

        let notes = try await liveMergedEvents(
            relays: readRelays,
            request: NostrHomeFetchPlanner(authors: Array(contacts.prefix(24)), pageLimit: 10)
                .initialRequest(subscriptionID: "test-live-home"),
            relayClient: relayClient
        )
        #expect(!notes.isEmpty)
        #expect(notes.allSatisfy { NostrEventValidator().isValid($0) })
    }

    private func signedShapeOnlyEvent(kind: Int, pubkey: String, createdAt: Int, content: String) -> NostrEvent {
        let canonical = NostrCanonicalJSON.serialize(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: [],
            content: content
        )
        let id = SHA256Digest.hex(for: canonical)
        return NostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: [],
            content: content,
            sig: String(repeating: "1", count: 128)
        )
    }

}

private func authorCount(in packet: NostrREQPacket) -> Int {
    guard let value = packet.filters.first?["authors"] else { return 0 }
    switch value {
    case .strings(let authors):
        return authors.count
    default:
        return 0
    }
}

private func authorsByRelay(in plan: HomeTimelineForwardPlan) -> [String: [String]] {
    var result: [String: [String]] = [:]
    for packet in plan.packets {
        guard case .strings(let authors)? = packet.filters.first?["authors"] else {
            continue
        }
        for relayURL in packet.relayURLs {
            result[relayURL, default: []].append(contentsOf: authors)
        }
    }
    return result.mapValues { Array(Set($0)).sorted() }
}

private func liveMergedEvents(
    relays: [String],
    request: NostrRelayRequest,
    relayClient: NostrRelayClient
) async throws -> [NostrEvent] {
    try await withThrowingTaskGroup(of: [NostrEvent].self) { group in
        for relay in relays {
            group.addTask {
                (try? await relayClient.fetch(relayURL: relay, request: request)) ?? []
            }
        }

        var eventsByID: [String: NostrEvent] = [:]
        for try await events in group {
            for event in events {
                eventsByID[event.id] = event
            }
        }

        return eventsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private func signedEvent(kind: Int, createdAt: Int, tags: [[String]], content: String) throws -> NostrEvent {
    let privateBytes = Array(repeating: UInt8(0x21), count: 32)
    let privateKey = try secp256k1.Signing.PrivateKey(rawRepresentation: privateBytes)
    let pubkey = NostrHex.hexString(Array(privateKey.publicKey.xonly.bytes))
    let canonical = NostrCanonicalJSON.serialize(
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content
    )
    let id = SHA256Digest.hex(for: canonical)
    var digest = try #require(NostrHex.bytes(fromLowercaseHex: id))
    var auxiliaryRandomness = Array(repeating: UInt8(0), count: 64)
    let signature = try privateKey.schnorr.signature(message: &digest, auxiliaryRand: &auxiliaryRandomness)
    return NostrEvent(
        id: id,
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: NostrHex.hexString(Array(signature.rawRepresentation))
    )
}

private enum SHA256Digest {
    static func hex(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
