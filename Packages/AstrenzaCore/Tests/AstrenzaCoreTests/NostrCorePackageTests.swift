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

    @Test("NIP-19 note decodes to canonical hex event id")
    func noteDecoding() throws {
        let eventID = try NostrNIP19.eventIDHex(
            from: "nostr:note1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q7k28gn"
        )

        #expect(eventID == "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
    }

    @Test("NIP-19 nsec decodes to canonical hex private key")
    func nsecDecoding() throws {
        let privateKey = try NostrNIP19.privateKeyHex(
            from: "nsec1g9q5zs2pg9q5zs2pg9q5zs2pg9q5zs2pg9q5zs2pg9q5zs2pg9qs3whxln"
        )

        #expect(privateKey == String(repeating: "41", count: 32))
    }

    @Test("Nostr private key signer creates valid kind 1 events")
    func privateKeySigner() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "21", count: 32))
        let unsigned = NostrPublishInput.post(content: "signed")
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 900)

        let event = try await signer.sign(unsigned)

        #expect(event.id == unsigned.eventID)
        #expect(event.pubkey == signer.pubkey)
        #expect(NostrEventValidator().isValid(event))
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

    @Test("NIP-05 resolver verifies pubkey and reuses cache")
    func nip05ResolverVerifiesAndCaches() async throws {
        let pubkey = String(repeating: "b", count: 64)
        let cache = NostrNIP05Cache(defaults: nil)
        let callCount = LockedCounter()
        let resolver = NostrNIP05Resolver(cache: cache) { request in
            await callCount.increment()
            #expect(request.url?.absoluteString == "https://example.test/.well-known/nostr.json?name=alice")
            let data = Data(#"{"names":{"alice":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},"relays":{"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":["wss://relay.example"]}}"#.utf8)
            return (data, httpResponse(url: request.url, statusCode: 200))
        }

        let first = await resolver.resolve(identifier: "alice@example.test", expectedPubkey: pubkey)
        let second = await resolver.resolve(identifier: "alice@example.test", expectedPubkey: pubkey)

        #expect(first.status == .verified)
        #expect(first.pubkey == pubkey)
        #expect(first.relays == ["wss://relay.example"])
        #expect(second == first)
        #expect(await callCount.value == 1)
    }

    @Test("NIP-05 resolver marks mismatched pubkey invalid")
    func nip05ResolverMismatch() async throws {
        let resolver = NostrNIP05Resolver(cache: NostrNIP05Cache(defaults: nil)) { request in
            let data = Data(#"{"names":{"alice":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}}"#.utf8)
            return (data, httpResponse(url: request.url, statusCode: 200))
        }

        let resolution = await resolver.resolve(identifier: "alice@example.test", expectedPubkey: String(repeating: "b", count: 64))

        #expect(resolution.status == .invalid)
    }

    @Test("NIP-11 relay information client requests HTTP info document")
    func relayInformationClient() async throws {
        let client = NostrRelayInformationClient(cache: NostrRelayInformationCache(defaults: nil)) { request in
            #expect(request.url?.absoluteString == "https://relay.example/")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/nostr+json")
            let data = Data(#"{"name":"Relay Example","description":"public relay","supported_nips":[1,11,65],"software":"strfry","version":"1.0","limitation":{"auth_required":true,"max_limit":500}}"#.utf8)
            return (data, httpResponse(url: request.url, statusCode: 200))
        }

        let info = try await client.information(for: "wss://relay.example")

        #expect(info.name == "Relay Example")
        #expect(info.supportedNips == [1, 11, 65])
        #expect(info.limitation?.authRequired == true)
        #expect(info.limitation?.maxLimit == 500)
    }

    @Test("Nostr relay message parses AUTH challenge")
    func relayMessageParsesAuthChallenge() throws {
        let message = try #require(NostrRelayMessage.parse(#"["AUTH","challenge-token"]"#))

        #expect(message == .auth("challenge-token"))
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

    @Test("Nostr event store persists events and deduplicates by id")
    func eventStorePersistsEvents() throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(kind: 1, content: "local-first timeline")

        try store.save(events: [event, event], receivedAt: 1_800_000_010)

        #expect(try store.eventCount() == 1)
        #expect(try store.event(id: event.id) == event)
        #expect(try store.events(kind: 1, limit: 10).map(\.id) == [event.id])
    }

    @Test("Nostr event store normalizes event tags")
    func eventStoreNormalizesTags() throws {
        let store = try NostrEventStore.inMemory()
        let rootID = String(repeating: "b", count: 64)
        let replyID = String(repeating: "c", count: 64)
        let event = nostrEvent(
            kind: 1,
            content: "reply chain",
            tags: [
                ["e", rootID, "wss://relay.example", "root"],
                ["e", replyID, "wss://relay.example", "reply"],
                ["p", String(repeating: "d", count: 64), "wss://people.example"],
                ["alt", "screen reader text"]
            ]
        )

        try store.save(events: [event])
        let tags = try store.tags(eventID: event.id)

        #expect(tags.map { $0.name } == ["e", "e", "p", "alt"])
        #expect(tags[0].value == rootID)
        #expect(tags[0].relayHint == "wss://relay.example")
        #expect(tags[0].marker == "root")
        #expect(tags[1].marker == "reply")
        #expect(tags[2].relayHint == "wss://people.example")
        #expect(tags[3].value == "screen reader text")
    }

    @Test("Nostr event store keeps latest replaceable head")
    func eventStoreReplaceableHeads() throws {
        let store = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "e", count: 64)
        let older = nostrEvent(kind: 0, pubkey: pubkey, createdAt: 100, content: #"{"name":"old"}"#)
        let newer = nostrEvent(kind: 0, pubkey: pubkey, createdAt: 200, content: #"{"name":"new"}"#)

        try store.save(events: [newer, older])

        #expect(try store.latestReplaceableEvent(pubkey: pubkey, kind: 0)?.id == newer.id)
    }

    @Test("Nostr event store keeps latest addressable head by d tag")
    func eventStoreAddressableHeads() throws {
        let store = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "e", count: 64)
        let older = nostrEvent(kind: 30_000, pubkey: pubkey, createdAt: 100, tags: [["d", "friends"], ["title", "Old"]])
        let newer = nostrEvent(kind: 30_000, pubkey: pubkey, createdAt: 200, tags: [["d", "friends"], ["title", "New"]])
        let other = nostrEvent(kind: 30_000, pubkey: pubkey, createdAt: 300, tags: [["d", "work"], ["title", "Work"]])

        try store.save(events: [newer, older, other])

        #expect(try store.latestAddressableEvent(kind: 30_000, pubkey: pubkey, dTag: "friends")?.id == newer.id)
        #expect(try store.latestAddressableEvent(kind: 30_000, pubkey: pubkey, dTag: "work")?.id == other.id)
    }

    @Test("Nostr event store stores public NIP-51 list summaries and items")
    func eventStoreNIP51PublicLists() throws {
        let store = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "e", count: 64)
        let followed = String(repeating: "f", count: 64)
        let followSet = nostrEvent(
            kind: 30_000,
            pubkey: pubkey,
            createdAt: 200,
            content: "encrypted-private-content",
            tags: [
                ["d", "friends"],
                ["title", "Friends"],
                ["p", followed, "wss://people.example"]
            ]
        )
        let relaySet = nostrEvent(
            kind: 30_002,
            pubkey: pubkey,
            createdAt: 210,
            tags: [["d", "relays"], ["relay", "wss://relay-set.example"]]
        )
        let bookmarkSet = nostrEvent(
            kind: 30_003,
            pubkey: pubkey,
            createdAt: 220,
            tags: [["d", "bookmarks"], ["e", String(repeating: "b", count: 64)]]
        )

        try store.save(events: [followSet, relaySet, bookmarkSet])
        let summaries = try store.listSummaries(accountID: pubkey)
        let followSummary = try #require(summaries.first { $0.kind == 30_000 })
        let followItems = try store.listItems(listID: followSummary.listID)
        let relaySummary = try #require(summaries.first { $0.kind == 30_002 })
        let bookmarkSummary = try #require(summaries.first { $0.kind == 30_003 })

        #expect(followSummary.dTag == "friends")
        #expect(followSummary.title == "Friends")
        #expect(followSummary.visibility == "public+encrypted")
        #expect(followSummary.privateContent == "encrypted-private-content")
        #expect(followItems.map(\.itemType) == ["pubkey"])
        #expect(followItems.map(\.value) == [followed])
        #expect(followItems.first?.relayHint == "wss://people.example")
        #expect(try store.listItems(listID: relaySummary.listID).map(\.value) == ["wss://relay-set.example"])
        #expect(try store.listItems(listID: bookmarkSummary.listID).map(\.itemType) == ["event"])
    }

    @Test("Nostr event store stores mute bookmark and search relay lists")
    func eventStoreNIP51StandardLists() throws {
        let store = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "e", count: 64)
        let muted = String(repeating: "a", count: 64)
        let bookmarked = String(repeating: "b", count: 64)
        let muteList = nostrEvent(kind: 10_000, pubkey: pubkey, createdAt: 100, tags: [["p", muted], ["t", "spam"], ["word", "spoiler"]])
        let bookmarks = nostrEvent(kind: 10_003, pubkey: pubkey, createdAt: 110, tags: [["e", bookmarked]])
        let searchRelays = nostrEvent(kind: 10_007, pubkey: pubkey, createdAt: 120, tags: [["relay", "wss://search.example"]])

        try store.save(events: [muteList, bookmarks, searchRelays])
        let summaries = try store.listSummaries(accountID: pubkey)
        let itemsByKind = Dictionary(uniqueKeysWithValues: try summaries.map { summary in
            (summary.kind, try store.listItems(listID: summary.listID))
        })

        #expect(Set(summaries.map(\.kind)) == [10_000, 10_003, 10_007])
        #expect(itemsByKind[10_000]?.map(\.itemType) == ["pubkey", "hashtag", "word"])
        #expect(itemsByKind[10_003]?.map(\.value) == [bookmarked])
        #expect(itemsByKind[10_007]?.map(\.value) == ["wss://search.example"])
    }

    @Test("NIP-51 public mute items project into filter rules")
    func nip51MuteItemsProjectIntoFilterRules() throws {
        let listID = "10000:account:"
        let items = [
            NostrListItemRecord(listID: listID, itemKey: "pubkey:pub", itemType: "pubkey", value: "pub", relayHint: nil, visibility: "public", position: 0),
            NostrListItemRecord(listID: listID, itemKey: "hashtag:nostr", itemType: "hashtag", value: "nostr", relayHint: nil, visibility: "public", position: 1),
            NostrListItemRecord(listID: listID, itemKey: "word:noise", itemType: "word", value: "noise", relayHint: nil, visibility: "public", position: 2),
            NostrListItemRecord(listID: listID, itemKey: "event:ignored", itemType: "event", value: "ignored", relayHint: nil, visibility: "public", position: 3)
        ]

        let rules = NostrFilterRuleSet.publicMuteRules(accountID: "account", items: items, updatedAt: 123)

        #expect(rules.map(\.kind) == [.mutedPubkey, .mutedHashtag, .keyword])
        #expect(rules.map(\.value) == ["pub", "nostr", "noise"])
        #expect(rules.allSatisfy { $0.accountID == "account" && $0.createdAt == 123 && $0.updatedAt == 123 })
    }

    @Test("Nostr event store persists NIP-92 imeta media assets")
    func eventStoreNIP92MediaAssets() throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(
            kind: 1,
            content: "photo",
            tags: [
                [
                    "imeta",
                    "url https://cdn.example.test/photo.png",
                    "m image/png",
                    "dim 1200x800",
                    "blurhash LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                    "alt screen reader description",
                    "x \(String(repeating: "f", count: 64))"
                ]
            ]
        )

        try store.save(events: [event], receivedAt: 222)
        let assets = try store.mediaAssets(eventID: event.id)
        let asset = try #require(assets.first)

        #expect(assets.count == 1)
        #expect(asset.url == "https://cdn.example.test/photo.png")
        #expect(asset.mimeType == "image/png")
        #expect(asset.width == 1200)
        #expect(asset.height == 800)
        #expect(asset.blurhash == "LEHV6nWB2yk8pyo0adR*.7kCMdnj")
        #expect(asset.alt == "screen reader description")
        #expect(asset.sha256 == String(repeating: "f", count: 64))
        #expect(asset.status == "unresolved")
        #expect(asset.createdAt == 222)
    }

    @Test("Nostr media parser uses content URLs only when imeta is absent")
    func eventStoreMediaContentFallback() throws {
        let store = try NostrEventStore.inMemory()
        let fallback = nostrEvent(kind: 1, content: "image https://cdn.example.test/fallback.jpg link https://example.test/page")
        let imetaPreferred = nostrEvent(
            kind: 1,
            content: "ignored https://cdn.example.test/ignored.jpg",
            tags: [["imeta", "url https://cdn.example.test/tagged.webp", "m image/webp"]]
        )

        try store.save(events: [fallback, imetaPreferred])

        #expect(try store.mediaAssets(eventID: fallback.id).map(\.url) == ["https://cdn.example.test/fallback.jpg"])
        #expect(try store.mediaAssets(eventID: imetaPreferred.id).map(\.url) == ["https://cdn.example.test/tagged.webp"])
    }

    @Test("Nostr event store records unresolved link preview requests")
    func eventStoreLinkPreviewRequests() throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(
            kind: 1,
            content: "read https://Example.TEST/page#section and image https://cdn.example.test/photo.png"
        )

        try store.save(events: [event])
        let previews = try store.linkPreviews(urls: [
            try #require(URL(string: "https://example.test/page")),
            try #require(URL(string: "https://cdn.example.test/photo.png"))
        ])
        let preview = try #require(previews["https://example.test/page"])

        #expect(previews.count == 1)
        #expect(preview.url == "https://Example.TEST/page#section")
        #expect(preview.status == "unresolved")
        #expect(preview.title == nil)
    }

    @Test("Nostr link preview cache can store resolved metadata")
    func eventStoreResolvedLinkPreview() throws {
        let store = try NostrEventStore.inMemory()
        let url = try #require(URL(string: "https://example.test/article?b=1"))
        let preview = NostrLinkPreviewRecord(
            url: url.absoluteString,
            normalizedURL: NostrLinkParser.normalizedURLString(url),
            status: "resolved",
            title: "Article",
            summary: "Cached summary",
            siteName: "Example",
            imageURL: "https://example.test/og.png",
            fetchedAt: 100,
            expiresAt: 200,
            error: nil
        )

        try store.saveLinkPreview(preview)
        let loaded = try #require(store.linkPreviews(urls: [url]).values.first)

        #expect(loaded.status == "resolved")
        #expect(loaded.title == "Article")
        #expect(loaded.summary == "Cached summary")
        #expect(loaded.siteName == "Example")
    }

    @Test("Nostr outbox persists events and relay destinations")
    func eventStoreOutboxPersistence() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let event = nostrEvent(kind: 1, pubkey: accountID, createdAt: 300, content: "queued")

        let record = try store.enqueueOutboxEvent(
            event,
            accountID: accountID,
            relayURLs: ["wss://Relay.Example", "wss://relay.example", "wss://other.example"],
            localID: "local-1",
            createdAt: 400
        )
        let events = try store.outboxEvents(accountID: accountID)
        let relays = try store.outboxRelays(localID: record.localID)

        #expect(events.map(\.localID) == ["local-1"])
        #expect(events.first?.event == event)
        #expect(events.first?.status == NostrOutboxStatus.pending)
        #expect(relays.map(\.relayURL) == ["wss://other.example", "wss://relay.example"])
        #expect(relays.allSatisfy { $0.status == NostrOutboxStatus.pending })
    }

    @Test("Nostr outbox aggregates relay OK results")
    func eventStoreOutboxRelayResultAggregation() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let event = nostrEvent(kind: 1, pubkey: accountID, createdAt: 300, content: "queued")

        let record = try store.enqueueOutboxEvent(
            event,
            accountID: accountID,
            relayURLs: ["wss://one.example", "wss://two.example"],
            localID: "local-ok",
            createdAt: 400
        )

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://one.example",
            accepted: true,
            message: "saved",
            attemptedAt: 410
        )
        #expect(try store.outboxEvents(accountID: accountID).first?.status == NostrOutboxStatus.pending)

        try store.recordOutboxRelayResult(
            localID: record.localID,
            relayURL: "wss://two.example",
            accepted: false,
            message: "blocked",
            attemptedAt: 411
        )
        let partial = try #require(store.outboxEvents(accountID: accountID).first)
        let relays = try store.outboxRelays(localID: record.localID)

        #expect(partial.status == NostrOutboxStatus.partial)
        #expect(partial.lastError == "blocked")
        #expect(relays.first { $0.relayURL == "wss://one.example" }?.status == NostrOutboxStatus.published)
        #expect(relays.first { $0.relayURL == "wss://two.example" }?.status == NostrOutboxStatus.failed)
    }

    @Test("Nostr publish destination resolver prioritizes account relays")
    func publishDestinationResolver() {
        let relays = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: ["wss://Write.example", "invalid"],
            taggedUserReadRelays: ["wss://read.example", "wss://write.example"],
            fallbackRelays: ["wss://fallback.example"],
            limit: 3
        )

        #expect(relays == ["wss://write.example", "wss://read.example", "wss://fallback.example"])
    }

    @Test("Nostr publish inputs build post reply and deletion events")
    func publishInputEventBuilders() {
        let pubkey = String(repeating: "a", count: 64)
        let root = NostrReplyReference(
            eventID: String(repeating: "b", count: 64),
            relayHint: "wss://root.example",
            pubkey: String(repeating: "c", count: 64)
        )
        let parent = NostrReplyReference(
            eventID: String(repeating: "d", count: 64),
            relayHint: "wss://parent.example",
            pubkey: String(repeating: "e", count: 64)
        )

        let post = NostrPublishInput.post(content: "hello", tags: [["t", "nostr"]])
            .unsignedEvent(pubkey: pubkey, createdAt: 10)
        let reply = NostrPublishInput.reply(content: "reply", root: root, parent: parent)
            .unsignedEvent(pubkey: pubkey, createdAt: 11)
        let deletion = NostrPublishInput.delete(eventIDs: [root.eventID], reason: "mistake")
            .unsignedEvent(pubkey: pubkey, createdAt: 12)

        #expect(post.kind == 1)
        #expect(post.tags == [["t", "nostr"]])
        #expect(reply.tags == [
            ["e", root.eventID, "wss://root.example", "root"],
            ["e", parent.eventID, "wss://parent.example", "reply"],
            ["p", parent.pubkey!]
        ])
        #expect(deletion.kind == 5)
        #expect(deletion.tags == [["e", root.eventID]])
        #expect(deletion.content == "mistake")
    }

    @Test("Nostr publisher signs and enqueues outbox records")
    func publisherSignsAndEnqueuesOutboxRecord() async throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let signer = FakeNostrSigner()
        let publisher = NostrPublisher(
            store: store,
            signer: signer,
            clock: { 500 },
            localID: { "publish-local-1" }
        )

        let record = try await publisher.enqueue(
            .post(content: "queued post"),
            accountID: accountID,
            relayURLs: ["wss://write.example"],
            taggedUserReadRelays: ["wss://read.example"],
            fallbackRelays: ["wss://fallback.example"]
        )
        let events = try store.outboxEvents(accountID: accountID)
        let relays = try store.outboxRelays(localID: record.localID)

        #expect(record.localID == "publish-local-1")
        #expect(record.event.kind == 1)
        #expect(record.event.content == "queued post")
        #expect(events.first?.event.id == record.event.id)
        #expect(await signer.signedEvents().first?.content == "queued post")
        #expect(relays.map(\.relayURL) == ["wss://fallback.example", "wss://read.example", "wss://write.example"])
    }

    @Test("Nostr event store keeps timeline entries in display order")
    func eventStoreTimelineEntries() throws {
        let store = try NostrEventStore.inMemory()
        let older = nostrEvent(kind: 1, createdAt: 100, content: "older")
        let newer = nostrEvent(kind: 1, createdAt: 200, content: "newer")
        try store.save(events: [older, newer])

        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(accountID: "account", timelineKey: "home", eventID: older.id, sortTimestamp: older.createdAt, insertedAt: 300),
            NostrTimelineEntryRecord(accountID: "account", timelineKey: "home", eventID: newer.id, sortTimestamp: newer.createdAt, insertedAt: 300)
        ])

        #expect(try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10).map(\.eventID) == [newer.id, older.id])
        #expect(try store.timelineEvents(accountID: "account", timelineKey: "home", limit: 10).map(\.id) == [newer.id, older.id])
    }

    @Test("Nostr event store applies same-author deletion requests")
    func eventStoreAppliesSameAuthorDeletionRequests() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let note = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "delete me")
        let deletion = nostrEvent(kind: 5, pubkey: author, createdAt: 120, content: "remove", tags: [["e", note.id]])

        try store.save(events: [deletion, note])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(accountID: "account", timelineKey: "home", eventID: note.id, sortTimestamp: note.createdAt, insertedAt: 130)
        ])

        #expect(try store.event(id: note.id) == note)
        #expect(try store.events(kind: 1, limit: 10, now: 200).isEmpty)
        #expect(try store.timelineEvents(accountID: "account", timelineKey: "home", limit: 10, now: 200).isEmpty)
    }

    @Test("Nostr event store returns deleted timeline rows from timeline entries")
    func eventStoreReturnsDeletedTimelineEntries() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let note = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "delete me")
        let deletion = nostrEvent(kind: 5, pubkey: author, createdAt: 120, content: "remove", tags: [["e", note.id]])

        try store.save(events: [note, deletion])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(accountID: "account", timelineKey: "home", eventID: note.id, sortTimestamp: note.createdAt, insertedAt: 130)
        ])

        let deletedRows = try store.deletedTimelineEntries(accountID: "account", timelineKey: "home", limit: 10, now: 200)

        #expect(deletedRows == [
            NostrDeletedTimelineEntryRecord(
                targetEventID: note.id,
                deletionEventID: deletion.id,
                deletedAt: deletion.createdAt,
                sortTimestamp: note.createdAt
            )
        ])
    }

    @Test("Nostr event store ignores deletion requests from other authors")
    func eventStoreIgnoresOtherAuthorDeletionRequests() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let otherAuthor = String(repeating: "b", count: 64)
        let note = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "keep me")
        let deletion = nostrEvent(kind: 5, pubkey: otherAuthor, createdAt: 120, content: "remove", tags: [["e", note.id]])

        try store.save(events: [note, deletion])

        #expect(try store.events(kind: 1, limit: 10, now: 200).map(\.id) == [note.id])
    }

    @Test("Nostr event store filters expired events from visible queries")
    func eventStoreFiltersExpiredEvents() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let expiring = nostrEvent(
            kind: 1,
            pubkey: author,
            createdAt: 100,
            content: "short lived",
            tags: [["expiration", "150"]]
        )

        try store.save(events: [expiring])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(accountID: "account", timelineKey: "home", eventID: expiring.id, sortTimestamp: expiring.createdAt, insertedAt: 120)
        ])

        #expect(try store.events(kind: 1, limit: 10, now: 149).map(\.id) == [expiring.id])
        #expect(try store.events(kind: 1, limit: 10, now: 150).isEmpty)
        #expect(try store.timelineEvents(accountID: "account", timelineKey: "home", limit: 10, now: 149).map(\.id) == [expiring.id])
        #expect(try store.timelineEvents(accountID: "account", timelineKey: "home", limit: 10, now: 150).isEmpty)
    }

    @Test("Nostr event store persists sync cursors")
    func eventStoreSyncCursors() throws {
        let store = try NostrEventStore.inMemory()
        let cursor = NostrSyncCursorRecord(
            accountID: "account",
            timelineKey: "home",
            relayURL: "wss://relay.example",
            newestCreatedAt: 300,
            oldestCreatedAt: 100,
            lastEOSEAt: 400,
            lastNegentropyAt: 500
        )

        try store.saveSyncCursor(cursor)

        #expect(try store.syncCursor(accountID: "account", timelineKey: "home", relayURL: "wss://relay.example") == cursor)
    }

    @Test("Nostr event store persists relay sync history and updates cursors from relay results")
    func eventStoreRelaySyncHistory() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = "account"
        let relayURL = "wss://relay.example"
        let eoseEvent =
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .eose,
                occurredAt: 1_000,
                subscriptionID: "home",
                eventCount: 4,
                newestCreatedAt: 900,
                oldestCreatedAt: 500,
                latencyMilliseconds: 120,
                message: "EOSE received"
            )
        let events = [
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .timeout,
                occurredAt: 1_100,
                subscriptionID: "home-newer",
                eventCount: 0,
                latencyMilliseconds: 7_000,
                message: "timeout"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .partialFailure,
                occurredAt: 1_200,
                subscriptionID: "kind0",
                eventCount: 0,
                message: "network lost"
            )
        ]

        try store.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: [relayURL],
                followedPubkeys: [accountID],
                noteEvents: [],
                metadataEvents: [],
                relaySyncEvents: [eoseEvent]
            ),
            accountID: accountID,
            savedAt: 1_300
        )
        try store.saveRelaySyncEvents(events)

        let history = try store.relaySyncEvents(accountID: accountID, timelineKey: "home", relayURL: relayURL, limit: 10)
        let summary = try #require(try store.relaySyncSummaries(accountID: accountID, timelineKey: "home").first)
        let cursor = try #require(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: relayURL))

        #expect(history.map(\.kind).prefix(3) == [.partialFailure, .timeout, .eose])
        #expect(summary.timeoutCount == 1)
        #expect(summary.partialFailureCount == 1)
        #expect(summary.totalEventCount == 4)
        #expect(summary.averageEOSELatencyMilliseconds == 120)
        #expect(summary.lastPartialFailureReason == "network lost")
        #expect(cursor.newestCreatedAt == 900)
        #expect(cursor.oldestCreatedAt == 500)
        #expect(cursor.lastEOSEAt == 1_000)
    }

    @Test("Nostr event store summarizes relay lifecycle states")
    func eventStoreRelayLifecycleSummary() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = "account"
        let relayURL = "wss://relay.example"

        try store.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .connected,
                occurredAt: 10,
                message: "connected"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .authRequired,
                occurredAt: 20,
                message: "challenge-token"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .paymentRequired,
                occurredAt: 30,
                message: "payment-required: paid relay"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .closed,
                occurredAt: 40,
                message: "closed"
            )
        ])

        let summary = try #require(try store.relaySyncSummaries(accountID: accountID, timelineKey: "home").first)

        #expect(summary.lastEventKind == .closed)
        #expect(summary.lastConnectedAt == 10)
        #expect(summary.lastErrorAt == 40)
        #expect(summary.closedCount == 1)
        #expect(summary.authRequiredCount == 1)
        #expect(summary.paymentRequiredCount == 1)
    }

    @Test("Nostr event store bounds relay lifecycle history per relay")
    func eventStoreBoundsRelayLifecycleHistory() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = "account"
        let relayURL = "wss://relay.example"
        let events = (0..<205).map { index in
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .reconnect,
                occurredAt: index,
                message: "reconnect \(index)"
            )
        }

        try store.saveRelaySyncEvents(events)

        let history = try store.relaySyncEvents(accountID: accountID, timelineKey: "home", relayURL: relayURL, limit: 300)
        #expect(history.count == 200)
        #expect(history.first?.occurredAt == 204)
        #expect(history.last?.occurredAt == 5)
    }

    @Test("Nostr event store persists relay preferences per account")
    func eventStoreRelayPreferences() throws {
        let store = try NostrEventStore.inMemory()
        let preference = NostrRelayPreferenceRecord(
            accountID: "account",
            relayURL: "wss://relay.example",
            isEnabled: true,
            readEnabled: true,
            writeEnabled: false,
            updatedAt: 100
        )
        let updatedPreference = NostrRelayPreferenceRecord(
            accountID: "account",
            relayURL: "wss://relay.example",
            isEnabled: false,
            readEnabled: false,
            writeEnabled: true,
            updatedAt: 200
        )

        try store.saveRelayPreference(preference)
        try store.saveRelayPreference(updatedPreference)

        #expect(try store.relayPreferences(accountID: "account") == [updatedPreference])
        #expect(try store.relayPreferences(accountID: "other").isEmpty)
    }

    @Test("Nostr event store persists and deletes compose drafts")
    func eventStoreComposeDrafts() throws {
        let store = try NostrEventStore.inMemory()
        let draft = NostrDraftRecord(
            draftID: "draft-1",
            accountID: "account",
            kind: 1,
            parentEventID: "parent",
            text: "draft text",
            contentWarning: "spoilers",
            media: [
                NostrDraftMediaReference(id: "media-1", kind: "photo", localIdentifier: "local-1", altText: "alt")
            ],
            updatedAt: 100
        )
        let updatedDraft = NostrDraftRecord(
            draftID: "draft-1",
            accountID: "account",
            kind: 1,
            parentEventID: "parent",
            text: "updated draft",
            contentWarning: nil,
            media: [],
            updatedAt: 200
        )

        try store.saveDraft(draft)
        try store.saveDraft(updatedDraft)

        #expect(try store.drafts(accountID: "account") == [updatedDraft])
        #expect(try store.drafts(accountID: "other").isEmpty)

        try store.deleteDraft(accountID: "account", draftID: "draft-1")
        #expect(try store.drafts(accountID: "account").isEmpty)
    }

    @Test("Nostr event store keeps compose drafts account scoped")
    func eventStoreComposeDraftsAreAccountScoped() throws {
        let store = try NostrEventStore.inMemory()
        let first = NostrDraftRecord(draftID: "draft-1", accountID: "account-a", kind: 1, text: "a", updatedAt: 100)
        let second = NostrDraftRecord(draftID: "draft-2", accountID: "account-b", kind: 1, text: "b", updatedAt: 200)

        try store.saveDraft(first)
        try store.saveDraft(second)
        try store.deleteDraft(accountID: "account-a", draftID: "draft-2")

        #expect(try store.drafts(accountID: "account-a") == [first])
        #expect(try store.drafts(accountID: "account-b") == [second])
    }

    @Test("Nostr filter rules match pubkey hashtag keyword regex and kind")
    func filterRulesMatchEvents() throws {
        let pubkey = String(repeating: "b", count: 64)
        let event = nostrEvent(
            kind: 1,
            pubkey: pubkey,
            content: "hello filtered timeline",
            tags: [["t", "Nostr"]]
        )
        let rules = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(ruleID: "expired", accountID: "account", kind: .keyword, value: "hello", expiresAt: 10, createdAt: 1, updatedAt: 1),
            NostrFilterRuleRecord(ruleID: "pubkey", accountID: "account", kind: .mutedPubkey, value: pubkey, createdAt: 2, updatedAt: 2)
        ])

        #expect(rules.match(event: event, now: 20) == .mutedPubkey(pubkey))
        #expect(NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(ruleID: "tag", accountID: "account", kind: .mutedHashtag, value: "nostr", createdAt: 1, updatedAt: 1)
        ]).match(event: event, now: 20) == .mutedHashtag("nostr"))
        #expect(NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(ruleID: "keyword", accountID: "account", kind: .keyword, value: "FILTERED", createdAt: 1, updatedAt: 1)
        ]).match(event: event, now: 20) == .keyword("FILTERED"))
        #expect(NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(ruleID: "regex", accountID: "account", kind: .regex, value: "filter[a-z]+", createdAt: 1, updatedAt: 1)
        ]).match(event: event, now: 20) == .regex("filter[a-z]+"))
        #expect(NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(ruleID: "kind", accountID: "account", kind: .mutedKind, value: "1", createdAt: 1, updatedAt: 1)
        ]).match(event: event, now: 20) == .mutedKind(1))
    }

    @Test("Nostr event store persists filter rules and local bookmarks")
    func eventStoreFilterRulesAndBookmarks() throws {
        let store = try NostrEventStore.inMemory()
        let rule = NostrFilterRuleRecord(ruleID: "rule-1", accountID: "account", kind: .keyword, value: "noise", createdAt: 100, updatedAt: 100)
        let bookmark = NostrLocalBookmarkRecord(accountID: "account", eventID: "event-1", createdAt: 200)

        try store.saveFilterRule(rule)
        try store.saveLocalBookmark(bookmark)

        #expect(try store.filterRules(accountID: "account") == [rule])
        #expect(try store.filterRules(accountID: "other").isEmpty)
        #expect(try store.localBookmarks(accountID: "account") == [bookmark])

        try store.deleteLocalBookmark(accountID: "account", eventID: "event-1")
        #expect(try store.localBookmarks(accountID: "account").isEmpty)
    }

    @Test("Nostr event store persists relay profiles and event sources")
    func eventStoreRelayProfilesAndSources() throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(kind: 1, content: "relay indexed")
        try store.save(events: [event])
        try store.recordEventSources(eventIDs: [event.id], relayURL: "wss://relay.example", seenAt: 600)
        try store.saveRelayProfile(NostrRelayProfileRecord(
            relayURL: "wss://relay.example",
            information: NostrRelayInformationDocument(
                name: "Relay Example",
                description: "test relay",
                pubkey: nil,
                contact: nil,
                supportedNips: [1, 11, 65],
                software: "strfry",
                version: "1.0",
                limitation: NostrRelayLimitation(maxMessageLength: nil, maxSubscriptions: nil, maxLimit: 500, maxSubIDLength: nil, authRequired: true, paymentRequired: false, restrictedWrites: nil)
            ),
            healthScore: 0.9,
            lastEOSEAt: 700,
            lastConnectedAt: 800,
            authRequired: true,
            paymentRequired: false
        ))

        let sources = try store.eventSources(eventID: event.id)
        let relayProfile = try store.relayProfile(relayURL: "wss://relay.example")
        let relay = try #require(relayProfile)

        #expect(sources == [NostrEventSourceRecord(eventID: event.id, relayURL: "wss://relay.example", firstSeenAt: 600, lastSeenAt: 600)])
        #expect(relay.information?.name == "Relay Example")
        #expect(relay.information?.supportedNips == [1, 11, 65])
        #expect(relay.healthScore == 0.9)
        #expect(relay.authRequired)
    }

    @Test("Nostr event store writes home timeline state")
    func eventStoreHomeTimelineStateWritePath() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "f", count: 64)
        let note = nostrEvent(kind: 1, pubkey: accountID, createdAt: 200, content: "home")
        let metadata = nostrEvent(kind: 0, pubkey: accountID, createdAt: 150, content: #"{"name":"Home"}"#)
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [accountID],
            noteEvents: [note],
            metadataEvents: [metadata],
            hasMoreOlder: true
        )

        try store.saveHomeTimelineState(state, accountID: accountID, savedAt: 300)

        #expect(try store.event(id: note.id) == note)
        #expect(try store.latestReplaceableEvent(pubkey: accountID, kind: 0)?.id == metadata.id)
        #expect(try store.timelineEvents(accountID: accountID, timelineKey: "home", limit: 10).map(\.id) == [note.id])
        #expect(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: "wss://relay.example")?.newestCreatedAt == 200)
    }

    @Test("Nostr event store restores home timeline state")
    func eventStoreHomeTimelineStateReadPath() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "f", count: 64)
        let note = nostrEvent(kind: 1, pubkey: accountID, createdAt: 200, content: "home")
        let metadata = nostrEvent(kind: 0, pubkey: accountID, createdAt: 150, content: #"{"name":"Home"}"#)
        let resolution = NostrNIP05Resolution(
            identifier: "home@example.test",
            pubkey: accountID,
            relays: ["wss://relay.example"],
            status: .verified
        )
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [accountID],
            noteEvents: [note],
            metadataEvents: [metadata],
            nip05Resolutions: [accountID: resolution],
            hasMoreOlder: false
        )

        try store.saveHomeTimelineState(state, accountID: accountID, savedAt: 300)
        let restoredState = try store.homeTimelineState(accountID: accountID)
        let restored = try #require(restoredState)

        #expect(restored.relays == ["wss://relay.example"])
        #expect(restored.followedPubkeys == [accountID])
        #expect(restored.noteEvents == [note])
        #expect(restored.metadataEvents == [metadata])
        #expect(restored.nip05Resolutions == [accountID: resolution])
        #expect(!restored.hasMoreOlder)
    }

    @Test("Nostr event store restores follows and relays from replaceable heads")
    func eventStoreHomeTimelineReplaceableHeads() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "f", count: 64)
        let followed = String(repeating: "a", count: 64)
        let note = nostrEvent(kind: 1, pubkey: followed, createdAt: 200, content: "followed")
        let relayList = nostrEvent(
            kind: 10002,
            pubkey: accountID,
            createdAt: 150,
            tags: [["r", "wss://read.example", "read"]]
        )
        let contacts = nostrEvent(
            kind: 3,
            pubkey: accountID,
            createdAt: 160,
            tags: [["p", followed]]
        )
        let state = NostrHomeTimelineState(
            relays: ["wss://stale.example"],
            followedPubkeys: [],
            noteEvents: [note],
            metadataEvents: [],
            relayListEvent: relayList,
            contactListEvent: contacts,
            hasMoreOlder: true
        )

        try store.saveHomeTimelineState(state, accountID: accountID, savedAt: 300)
        let restored = try #require(try store.homeTimelineState(accountID: accountID))

        #expect(restored.relays == ["wss://read.example"])
        #expect(restored.followedPubkeys == [followed])
        #expect(restored.relayListEvent == relayList)
        #expect(restored.contactListEvent == contacts)
    }

    @Test("Nostr event store restores home state after store recreation")
    func eventStoreHomeTimelineSurvivesStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AstrenzaCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("nostr.sqlite")
        let accountID = String(repeating: "f", count: 64)
        let followed = String(repeating: "1", count: 64)
        let note = nostrEvent(kind: 1, pubkey: followed, createdAt: 200, content: "persisted home")
        let relayList = nostrEvent(
            kind: 10002,
            pubkey: accountID,
            createdAt: 150,
            tags: [
                ["r", "wss://read.example", "read"],
                ["r", "wss://write.example", "write"]
            ]
        )
        let contacts = nostrEvent(kind: 3, pubkey: accountID, createdAt: 160, tags: [["p", followed]])
        let metadata = nostrEvent(kind: 0, pubkey: followed, createdAt: 140, content: #"{"name":"Persisted"}"#)

        do {
            let store = try NostrEventStore(path: databaseURL.path)
            try store.saveHomeTimelineState(
                NostrHomeTimelineState(
                    relays: ["wss://stale.example"],
                    followedPubkeys: [],
                    noteEvents: [note],
                    metadataEvents: [metadata],
                    relayListEvent: relayList,
                    contactListEvent: contacts,
                    hasMoreOlder: false
                ),
                accountID: accountID,
                savedAt: 300
            )
        }

        let reopenedStore = try NostrEventStore(path: databaseURL.path)
        let restored = try #require(try reopenedStore.homeTimelineState(accountID: accountID))

        #expect(restored.relays == ["wss://read.example"])
        #expect(restored.followedPubkeys == [followed])
        #expect(restored.noteEvents == [note])
        #expect(restored.metadataEvents == [metadata])
        #expect(restored.relayListEvent == relayList)
        #expect(restored.contactListEvent == contacts)
        #expect(!restored.hasMoreOlder)
    }

    @Test("Nostr event store restores bounded slice from persisted timeline events")
    func eventStoreRestoresBoundedTimelineSlice() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "f", count: 64)
        let author = String(repeating: "2", count: 64)
        let notes = (0..<250).map { index in
            nostrEvent(kind: 1, pubkey: author, createdAt: 1_800_000_000 + index, content: "large timeline \(index)")
        }
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [author],
            noteEvents: notes,
            metadataEvents: [],
            hasMoreOlder: true
        )

        try store.saveHomeTimelineState(state, accountID: accountID, savedAt: 1_800_010_001)
        let restored = try #require(try store.homeTimelineState(accountID: accountID, limit: 25))

        #expect(restored.noteEvents.count == 25)
        #expect(restored.noteEvents.map(\.createdAt) == Array((1_800_000_225...1_800_000_249).reversed()))
        #expect(restored.noteEvents.first?.content == "large timeline 249")
        #expect(restored.noteEvents.last?.content == "large timeline 225")
    }

    @Test("Nostr event store returns local backfill events for NIP-77")
    func eventStoreLocalBackfillEvents() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let matching = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "matching")
        let tooNew = nostrEvent(kind: 1, pubkey: author, createdAt: 300, content: "too-new")
        let otherKind = nostrEvent(kind: 0, pubkey: author, createdAt: 90, content: "{}")

        try store.save(events: [matching, tooNew, otherKind])

        #expect(try store.events(kind: 1, authors: [author], until: 200, limit: 10).map(\.id) == [matching.id])
    }

    @Test("Nostr event store returns profile events by author")
    func eventStoreProfileEventsByAuthor() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let other = String(repeating: "b", count: 64)
        let newest = nostrEvent(kind: 1, pubkey: author, createdAt: 300, content: "newest")
        let oldest = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "oldest")
        let otherAuthor = nostrEvent(kind: 1, pubkey: other, createdAt: 200, content: "other")

        try store.save(events: [oldest, otherAuthor, newest])

        #expect(try store.events(kind: 1, authors: [author], limit: 10).map(\.id) == [newest.id, oldest.id])
    }

    @Test("Nostr event store returns replies by event reference")
    func eventStoreRepliesByReference() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let parent = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "parent")
        let reply = nostrEvent(kind: 1, pubkey: author, createdAt: 120, content: "reply", tags: [["e", parent.id, "", "reply"]])
        let unrelated = nostrEvent(kind: 1, pubkey: author, createdAt: 130, content: "unrelated")

        try store.save(events: [parent, reply, unrelated])

        #expect(try store.eventsReferencing(eventID: parent.id, kind: 1, limit: 10).map(\.id) == [reply.id])
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
        #expect(item.nip05Status == .unchecked)
        #expect(item.isFollowed)
        #expect(item.body == "hello nostr")
        #expect(item.avatarPictureState == .resolved)
        #expect(item.avatarImageURL?.absoluteString == "https://cdn.example.test/avatar.png")
    }

    @Test("Home materializer applies NIP-05 verification status")
    func homeTimelineMaterializerNIP05Status() throws {
        let pubkey = String(repeating: "d", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "verified identity")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"display_name":"Reader","nip05":"reader@example.com"}"#
        )
        let resolution = NostrNIP05Resolution(
            identifier: "reader@example.com",
            pubkey: pubkey,
            relays: [],
            status: .verified
        )

        let item = try #require(NostrHomeTimelineMaterializer.items(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey],
            nip05Resolutions: [pubkey: resolution]
        ).first)

        #expect(item.nip05Status == .verified)
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
        #expect(state.relaySyncEvents.map(\.subscriptionID).contains("astrenza-home"))
        #expect(state.relaySyncEvents.allSatisfy { $0.kind == .eose })
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

    @Test("Home timeline loader records relay timeout results")
    func homeTimelineLoaderRecordsRelayTimeouts() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let fake = FakeRelayClient(
            eventsBySubscriptionID: [
                "astrenza-kind3": [nostrEvent(kind: 3, pubkey: account.pubkey, tags: [])]
            ],
            failingSubscriptionIDs: ["astrenza-nip65"]
        )
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.initialState(account: account)

        #expect(state.relays == ["wss://bootstrap.example"])
        #expect(state.relaySyncEvents.contains { $0.subscriptionID == "astrenza-nip65" && $0.kind == .timeout })
        #expect(state.relaySyncEvents.contains { $0.subscriptionID == "astrenza-kind3" && $0.kind == .eose })
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

    @Test("Home timeline loader uses database local events for NIP-77 backfill")
    func homeTimelineLoaderUsesLocalBackfillEvents() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let currentNote = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 300, content: "current")
        let cachedOlder = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 100, content: "cached")
        let remoteOlder = signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 90, content: "remote")
        let fake = FakeRelayClient(
            eventsBySubscriptionID: [
                "astrenza-home-older": [],
                "astrenza-gap-events": [remoteOlder]
            ],
            missingIDsBySubscriptionID: ["astrenza-neg-gap": [remoteOlder.id]]
        )
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)
        let current = NostrHomeTimelineState(
            relays: ["wss://read.example"],
            followedPubkeys: [followed],
            noteEvents: [currentNote],
            metadataEvents: []
        )

        _ = try await loader.olderState(account: account, current: current, localBackfillEvents: [cachedOlder])

        #expect(await fake.missingLocalEventIDs() == [cachedOlder.id])
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

private actor LockedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor FakeNostrSigner: NostrEventSigning {
    private var events: [NostrEvent] = []

    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        let event = NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: String(repeating: "1", count: 128)
        )
        events.append(event)
        return event
    }

    func signedEvents() -> [NostrEvent] {
        events
    }
}

private func httpResponse(url: URL?, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url ?? URL(string: "https://example.test")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
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
    private let failingSubscriptionIDs: Set<String>
    private var fetchCalls: [String] = []
    private var missingCalls: [String] = []
    private var latestMissingLocalEventIDs: [String] = []

    init(
        eventsBySubscriptionID: [String: [NostrEvent]],
        missingIDsBySubscriptionID: [String: [String]] = [:],
        failingSubscriptionIDs: Set<String> = []
    ) {
        self.eventsBySubscriptionID = eventsBySubscriptionID
        self.missingIDsBySubscriptionID = missingIDsBySubscriptionID
        self.failingSubscriptionIDs = failingSubscriptionIDs
    }

    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        fetchCalls.append(request.subscriptionID)
        if failingSubscriptionIDs.contains(request.subscriptionID) {
            throw NostrRelayClientError.timeout
        }
        return eventsBySubscriptionID[request.subscriptionID] ?? []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        missingCalls.append(subscriptionID)
        latestMissingLocalEventIDs = localEvents.map(\.id)
        return missingIDsBySubscriptionID[subscriptionID] ?? []
    }

    func fetchSubscriptionIDs() -> [String] {
        fetchCalls
    }

    func missingSubscriptionIDs() -> [String] {
        missingCalls
    }

    func missingLocalEventIDs() -> [String] {
        latestMissingLocalEventIDs
    }
}
