import CryptoKit
import Foundation
import Testing
import AstrenzaCore
@testable import Astrenza

@Suite("Nostr timeline sync")
struct NostrTimelineSyncTests {
    @Test("BIP340 verifier accepts signed events and rejects tampering")
    func bip340SignatureVerification() async throws {
        let event = try await signedEvent(
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
        #expect(plan.packets.allSatisfy { $0.filters[0]["since"] == nil })
        #expect(plan.packets.allSatisfy { $0.filters[0]["limit"] == .int(250) })
        #expect(plan.totalAuthorCount == 300)
        #expect(plan.mode == .ownRelayList)
    }

    @Test("Home forward sync keeps an independent reconnect cursor for each relay")
    func homeTimelinePlannerUsesRelayScopedCursors() throws {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let relays = [
            "wss://first.example",
            "wss://second.example",
            "wss://new.example"
        ]
        let plan = HomeTimelineSyncPlanner().forwardPlan(
            account: account,
            followedPubkeys: [String(repeating: "b", count: 64)],
            newestCreatedAt: 300,
            newestCreatedAtByRelay: [
                relays[0]: 100,
                relays[1]: 200
            ],
            initialCreatedAt: 50,
            relayURLs: relays,
            policy: .default(networkType: .wifi)
        )

        #expect(plan.packets.count == 3)
        #expect(Set(plan.packets.map(\.subscriptionID)).count == 3)
        #expect(plan.packets.allSatisfy { $0.relayURLs.count == 1 })
        let sinceByRelay = Dictionary(uniqueKeysWithValues: plan.packets.map { packet in
            (packet.relayURLs[0], packet.filters[0]["since"])
        })
        #expect(sinceByRelay[relays[0]] == .int(90))
        #expect(sinceByRelay[relays[1]] == .int(190))
        #expect(sinceByRelay[relays[2]] == .int(40))
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

    @Test("Backward sync keeps request provenance and a partial-page gap")
    @MainActor
    func backwardSyncKeepsRequestProvenanceAndGap() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let author = String(repeating: "b", count: 64)
        let account = NostrAccount(pubkey: accountID, displayIdentifier: "account", readOnly: true)
        let anchor = signedShapeOnlyEvent(kind: 1, pubkey: author, createdAt: 200, content: "anchor")
        let older = signedShapeOnlyEvent(kind: 1, pubkey: author, createdAt: 100, content: "older")
        let definition = try homeFeedDefinition(accountID: accountID, revision: 1, authors: [author])
        try eventStore.save(events: [anchor], receivedAt: 10)
        try eventStore.replaceFeedProjection(
            definition,
            memberships: [NostrFeedMembershipRecord(
                feedID: definition.feedID,
                eventID: anchor.id,
                sortTimestamp: anchor.createdAt,
                reason: "initial",
                insertedAt: 10,
                feedRevision: definition.revision
            )]
        )

        let packet = NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [[
                "authors": .strings([author]),
                "kinds": .ints([1, 6]),
                "until": .int(anchor.createdAt - 1)
            ]],
            relayURLs: ["wss://relay.example"],
            groupID: "astrenza-older-notes-test",
            subscriptionID: "astrenza-older-notes-test-req"
        )
        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.testingActivateHomeFeed(account: account, definition: definition, sourceAuthors: [author])
        store.testingRegisterOlderFeedRequest(
            packet: packet,
            definition: definition,
            anchorEventID: anchor.id
        )
        let attempt = NostrRelayRequestAttempt(
            requestID: "older-attempt",
            relayURL: "wss://relay.example",
            packet: packet,
            startedAt: 20
        )
        await store.testingHandleFeedSyncRequestStarted(attempt)
        await store.testingHandleBackwardEvent(
            relayURL: attempt.relayURL,
            subscriptionID: packet.subscriptionID,
            event: older
        )
        store.testingHandleBackwardCompletion(NostrBackwardREQCompletion(
            groupID: packet.groupID,
            relayURLs: [attempt.relayURL],
            subscriptionIDs: [packet.subscriptionID],
            eventCount: 1,
            eoseCount: 0,
            closedCount: 1,
            timeoutCount: 0
        ))

        let sources = try eventStore.feedMembershipSources(
            feedID: definition.feedID,
            revision: definition.revision,
            eventID: older.id
        )
        #expect(sources.contains {
            $0.sourceType == "sync-request" && $0.sourceID == attempt.requestID
        })
        let gap = try #require(try eventStore.feedGaps(
            feedID: definition.feedID,
            revision: definition.revision
        ).first)
        #expect(gap.newerEventID == anchor.id)
        #expect(gap.olderEventID == older.id)
        #expect(gap.sourceRequestID == attempt.requestID)
    }

    @Test("Backward EVENT is projected even when request provenance is still queued")
    @MainActor
    func backwardEventDoesNotWaitForRequestProvenance() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "1", count: 64)
        let author = String(repeating: "2", count: 64)
        let account = NostrAccount(pubkey: accountID, displayIdentifier: "account", readOnly: true)
        let older = signedShapeOnlyEvent(kind: 1, pubkey: author, createdAt: 100, content: "early event")
        let definition = try homeFeedDefinition(accountID: accountID, revision: 1, authors: [author])
        try eventStore.replaceFeedProjection(definition, memberships: [])
        let packet = NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [["authors": .strings([author]), "kinds": .ints([1, 6])]],
            relayURLs: ["wss://relay.example"],
            groupID: "astrenza-older-notes-early",
            subscriptionID: "astrenza-older-notes-early-req"
        )
        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.testingActivateHomeFeed(account: account, definition: definition, sourceAuthors: [author])
        store.testingRegisterOlderFeedRequest(packet: packet, definition: definition, anchorEventID: nil)

        await store.testingHandleBackwardEvent(
            relayURL: "wss://relay.example",
            subscriptionID: packet.subscriptionID,
            event: older
        )

        #expect(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 10
        ).map(\.eventID) == [older.id])
    }

    @Test("A superseded feed revision cannot receive a delayed backward result")
    @MainActor
    func supersededRevisionRejectsDelayedBackwardResult() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "c", count: 64)
        let oldAuthor = String(repeating: "d", count: 64)
        let newAuthor = String(repeating: "e", count: 64)
        let account = NostrAccount(pubkey: accountID, displayIdentifier: "account", readOnly: true)
        let revision1 = try homeFeedDefinition(accountID: accountID, revision: 1, authors: [oldAuthor])
        let revision2 = try homeFeedDefinition(accountID: accountID, revision: 2, authors: [newAuthor])
        try eventStore.replaceFeedProjection(revision1, memberships: [])

        let packet = NostrREQPacket.backward(
            purpose: "older-notes",
            filters: [["authors": .strings([oldAuthor]), "kinds": .ints([1, 6])]],
            relayURLs: ["wss://relay.example"],
            groupID: "astrenza-older-notes-stale",
            subscriptionID: "astrenza-older-notes-stale-req"
        )
        let forwardPacket = NostrREQPacket.forward(
            subscriptionID: "astrenza-home-forward-stale",
            filters: [["authors": .strings([oldAuthor]), "kinds": .ints([1, 6])]],
            relayURLs: ["wss://relay.example"]
        )
        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.testingActivateHomeFeed(account: account, definition: revision1, sourceAuthors: [oldAuthor])
        store.testingRegisterOlderFeedRequest(packet: packet, definition: revision1, anchorEventID: nil)
        store.testingRegisterForwardFeedRequest(packet: forwardPacket, definition: revision1)
        let forwardAttempt = NostrRelayRequestAttempt(
            requestID: "stale-forward-attempt",
            relayURL: "wss://relay.example",
            packet: forwardPacket,
            startedAt: 29
        )
        let attempt = NostrRelayRequestAttempt(
            requestID: "stale-attempt",
            relayURL: "wss://relay.example",
            packet: packet,
            startedAt: 30
        )
        await store.testingHandleFeedSyncRequestStarted(forwardAttempt)
        await store.testingHandleFeedSyncRequestStarted(attempt)

        try eventStore.replaceFeedProjection(revision2, memberships: [])
        store.testingActivateHomeFeed(account: account, definition: revision2, sourceAuthors: [newAuthor])
        let delayed = signedShapeOnlyEvent(
            kind: 1,
            pubkey: oldAuthor,
            createdAt: 50,
            content: "delayed"
        )
        await store.testingHandleBackwardEvent(
            relayURL: attempt.relayURL,
            subscriptionID: packet.subscriptionID,
            event: delayed
        )
        let delayedForward = signedShapeOnlyEvent(
            kind: 1,
            pubkey: oldAuthor,
            createdAt: 60,
            content: "delayed forward"
        )
        await store.testingHandleHomeForwardEvent(
            relayURL: forwardAttempt.relayURL,
            subscriptionID: forwardPacket.subscriptionID,
            event: delayedForward
        )
        store.testingHandleBackwardCompletion(NostrBackwardREQCompletion(
            groupID: packet.groupID,
            relayURLs: [attempt.relayURL],
            subscriptionIDs: [packet.subscriptionID],
            eventCount: 0,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        ))

        #expect(try eventStore.event(id: delayed.id) == delayed)
        #expect(try eventStore.event(id: delayedForward.id) == delayedForward)
        #expect(try eventStore.feedMemberships(
            feedID: revision2.feedID,
            revision: revision2.revision,
            limit: 10
        ).isEmpty)
        #expect(try eventStore.feedMembershipSources(
            feedID: revision2.feedID,
            revision: revision2.revision,
            eventID: delayed.id
        ).isEmpty)
        #expect(Set(try eventStore.feedSyncRequests(
            feedID: revision1.feedID,
            revision: revision1.revision
        ).map(\.requestID)) == Set([attempt.requestID, forwardAttempt.requestID]))
        #expect(try eventStore.feedSyncRequests(
            feedID: revision2.feedID,
            revision: revision2.revision
        ).isEmpty)
        #expect(store.hasMoreOlder)
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

    private func homeFeedDefinition(
        accountID: String,
        revision: Int,
        authors: [String]
    ) throws -> NostrFeedDefinitionRecord {
        let specificationJSON = try JSONSerialization.data(
            withJSONObject: ["authors": authors.sorted(), "kinds": [1, 6]],
            options: [.sortedKeys]
        )
        return NostrFeedDefinitionRecord(
            feedID: "feed:home:\(accountID)",
            accountID: accountID,
            kind: "home",
            specificationJSON: specificationJSON,
            specificationHash: "specification-\(revision)",
            sortPolicy: "created_at_desc_event_id_asc",
            revision: revision,
            createdAt: 1,
            updatedAt: revision
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

private func signedEvent(kind: Int, createdAt: Int, tags: [[String]], content: String) async throws -> NostrEvent {
    let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "21", count: 32))
    let unsignedEvent = NostrUnsignedEvent(
        pubkey: signer.pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content
    )
    return try await signer.sign(unsignedEvent)
}

private enum SHA256Digest {
    static func hex(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
