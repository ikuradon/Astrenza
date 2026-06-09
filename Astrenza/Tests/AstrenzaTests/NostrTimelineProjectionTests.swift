import Foundation
import Testing
import AstrenzaCore
@testable import Astrenza

@Suite("Nostr timeline projection")
struct NostrTimelineProjectionTests {
    @Test("Projection facade matches materializer entry IDs")
    func projectionFacadeMatchesMaterializerEntryIDs() {
        let author = String(repeating: "a", count: 64)
        let note = projectionEvent(idSeed: "1", pubkey: author, createdAt: 100, content: "projection")
        let materialized = NostrTimelineMaterializer.entries(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author]
        )

        let projected = NostrTimelineProjection.entries(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author]
        )

        #expect(projected.map(\.id) == materialized.map(\.id))
    }
}

private func projectionEvent(idSeed: Character, pubkey: String, createdAt: Int, content: String) -> NostrEvent {
    NostrEvent(
        id: String(repeating: String(idSeed), count: 64),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: 1,
        tags: [],
        content: content,
        sig: String(repeating: "5", count: 128)
    )
}
