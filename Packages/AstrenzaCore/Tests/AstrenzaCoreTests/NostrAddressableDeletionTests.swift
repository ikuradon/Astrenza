import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr addressable deletion tombstones")
struct NostrAddressableDeletionTests {
    @Test("AddressableDeletion hides matching older addressable events")
    func addressableDeletionHidesOlderMatchingEvents() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let older = addressableDeletionEvent(idSeed: "1", kind: 30_023, pubkey: author, createdAt: 100, tags: [["d", "article"]])
        let newer = addressableDeletionEvent(idSeed: "2", kind: 30_023, pubkey: author, createdAt: 150, tags: [["d", "article"]])
        let future = addressableDeletionEvent(idSeed: "3", kind: 30_023, pubkey: author, createdAt: 200, tags: [["d", "article"]])
        let deletion = addressableDeletionEvent(
            idSeed: "4",
            kind: 5,
            pubkey: author,
            createdAt: 160,
            tags: [["a", "30023:\(author):article"]]
        )

        try store.save(events: [older, newer, future, deletion])

        #expect(try store.events(kind: 30_023, limit: 10, now: 300).map(\.id) == [future.id])
        #expect(try store.latestAddressableEvent(kind: 30_023, pubkey: author, dTag: "article", now: 300)?.id == future.id)
    }

    @Test("AddressableDeletion applies pending address tombstone after target arrives")
    func pendingAddressableDeletionAppliesAfterTargetArrives() throws {
        let store = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let target = addressableDeletionEvent(idSeed: "5", kind: 30_023, pubkey: author, createdAt: 100, tags: [["d", "article"]])
        let deletion = addressableDeletionEvent(
            idSeed: "6",
            kind: 5,
            pubkey: author,
            createdAt: 160,
            tags: [["a", "30023:\(author):article"]]
        )

        try store.save(events: [deletion])
        try store.save(events: [target])

        #expect(try store.event(id: target.id) == target)
        #expect(try store.events(kind: 30_023, limit: 10, now: 300).isEmpty)
        #expect(try store.latestAddressableEvent(kind: 30_023, pubkey: author, dTag: "article", now: 300) == nil)
    }
}

private func addressableDeletionEvent(
    idSeed: Character,
    kind: Int,
    pubkey: String,
    createdAt: Int,
    tags: [[String]] = []
) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idSeed), count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: "addressable \(createdAt)",
        sig: String(repeating: "4", count: 128)
    )
}
