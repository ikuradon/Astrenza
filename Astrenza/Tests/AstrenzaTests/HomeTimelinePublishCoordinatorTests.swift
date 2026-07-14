import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline publish coordinator")
struct HomeTimelinePublishCoordinatorTests {
    @Test("Prepare signs immutable input and resolves ordered relay destinations")
    func prepareSignsAndResolvesDestinations() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = SignerSpy()
        let coordinator = HomeTimelinePublishCoordinator(eventStore: eventStore)
        let accountID = String(repeating: "a", count: 64)

        let publish = try await coordinator.prepare(
            .post(content: "hello"),
            accountID: accountID,
            accountWriteRelays: [
                "wss://write.example",
                "wss://write.example"
            ],
            fallbackRelays: [
                "wss://fallback.example",
                "wss://write.example"
            ],
            signer: signer,
            createdAt: 123
        )

        #expect(await signer.lastUnsignedEvent == NostrUnsignedEvent(
            pubkey: accountID,
            createdAt: 123,
            kind: 1,
            tags: [],
            content: "hello"
        ))
        #expect(publish.accountID == accountID)
        #expect(publish.createdAt == 123)
        #expect(publish.event.content == "hello")
        #expect(publish.destinationRelayURLs == [
            "wss://write.example",
            "wss://fallback.example"
        ])
        #expect(try eventStore.outboxEvents(accountID: accountID).isEmpty)
    }

    @Test("Missing relay destinations fail after signing without durable side effects")
    func missingDestinationsDoNotPersist() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = SignerSpy()
        let coordinator = HomeTimelinePublishCoordinator(eventStore: eventStore)
        let accountID = String(repeating: "b", count: 64)

        await #expect(throws: HomeTimelinePublishError.noRelayDestinations) {
            try await coordinator.prepare(
                .post(content: "offline"),
                accountID: accountID,
                accountWriteRelays: [],
                fallbackRelays: [],
                signer: signer,
                createdAt: 200
            )
        }

        #expect(await signer.lastUnsignedEvent?.content == "offline")
        #expect(try eventStore.outboxEvents(accountID: accountID).isEmpty)
    }

    @Test("Persist writes the outbox event and its Home feed provenance")
    func persistWritesOutboxAndFeedProjection() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = SignerSpy()
        let coordinator = HomeTimelinePublishCoordinator(eventStore: eventStore)
        let accountID = String(repeating: "c", count: 64)
        let definition = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [accountID],
            existingDefinition: nil,
            now: 300
        )?.definition)
        try eventStore.saveFeedDefinition(definition)
        let publish = try await coordinator.prepare(
            .post(content: "persisted"),
            accountID: accountID,
            accountWriteRelays: ["wss://relay.example"],
            fallbackRelays: [],
            signer: signer,
            createdAt: 301
        )

        let event = try coordinator.persist(publish, feedDefinition: definition)
        let outbox = try #require(eventStore.outboxEvents(accountID: accountID).first)

        #expect(event == publish.event)
        #expect(outbox.event == event)
        #expect(outbox.status == NostrOutboxStatus.pending)
        #expect(try eventStore.outboxRelays(localID: outbox.localID).map(\.relayURL) == [
            "wss://relay.example"
        ])
        #expect(try eventStore.event(id: event.id) == event)
        #expect(try eventStore.feedMemberships(
            feedID: definition.feedID,
            revision: definition.revision,
            limit: 10
        ) == HomeFeedProjectionBuilder.memberships(
            events: [event],
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "outbox",
            insertedAt: 301
        ))
        #expect(try eventStore.feedMembershipSources(
            feedID: definition.feedID,
            revision: definition.revision,
            eventID: event.id
        ) == HomeFeedProjectionBuilder.membershipSources(
            events: [event],
            feedID: definition.feedID,
            feedRevision: definition.revision,
            reason: "outbox",
            insertedAt: 301
        ))
    }

    @Test("An account switch during signing prevents stale publish persistence")
    @MainActor
    func accountSwitchDuringSigningDoesNotPersist() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let firstAccount = NostrAccount(
            pubkey: String(repeating: "d", count: 64),
            displayIdentifier: "first",
            readOnly: true
        )
        let secondAccount = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "second",
            readOnly: true
        )
        let firstDefinition = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: firstAccount.pubkey,
            followedPubkeys: [firstAccount.pubkey],
            existingDefinition: nil,
            now: 399
        )?.definition)
        try eventStore.saveHomeFeedState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [firstAccount.pubkey],
                noteEvents: [],
                metadataEvents: []
            ),
            accountID: firstAccount.pubkey,
            definition: firstDefinition,
            memberships: [],
            savedAt: 399
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: EmptyRelayFetcher(),
                bootstrapRelays: []
            ),
            eventStore: eventStore
        )
        let signer = SuspendedSigner()
        store.start(account: firstAccount)
        defer { store.cancel() }
        #expect(store.resolvedRelays == ["wss://relay.example"])

        let publishTask = Task {
            try await store.enqueuePublish(.post(content: "stale"), signer: signer)
        }
        await signer.waitUntilSigningStarts()
        store.start(account: secondAccount)
        await signer.resume()
        try await publishTask.value

        #expect(try eventStore.outboxEvents(accountID: firstAccount.pubkey).isEmpty)
        #expect(try eventStore.outboxEvents(accountID: secondAccount.pubkey).isEmpty)
    }
}

private actor SignerSpy: NostrEventSigning {
    private(set) var lastUnsignedEvent: NostrUnsignedEvent?

    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        lastUnsignedEvent = unsignedEvent
        return NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: String(repeating: "1", count: 128)
        )
    }
}

private actor SuspendedSigner: NostrEventSigning {
    private var signingContinuation: CheckedContinuation<Void, Never>?

    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        await withCheckedContinuation { continuation in
            signingContinuation = continuation
        }
        return NostrEvent(
            id: unsignedEvent.eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: String(repeating: "2", count: 128)
        )
    }

    func waitUntilSigningStarts() async {
        while signingContinuation == nil {
            await Task.yield()
        }
    }

    func resume() {
        signingContinuation?.resume()
        signingContinuation = nil
    }
}

private actor EmptyRelayFetcher: NostrRelayFetching {
    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        []
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
