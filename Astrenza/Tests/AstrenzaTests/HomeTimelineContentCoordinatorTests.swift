import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline content coordinator")
struct HomeTimelineContentCoordinatorTests {
    @Test("Hydrated replacement does not query persisted heads again on MainActor")
    @MainActor
    func hydratedReplacementDoesNotRequeryPersistedHeads() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let firstFollow = String(repeating: "b", count: 64)
        let secondFollow = String(repeating: "c", count: 64)
        let storedRelayList = event(
            id: "1",
            pubkey: accountID,
            createdAt: 300,
            kind: 10_002,
            tags: [
                ["r", "wss://relay-a.example", "read"],
                ["r", "wss://relay-b.example", "read"]
            ]
        )
        let storedContactList = event(
            id: "2",
            pubkey: accountID,
            createdAt: 300,
            kind: 3,
            tags: [["p", firstFollow], ["p", secondFollow]]
        )
        try eventStore.save(events: [storedRelayList, storedContactList])
        let staleRelayList = event(
            id: "3",
            pubkey: accountID,
            createdAt: 100,
            kind: 10_002,
            tags: [["r", "wss://stale.example", "read"]]
        )
        let staleContactList = event(
            id: "4",
            pubkey: accountID,
            createdAt: 100,
            kind: 3,
            tags: [["p", String(repeating: "d", count: 64)]]
        )
        let note = event(id: "5", pubkey: firstFollow, createdAt: 90)
        let metadata = event(id: "6", pubkey: firstFollow, createdAt: 80, kind: 0)
        let coordinator = HomeTimelineContentCoordinator(eventStore: eventStore)

        let snapshot = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: ["wss://incoming.example"],
                followedPubkeys: [String(repeating: "d", count: 64)],
                noteEvents: [note],
                metadataEvents: [metadata],
                relayListEvent: staleRelayList,
                contactListEvent: staleContactList,
                hasMoreOlder: false
            )
        )

        #expect(snapshot.resolvedRelays == ["wss://stale.example"])
        #expect(snapshot.followedPubkeys == [String(repeating: "d", count: 64)])
        #expect(snapshot.noteEvents == [note])
        #expect(snapshot.metadataEvents == [metadata])
        #expect(snapshot.relayListEvent == staleRelayList)
        #expect(snapshot.contactListEvent == staleContactList)
        #expect(!snapshot.hasMoreOlder)
    }

    @Test("A newer empty contact list remains an explicit unfollow-all")
    @MainActor
    func newerEmptyContactListRemainsExplicitUnfollowAll() {
        let accountID = String(repeating: "a", count: 64)
        let followed = String(repeating: "b", count: 64)
        let emptyContactList = event(
            id: "1",
            pubkey: accountID,
            createdAt: 300,
            kind: 3
        )
        let staleContactList = event(
            id: "2",
            pubkey: accountID,
            createdAt: 100,
            kind: 3,
            tags: [["p", followed]]
        )
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)
        _ = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [followed],
                noteEvents: [],
                metadataEvents: [],
                contactListEvent: staleContactList
            )
        )

        let snapshot = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [],
                noteEvents: [],
                metadataEvents: [],
                contactListEvent: emptyContactList
            )
        )

        #expect(snapshot.followedPubkeys.isEmpty)
        #expect(snapshot.contactListEvent == emptyContactList)
    }

    @Test("Relay fallback preserves an installed provisional plan")
    @MainActor
    func relayFallbackPreservesInstalledProvisionalPlan() {
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)
        _ = coordinator.installProvisionalRelays(["wss://discovery.example"])

        let snapshot = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [],
                noteEvents: [],
                metadataEvents: []
            )
        )

        #expect(snapshot.resolvedRelays == ["wss://discovery.example"])
    }

    @Test("Metadata replacement selects the freshest persisted head and reports visible changes")
    @MainActor
    func metadataReplacementSelectsFreshestPersistedHead() throws {
        let eventStore = try NostrEventStore.inMemory()
        let pubkey = String(repeating: "a", count: 64)
        let stale = event(id: "1", pubkey: pubkey, createdAt: 100, kind: 0)
        let candidate = event(id: "2", pubkey: pubkey, createdAt: 200, kind: 0)
        let persisted = event(id: "3", pubkey: pubkey, createdAt: 300, kind: 0)
        try eventStore.save(events: [persisted])
        let coordinator = HomeTimelineContentCoordinator(eventStore: eventStore)
        _ = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [],
                noteEvents: [],
                metadataEvents: [stale]
            )
        )

        let first = coordinator.rememberLatestMetadataEvent(candidate)
        let duplicate = coordinator.rememberLatestMetadataEvent(candidate)

        #expect(first.event == persisted)
        #expect(first.didChange)
        #expect(duplicate.event == persisted)
        #expect(!duplicate.didChange)
        #expect(coordinator.metadataEvents == [persisted])
    }

    @Test("Deletion removes only targets authored by the deletion signer")
    @MainActor
    func deletionRemovesOnlyTargetsOwnedBySigner() {
        let firstAuthor = String(repeating: "a", count: 64)
        let secondAuthor = String(repeating: "b", count: 64)
        let ownedTarget = event(id: "1", pubkey: firstAuthor, createdAt: 100)
        let foreignTarget = event(id: "2", pubkey: secondAuthor, createdAt: 90)
        let untouched = event(id: "3", pubkey: firstAuthor, createdAt: 80)
        let deletion = event(
            id: "4",
            pubkey: firstAuthor,
            createdAt: 110,
            kind: 5,
            tags: [["e", ownedTarget.id], ["e", foreignTarget.id]]
        )
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)
        _ = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [],
                noteEvents: [ownedTarget, foreignTarget, untouched],
                metadataEvents: []
            )
        )

        let anchor = coordinator.removeEventsDeletedFromCurrentProjection(by: deletion)

        #expect(anchor == ownedTarget.id)
        #expect(coordinator.noteEvents == [foreignTarget, untouched])
    }

    @Test("Content lifecycle actions remain one atomic snapshot boundary")
    @MainActor
    func contentLifecycleActionsRemainAtomic() {
        let accountID = String(repeating: "a", count: 64)
        let outboxEvent = event(id: "1", pubkey: accountID, createdAt: 100)
        let projectedEvent = event(id: "2", pubkey: accountID, createdAt: 90)
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)

        _ = coordinator.installProvisionalRelays(["wss://relay.example"])
        _ = coordinator.replaceFollowedPubkeys([String(repeating: "b", count: 64)])
        _ = coordinator.insertOutboxEvent(outboxEvent, accountID: accountID)
        let afterDuplicate = coordinator.insertOutboxEvent(outboxEvent, accountID: accountID)
        coordinator.replaceProjectionEvents([projectedEvent])
        let ended = coordinator.markOlderEnd()

        #expect(afterDuplicate.noteEvents == [outboxEvent])
        #expect(afterDuplicate.followedPubkeys == [
            String(repeating: "b", count: 64),
            accountID
        ])
        #expect(ended.noteEvents == [projectedEvent])
        #expect(!ended.hasMoreOlder)

        let reset = coordinator.reset()
        #expect(reset == .initial)
    }

    @Test("Runtime bootstrap keeps the visible content and strips timeline cursors")
    @MainActor
    func runtimeBootstrapKeepsVisibleContentAndStripsCursors() {
        let accountID = String(repeating: "a", count: 64)
        let note = event(id: "1", pubkey: accountID, createdAt: 100)
        let metadata = event(id: "2", pubkey: accountID, createdAt: 90, kind: 0)
        let coordinator = HomeTimelineContentCoordinator(eventStore: nil)
        _ = coordinator.replace(
            with: NostrHomeTimelineState(
                relays: ["wss://old.example"],
                followedPubkeys: [accountID],
                noteEvents: [note],
                metadataEvents: [metadata],
                hasMoreOlder: false
            )
        )
        let diagnostic = NostrRelaySyncEventRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            kind: .eose,
            occurredAt: 200,
            subscriptionID: "bootstrap",
            eventCount: 3,
            newestCreatedAt: 100,
            oldestCreatedAt: 50,
            latencyMilliseconds: 12,
            message: "EOSE"
        )

        let state = coordinator.runtimeBootstrapState(
            from: NostrHomeTimelineState(
                relays: ["wss://new.example"],
                followedPubkeys: [String(repeating: "b", count: 64)],
                noteEvents: [],
                metadataEvents: [],
                relaySyncEvents: [diagnostic]
            ),
            nip05Resolutions: [:]
        )

        #expect(state.noteEvents == [note])
        #expect(state.metadataEvents == [metadata])
        #expect(!state.hasMoreOlder)
        #expect(state.relays == ["wss://new.example"])
        #expect(state.relaySyncEvents.first?.newestCreatedAt == nil)
        #expect(state.relaySyncEvents.first?.oldestCreatedAt == nil)
    }

    private func event(
        id: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int = 1,
        tags: [[String]] = []
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: kind == 0 ? #"{"name":"profile"}"# : "event",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@Suite("Home timeline persisted configuration hydration")
struct HomeTimelinePersistedConfigurationHydrationTests {
    @Test("Local replaceable heads hydrate a stale remote state off MainActor")
    func localReplaceableHeadsHydrateRemoteState() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let followed = String(repeating: "b", count: 64)
        let staleFollow = String(repeating: "c", count: 64)
        let relayList = event(
            id: "1",
            pubkey: accountID,
            createdAt: 300,
            kind: 10_002,
            tags: [["r", "wss://current.example", "read"]]
        )
        let contactList = event(
            id: "2",
            pubkey: accountID,
            createdAt: 300,
            kind: 3,
            tags: [["p", followed]]
        )
        let authorRelayList = event(
            id: "3",
            pubkey: followed,
            createdAt: 300,
            kind: 10_002,
            tags: [["r", "wss://author.example", "write"]]
        )
        try eventStore.save(events: [relayList, contactList, authorRelayList])
        let worker = HomeTimelinePersistenceWorker(eventStore: eventStore)

        let hydrated = await worker.hydratingReplaceableConfiguration(
            in: NostrHomeTimelineState(
                relays: ["wss://stale.example"],
                followedPubkeys: [staleFollow],
                noteEvents: [],
                metadataEvents: [],
                relayListEvent: event(
                    id: "4",
                    pubkey: accountID,
                    createdAt: 100,
                    kind: 10_002,
                    tags: [["r", "wss://stale.example", "read"]]
                ),
                contactListEvent: event(
                    id: "5",
                    pubkey: accountID,
                    createdAt: 100,
                    kind: 3,
                    tags: [["p", staleFollow]]
                )
            ),
            accountID: accountID
        )

        #expect(hydrated.relays == ["wss://current.example"])
        #expect(hydrated.followedPubkeys == [followed])
        #expect(hydrated.relayListEvent == relayList)
        #expect(hydrated.contactListEvent == contactList)
        #expect(hydrated.authorRelayListEvents == [authorRelayList])
    }

    private func event(
        id: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]]
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: "",
            sig: String(repeating: "0", count: 128)
        )
    }
}
