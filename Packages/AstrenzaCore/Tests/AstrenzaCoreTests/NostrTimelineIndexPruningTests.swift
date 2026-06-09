import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr timeline index pruning")
struct NostrTimelineIndexPruningTests {
    @Test("PrunesTimelineIndex keeps protected entries and canonical events")
    func prunesTimelineIndexSafely() throws {
        let store = try NostrEventStore.inMemory()
        let newest = pruningEvent(idSeed: "a", createdAt: 500)
        let gapNewer = pruningEvent(idSeed: "b", createdAt: 400)
        let anchor = pruningEvent(idSeed: "c", createdAt: 300)
        let gapOlder = pruningEvent(idSeed: "d", createdAt: 200)
        let oldUnprotected = pruningEvent(idSeed: "e", createdAt: 100)
        let events = [newest, gapNewer, anchor, gapOlder, oldUnprotected]

        try store.save(events: events)
        try store.saveTimelineEntries(events.map { event in
            NostrTimelineEntryRecord(
                accountID: "account",
                timelineKey: "home",
                eventID: event.id,
                sortTimestamp: event.createdAt,
                insertedAt: event.createdAt,
                gapBefore: event.id == gapOlder.id,
                gapAfter: event.id == gapNewer.id
            )
        })

        let deletedCount = try store.pruneTimelineEntries(
            accountID: "account",
            timelineKey: "home",
            policy: NostrTimelineIndexPolicy(
                recentLimit: 1,
                anchorRadius: 1,
                retainedAgeSeconds: 20
            ),
            anchorEventID: anchor.id,
            now: 1_000
        )

        let remaining = try store.timelineEntries(
            accountID: "account",
            timelineKey: "home",
            limit: 10
        ).map(\.eventID)

        #expect(deletedCount == 1)
        #expect(remaining == [newest.id, gapNewer.id, anchor.id, gapOlder.id])
        #expect(!remaining.contains(oldUnprotected.id))
        #expect(try store.event(id: oldUnprotected.id) != nil)
    }
}

private func pruningEvent(idSeed: Character, createdAt: Int) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idSeed), count: 64),
        pubkey: String(repeating: "1", count: 64),
        createdAt: createdAt,
        kind: 1,
        tags: [],
        content: "event \(createdAt)",
        sig: String(repeating: "2", count: 128)
    )
}
