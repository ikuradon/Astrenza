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

    @Test("NIP-19 nprofile decodes TLV pubkey and relay hints")
    func nip19NProfileDecodesTLV() throws {
        let profile = try NostrNIP19.profileReference(
            from: "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        )

        #expect(profile.pubkey == "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
        #expect(profile.relays == ["wss://r.x.com", "wss://djbas.sadkb.com"])
    }

    @Test("NIP-19 nevent decodes TLV event id author kind and relay hints")
    func nip19NEventDecodesTLV() throws {
        let eventID = String(repeating: "a", count: 64)
        let author = String(repeating: "b", count: 64)
        let encoded = try NostrNIP19.encodeEventReference(
            eventID: eventID,
            relays: ["wss://relay.example"],
            author: author,
            kind: 1
        )

        let decoded = try NostrNIP19.eventReference(from: encoded)

        #expect(decoded.eventID == eventID)
        #expect(decoded.relays == ["wss://relay.example"])
        #expect(decoded.author == author)
        #expect(decoded.kind == 1)
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

    @Test("Login resolver accepts root NIP-05 identifiers")
    func loginResolverRootNIP05() async throws {
        let pubkey = String(repeating: "c", count: 64)
        let resolver = NostrLoginResolver(
            nip05Resolver: NostrNIP05Resolver(cache: NostrNIP05Cache(defaults: nil)) { request in
                #expect(request.url?.absoluteString == "https://example.test/.well-known/nostr.json?name=_")
                let data = Data(#"{"names":{"_":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},"relays":{"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc":["wss://hint.example"]}}"#.utf8)
                return (data, httpResponse(url: request.url, statusCode: 200))
            }
        )

        let account = try await resolver.resolve("_@example.test")

        #expect(account.pubkey == pubkey)
        #expect(account.displayIdentifier == "_@example.test")
        #expect(account.discoveryRelays == ["wss://hint.example"])
        #expect(account.readOnly)
    }

    @Test("Login resolver rewrites bare domains to root NIP-05 identifiers")
    func loginResolverBareDomainAsRootNIP05() async throws {
        let pubkey = String(repeating: "d", count: 64)
        let resolver = NostrLoginResolver(
            nip05Resolver: NostrNIP05Resolver(cache: NostrNIP05Cache(defaults: nil)) { request in
                #expect(request.url?.absoluteString == "https://example.test/.well-known/nostr.json?name=_")
                let data = Data(#"{"names":{"_":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}"#.utf8)
                return (data, httpResponse(url: request.url, statusCode: 200))
            }
        )

        let account = try await resolver.resolve("example.test")

        #expect(account.pubkey == pubkey)
        #expect(account.displayIdentifier == "_@example.test")
        #expect(account.readOnly)
    }

    @Test("NIP-05 resolver can run without caching for login")
    func loginNIP05ResolverCanSkipCache() async throws {
        let pubkey = String(repeating: "e", count: 64)
        let callCount = LockedCounter()
        let resolver = NostrLoginResolver(
            nip05Resolver: NostrNIP05Resolver(cache: nil) { request in
                await callCount.increment()
                #expect(request.url?.absoluteString == "https://example.test/.well-known/nostr.json?name=_")
                let data = Data(#"{"names":{"_":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}}"#.utf8)
                return (data, httpResponse(url: request.url, statusCode: 200))
            }
        )

        let first = try await resolver.resolve("example.test")
        let second = try await resolver.resolve("example.test")

        #expect(first.pubkey == pubkey)
        #expect(second.pubkey == pubkey)
        #expect(await callCount.value == 2)
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

    @Test("NIP-05 cache expires stale verified resolutions")
    func nip05CacheExpiresStaleVerifiedResolutions() async {
        let cache = NostrNIP05Cache(defaults: nil)
        let freshPolicy = NostrNIP05CachePolicy(verifiedTTLSeconds: 60, failureTTLSeconds: 10)
        let stale = NostrNIP05Resolution(
            identifier: "alice@example.test",
            pubkey: String(repeating: "a", count: 64),
            relays: [],
            status: .verified,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )

        await cache.store(stale, expectedPubkey: stale.pubkey)
        let cached = await cache.resolution(
            for: "alice@example.test",
            expectedPubkey: stale.pubkey,
            now: Date(timeIntervalSince1970: 120),
            policy: freshPolicy
        )
        let expired = await cache.resolution(
            for: "alice@example.test",
            expectedPubkey: stale.pubkey,
            now: Date(timeIntervalSince1970: 200),
            policy: freshPolicy
        )

        #expect(cached == stale)
        #expect(expired == nil)
    }

    @Test("NIP-05 resolver refreshes stale verified cache")
    func nip05ResolverRefreshesStaleVerifiedCache() async throws {
        let oldPubkey = String(repeating: "a", count: 64)
        let newPubkey = String(repeating: "b", count: 64)
        let cache = NostrNIP05Cache(defaults: nil)
        await cache.store(
            NostrNIP05Resolution(
                identifier: "alice@example.test",
                pubkey: oldPubkey,
                relays: [],
                status: .verified,
                resolvedAt: Date(timeIntervalSince1970: 100)
            ),
            expectedPubkey: nil
        )
        let callCount = LockedCounter()
        let resolver = NostrNIP05Resolver(
            cache: cache,
            cachePolicy: NostrNIP05CachePolicy(verifiedTTLSeconds: 1, failureTTLSeconds: 1)
        ) { request in
            await callCount.increment()
            #expect(request.url?.absoluteString == "https://example.test/.well-known/nostr.json?name=alice")
            let data = Data(#"{"names":{"alice":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}"#.utf8)
            return (data, httpResponse(url: request.url, statusCode: 200))
        }

        let refreshed = await resolver.resolve(identifier: "alice@example.test", expectedPubkey: nil)

        #expect(refreshed.pubkey == newPubkey)
        #expect(refreshed.status == .verified)
        #expect(await callCount.value == 1)
    }

    @Test("NIP-05 cache uses shorter TTL for failed resolutions")
    func nip05CacheUsesShorterTTLForFailures() async {
        let cache = NostrNIP05Cache(defaults: nil)
        let policy = NostrNIP05CachePolicy(verifiedTTLSeconds: 3_600, failureTTLSeconds: 30)
        let failed = NostrNIP05Resolution(
            identifier: "alice@example.test",
            pubkey: nil,
            relays: [],
            status: .failed,
            resolvedAt: Date(timeIntervalSince1970: 100)
        )

        await cache.store(failed, expectedPubkey: nil)
        let cached = await cache.resolution(
            for: "alice@example.test",
            expectedPubkey: nil,
            now: Date(timeIntervalSince1970: 120),
            policy: policy
        )
        let expired = await cache.resolution(
            for: "alice@example.test",
            expectedPubkey: nil,
            now: Date(timeIntervalSince1970: 140),
            policy: policy
        )

        #expect(cached == failed)
        #expect(expired == nil)
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

    @Test("Nostr event store returns replaceable head received timestamps")
    func eventStoreReplaceableHeadReceivedAtByPubkey() throws {
        let store = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "e", count: 64)
        let metadata = nostrEvent(kind: 0, pubkey: pubkey, createdAt: 100, content: #"{"name":"cached"}"#)

        try store.save(events: [metadata], receivedAt: 1234)

        #expect(try store.latestReplaceableEventReceivedAtByPubkey(pubkeys: [pubkey], kind: 0) == [pubkey: 1234])
    }

    @Test("Dependency fetch queue batches missing dependencies by relay hint")
    func dependencyFetchQueueBatchesMissingDependenciesByRelayHint() {
        let pubkey = String(repeating: "a", count: 64)
        let eventID = String(repeating: "b", count: 64)
        var queue = NostrDependencyFetchQueue(
            policy: NostrDependencyFetchPolicy(profileStaleAfterSeconds: 60, retryAfterSeconds: 30)
        )
        let dependencies = NostrEventDependencies(
            profilePubkeys: [pubkey, pubkey],
            sourceEventIDs: [eventID],
            profileRelayURLsByPubkey: [pubkey: ["wss://profiles.example", "wss://missing.example"]],
            sourceRelayURLsByEventID: [eventID: ["wss://source.example"]]
        )

        let didEnqueue = queue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://profiles.example", "wss://source.example"],
            now: 100
        )
        let batch = queue.drain()

        #expect(didEnqueue)
        #expect(batch.profileGroups == [
            NostrDependencyFetchGroup(relayURLs: ["wss://profiles.example"], values: [pubkey])
        ])
        #expect(batch.sourceGroups == [
            NostrDependencyFetchGroup(relayURLs: ["wss://source.example"], values: [eventID])
        ])
        #expect(queue.pendingProfilePubkeys == [pubkey])
        #expect(queue.pendingSourceEventIDs == [eventID])
    }

    @Test("Dependency fetch queue refreshes stale profiles but not cached source events")
    func dependencyFetchQueueRefreshesStaleProfilesOnly() {
        let stalePubkey = String(repeating: "c", count: 64)
        let freshPubkey = String(repeating: "d", count: 64)
        let cachedEventID = String(repeating: "e", count: 64)
        let missingEventID = String(repeating: "f", count: 64)
        var queue = NostrDependencyFetchQueue(
            policy: NostrDependencyFetchPolicy(profileStaleAfterSeconds: 60, retryAfterSeconds: 30)
        )
        let dependencies = NostrEventDependencies(
            profilePubkeys: [stalePubkey, freshPubkey],
            sourceEventIDs: [cachedEventID, missingEventID]
        )
        let snapshot = NostrDependencyFetchCacheSnapshot(
            profileReceivedAtByPubkey: [
                stalePubkey: 10,
                freshPubkey: 90
            ],
            sourceEventIDs: [cachedEventID]
        )

        let didEnqueue = queue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: snapshot,
            availableRelayURLs: ["wss://relay.example"],
            now: 100
        )
        let batch = queue.drain()

        #expect(didEnqueue)
        #expect(batch.profileGroups == [
            NostrDependencyFetchGroup(relayURLs: ["wss://relay.example"], values: [stalePubkey])
        ])
        #expect(batch.sourceGroups == [
            NostrDependencyFetchGroup(relayURLs: ["wss://relay.example"], values: [missingEventID])
        ])
    }

    @Test("Dependency fetch queue suppresses retries until backoff expires")
    func dependencyFetchQueueSuppressesRetriesUntilBackoffExpires() {
        let pubkey = String(repeating: "a", count: 64)
        var queue = NostrDependencyFetchQueue(
            policy: NostrDependencyFetchPolicy(profileStaleAfterSeconds: 60, retryAfterSeconds: 30)
        )
        let dependencies = NostrEventDependencies(profilePubkeys: [pubkey])

        let firstEnqueue = queue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://relay.example"],
            now: 100
        )
        _ = queue.drain()
        queue.finish(profilePubkeys: [pubkey], succeeded: false, now: 110)

        let suppressedEnqueue = queue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://relay.example"],
            now: 120
        )
        let retryEnqueue = queue.enqueue(
            dependencies: dependencies,
            cacheSnapshot: NostrDependencyFetchCacheSnapshot(),
            availableRelayURLs: ["wss://relay.example"],
            now: 141
        )

        #expect(firstEnqueue)
        #expect(!suppressedEnqueue)
        #expect(retryEnqueue)
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

    @Test("Nostr attachment classifier prioritizes NIP-92 imeta and dedupes content URLs")
    func attachmentClassifierPrioritizesIMeta() throws {
        let event = nostrEvent(
            kind: 1,
            content: "photo https://cdn.example.test/photo.png read https://example.test/article",
            tags: [["imeta", "url https://cdn.example.test/photo.png", "m image/png", "dim 1200x800", "alt preview"]]
        )

        let attachments = NostrContentAttachmentClassifier.attachments(from: event)

        #expect(attachments.map(\.url.absoluteString) == [
            "https://cdn.example.test/photo.png",
            "https://example.test/article"
        ])
        #expect(attachments[0].kind == .media)
        #expect(attachments[0].source == .imeta(position: 0))
        #expect(attachments[0].mimeType == "image/png")
        #expect(attachments[0].width == 1200)
        #expect(attachments[0].height == 800)
        #expect(attachments[0].alt == "preview")
        #expect(attachments[1].kind == .linkPreview)
        #expect(attachments[1].source == .content(position: 1))
    }

    @Test("Nostr attachment classifier treats direct videos as media")
    func attachmentClassifierTreatsDirectVideosAsMedia() throws {
        let event = nostrEvent(
            kind: 1,
            content: "clip https://video.example.test/movie.mp4 page https://example.test/watch"
        )

        let attachments = NostrContentAttachmentClassifier.attachments(from: event)

        #expect(attachments.map(\.kind) == [.media, .linkPreview])
        #expect(attachments[0].mimeType == "video/mp4")
        #expect(NostrContentAttachmentClassifier.mediaURLs(from: event).map(\.absoluteString) == [
            "https://video.example.test/movie.mp4"
        ])
        #expect(NostrContentAttachmentClassifier.linkPreviewURLs(from: event).map(\.absoluteString) == [
            "https://example.test/watch"
        ])
    }

    @Test("Rich content removes promoted media URLs but keeps fallback clickable URLs")
    func richContentRemovesMediaAndKeepsClickableURLs() throws {
        let event = nostrEvent(
            kind: 1,
            content: "photo https://cdn.example.test/pic.png read https://example.test/page",
            tags: [["imeta", "url https://cdn.example.test/pic.png", "m image/png", "alt image alt"]]
        )
        let attachments = NostrContentAttachmentClassifier.attachments(from: event)

        let rich = NostrRichContentParser.parse(event: event, attachments: attachments, promotedLinkURLs: [])

        #expect(rich.displayText == "photo read https://example.test/page")
        #expect(rich.tokens.contains(.url(url: try #require(URL(string: "https://example.test/page")))))
        #expect(rich.tokens.contains { token in
            if case .url(let url) = token {
                return url.absoluteString == "https://cdn.example.test/pic.png"
            }
            return false
        } == false)
    }

    @Test("Rich content removes promoted link preview URLs")
    func richContentRemovesPromotedLinkPreviewURLs() throws {
        let previewURL = try #require(URL(string: "https://example.test/page"))
        let event = nostrEvent(
            kind: 1,
            content: "read https://example.test/page"
        )

        let rich = NostrRichContentParser.parse(
            event: event,
            attachments: [],
            promotedLinkURLs: [previewURL]
        )

        #expect(rich.displayText == "read")
        #expect(rich.tokens.contains { token in
            if case .url = token {
                return true
            }
            return false
        } == false)
    }

    @Test("Rich content turns tagged custom emoji shortcode into token")
    func richContentParsesCustomEmoji() throws {
        let event = nostrEvent(
            kind: 1,
            content: "hello :astrenza:",
            tags: [["emoji", "astrenza", "https://emoji.example.test/astrenza.png"]]
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])

        #expect(rich.tokens.contains(.customEmoji(
            shortcode: "astrenza",
            url: try #require(URL(string: "https://emoji.example.test/astrenza.png"))
        )))
    }

    @Test("Rich content preserves line breaks and parses hashtags")
    func richContentPreservesLineBreaksAndParsesHashtags() throws {
        let event = nostrEvent(
            kind: 1,
            content: "first line\n#nostr second line\n#swift_lang"
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])

        #expect(rich.displayText == "first line\n#nostr second line\n#swift_lang")
        #expect(rich.tokens.contains(.hashtag("nostr")))
        #expect(rich.tokens.contains(.hashtag("swift_lang")))
    }

    @Test("Rich content parses profile and event references")
    func richContentParsesNostrReferences() throws {
        let pubkey = String(repeating: "c", count: 64)
        let eventID = String(repeating: "d", count: 64)
        let nevent = try NostrNIP19.encodeEventReference(
            eventID: eventID,
            relays: ["wss://relay.example"],
            author: pubkey,
            kind: 1
        )
        let npub = try NostrNIP19.publicKey(pubkey)
        let event = nostrEvent(
            kind: 1,
            content: "hi nostr:\(npub) see nostr:\(nevent)"
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])

        #expect(rich.references.contains(.profile(pubkey: pubkey, relays: [])))
        #expect(rich.references.contains(.event(
            eventID: eventID,
            relays: ["wss://relay.example"],
            author: pubkey,
            kind: 1
        )))
    }

    @Test("Rich content can render profile references with resolved display names")
    func richContentRendersResolvedProfileDisplayNames() throws {
        let pubkey = String(repeating: "c", count: 64)
        let npub = try NostrNIP19.publicKey(pubkey)
        let event = nostrEvent(
            kind: 1,
            content: "hello nostr:\(npub)"
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])
            .resolving(profileDisplayNamesByPubkey: [pubkey: "User Gamma"])

        #expect(rich.displayText == "hello @User Gamma")
        #expect(rich.tokens.map { rich.displayText(for: $0) }.joined() == "hello @User Gamma")
    }

    @Test("Rich content keeps URL trailing punctuation visible")
    func richContentKeepsURLTrailingPunctuationVisible() throws {
        let event = nostrEvent(
            kind: 1,
            content: "read https://example.test/page."
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])

        #expect(rich.displayText == "read https://example.test/page.")
        #expect(rich.tokens.contains(.url(url: try #require(URL(string: "https://example.test/page")))))
        #expect(rich.tokens.last == .text("."))
    }

    @Test("Rich content parses indexed profile and event references")
    func richContentParsesIndexedProfileAndEventReferences() throws {
        let pubkey = String(repeating: "c", count: 64)
        let eventID = String(repeating: "d", count: 64)
        let event = nostrEvent(
            kind: 1,
            content: "hi #[0] see #[1]",
            tags: [
                ["p", pubkey],
                ["e", eventID, "wss://Relay.Example", "mention"]
            ]
        )

        let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])

        #expect(rich.references.contains(.profile(pubkey: pubkey, relays: [])))
        #expect(rich.references.contains(.event(
            eventID: eventID,
            relays: ["wss://relay.example"],
            author: nil,
            kind: nil
        )))
    }

    @Test("Rich content hides promoted event references")
    func richContentHidesPromotedEventReferences() throws {
        let pubkey = String(repeating: "c", count: 64)
        let eventID = String(repeating: "d", count: 64)
        let nevent = try NostrNIP19.encodeEventReference(
            eventID: eventID,
            relays: ["wss://relay.example"],
            author: pubkey,
            kind: 1
        )
        let event = nostrEvent(
            kind: 1,
            content: "see nostr:\(nevent)"
        )

        let rich = NostrRichContentParser.parse(
            event: event,
            attachments: [],
            promotedLinkURLs: [],
            hiddenEventIDs: [eventID]
        )

        #expect(rich.displayText == "see")
        #expect(rich.references.isEmpty)
        #expect(rich.tokens.contains { token in
            if case .event = token {
                return true
            }
            return false
        } == false)
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

    @Test("Nostr event store treats direct video URLs as media not OGP")
    func eventStoreDirectVideoIsMediaNotPreview() throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(
            kind: 1,
            content: "clip https://cdn.example.test/movie.mp4 page https://example.test/article"
        )

        try store.save(events: [event])

        #expect(try store.mediaAssets(eventID: event.id).map(\.url) == ["https://cdn.example.test/movie.mp4"])
        let previews = try store.linkPreviews(urls: [
            try #require(URL(string: "https://cdn.example.test/movie.mp4")),
            try #require(URL(string: "https://example.test/article"))
        ])
        #expect(previews.keys.sorted() == ["https://example.test/article"])
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

    @Test("Nostr link preview resolver stores OGP metadata from unresolved requests")
    func linkPreviewResolverStoresOGPMetadata() async throws {
        let store = try NostrEventStore.inMemory()
        let event = nostrEvent(
            kind: 1,
            content: "read https://example.test/article"
        )
        let html = """
        <html>
          <head>
            <meta property="og:title" content="Resolved &amp; Cached">
            <meta property="og:description" content="OGP summary from source">
            <meta property="og:site_name" content="Example Site">
            <meta property="og:image" content="/og.png">
          </head>
        </html>
        """
        let resolver = NostrLinkPreviewResolver(
            dataLoader: { request in
                #expect(request.url?.absoluteString == "https://example.test/article")
                let data = try #require(html.data(using: .utf8))
                return (data, httpResponse(url: request.url, statusCode: 200))
            },
            now: { Date(timeIntervalSince1970: 1_000) },
            cacheTTLSeconds: 300
        )

        try store.save(events: [event])
        let request = try #require(try store.unresolvedLinkPreviews().first)
        let resolved = await resolver.resolve(request)
        try store.saveLinkPreview(resolved)
        let url = try #require(URL(string: "https://example.test/article"))
        let loaded = try #require(try store.linkPreviews(urls: [url]).values.first)

        #expect(loaded.status == "resolved")
        #expect(loaded.title == "Resolved & Cached")
        #expect(loaded.summary == "OGP summary from source")
        #expect(loaded.siteName == "Example Site")
        #expect(loaded.imageURL == "https://example.test/og.png")
        #expect(loaded.fetchedAt == 1_000)
        #expect(loaded.expiresAt == 1_300)
    }

    @Test("Nostr link preview resolver falls back to oEmbed thumbnail")
    func linkPreviewResolverUsesOEmbedThumbnailFallback() async throws {
        let preview = NostrLinkPreviewRecord(
            url: "https://video.example.test/watch/1",
            normalizedURL: "https://video.example.test/watch/1",
            status: "unresolved",
            title: nil,
            summary: nil,
            siteName: nil,
            imageURL: nil,
            fetchedAt: nil,
            expiresAt: nil,
            error: nil
        )
        let html = """
        <html>
          <head>
            <meta property="og:title" content="Video without OG image">
            <link rel="alternate" type="application/json+oembed" href="/oembed?url=watch-1">
          </head>
        </html>
        """
        let oEmbed = """
        {
          "type": "video",
          "version": "1.0",
          "provider_name": "Example Video",
          "title": "oEmbed Video",
          "thumbnail_url": "https://cdn.example.test/thumb.jpg"
        }
        """
        let resolver = NostrLinkPreviewResolver(
            dataLoader: { request in
                switch request.url?.path {
                case "/watch/1":
                    let data = try #require(html.data(using: .utf8))
                    return (data, httpResponse(url: request.url, statusCode: 200))
                case "/oembed":
                    let data = try #require(oEmbed.data(using: .utf8))
                    return (data, httpResponse(url: request.url, statusCode: 200))
                default:
                    Issue.record("Unexpected URL \(request.url?.absoluteString ?? "nil")")
                    return (Data(), httpResponse(url: request.url, statusCode: 404))
                }
            },
            now: { Date(timeIntervalSince1970: 1_000) },
            cacheTTLSeconds: 300
        )

        let resolved = await resolver.resolve(preview)

        #expect(resolved.status == "resolved")
        #expect(resolved.title == "Video without OG image")
        #expect(resolved.siteName == "Example Video")
        #expect(resolved.imageURL == "https://cdn.example.test/thumb.jpg")
    }

    @Test("Nostr link preview resolver stores failed status for HTTP errors")
    func linkPreviewResolverStoresFailure() async throws {
        let preview = NostrLinkPreviewRecord(
            url: "https://example.test/missing",
            normalizedURL: "https://example.test/missing",
            status: "unresolved",
            title: nil,
            summary: nil,
            siteName: nil,
            imageURL: nil,
            fetchedAt: nil,
            expiresAt: nil,
            error: nil
        )
        let resolver = NostrLinkPreviewResolver(
            dataLoader: { request in
                (Data(), httpResponse(url: request.url, statusCode: 404))
            },
            now: { Date(timeIntervalSince1970: 2_000) },
            cacheTTLSeconds: 3_600
        )

        let failed = await resolver.resolve(preview)

        #expect(failed.status == "failed")
        #expect(failed.error == "HTTP 404")
        #expect(failed.fetchedAt == 2_000)
        #expect(failed.expiresAt == 3_800)
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

    @Test("Nostr event store reads timeline projection windows around anchors")
    func eventStoreTimelineProjectionWindows() throws {
        let store = try NostrEventStore.inMemory()
        let event500 = nostrEvent(kind: 1, createdAt: 500, content: "500")
        let event400 = nostrEvent(kind: 1, createdAt: 400, content: "400")
        let event300 = nostrEvent(kind: 1, createdAt: 300, content: "300")
        let event200 = nostrEvent(kind: 1, createdAt: 200, content: "200")
        let event100 = nostrEvent(kind: 1, createdAt: 100, content: "100")
        try store.save(events: [event100, event200, event300, event400, event500])
        try store.saveTimelineEntries([event100, event200, event300, event400, event500].map { event in
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: event.id,
                sortTimestamp: event.createdAt,
                insertedAt: 600
            )
        })

        #expect(
            try store.timelineEntries(
                accountID: "account",
                timelineKey: "home",
                newerThan: 300,
                limit: 10
            ).map(\.eventID) == [event500.id, event400.id]
        )
        #expect(
            try store.timelineEntries(
                accountID: "account",
                timelineKey: "home",
                olderThan: 300,
                limit: 10
            ).map(\.eventID) == [event200.id, event100.id]
        )
        #expect(
            try store.timelineEntries(
                accountID: "account",
                timelineKey: "home",
                aroundEventID: event300.id,
                leadingLimit: 1,
                trailingLimit: 2
            ).map(\.eventID) == [event400.id, event300.id, event200.id, event100.id]
        )
        #expect(
            try store.events(ids: [event300.id, event500.id, event100.id]).map(\.id) == [
                event300.id,
                event500.id,
                event100.id
            ]
        )
    }

    @Test("Nostr event store can clear resolved gap flags between timeline entries")
    func eventStoreClearsResolvedGapFlags() throws {
        let store = try NostrEventStore.inMemory()
        let older = nostrEvent(kind: 1, createdAt: 100, content: "older")
        let newer = nostrEvent(kind: 1, createdAt: 200, content: "newer")
        try store.save(events: [older, newer])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: newer.id,
                sortTimestamp: newer.createdAt,
                insertedAt: 300,
                gapAfter: true
            ),
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: older.id,
                sortTimestamp: older.createdAt,
                insertedAt: 300,
                gapBefore: true
            )
        ])

        try store.markTimelineGapResolved(
            accountID: "account",
            timelineKey: "home",
            newerEventID: newer.id,
            olderEventID: older.id
        )

        let entries = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10)
        #expect(entries.first { $0.eventID == newer.id }?.gapAfter == false)
        #expect(entries.first { $0.eventID == older.id }?.gapBefore == false)
    }

    @Test("Nostr event store preserves existing gap flags when timeline entries are re-saved")
    func eventStorePreservesGapFlagsOnTimelineEntryUpsert() throws {
        let store = try NostrEventStore.inMemory()
        let older = nostrEvent(kind: 1, createdAt: 100, content: "older")
        let newer = nostrEvent(kind: 1, createdAt: 200, content: "newer")
        try store.save(events: [older, newer])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: newer.id,
                sortTimestamp: newer.createdAt,
                insertedAt: 300,
                gapAfter: true
            ),
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: older.id,
                sortTimestamp: older.createdAt,
                insertedAt: 300,
                gapBefore: true
            )
        ])

        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: newer.id,
                sortTimestamp: newer.createdAt,
                insertedAt: 400
            ),
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: older.id,
                sortTimestamp: older.createdAt,
                insertedAt: 400
            )
        ])

        let entries = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10)
        #expect(entries.first { $0.eventID == newer.id }?.gapAfter == true)
        #expect(entries.first { $0.eventID == older.id }?.gapBefore == true)
    }

    @Test("Nostr event store can mark a gap between timeline entries")
    func eventStoreMarksGapBetweenTimelineEntries() throws {
        let store = try NostrEventStore.inMemory()
        let older = nostrEvent(kind: 1, createdAt: 100, content: "older")
        let newer = nostrEvent(kind: 1, createdAt: 200, content: "newer")
        try store.save(events: [older, newer])
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: newer.id,
                sortTimestamp: newer.createdAt,
                insertedAt: 300
            ),
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: older.id,
                sortTimestamp: older.createdAt,
                insertedAt: 300
            )
        ])

        try store.markTimelineGap(
            accountID: "account",
            timelineKey: "home",
            newerEventID: newer.id,
            olderEventID: older.id
        )

        let entries = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10)
        #expect(entries.first { $0.eventID == newer.id }?.gapAfter == true)
        #expect(entries.first { $0.eventID == older.id }?.gapBefore == true)
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

    @Test("Nostr event store updates relay cursors from runtime event history")
    func eventStoreRelayRuntimeEventsUpdateCursors() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = "account"
        let relayURL = "wss://relay.example"

        try store.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .connected,
                occurredAt: 2_000,
                subscriptionID: "astrenza-home-forward",
                eventCount: 1,
                newestCreatedAt: 700,
                oldestCreatedAt: 700,
                message: "EVENT received"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .connected,
                occurredAt: 2_010,
                subscriptionID: "astrenza-home-forward",
                eventCount: 1,
                newestCreatedAt: 900,
                oldestCreatedAt: 600,
                message: "EVENT received"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .eose,
                occurredAt: 2_020,
                subscriptionID: "astrenza-home-forward",
                eventCount: 0,
                message: "EOSE received"
            )
        ])

        let cursor = try #require(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: relayURL))
        #expect(cursor.newestCreatedAt == 900)
        #expect(cursor.oldestCreatedAt == 600)
        #expect(cursor.lastEOSEAt == 2_020)
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
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .rejected,
                occurredAt: 50,
                message: "rejected"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .suspended,
                occurredAt: 60,
                message: "suspended"
            )
        ])

        let summary = try #require(try store.relaySyncSummaries(accountID: accountID, timelineKey: "home").first)

        #expect(summary.lastEventKind == .suspended)
        #expect(summary.lastConnectedAt == 10)
        #expect(summary.lastErrorAt == 60)
        #expect(summary.closedCount == 1)
        #expect(summary.authRequiredCount == 1)
        #expect(summary.paymentRequiredCount == 1)
        #expect(summary.rejectedCount == 1)
        #expect(summary.suspendedCount == 1)
    }

    @Test("Nostr relay sync summary only treats fresh reachable states as recently reachable")
    func relaySyncSummaryFreshReachability() {
        let fresh = NostrRelaySyncSummaryRecord(
            relayURL: "wss://relay.example",
            lastEventKind: .connected,
            lastEventAt: 1_000,
            lastConnectedAt: 1_000,
            lastEOSEAt: nil,
            lastTimeoutAt: nil,
            lastErrorAt: nil,
            closedCount: 0,
            reconnectCount: 0,
            timeoutCount: 0,
            partialFailureCount: 0,
            authRequiredCount: 0,
            paymentRequiredCount: 0,
            lastPartialFailureReason: nil,
            totalEventCount: 1,
            averageEOSELatencyMilliseconds: nil
        )
        let stale = NostrRelaySyncSummaryRecord(
            relayURL: "wss://relay.example",
            lastEventKind: .connected,
            lastEventAt: 700,
            lastConnectedAt: 700,
            lastEOSEAt: nil,
            lastTimeoutAt: nil,
            lastErrorAt: nil,
            closedCount: 0,
            reconnectCount: 0,
            timeoutCount: 0,
            partialFailureCount: 0,
            authRequiredCount: 0,
            paymentRequiredCount: 0,
            lastPartialFailureReason: nil,
            totalEventCount: 1,
            averageEOSELatencyMilliseconds: nil
        )
        let failed = NostrRelaySyncSummaryRecord(
            relayURL: "wss://relay.example",
            lastEventKind: .timeout,
            lastEventAt: 1_000,
            lastConnectedAt: 990,
            lastEOSEAt: nil,
            lastTimeoutAt: 1_000,
            lastErrorAt: 1_000,
            closedCount: 0,
            reconnectCount: 0,
            timeoutCount: 1,
            partialFailureCount: 0,
            authRequiredCount: 0,
            paymentRequiredCount: 0,
            lastPartialFailureReason: nil,
            totalEventCount: 0,
            averageEOSELatencyMilliseconds: nil
        )

        #expect(fresh.isRecentlyReachable(now: 1_060, freshnessWindowSeconds: 180))
        #expect(!stale.isRecentlyReachable(now: 1_000, freshnessWindowSeconds: 180))
        #expect(!failed.isRecentlyReachable(now: 1_020, freshnessWindowSeconds: 180))
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

    @Test("Nostr filter rules honor timeline scope and presentation")
    func filterRulesHonorTimelineScopeAndPresentation() throws {
        let pubkey = String(repeating: "b", count: 64)
        let event = nostrEvent(kind: 1, pubkey: pubkey, content: "hello scoped timeline")
        let homeRule = NostrFilterRuleRecord(
            ruleID: "home",
            accountID: "account",
            kind: .keyword,
            value: "scoped",
            presentation: .maskWithWarning,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )
        let mentionsRule = NostrFilterRuleRecord(
            ruleID: "mentions",
            accountID: "account",
            kind: .keyword,
            value: "scoped",
            presentation: .hide,
            scopes: [.mentions],
            createdAt: 1,
            updatedAt: 1
        )

        let rules = NostrFilterRuleSet(rules: [mentionsRule, homeRule])
        #expect(rules.match(event: event, timeline: .home, now: 20) == .keyword("scoped"))
        #expect(rules.match(event: event, timeline: .threads, now: 20) == nil)
        #expect(homeRule.presentation == .maskWithWarning)
        #expect(mentionsRule.presentation == .hide)
    }

    @Test("Nostr filter rules expose the matching rule details")
    func filterRulesExposeMatchingRuleDetails() throws {
        let event = nostrEvent(kind: 1, content: "hello quiet timeline")
        let rule = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: "account",
            kind: .keyword,
            value: "quiet",
            presentation: .hide,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )

        let match = try #require(NostrFilterRuleSet(rules: [rule]).matchDetail(event: event, timeline: .home, now: 20))
        #expect(match.rule == rule)
        #expect(match.reason == .keyword("quiet"))
    }

    @Test("Nostr home materializer omits hidden filtered items")
    func homeMaterializerOmitsHiddenFilteredItems() throws {
        let hidden = nostrEvent(kind: 1, content: "quiet filtered post")
        let visible = nostrEvent(kind: 1, content: "ordinary post")
        let filterRules = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(
                ruleID: "rule-1",
                accountID: "account",
                kind: .keyword,
                value: "quiet",
                presentation: .hide,
                scopes: [.home],
                createdAt: 1,
                updatedAt: 1
            )
        ])

        let items = NostrHomeTimelineMaterializer.items(
            noteEvents: [hidden, visible],
            metadataEvents: [],
            followedPubkeys: [],
            filterRules: filterRules,
            now: 20
        )

        #expect(items.map(\.id) == [visible.id])
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

    @Test("Nostr event store updates and deletes filter rules by account")
    func eventStoreUpdatesAndDeletesFilterRulesByAccount() throws {
        let store = try NostrEventStore.inMemory()
        let enabled = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: "account-a",
            kind: .keyword,
            value: "noise",
            isEnabled: true,
            createdAt: 100,
            updatedAt: 100
        )
        let disabled = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: "account-a",
            kind: .keyword,
            value: "noise",
            isEnabled: false,
            createdAt: 100,
            updatedAt: 200
        )
        let other = NostrFilterRuleRecord(
            ruleID: "rule-2",
            accountID: "account-b",
            kind: .mutedHashtag,
            value: "nostr",
            createdAt: 150,
            updatedAt: 150
        )

        try store.saveFilterRule(enabled)
        try store.saveFilterRule(other)
        try store.saveFilterRule(disabled)

        #expect(try store.filterRules(accountID: "account-a") == [disabled])
        #expect(try store.filterRules(accountID: "account-b") == [other])

        try store.deleteFilterRule(accountID: "account-b", ruleID: "rule-1")
        #expect(try store.filterRules(accountID: "account-a") == [disabled])
        #expect(try store.filterRules(accountID: "account-b") == [other])

        try store.deleteFilterRule(accountID: "account-a", ruleID: "rule-1")
        #expect(try store.filterRules(accountID: "account-a").isEmpty)
        #expect(try store.filterRules(accountID: "account-b") == [other])
    }

    @Test("Nostr event store persists filter rule options and counts cached matches")
    func eventStorePersistsFilterRuleOptionsAndCountsMatches() throws {
        let store = try NostrEventStore.inMemory()
        let account = String(repeating: "a", count: 64)
        let matching = nostrEvent(kind: 1, pubkey: account, content: "quiet keyword")
        let other = nostrEvent(kind: 1, pubkey: account, content: "ordinary text")
        try store.save(events: [matching, other])

        let rule = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: account,
            kind: .keyword,
            value: "keyword",
            presentation: .hide,
            scopes: [.home, .lists],
            createdAt: 100,
            updatedAt: 100
        )
        try store.saveFilterRule(rule)

        #expect(try store.filterRules(accountID: account) == [rule])
        #expect(try store.filterRuleMatchingCount(accountID: account, rule: rule, timeline: .home, now: 200) == 1)
        #expect(try store.filterRuleMatchingCount(accountID: account, rule: rule, timeline: .mentions, now: 200) == 0)
    }

    @Test("Nostr event store returns cached filter matching events")
    func eventStoreReturnsCachedFilterMatchingEvents() throws {
        let store = try NostrEventStore.inMemory()
        let account = String(repeating: "a", count: 64)
        let newest = nostrEvent(kind: 1, pubkey: account, createdAt: 300, content: "quiet newest")
        let older = nostrEvent(kind: 1, pubkey: account, createdAt: 200, content: "quiet older")
        let other = nostrEvent(kind: 1, pubkey: account, createdAt: 100, content: "ordinary text")
        try store.save(events: [other, older, newest])

        let rule = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: account,
            kind: .keyword,
            value: "quiet",
            scopes: [.home],
            createdAt: 100,
            updatedAt: 100
        )

        let matches = try store.filterRuleMatchingEvents(
            accountID: account,
            rule: rule,
            timeline: .home,
            limit: 10,
            now: 400
        )
        #expect(matches.map(\.id) == [newest.id, older.id])
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
        #expect(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: "wss://relay.example") == nil)
    }

    @Test("Nostr event store only advances relay cursors from relay sync events")
    func eventStoreTimelineSnapshotDoesNotInventRelayCursors() throws {
        let store = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let note = nostrEvent(kind: 1, pubkey: accountID, createdAt: 300, content: "home")
        let state = NostrHomeTimelineState(
            relays: ["wss://seen.example", "wss://silent.example"],
            followedPubkeys: [accountID],
            noteEvents: [note],
            metadataEvents: [],
            hasMoreOlder: true,
            relaySyncEvents: [
                NostrRelaySyncEventRecord(
                    accountID: accountID,
                    timelineKey: "home",
                    relayURL: "wss://seen.example",
                    kind: .eose,
                    occurredAt: 400,
                    subscriptionID: "home-forward",
                    eventCount: 1,
                    newestCreatedAt: 300,
                    oldestCreatedAt: 300,
                    message: "EOSE received"
                )
            ]
        )

        try store.saveHomeTimelineState(state, accountID: accountID, savedAt: 500)

        let seenCursor = try #require(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: "wss://seen.example"))
        #expect(seenCursor.newestCreatedAt == 300)
        #expect(seenCursor.oldestCreatedAt == 300)
        #expect(seenCursor.lastEOSEAt == 400)
        #expect(try store.syncCursor(accountID: accountID, timelineKey: "home", relayURL: "wss://silent.example") == nil)
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

    @Test("Nostr event store searches cached profile metadata candidates")
    func eventStoreSearchesCachedProfileCandidates() throws {
        let store = try NostrEventStore.inMemory()
        let alpha = String(repeating: "a", count: 64)
        let beta = String(repeating: "b", count: 64)
        let alphaMetadata = #"{"display_name":"User Alpha","name":"alpha","nip05":"alpha@mock.example","picture":"https://example.com/a.png"}"#
        let betaMetadata = #"{"name":"Beta Relay","nip05":"relay@mock.example"}"#

        try store.save(events: [
            nostrEvent(kind: 0, pubkey: alpha, createdAt: 100, content: alphaMetadata),
            nostrEvent(kind: 0, pubkey: beta, createdAt: 200, content: betaMetadata)
        ])

        let alphaResults = try store.profileSearchCandidates(query: "alpha", limit: 10)
        #expect(alphaResults.map(\.pubkey) == [alpha])
        #expect(alphaResults.first?.displayName == "User Alpha")
        #expect(alphaResults.first?.nip05 == "alpha@mock.example")
        #expect(alphaResults.first?.pictureURL?.absoluteString == "https://example.com/a.png")

        let relayResults = try store.profileSearchCandidates(query: "relay", limit: 10)
        #expect(relayResults.map(\.pubkey) == [beta])
    }

    @Test("Nostr event store profile search skips malformed metadata")
    func eventStoreProfileSearchSkipsMalformedMetadata() throws {
        let store = try NostrEventStore.inMemory()
        let broken = String(repeating: "c", count: 64)
        let valid = String(repeating: "d", count: 64)

        try store.save(events: [
            nostrEvent(kind: 0, pubkey: broken, createdAt: 100, content: "{"),
            nostrEvent(kind: 0, pubkey: valid, createdAt: 120, content: #"{"name":"Valid User"}"#)
        ])

        let results = try store.profileSearchCandidates(query: "valid", limit: 10)
        #expect(results.map(\.pubkey) == [valid])
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

    @Test("Home timeline loader bootstrap resolves relays and follows without fetching home notes")
    func homeTimelineLoaderBootstrapSkipsHomeNotes() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let relayEvent = nostrEvent(kind: 10002, pubkey: account.pubkey, tags: [["r", "wss://read.example", "read"]])
        let contacts = nostrEvent(kind: 3, pubkey: account.pubkey, tags: [["p", followed]])
        let fake = FakeRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [relayEvent],
            "astrenza-kind3": [contacts],
            "astrenza-home": [signedShapeOnlyEvent(kind: 1, pubkey: followed, createdAt: 300, content: "should not fetch")],
            "astrenza-kind0": [nostrEvent(kind: 0, pubkey: followed, content: #"{"name":"Should Not Fetch"}"#)]
        ])
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.bootstrapState(account: account)

        #expect(state.relays == ["wss://read.example"])
        #expect(state.followedPubkeys == [followed])
        #expect(state.noteEvents.isEmpty)
        #expect(state.metadataEvents.isEmpty)
        #expect(state.relaySyncEvents.map(\.subscriptionID).contains("astrenza-nip65"))
        #expect(state.relaySyncEvents.map(\.subscriptionID).contains("astrenza-kind3"))
        let calls = await fake.fetchSubscriptionIDs()
        #expect(calls.contains("astrenza-nip65"))
        #expect(calls.contains("astrenza-kind3"))
        #expect(!calls.contains("astrenza-home"))
        #expect(!calls.contains("astrenza-kind0"))
    }

    @Test("Home timeline loader uses NIP-05 discovery relays for NIP-65")
    func homeTimelineLoaderUsesNIP05DiscoveryRelays() async throws {
        let account = NostrAccount(
            pubkey: String(repeating: "1", count: 64),
            displayIdentifier: "_@example.test",
            readOnly: true,
            discoveryRelays: ["hint.example"]
        )
        let relayEvent = nostrEvent(kind: 10002, pubkey: account.pubkey, tags: [["r", "wss://read.example", "read"]])
        let fake = FakeRelayClient(eventsByRelayAndSubscriptionID: [
            "wss://hint.example": ["astrenza-nip65": [relayEvent]]
        ])
        let loader = NostrHomeTimelineLoader(relayClient: fake, bootstrapRelays: ["wss://bootstrap.example"], pageLimit: 10)

        let state = try await loader.initialState(account: account)
        let relayURLs = await fake.fetchRelayURLs()

        #expect(state.relays == ["wss://read.example"])
        #expect(relayURLs.contains("wss://hint.example"))
        #expect(relayURLs.contains("wss://read.example"))
    }

    @Test("Home timeline loader chooses the newest NIP-65 relay list")
    func homeTimelineLoaderChoosesNewestNIP65RelayList() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let oldRelayEvent = nostrEvent(
            kind: 10002,
            pubkey: account.pubkey,
            createdAt: 100,
            tags: [["r", "wss://old-read.example", "read"]]
        )
        let newRelayEvent = nostrEvent(
            kind: 10002,
            pubkey: account.pubkey,
            createdAt: 200,
            tags: [["r", "wss://new-read.example", "read"]]
        )
        let fake = FakeRelayClient(
            eventsByRelayAndSubscriptionID: [
                "wss://fast.example": ["astrenza-nip65": [oldRelayEvent]],
                "wss://slow.example": ["astrenza-nip65": [newRelayEvent]]
            ],
            delayNanosecondsByRelayAndSubscriptionID: [
                "wss://slow.example": ["astrenza-nip65": 100_000_000]
            ]
        )
        let loader = NostrHomeTimelineLoader(
            relayClient: fake,
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 10
        )

        let state = try await loader.initialState(account: account)

        #expect(state.relays == ["wss://new-read.example"])
        #expect(state.relayListEvent?.id == newRelayEvent.id)
    }

    @Test("Home timeline bootstrap returns after the first kind 3 relay responds")
    func homeTimelineBootstrapReturnsAfterFirstKind3RelayResponds() async throws {
        let account = NostrAccount(pubkey: String(repeating: "1", count: 64), displayIdentifier: "npub-test", readOnly: true)
        let followed = String(repeating: "2", count: 64)
        let relayEvent = nostrEvent(
            kind: 10002,
            pubkey: account.pubkey,
            tags: [
                ["r", "wss://fast-kind3.example", "read"],
                ["r", "wss://slow-kind3.example", "read"]
            ]
        )
        let contacts = nostrEvent(kind: 3, pubkey: account.pubkey, tags: [["p", followed]])
        let fake = FakeRelayClient(
            eventsByRelayAndSubscriptionID: [
                "wss://bootstrap.example": ["astrenza-nip65": [relayEvent]],
                "wss://fast-kind3.example": ["astrenza-kind3": [contacts]],
                "wss://slow-kind3.example": ["astrenza-kind3": [contacts]]
            ],
            delayNanosecondsByRelayAndSubscriptionID: [
                "wss://slow-kind3.example": ["astrenza-kind3": 2_000_000_000]
            ]
        )
        let loader = NostrHomeTimelineLoader(
            relayClient: fake,
            bootstrapRelays: ["wss://bootstrap.example"],
            pageLimit: 10
        )
        let started = Date()

        let state = try await loader.bootstrapState(account: account)

        #expect(state.followedPubkeys == [followed])
        #expect(Date().timeIntervalSince(started) < 1)
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

    @Test("Relay runtime forward packets keep a stable subscription id")
    func relayRuntimeForwardPacketStableSubID() {
        let packet = NostrREQPacket.forward(
            subscriptionID: "astrenza-home-forward",
            filters: [
                [
                    "kinds": .ints([1]),
                    "authors": .strings([String(repeating: "a", count: 64)]),
                    "since": .int(100)
                ]
            ],
            relayURLs: ["wss://relay.example"]
        )

        #expect(packet.strategy == .forward)
        #expect(packet.subscriptionID == "astrenza-home-forward")
        #expect(packet.groupID == "astrenza-home-forward")
        #expect(packet.relayRequest.subscriptionID == "astrenza-home-forward")
    }

    @Test("Relay runtime backward packets can create unique request subscriptions inside one group")
    func relayRuntimeBackwardPacketUniqueSubIDs() {
        let first = NostrREQPacket.backward(
            purpose: "kind0",
            filters: [["kinds": .ints([0]), "authors": .strings(["a"])]],
            groupID: "profiles-burst",
            subscriptionID: "profiles-burst-1"
        )
        let second = NostrREQPacket.backward(
            purpose: "kind0",
            filters: [["kinds": .ints([0]), "authors": .strings(["b"])]],
            groupID: "profiles-burst",
            subscriptionID: "profiles-burst-2"
        )

        #expect(first.strategy == .backward)
        #expect(second.strategy == .backward)
        #expect(first.groupID == second.groupID)
        #expect(first.subscriptionID != second.subscriptionID)
    }

    @Test("Relay runtime batches compatible kind0 author requests")
    func relayRuntimeBatchesKind0Authors() {
        let firstAuthor = String(repeating: "a", count: 64)
        let secondAuthor = String(repeating: "b", count: 64)
        let first = NostrREQPacket.backward(
            purpose: "kind0",
            filters: [["kinds": .ints([0]), "authors": .strings([firstAuthor])]],
            relayURLs: ["wss://relay.example"],
            groupID: "profiles",
            subscriptionID: "profiles-1"
        )
        let second = NostrREQPacket.backward(
            purpose: "kind0",
            filters: [["kinds": .ints([0]), "authors": .strings([secondAuthor, firstAuthor])]],
            relayURLs: ["wss://relay.example"],
            groupID: "profiles",
            subscriptionID: "profiles-2"
        )

        let batched = NostrREQScheduler.batch([first, second], mergeField: .authors)

        #expect(batched.count == 1)
        #expect(batched[0].filters == [
            ["kinds": .ints([0]), "authors": .strings([firstAuthor, secondAuthor])]
        ])
    }

    @Test("Relay runtime chunks large id requests without dropping ids")
    func relayRuntimeChunksLargeIDRequests() {
        let ids = (0..<7).map { String(repeating: String($0), count: 64) }
        let packet = NostrREQPacket.backward(
            purpose: "sources",
            filters: [["ids": .strings(ids), "kinds": .ints([1])]],
            groupID: "source-events",
            subscriptionID: "source-events-1"
        )

        let chunks = NostrREQScheduler.chunk(
            packet,
            mergeField: .ids,
            policy: NostrREQChunkPolicy(maxIDsPerFilter: 3, maxAuthorsPerFilter: 3, maxFiltersPerRequest: 2)
        )

        let chunkIDs = chunks
            .flatMap(\.filters)
            .flatMap { filter -> [String] in
                guard case .strings(let values)? = filter["ids"] else { return [] }
                return values
            }

        #expect(chunks.count == 2)
        #expect(Set(chunkIDs) == Set(ids))
        #expect(chunkIDs.count == ids.count)
        #expect(chunks.map(\.groupID) == ["source-events", "source-events"])
        #expect(chunks.map(\.subscriptionID) == ["source-events-1-chunk1", "source-events-1-chunk2"])
    }

    @Test("Relay runtime extracts profile and source dependencies from timeline events")
    func relayRuntimeExtractsTimelineDependencies() {
        let author = String(repeating: "a", count: 64)
        let mentioned = String(repeating: "b", count: 64)
        let replyID = String(repeating: "c", count: 64)
        let quoteID = String(repeating: "d", count: 64)
        let event = nostrEvent(
            kind: 1,
            pubkey: author,
            content: "reply with quote",
            tags: [
                ["p", mentioned],
                ["e", replyID, "", "reply"],
                ["q", quoteID]
            ]
        )

        let dependencies = NostrEventDependencies.extract(from: event)

        #expect(dependencies.profilePubkeys == [author, mentioned])
        #expect(dependencies.sourceEventIDs == [replyID, quoteID])
    }

    @Test("Relay runtime extracts dependency relay hints from tags")
    func relayRuntimeExtractsDependencyRelayHints() {
        let author = String(repeating: "a", count: 64)
        let mentioned = String(repeating: "b", count: 64)
        let replyID = String(repeating: "c", count: 64)
        let quoteID = String(repeating: "d", count: 64)
        let event = nostrEvent(
            kind: 1,
            pubkey: author,
            content: "reply with hinted quote",
            tags: [
                ["p", mentioned, "WSS://Profile.Example"],
                ["e", replyID, "wss://Reply.Example", "reply"],
                ["q", quoteID, "wss://quote.example"]
            ]
        )

        let dependencies = NostrEventDependencies.extract(from: event)

        #expect(dependencies.profileRelayURLsByPubkey[mentioned] == ["wss://profile.example"])
        #expect(dependencies.sourceRelayURLsByEventID[replyID] == ["wss://reply.example"])
        #expect(dependencies.sourceRelayURLsByEventID[quoteID] == ["wss://quote.example"])
    }

    @Test("Relay runtime extracts dependencies from rich content references")
    func relayRuntimeExtractsRichContentDependencies() throws {
        let author = String(repeating: "a", count: 64)
        let mentioned = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let sourceID = String(repeating: "c", count: 64)
        let nprofile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let nevent = try NostrNIP19.encodeEventReference(
            eventID: sourceID,
            relays: ["wss://Source.Example"],
            author: mentioned,
            kind: 1
        )
        let event = nostrEvent(
            kind: 1,
            pubkey: author,
            content: "hello nostr:\(nprofile) see nostr:\(nevent)"
        )

        let dependencies = NostrEventDependencies.extract(from: event)

        #expect(dependencies.profilePubkeys == [mentioned, author])
        #expect(dependencies.profileRelayURLsByPubkey[mentioned] == ["wss://djbas.sadkb.com", "wss://r.x.com"])
        #expect(dependencies.sourceEventIDs == [sourceID])
        #expect(dependencies.sourceRelayURLsByEventID[sourceID] == ["wss://source.example"])
    }

    @Test("Relay filter matcher applies standard NIP-01 fields")
    func relayFilterMatcherAppliesStandardFields() {
        let author = String(repeating: "a", count: 64)
        let eventID = String(repeating: "b", count: 64)
        let event = NostrEvent(
            id: eventID,
            pubkey: author,
            createdAt: 200,
            kind: 1,
            tags: [["e", String(repeating: "c", count: 64)], ["t", "nostr"]],
            content: "tagged",
            sig: String(repeating: "d", count: 128)
        )

        #expect(NostrRelayFilterMatcher.matches(event: event, filters: [[
            "ids": .strings([eventID]),
            "authors": .strings([author]),
            "kinds": .ints([1]),
            "since": .int(100),
            "until": .int(300),
            "#t": .strings(["nostr"])
        ]]))
        #expect(!NostrRelayFilterMatcher.matches(event: event, filters: [["kinds": .ints([0])]]))
        #expect(!NostrRelayFilterMatcher.matches(event: event, filters: [["#t": .strings(["swift"])]]))
    }

    @Test("Relay runtime installs batched backward profile requests on default relays")
    func relayRuntimeInstallsBatchedBackwardProfiles() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(transportFactory: { _ in transport }, autoReceive: false)
        let firstAuthor = String(repeating: "a", count: 64)
        let secondAuthor = String(repeating: "b", count: 64)
        let first = try #require(NostrBackwardREQBuilder.profiles(authors: [firstAuthor], requestID: "profiles"))
        let second = try #require(NostrBackwardREQBuilder.profiles(authors: [secondAuthor, firstAuthor], requestID: "profiles"))

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installBackward([first, second], mergeField: .authors)

        let sent = await connection.sentFrames()
        #expect(sent.count == 1)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[0].contains(#""authors":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]"#))
    }

    @Test("Relay runtime older notes backward builder preserves author window")
    func relayRuntimeOlderNotesBackwardBuilder() throws {
        let firstAuthor = String(repeating: "b", count: 64)
        let secondAuthor = String(repeating: "a", count: 64)

        let packet = try #require(NostrBackwardREQBuilder.olderNotes(
            authors: [firstAuthor, secondAuthor, secondAuthor],
            until: 500,
            limit: 40,
            relayURLs: ["wss://relay.example"],
            requestID: "older"
        ))

        #expect(packet.strategy == .backward)
        #expect(packet.groupID == "astrenza-older-notes-older")
        #expect(packet.subscriptionID == "astrenza-older-notes-older-req")
        #expect(packet.relayURLs == ["wss://relay.example"])
        #expect(packet.filters == [[
            "kinds": .ints([1, 5, 6]),
            "authors": .strings([secondAuthor, firstAuthor]),
            "until": .int(500),
            "limit": .int(40)
        ]])
    }

    @Test("Relay runtime gap notes backward builder creates bounded since until windows")
    func relayRuntimeGapNotesBackwardBuilder() throws {
        let firstAuthor = String(repeating: "b", count: 64)
        let secondAuthor = String(repeating: "a", count: 64)

        let packet = try #require(NostrBackwardREQBuilder.notesWindow(
            authors: [firstAuthor, secondAuthor, secondAuthor],
            since: 101,
            until: 299,
            limit: 25,
            relayURLs: ["wss://relay.example"],
            requestID: "gap"
        ))

        #expect(packet.strategy == .backward)
        #expect(packet.groupID == "astrenza-gap-notes-gap")
        #expect(packet.subscriptionID == "astrenza-gap-notes-gap-req")
        #expect(packet.relayURLs == ["wss://relay.example"])
        #expect(packet.filters == [[
            "kinds": .ints([1, 5, 6]),
            "authors": .strings([secondAuthor, firstAuthor]),
            "since": .int(101),
            "until": .int(299),
            "limit": .int(25)
        ]])
    }

    @Test("Relay runtime closes idle backward subscriptions with a timeout packet")
    func relayRuntimeClosesIdleBackwardSubscriptionsWithTimeout() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }

        let packet = try #require(NostrBackwardREQBuilder.profiles(
            authors: [String(repeating: "a", count: 64)],
            relayURLs: ["wss://relay.example"],
            requestID: "idle"
        ))

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installBackward([packet], mergeField: .authors)
        try await Task.sleep(nanoseconds: 80_000_000)

        let sent = await connection.sentFrames()
        let packets = await collector.packets()
        #expect(sent.count == 2)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[1] == #"["CLOSE","astrenza-kind0-idle-req"]"#)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://relay.example").isEmpty)
        #expect(packets.contains { packet in
            if case .timeout("wss://relay.example", "astrenza-kind0-idle-req", "backward idle timeout") = packet {
                return true
            }
            return false
        })
        #expect(packets.contains { packet in
            guard case .backwardCompleted(let completion) = packet else { return false }
            return completion.groupID == "astrenza-kind0-idle"
                && completion.status == .timedOut
                && completion.timeoutCount == 1
                && completion.eventCount == 0
        })
    }

    @Test("Relay runtime emits one backward completion for a chunked group")
    func relayRuntimeEmitsBackwardCompletionForChunkedGroup() async throws {
        let firstAuthor = String(repeating: "a", count: 64)
        let secondAuthor = String(repeating: "b", count: 64)
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-kind0-grouped-req-chunk1"]"#,
            #"["EOSE","astrenza-kind0-grouped-req-chunk2"]"#
        ])
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = try #require(NostrBackwardREQBuilder.profiles(
            authors: [firstAuthor, secondAuthor],
            relayURLs: ["wss://relay.example"],
            requestID: "grouped"
        ))

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installBackward(
            [packet],
            mergeField: .authors,
            chunkPolicy: NostrREQChunkPolicy(maxAuthorsPerFilter: 1, maxFiltersPerRequest: 1)
        )
        try await runtime.receiveNext(relayURL: "wss://relay.example")
        try await runtime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 30_000_000)

        let sent = await connection.sentFrames()
        let completions = await collector.packets().compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion
        }
        #expect(sent.count == 4)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[1].contains(#""REQ""#))
        #expect(sent[2] == #"["CLOSE","astrenza-kind0-grouped-req-chunk1"]"#)
        #expect(sent[3] == #"["CLOSE","astrenza-kind0-grouped-req-chunk2"]"#)
        #expect(completions.count == 1)
        let completion = try #require(completions.first)
        #expect(completion.groupID == "astrenza-kind0-grouped")
        #expect(completion.status == .completed)
        #expect(completion.relayURLs == ["wss://relay.example"])
        #expect(completion.subscriptionIDs == [
            "astrenza-kind0-grouped-req-chunk1",
            "astrenza-kind0-grouped-req-chunk2"
        ])
        #expect(completion.eoseCount == 2)
        #expect(completion.closedCount == 0)
        #expect(completion.timeoutCount == 0)
    }

    @Test("Relay runtime reports partial backward completion when some relays answer")
    func relayRuntimeReportsPartialBackwardCompletion() async throws {
        let answeredConnection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-kind0-partial-req"]"#
        ])
        let timedOutConnection = FakeRelayRuntimeConnection()
        let transports = [
            "wss://answered.example": FakeRelayRuntimeTransport(connection: answeredConnection),
            "wss://timeout.example": FakeRelayRuntimeTransport(connection: timedOutConnection)
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                transports[relayURL] ?? FakeRelayRuntimeTransport(connection: FakeRelayRuntimeConnection())
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = try #require(NostrBackwardREQBuilder.profiles(
            authors: [String(repeating: "c", count: 64)],
            relayURLs: ["wss://answered.example", "wss://timeout.example"],
            requestID: "partial"
        ))

        try await runtime.setDefaultRelays(["wss://answered.example", "wss://timeout.example"])
        try await runtime.installBackward([packet], mergeField: .authors)
        try await runtime.receiveNext(relayURL: "wss://answered.example")
        try await Task.sleep(nanoseconds: 80_000_000)

        let packets = await collector.packets()
        let completion = try #require(packets.compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion.groupID == "astrenza-kind0-partial" ? completion : nil
        }.first)
        #expect(completion.status == .partial)
        #expect(completion.eoseCount == 1)
        #expect(completion.timeoutCount == 1)
    }

    @Test("Relay runtime heartbeat uses an impossible id filter")
    func relayRuntimeHeartbeatUsesImpossibleIDFilter() {
        let packet = NostrBackwardREQBuilder.heartbeat(relayURLs: ["wss://relay.example"], requestID: "probe")

        #expect(packet.strategy == .backward)
        #expect(packet.subscriptionID == "astrenza-heartbeat-probe-req")
        #expect(packet.relayURLs == ["wss://relay.example"])
        #expect(packet.filters == [["ids": .strings([String(repeating: "0", count: 64)])]])
    }

    @Test("Relay runtime can send heartbeat without closing the relay session")
    func relayRuntimeCanSendHeartbeat() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.sendHeartbeat(relayURL: "wss://relay.example")

        let sent = await connection.sentFrames()
        #expect(await transport.connectCallCount() == 1)
        #expect(await !connection.closed())
        #expect(sent.count == 1)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[0].contains(#""ids":["0000000000000000000000000000000000000000000000000000000000000000"]"#))
    }

    @Test("Relay runtime heartbeat participates in backward timeout completion")
    func relayRuntimeHeartbeatParticipatesInBackwardTimeoutCompletion() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.sendHeartbeat(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 80_000_000)

        let sent = await connection.sentFrames()
        let packets = await collector.packets()
        #expect(sent.count == 2)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[0].contains(#""ids":["0000000000000000000000000000000000000000000000000000000000000000"]"#))
        #expect(sent[1].contains(#"["CLOSE","astrenza-heartbeat-"#))
        #expect(packets.contains { packet in
            guard case .timeout("wss://relay.example", let subscriptionID, "backward idle timeout") = packet else {
                return false
            }
            return subscriptionID.hasPrefix("astrenza-heartbeat-")
        })
        #expect(packets.contains { packet in
            guard case .backwardCompleted(let completion) = packet else { return false }
            return completion.groupID.hasPrefix("astrenza-heartbeat-")
                && completion.status == .timedOut
                && completion.timeoutCount == 1
        })
    }

    @Test("Relay runtime reconnects and restores forward subscriptions after heartbeat misses")
    func relayRuntimeReconnectsAfterHeartbeatMisses() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: false,
            heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy(isEnabled: false, reconnectAfterMisses: 1),
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }

        let forward = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installForward(forward)
        try await runtime.sendHeartbeat(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 100_000_000)

        let sent = await connection.sentFrames()
        let packets = await collector.packets()
        #expect(await transport.connectCallCount() == 2)
        #expect(await connection.closed())
        #expect(await runtime.connectionState(relayURL: "wss://relay.example") == .connected)
        #expect(sent.count == 4)
        #expect(sent[0].contains(#""REQ""#))
        #expect(sent[0].contains(#""home-forward""#))
        #expect(sent[1].contains(#""ids":["0000000000000000000000000000000000000000000000000000000000000000"]"#))
        #expect(sent[2].contains(#"["CLOSE","astrenza-heartbeat-"#))
        #expect(sent[3] == sent[0])
        #expect(packets.contains { packet in
            if case .stateChanged("wss://relay.example", .waitingForRetry) = packet {
                return true
            }
            return false
        })
        #expect(packets.contains { packet in
            if case .stateChanged("wss://relay.example", .retrying) = packet {
                return true
            }
            return false
        })
        #expect(packets.contains { packet in
            if case .stateChanged("wss://relay.example", .connected) = packet {
                return true
            }
            return false
        })
    }

    @Test("Relay session emits state changes only when the state actually changes")
    func relaySessionEmitsDistinctStateChanges() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let collector = RelayRuntimePacketCollector()
        let stream = await session.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }

        try await session.connect()
        await session.markWaitingForRetry(message: "first timeout")
        await session.markWaitingForRetry(message: "second timeout")
        await session.markSuspended(message: "retry attempts exhausted")
        await session.markSuspended(message: "still suspended")
        try await Task.sleep(nanoseconds: 10_000_000)

        let states = await collector.packets().compactMap { packet -> NostrRelayConnectionState? in
            guard case .stateChanged("wss://relay.example", let state) = packet else { return nil }
            return state
        }

        #expect(states == [.connecting, .connected, .waitingForRetry, .suspended])
    }

    @Test("Relay runtime heartbeat loop starts for auto receive sessions")
    func relayRuntimeHeartbeatLoopStartsForAutoReceiveSessions() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(maxAttempts: 0, initialDelayMilliseconds: 0, delayStepMilliseconds: 0),
            heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy(initialDelayMilliseconds: 0, intervalMilliseconds: 1_000)
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await Task.sleep(nanoseconds: 30_000_000)

        let sent = await connection.sentFrames()
        #expect(sent.contains { $0.contains("astrenza-heartbeat-") })
        #expect(sent.contains { $0.contains(#""ids":["0000000000000000000000000000000000000000000000000000000000000000"]"#) })
    }

    @Test("Relay session keeps forward subscriptions active after EOSE")
    func relaySessionKeepsForwardSubscriptionAfterEOSE() async throws {
        let connection = FakeRelayRuntimeConnection(inboundFrames: [#"["EOSE","home-forward"]"#])
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "since": .int(100)]]
        )

        try await session.install(packet)
        try await session.receiveNext()

        #expect(await transport.connectCallCount() == 1)
        #expect(await session.activeSubscriptionIDs() == ["home-forward"])
        #expect(await connection.sentFrames().count == 1)
    }

    @Test("Relay session ignores signed events that do not match subscription filters")
    func relaySessionIgnoresFilterMismatchedEvents() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "41", count: 32))
        let event = try await signer.sign(
            NostrPublishInput.post(content: "valid but wrong kind filter")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            try relayRuntimeEventFrame(subscriptionID: "home-forward", event: event)
        ])
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let collector = RelayRuntimePacketCollector()
        let collectTask = Task {
            for await packet in await session.events() {
                await collector.append(packet)
            }
        }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([0]), "authors": .strings([signer.pubkey])]]
        )

        try await session.install(packet)
        try await session.receiveNext()
        try await Task.sleep(nanoseconds: 30_000_000)
        collectTask.cancel()

        #expect(await collector.packets().contains { packet in
            if case .event = packet { return true }
            return false
        } == false)
    }

    @Test("Relay session ignores events with invalid signatures")
    func relaySessionIgnoresInvalidSignatures() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "42", count: 32))
        let event = try await signer.sign(
            NostrPublishInput.post(content: "valid original")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 210)
        )
        let tampered = NostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: "tampered body",
            sig: event.sig
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            try relayRuntimeEventFrame(subscriptionID: "home-forward", event: tampered)
        ])
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let collector = RelayRuntimePacketCollector()
        let collectTask = Task {
            for await packet in await session.events() {
                await collector.append(packet)
            }
        }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "authors": .strings([signer.pubkey])]]
        )

        try await session.install(packet)
        try await session.receiveNext()
        try await Task.sleep(nanoseconds: 30_000_000)
        collectTask.cancel()

        #expect(await collector.packets().contains { packet in
            if case .event = packet { return true }
            return false
        } == false)
    }

    @Test("Relay session closes backward subscriptions after EOSE")
    func relaySessionClosesBackwardSubscriptionAfterEOSE() async throws {
        let connection = FakeRelayRuntimeConnection(inboundFrames: [#"["EOSE","profile-backward"]"#])
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let packet = NostrREQPacket.backward(
            purpose: "kind0",
            filters: [["kinds": .ints([0]), "authors": .strings([String(repeating: "a", count: 64)])]],
            groupID: "profile-backward",
            subscriptionID: "profile-backward"
        )

        try await session.install(packet)
        try await session.receiveNext()

        let sent = await connection.sentFrames()
        #expect(await transport.connectCallCount() == 1)
        #expect(await session.activeSubscriptionIDs().isEmpty)
        #expect(sent.count == 2)
        #expect(sent[1] == #"["CLOSE","profile-backward"]"#)
    }

    @Test("Relay session reconnect restores active forward subscriptions")
    func relaySessionReconnectRestoresActiveForwardSubscriptions() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )

        try await session.install(packet)
        try await session.reconnectRestoringSubscriptions()

        let sent = await connection.sentFrames()
        #expect(await transport.connectCallCount() == 2)
        #expect(await connection.closed())
        #expect(await session.state() == .connected)
        #expect(await session.activeSubscriptionIDs() == ["home-forward"])
        #expect(sent.count == 2)
        #expect(sent[0] == sent[1])
    }

    @Test("Home forward REQ builder creates stable reconnect filters with overlap")
    func homeForwardREQBuilderCreatesReconnectFilter() {
        let firstAuthor = String(repeating: "b", count: 64)
        let secondAuthor = String(repeating: "a", count: 64)

        let packet = NostrHomeForwardREQBuilder.reconnectPacket(
            authors: [firstAuthor, secondAuthor, secondAuthor],
            newestCreatedAt: 1_800_000_100,
            overlapSeconds: 15,
            relayURLs: ["wss://relay.example"]
        )

        #expect(packet.strategy == .forward)
        #expect(packet.subscriptionID == "astrenza-home-forward")
        #expect(packet.relayURLs == ["wss://relay.example"])
        #expect(packet.filters == [
            [
                "kinds": .ints([1, 5, 6]),
                "authors": .strings([secondAuthor, firstAuthor]),
                "since": .int(1_800_000_085)
            ]
        ])
    }

    @Test("Relay runtime restores active forward REQs on newly added default relays")
    func relayRuntimeRestoresForwardREQOnAddedRelay() async throws {
        let firstConnection = FakeRelayRuntimeConnection()
        let secondConnection = FakeRelayRuntimeConnection()
        let transports = [
            "wss://one.example": FakeRelayRuntimeTransport(connection: firstConnection),
            "wss://two.example": FakeRelayRuntimeTransport(connection: secondConnection)
        ]
        let runtime = NostrRelayRuntime(transportFactory: { relayURL in
            transports[relayURL] ?? FakeRelayRuntimeTransport(connection: FakeRelayRuntimeConnection())
        }, autoReceive: false)
        let packet = NostrHomeForwardREQBuilder.packet(
            authors: [String(repeating: "a", count: 64)],
            since: 100
        )

        try await runtime.setDefaultRelays(["wss://one.example"])
        try await runtime.installForward(packet)
        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])

        #expect(await runtime.defaultRelayURLs() == ["wss://one.example", "wss://two.example"])
        #expect(await runtime.activeForwardSubscriptionIDs() == ["astrenza-home-forward"])
        #expect(await firstConnection.sentFrames().count == 1)
        #expect(await secondConnection.sentFrames().count == 1)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://two.example") == ["astrenza-home-forward"])
    }

    @Test("Relay runtime terminates sessions removed from default relays")
    func relayRuntimeTerminatesRemovedDefaultRelay() async throws {
        let firstConnection = FakeRelayRuntimeConnection()
        let secondConnection = FakeRelayRuntimeConnection()
        let transports = [
            "wss://one.example": FakeRelayRuntimeTransport(connection: firstConnection),
            "wss://two.example": FakeRelayRuntimeTransport(connection: secondConnection)
        ]
        let runtime = NostrRelayRuntime(transportFactory: { relayURL in
            transports[relayURL] ?? FakeRelayRuntimeTransport(connection: FakeRelayRuntimeConnection())
        }, autoReceive: false)

        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])
        try await runtime.setDefaultRelays(["wss://two.example"])

        #expect(await runtime.defaultRelayURLs() == ["wss://two.example"])
        #expect(await firstConnection.closed())
        #expect(await !secondConnection.closed())
        #expect(await runtime.connectionState(relayURL: "wss://one.example") == .initialized)
        #expect(await runtime.connectionState(relayURL: "wss://two.example") == .connected)
    }

    @Test("Relay runtime suspends auto receive after retry exhaustion")
    func relayRuntimeSuspendsAutoReceiveAfterRetryExhaustion() async throws {
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(maxAttempts: 1, initialDelayMilliseconds: 0, delayStepMilliseconds: 0)
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(await transport.connectCallCount() >= 2)
        #expect(await runtime.connectionState(relayURL: "wss://relay.example") == .suspended)
    }

    @Test("Relay runtime resumes forward receive after retry exhaustion")
    func relayRuntimeResumesForwardReceiveAfterRetryExhaustion() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "43", count: 32))
        let event = try await signer.sign(
            NostrPublishInput.post(content: "recovered")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let connection = FakeRelayRuntimeConnection()
        let transport = FakeRelayRuntimeTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(maxAttempts: 0, initialDelayMilliseconds: 0, delayStepMilliseconds: 0),
            heartbeatPolicy: .disabled
        )
        let collector = RelayRuntimePacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }

        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "authors": .strings([signer.pubkey])]]
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installForward(packet)
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(await runtime.connectionState(relayURL: "wss://relay.example") == .suspended)

        await connection.appendInboundFrames([try relayRuntimeEventFrame(subscriptionID: "home-forward", event: event)])
        try await Task.sleep(nanoseconds: 80_000_000)

        let packets = await collector.packets()
        #expect(packets.contains { packet in
            if case .event("wss://relay.example", "home-forward", event) = packet {
                return true
            }
            return false
        })
    }

    @Test("Sync policy defaults to own relay list and tap-to-load on cellular")
    func syncPolicyDefaults() {
        let wifi = NostrSyncPolicy.default(networkType: .wifi, lowPowerMode: false)
        #expect(wifi.mode == .ownRelayList)
        #expect(!wifi.tapToLoadMedia)
        #expect(wifi.queueOGPPreviews)

        let cellular = NostrSyncPolicy.default(networkType: .cellular, lowPowerMode: false)
        #expect(cellular.mode == .ownRelayList)
        #expect(cellular.tapToLoadMedia)
        #expect(cellular.disableOGPOnCellular)

        let lowPower = NostrSyncPolicy.default(networkType: .wifi, lowPowerMode: true)
        #expect(lowPower.mode == .energySaver)
        #expect(lowPower.tapToLoadMedia)
    }

    @Test("Relay traffic counters accumulate by hour relay network and sync mode")
    func relayTrafficCountersAccumulate() throws {
        let store = try NostrEventStore.inMemory()
        let hour = 1_717_891_200
        let first = NostrRelayTrafficDelta(
            accountID: "account",
            relayURL: "wss://relay.example",
            occurredAt: hour + 30,
            networkType: .wifi,
            syncMode: .ownRelayList,
            receivedBytes: 120,
            sentBytes: 40,
            receivedMessages: 2,
            sentMessages: 1
        )
        let second = NostrRelayTrafficDelta(
            accountID: "account",
            relayURL: "wss://relay.example",
            occurredAt: hour + 600,
            networkType: .wifi,
            syncMode: .ownRelayList,
            receivedBytes: 80,
            sentBytes: 10,
            receivedMessages: 1,
            sentMessages: 1
        )

        try store.recordRelayTraffic([first, second])

        let totals = try store.relayTrafficTotals(
            accountID: "account",
            start: hour,
            end: hour + 3_600
        )
        #expect(totals.receivedBytes == 200)
        #expect(totals.sentBytes == 50)
        #expect(totals.receivedMessages == 3)
        #expect(totals.sentMessages == 2)
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

private func relayRuntimeEventFrame(subscriptionID: String, event: NostrEvent) throws -> String {
    let eventData = try JSONEncoder().encode(event)
    let eventObject = try JSONSerialization.jsonObject(with: eventData)
    let frameData = try JSONSerialization.data(withJSONObject: ["EVENT", subscriptionID, eventObject], options: [.sortedKeys])
    return String(data: frameData, encoding: .utf8) ?? "[]"
}

private actor RelayRuntimePacketCollector {
    private var collected: [NostrRelayRuntimePacket] = []

    func append(_ packet: NostrRelayRuntimePacket) {
        collected.append(packet)
    }

    func packets() -> [NostrRelayRuntimePacket] {
        collected
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
    private let eventsByRelayAndSubscriptionID: [String: [String: [NostrEvent]]]
    private let missingIDsBySubscriptionID: [String: [String]]
    private let failingSubscriptionIDs: Set<String>
    private let delayNanosecondsByRelay: [String: UInt64]
    private let delayNanosecondsByRelayAndSubscriptionID: [String: [String: UInt64]]
    private var fetchCalls: [String] = []
    private var fetchRelayCalls: [String] = []
    private var missingCalls: [String] = []
    private var latestMissingLocalEventIDs: [String] = []

    init(
        eventsBySubscriptionID: [String: [NostrEvent]] = [:],
        eventsByRelayAndSubscriptionID: [String: [String: [NostrEvent]]] = [:],
        missingIDsBySubscriptionID: [String: [String]] = [:],
        failingSubscriptionIDs: Set<String> = [],
        delayNanosecondsByRelay: [String: UInt64] = [:],
        delayNanosecondsByRelayAndSubscriptionID: [String: [String: UInt64]] = [:]
    ) {
        self.eventsBySubscriptionID = eventsBySubscriptionID
        self.eventsByRelayAndSubscriptionID = eventsByRelayAndSubscriptionID
        self.missingIDsBySubscriptionID = missingIDsBySubscriptionID
        self.failingSubscriptionIDs = failingSubscriptionIDs
        self.delayNanosecondsByRelay = delayNanosecondsByRelay
        self.delayNanosecondsByRelayAndSubscriptionID = delayNanosecondsByRelayAndSubscriptionID
    }

    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        fetchCalls.append(request.subscriptionID)
        fetchRelayCalls.append(relayURL)
        if let delay = delayNanosecondsByRelayAndSubscriptionID[relayURL]?[request.subscriptionID] ?? delayNanosecondsByRelay[relayURL] {
            try await Task.sleep(nanoseconds: delay)
        }
        if failingSubscriptionIDs.contains(request.subscriptionID) {
            throw NostrRelayClientError.timeout
        }
        if let events = eventsByRelayAndSubscriptionID[relayURL]?[request.subscriptionID] {
            return events
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

    func fetchRelayURLs() -> [String] {
        fetchRelayCalls
    }

    func missingSubscriptionIDs() -> [String] {
        missingCalls
    }

    func missingLocalEventIDs() -> [String] {
        latestMissingLocalEventIDs
    }
}

private actor FakeRelayRuntimeTransport: NostrRelayTransport {
    private let connection: FakeRelayRuntimeConnection
    private var callCount = 0

    init(connection: FakeRelayRuntimeConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        callCount += 1
        return connection
    }

    func connectCallCount() -> Int {
        callCount
    }
}

private actor FakeRelayRuntimeConnection: NostrRelayTransportConnection {
    private var inboundFrames: [String]
    private var outboundFrames: [String] = []
    private var isClosed = false

    init(inboundFrames: [String] = []) {
        self.inboundFrames = inboundFrames
    }

    func send(_ textFrame: String) async throws {
        outboundFrames.append(textFrame)
    }

    func receive() async throws -> String {
        guard !inboundFrames.isEmpty else {
            throw NostrRelayClientError.timeout
        }
        return inboundFrames.removeFirst()
    }

    func appendInboundFrames(_ frames: [String]) {
        inboundFrames.append(contentsOf: frames)
    }

    func close() async {
        isClosed = true
    }

    func sentFrames() -> [String] {
        outboundFrames
    }

    func closed() -> Bool {
        isClosed
    }
}
