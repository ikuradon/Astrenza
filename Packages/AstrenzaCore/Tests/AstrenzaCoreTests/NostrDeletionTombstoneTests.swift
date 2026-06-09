import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr deletion tombstones")
struct NostrDeletionTombstoneTests {
    @Test("PendingDeletion applies same-author tombstone after target arrives")
    func pendingDeletionAppliesAfterTargetArrives() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let target = tombstoneEvent(idSeed: "1", kind: 1, pubkey: author, createdAt: 100, content: "delete later")
        let deletion = tombstoneEvent(
            idSeed: "2",
            kind: 5,
            pubkey: author,
            createdAt: 120,
            tags: [["e", target.id]],
            content: "remove"
        )

        try store.save(events: [deletion])
        #expect(try store.event(id: target.id) == nil)

        try store.save(events: [target])
        let reloaded = try #require(try store.event(id: target.id))
        try store.saveTimelineEntries([
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: target.id,
                sortTimestamp: target.createdAt,
                insertedAt: 130
            )
        ])
        let deletedRows = try store.deletedTimelineEntries(
            accountID: "account",
            timelineKey: "home",
            limit: 10,
            now: 200
        )

        #expect(reloaded == target)
        #expect(try store.events(kind: 1, limit: 10, now: 200).isEmpty)
        #expect(deletedRows == [
            NostrDeletedTimelineEntryRecord(
                targetEventID: target.id,
                deletionEventID: deletion.id,
                deletedAt: deletion.createdAt,
                sortTimestamp: target.createdAt
            )
        ])
    }

    @Test("PendingDeletion ignores tombstones from another author")
    func pendingDeletionIgnoresOtherAuthor() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let otherAuthor = String(repeating: "b", count: 64)
        let target = tombstoneEvent(idSeed: "3", kind: 1, pubkey: author, createdAt: 100, content: "keep")
        let deletion = tombstoneEvent(
            idSeed: "4",
            kind: 5,
            pubkey: otherAuthor,
            createdAt: 120,
            tags: [["e", target.id]],
            content: "invalid"
        )

        try store.save(events: [deletion])
        try store.save(events: [target])

        #expect(try store.event(id: target.id) == target)
        #expect(try store.events(kind: 1, limit: 10, now: 200).map(\.id) == [target.id])
    }
}

private func tombstoneEvent(
    idSeed: Character,
    kind: Int,
    pubkey: String,
    createdAt: Int,
    tags: [[String]] = [],
    content: String
) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idSeed), count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: String(repeating: "3", count: 128)
    )
}
