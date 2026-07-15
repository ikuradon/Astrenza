import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline snapshot coordinator")
@MainActor
struct HomeTimelineSnapshotCoordinatorTests {
    @Test("Restore prefers Generic Feed and falls back to the legacy migration snapshot")
    func restorePrefersGenericFeedAndFallsBackToLegacy() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let legacyNote = event(id: "1", pubkey: accountID, content: "legacy")
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://legacy.example"],
                followedPubkeys: [accountID],
                noteEvents: [legacyNote],
                metadataEvents: []
            ),
            accountID: accountID
        )
        let (coordinator, _) = makeCoordinator(eventStore: eventStore)

        let legacy = try #require(coordinator.restoredState(accountID: accountID))

        #expect(legacy.relays == ["wss://legacy.example"])
        #expect(legacy.noteEvents == [legacyNote])

        let genericNote = event(id: "2", pubkey: accountID, content: "generic")
        let genericSavedAt = Int(Date().timeIntervalSince1970) + 10
        let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: accountID,
            followedPubkeys: [accountID],
            existingDefinition: nil,
            now: genericSavedAt
        ))
        try eventStore.saveHomeFeedState(
            NostrHomeTimelineState(
                relays: ["wss://generic.example"],
                followedPubkeys: [accountID],
                noteEvents: [genericNote],
                metadataEvents: []
            ),
            accountID: accountID,
            definition: plan.definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [genericNote],
                feedID: plan.definition.feedID,
                feedRevision: plan.definition.revision,
                reason: "test",
                insertedAt: genericSavedAt
            ),
            savedAt: genericSavedAt
        )

        let generic = try #require(coordinator.restoredState(accountID: accountID))

        #expect(generic.relays == ["wss://generic.example"])
        #expect(generic.noteEvents == [genericNote])
    }

    @Test("Snapshot persistence bounds the Home projection and activates its saved window")
    func snapshotPersistenceBoundsProjectionAndActivatesWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let followed = String(repeating: "b", count: 64)
        let excluded = String(repeating: "c", count: 64)
        let includedNote = event(id: "3", pubkey: followed, content: "included")
        let excludedNote = event(id: "4", pubkey: excluded, content: "excluded")
        let excludedKind = event(id: "5", pubkey: followed, kind: 7, content: "reaction")
        let accountMetadata = event(id: "6", pubkey: accountID, kind: 0, content: "{}")
        let followedMetadata = event(id: "7", pubkey: followed, kind: 0, content: "{}")
        let excludedMetadata = event(id: "8", pubkey: excluded, kind: 0, content: "{}")
        let (coordinator, projectionController) = makeCoordinator(eventStore: eventStore)

        let receipt = try #require(await coordinator.persistSnapshot(
            snapshot(
                accountID: accountID,
                followedPubkeys: [followed],
                noteEvents: [excludedNote, excludedKind, includedNote],
                metadataEvents: [excludedMetadata, followedMetadata, accountMetadata]
            ),
            savedAt: 100
        ))
        let restored = try #require(try eventStore.homeFeedState(accountID: accountID))

        #expect(restored.noteEvents == [includedNote])
        #expect(restored.metadataEvents == [followedMetadata])
        #expect(try eventStore.event(id: accountMetadata.id) == accountMetadata)
        #expect(try eventStore.event(id: excludedMetadata.id) == nil)
        #expect(receipt.sourceAuthors == [followed])
        #expect(await coordinator.activatePersistedSnapshot(
            receipt,
            accountID: accountID,
            followedPubkeys: [followed]
        ))
        #expect(projectionController.definition == receipt.definition)
        #expect(projectionController.window?.events == [includedNote])
    }

    @Test("A stale projection generation cannot reactivate a saved window")
    func staleProjectionGenerationCannotReactivateSavedWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "d", count: 64)
        let note = event(id: "9", pubkey: accountID, content: "note")
        let (coordinator, projectionController) = makeCoordinator(eventStore: eventStore)
        let receipt = try #require(await coordinator.persistSnapshot(
            snapshot(
                accountID: accountID,
                followedPubkeys: [],
                noteEvents: [note]
            ),
            savedAt: 100
        ))

        projectionController.clearWindow()

        #expect(await coordinator.activatePersistedSnapshot(
            receipt,
            accountID: accountID,
            followedPubkeys: []
        ) == false)
        #expect(projectionController.definition == nil)
        #expect(projectionController.window == nil)
    }

    @Test("Changed follow sources cannot activate a saved window")
    func changedFollowSourcesCannotActivateSavedWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "d", count: 64)
        let originalFollow = String(repeating: "b", count: 64)
        let replacementFollow = String(repeating: "c", count: 64)
        let note = event(id: "b", pubkey: originalFollow, content: "note")
        let (coordinator, projectionController) = makeCoordinator(eventStore: eventStore)
        let receipt = try #require(await coordinator.persistSnapshot(
            snapshot(
                accountID: accountID,
                followedPubkeys: [originalFollow],
                noteEvents: [note]
            ),
            savedAt: 100
        ))

        #expect(await coordinator.activatePersistedSnapshot(
            receipt,
            accountID: accountID,
            followedPubkeys: [replacementFollow]
        ) == false)
        #expect(projectionController.definition == nil)
        #expect(projectionController.window == nil)
    }

    @Test("Metadata persistence updates sync state without replacing projection events")
    func metadataPersistencePreservesProjectionEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "e", count: 64)
        let note = event(id: "a", pubkey: accountID, content: "preserved")
        let (coordinator, _) = makeCoordinator(eventStore: eventStore)
        _ = try #require(await coordinator.persistSnapshot(
            snapshot(
                accountID: accountID,
                followedPubkeys: [],
                noteEvents: [note]
            ),
            savedAt: 100
        ))

        let didPersist = await coordinator.persistMetadata(
            HomeTimelineMetadataSnapshot(
                accountID: accountID,
                relays: ["wss://updated.example"],
                followedPubkeys: [],
                nip05Resolutions: [:],
                hasMoreOlder: false
            ),
            savedAt: 200
        )
        let restored = try #require(try eventStore.homeFeedState(accountID: accountID))

        #expect(didPersist)
        #expect(restored.noteEvents == [note])
        #expect(restored.relays == ["wss://updated.example"])
        #expect(!restored.hasMoreOlder)
    }

    private func makeCoordinator(
        eventStore: NostrEventStore
    ) -> (HomeTimelineSnapshotCoordinator, HomeFeedProjectionController) {
        let projectionController = HomeFeedProjectionController(eventStore: eventStore)
        return (
            HomeTimelineSnapshotCoordinator(
                eventStore: eventStore,
                persistenceWorker: HomeTimelinePersistenceWorker(eventStore: eventStore),
                projectionController: projectionController
            ),
            projectionController
        )
    }

    private func snapshot(
        accountID: String,
        followedPubkeys: [String],
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent] = []
    ) -> HomeTimelineSnapshotInput {
        HomeTimelineSnapshotInput(
            accountID: accountID,
            relays: ["wss://relay.example"],
            followedPubkeys: followedPubkeys,
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            relayListEvent: nil,
            contactListEvent: nil,
            nip05Resolutions: [:],
            hasMoreOlder: true
        )
    }

    private func event(
        id: Character,
        pubkey: String,
        kind: Int = 1,
        content: String
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: kind,
            tags: [],
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}
