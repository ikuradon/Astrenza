import NostrProtocol
import NostrStoreAPI
import NostrStoreGRDB
import Testing

@Suite("GRDB store contract")
struct NostrStoreGRDBTests {
    @Test("GRDB implementation satisfies event read and write capabilities")
    func readsAndWritesEvents() throws {
        let store = try NostrEventStore.inMemory()
        let event = event(content: "stored")
        let writer: any NostrEventWriting = store
        let reader: any NostrEventReading = store

        try writer.save(events: [event], receivedAt: 100)

        #expect(try reader.event(id: event.id) == event)
        #expect(try reader.events(ids: [event.id], now: 101) == [event])
    }

    private func event(content: String) -> NostrEvent {
        let unsigned = NostrEvent(
            id: String(repeating: "0", count: 64),
            pubkey: String(repeating: "1", count: 64),
            createdAt: 90,
            kind: 1,
            tags: [],
            content: content,
            sig: String(repeating: "2", count: 128)
        )
        return NostrEvent(
            id: unsigned.computedID,
            pubkey: unsigned.pubkey,
            createdAt: unsigned.createdAt,
            kind: unsigned.kind,
            tags: unsigned.tags,
            content: unsigned.content,
            sig: unsigned.sig
        )
    }
}
