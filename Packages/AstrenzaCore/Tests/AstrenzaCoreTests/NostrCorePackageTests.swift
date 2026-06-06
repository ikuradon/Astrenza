import CryptoKit
import Foundation
import Testing
import secp256k1
@testable import AstrenzaCore

@Suite("AstrenzaCore Nostr package")
struct NostrCorePackageTests {
    @Test("NIP-19 npub decodes to canonical hex pubkey without launching Simulator")
    func npubDecoding() throws {
        let pubkey = try NostrNIP19.publicKeyHex(
            from: "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"
        )

        #expect(pubkey == "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
    }

    @Test("kind:3 contact list extracts unique p tags")
    func contactList() {
        let first = String(repeating: "a", count: 64)
        let second = String(repeating: "b", count: 64)
        let event = nostrEvent(
            kind: 3,
            tags: [
                ["p", first],
                ["p", second, "wss://relay.example"],
                ["p", first],
                ["e", String(repeating: "c", count: 64)]
            ]
        )

        #expect(NostrContactList.pubkeys(from: event) == [first, second])
    }

    @Test("NIP-65 relay list keeps read and write markers")
    func nip65RelayList() {
        let event = nostrEvent(
            kind: 10002,
            tags: [
                ["r", "wss://read.example", "read"],
                ["r", "wss://write.example", "write"],
                ["r", "wss://both.example"]
            ]
        )

        let relayList = NostrRelayList.parse(from: event)

        #expect(relayList.readRelays == ["wss://read.example", "wss://both.example"])
        #expect(relayList.writeRelays == ["wss://write.example", "wss://both.example"])
    }

    @Test("kind:0 metadata exposes display name and safe picture URL")
    func profileMetadata() throws {
        let metadata = try JSONDecoder().decode(
            NostrProfileMetadata.self,
            from: Data(#"{"display_name":"Reader","name":"fallback","nip05":"reader@example.com","picture":"https://cdn.example.test/avatar.png"}"#.utf8)
        )

        #expect(metadata.bestName == "Reader")
        #expect(metadata.pictureURL?.absoluteString == "https://cdn.example.test/avatar.png")
    }

    @Test("Login resolver accepts npub as read-only account without network")
    func loginResolverNpub() async throws {
        let account = try await NostrLoginResolver().resolve(
            "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"
        )

        #expect(account.pubkey == "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
        #expect(account.displayIdentifier == "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m")
        #expect(account.readOnly)
    }

    @Test("Remote data cache stores and reads response data by URL")
    func remoteDataCacheStoresData() throws {
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let cache = NostrRemoteDataCache(urlCache: urlCache)
        let url = try #require(URL(string: "https://cdn.example.test/avatar.png"))
        let request = cache.request(for: url, cachePolicy: .returnCacheDataElseLoad)
        let response = try #require(URLResponse(url: url, mimeType: "image/png", expectedContentLength: 68, textEncodingName: nil))
        let data = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))

        cache.store(data: data, response: response, for: request)

        #expect(cache.cachedData(for: url) == data)
    }

    @Test("Home materializer builds UI-independent timeline items")
    func homeTimelineMaterializerItems() throws {
        let pubkey = String(repeating: "d", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "hello nostr")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"display_name":"Reader","nip05":"reader@example.com","picture":"https://cdn.example.test/avatar.png"}"#
        )

        let item = try #require(NostrHomeTimelineMaterializer.items(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey]
        ).first)

        #expect(item.id == note.id)
        #expect(item.displayName == "Reader")
        #expect(item.nip05 == "reader@example.com")
        #expect(item.isFollowed)
        #expect(item.body == "hello nostr")
        #expect(item.avatarPictureState == .resolved)
        #expect(item.avatarImageURL?.absoluteString == "https://cdn.example.test/avatar.png")
    }

    @Test("Home materializer marks invalid picture URL as missing")
    func homeTimelineMaterializerInvalidPicture() throws {
        let pubkey = String(repeating: "f", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "hello fallback")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"name":"Fallback User","picture":"file:///private/avatar.png"}"#
        )

        let item = try #require(NostrHomeTimelineMaterializer.items(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey]
        ).first)

        #expect(item.avatarPictureState == .missing)
        #expect(item.avatarImageURL == nil)
    }

    @Test("BIP340 verifier accepts signed events and rejects tampering")
    func bip340SignatureVerification() throws {
        let event = try signedEvent(
            kind: 1,
            createdAt: 1_707_409_439,
            tags: [["-"]],
            content: "hello package tests"
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

        let older = try #require(planner.olderRequest(subscriptionID: "home-old", before: 100).filters.first)
        #expect(older["until"] == .int(99))
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

    @Test("Home timeline loader resolves relays, follows, home notes, and metadata")
    func homeTimelineLoaderInitialFlow() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let relayEvent = nostrEvent(kind: 10002, pubkey: account.pubkey, tags: [["r", "wss://read.example", "read"]])
        let contacts = nostrEvent(kind: 3, pubkey: account.pubkey, tags: [["p", followed]])
        let note = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 300, content: "home note")
        let metadata = nostrEvent(kind: 0, pubkey: followed, content: #"{"name":"Followed User"}"#)
        let fake = FakeRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [relayEvent],
            "astrenza-kind3": [contacts],
            "astrenza-home": [note],
            "astrenza-kind0": [metadata]
        ])
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.initialState(account: account)

        #expect(state.relays == ["wss://read.example"])
        #expect(state.followedPubkeys == [followed])
        #expect(state.noteEvents.map(\.id) == [note.id])
        #expect(state.metadataEvents.map(\.id) == [metadata.id])
        let calls = await fake.fetchSubscriptionIDs()
        #expect(calls.contains("astrenza-nip65"))
        #expect(calls.contains("astrenza-kind3"))
        #expect(calls.contains("astrenza-home"))
        #expect(calls.contains("astrenza-kind0"))
    }

    @Test("Home timeline loader stops after kind:3 when follow list is empty")
    func homeTimelineLoaderEmptyFollows() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let fake = FakeRelayClient(eventsBySubscriptionID: [
            "astrenza-kind3": [nostrEvent(kind: 3, pubkey: account.pubkey, tags: [])]
        ])
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.initialState(account: account)

        #expect(state.relays == ["wss://bootstrap.example"])
        #expect(state.followedPubkeys.isEmpty)
        #expect(state.noteEvents.isEmpty)
        #expect(state.metadataEvents.isEmpty)
        let calls = await fake.fetchSubscriptionIDs()
        #expect(!calls.contains("astrenza-home"))
        #expect(!calls.contains("astrenza-kind0"))
    }

    @Test("Home timeline loader dedupes and sorts fetched notes")
    func homeTimelineLoaderDedupeSort() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let older = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 100, content: "older")
        let newer = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 200, content: "newer")
        let fake = FakeRelayClient(eventsBySubscriptionID: [
            "astrenza-kind3": [nostrEvent(kind: 3, pubkey: account.pubkey, tags: [["p", followed]])],
            "astrenza-home": [older, newer, older]
        ])
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.initialState(account: account)

        #expect(state.noteEvents.map(\.id) == [newer.id, older.id])
    }

    @Test("Home timeline loader falls back to NIP-77 for older notes")
    func homeTimelineLoaderOlderFallbackToNIP77() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let currentNote = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 300, content: "current")
        let older = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 100, content: "older")
        let fake = FakeRelayClient(
            eventsBySubscriptionID: [
                "astrenza-home-older": [],
                "astrenza-gap-events": [older]
            ],
            missingIDsBySubscriptionID: ["astrenza-neg-gap": [older.id]]
        )
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)
        let current = NostrHomeTimelineState(
            relays: ["wss://read.example"],
            followedPubkeys: [followed],
            noteEvents: [currentNote],
            metadataEvents: []
        )

        let state = try await loader.olderState(account: account, current: current)

        #expect(state.noteEvents.map(\.id) == [currentNote.id, older.id])
        #expect(state.hasMoreOlder)
        #expect(await fake.missingSubscriptionIDs() == ["astrenza-neg-gap"])
        #expect(await fake.fetchSubscriptionIDs().contains("astrenza-gap-events"))
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

    private func nostrEvent(
        kind: Int,
        pubkey: String = String(repeating: "a", count: 64),
        createdAt: Int = 1_800_000_000,
        content: String = "",
        tags: [[String]] = []
    ) -> NostrEvent {
        let canonical = NostrCanonicalJSON.serialize(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        let digest = SHA256Digest.hex(for: canonical)
        return NostrEvent(
            id: digest,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "1", count: 128)
        )
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
}

private enum SHA256Digest {
    static func hex(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private actor FakeRelayClient: NostrRelayFetching {
    private let eventsBySubscriptionID: [String: [NostrEvent]]
    private let missingIDsBySubscriptionID: [String: [String]]
    private var fetchCalls: [String] = []
    private var missingCalls: [String] = []

    init(
        eventsBySubscriptionID: [String: [NostrEvent]],
        missingIDsBySubscriptionID: [String: [String]] = [:]
    ) {
        self.eventsBySubscriptionID = eventsBySubscriptionID
        self.missingIDsBySubscriptionID = missingIDsBySubscriptionID
    }

    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        fetchCalls.append(request.subscriptionID)
        return eventsBySubscriptionID[request.subscriptionID] ?? []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        missingCalls.append(subscriptionID)
        return missingIDsBySubscriptionID[subscriptionID] ?? []
    }

    func fetchSubscriptionIDs() -> [String] {
        fetchCalls
    }

    func missingSubscriptionIDs() -> [String] {
        missingCalls
    }
}
