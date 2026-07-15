import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline list repository")
@MainActor
struct HomeTimelineListRepositoryTests {
    @Test("List reads materialize cached NIP-51 follow and bookmark sets")
    func listReadsMaterializeCachedNIP51Sets() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b", count: 64)
        let followedAuthor = String(repeating: "c", count: 64)
        let fixture = listFixture(
            accountID: accountID,
            followedAuthor: followedAuthor
        )
        try eventStore.save(events: fixture.events)

        let entries = HomeTimelineRepository(eventStore: eventStore)
            .listEntries(
                limit: 10,
                context: readContext(
                    accountID: accountID,
                    followedPubkeys: [accountID]
                )
            )

        #expect(entries.compactMap(\.post).map(\.id) == [
            fixture.followedNote.id,
            fixture.bookmarkedNote.id
        ])
    }

    private func listFixture(
        accountID: String,
        followedAuthor: String
    ) -> ListFixture {
        let followedNote = event(
            id: "b",
            pubkey: followedAuthor,
            createdAt: 300,
            content: "followed"
        )
        let bookmarkedNote = event(
            id: "c",
            pubkey: accountID,
            createdAt: 200,
            content: "bookmarked"
        )
        let unrelated = event(
            id: "d",
            pubkey: String(repeating: "d", count: 64),
            createdAt: 400,
            content: "unrelated"
        )
        let followSet = event(
            id: "e",
            pubkey: accountID,
            createdAt: 500,
            kind: 30_000,
            tags: [["d", "friends"], ["title", "Friends"], ["p", followedAuthor]]
        )
        let bookmarkSet = event(
            id: "f",
            pubkey: accountID,
            createdAt: 450,
            kind: 30_003,
            tags: [["d", "reads"], ["title", "Reads"], ["e", bookmarkedNote.id]]
        )
        return ListFixture(
            followedNote: followedNote,
            bookmarkedNote: bookmarkedNote,
            events: [
                followedNote,
                bookmarkedNote,
                unrelated,
                followSet,
                bookmarkSet
            ]
        )
    }

    private func readContext(
        accountID: String,
        followedPubkeys: Set<String>
    ) -> HomeTimelineReadContext {
        HomeTimelineReadContext(
            accountID: accountID,
            fallbackEntries: [],
            metadataEvents: [],
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            followedPubkeys: followedPubkeys,
            resolvedRelayCount: 0,
            filterRules: nil,
            syncPolicy: .default()
        )
    }

    private func event(
        id: Character,
        pubkey: String,
        createdAt: Int,
        kind: Int = 1,
        tags: [[String]] = [],
        content: String = ""
    ) -> NostrEvent {
        NostrEvent(
            id: String(repeating: String(id), count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}

private struct ListFixture {
    let followedNote: NostrEvent
    let bookmarkedNote: NostrEvent
    let events: [NostrEvent]
}
