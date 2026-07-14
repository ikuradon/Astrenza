import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline repository reads")
@MainActor
struct HomeTimelineRepositoryReadTests {
    @Test("Post reads prefer storage and fall back to the visible projection")
    func postReadsPreferStorageAndFallBackToVisibleProjection() throws {
        let eventStore = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let storedEvent = event(
            id: "1",
            pubkey: author,
            createdAt: 200,
            content: "stored"
        )
        let fallbackEvent = event(
            id: "2",
            pubkey: author,
            createdAt: 100,
            content: "fallback"
        )
        try eventStore.save(events: [storedEvent])
        let fallbackPost = try #require(
            NostrTimelineMaterializer.posts(
                noteEvents: [fallbackEvent],
                metadataEvents: [],
                followedPubkeys: [author]
            ).first
        )
        let context = readContext(
            fallbackEntries: [.post(fallbackPost)],
            followedPubkeys: [author]
        )

        let storedPost = HomeTimelineRepository(eventStore: eventStore).post(
            eventID: storedEvent.id,
            context: context
        )
        let fallback = HomeTimelineRepository(eventStore: nil).post(
            eventID: fallbackEvent.id,
            context: context
        )

        #expect(storedPost?.id == storedEvent.id)
        #expect(storedPost?.body == "stored")
        #expect(fallback?.id == fallbackEvent.id)
        #expect(fallback?.body == "fallback")
    }

    @Test("Profile reads combine cached metadata, posts, follows, and relays")
    func profileReadsCombineCachedState() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let otherFollow = String(repeating: "b", count: 64)
        let metadata = event(
            id: "3",
            pubkey: accountID,
            createdAt: 300,
            kind: 0,
            content: #"{"name":"Alice","nip05":"_@alice.example"}"#
        )
        let newerPost = event(
            id: "4",
            pubkey: accountID,
            createdAt: 200,
            content: "newer"
        )
        let olderPost = event(
            id: "5",
            pubkey: accountID,
            createdAt: 100,
            content: "older"
        )
        try eventStore.save(events: [metadata, newerPost, olderPost])
        let context = readContext(
            accountID: accountID,
            followedPubkeys: [accountID, otherFollow],
            resolvedRelayCount: 3
        )
        let repository = HomeTimelineRepository(eventStore: eventStore)

        let profile = repository.profile(
            pubkey: accountID,
            isCurrentUser: true,
            context: context
        )
        let posts = repository.profilePosts(
            pubkey: accountID,
            limit: 10,
            context: context
        )

        #expect(profile.author.primaryText == "Alice")
        #expect(profile.author.secondaryText == "alice.example")
        #expect(profile.author.profileResolutionState == .resolved)
        #expect(profile.bio == "kind:0 profile metadata is cached.")
        #expect(profile.isCurrentUser)
        #expect(profile.isFollowed)
        #expect(profile.followingCount == 2)
        #expect(profile.postCount == 2)
        #expect(profile.relayCount == 3)
        #expect(posts.map(\.id) == [newerPost.id, olderPost.id])
    }

    @Test("Thread reads preserve materialized ancestor order and exclude non-reply references")
    func threadReadsPreserveMaterializedOrderAndFilterReferences() throws {
        let eventStore = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let root = event(id: "6", pubkey: author, createdAt: 100, content: "root")
        let parent = event(
            id: "7",
            pubkey: author,
            createdAt: 200,
            tags: [["e", root.id, "", "reply"]],
            content: "parent"
        )
        let child = event(
            id: "8",
            pubkey: author,
            createdAt: 300,
            tags: [
                ["e", root.id, "", "root"],
                ["e", parent.id, "", "reply"]
            ],
            content: "child"
        )
        let directReply = event(
            id: "9",
            pubkey: author,
            createdAt: 400,
            tags: [["e", child.id, "", "reply"]],
            content: "reply"
        )
        let mentionOnly = event(
            id: "a",
            pubkey: author,
            createdAt: 500,
            tags: [["e", child.id, "", "mention"]],
            content: "mention"
        )
        try eventStore.save(events: [root, parent, child, directReply, mentionOnly])
        let repository = HomeTimelineRepository(eventStore: eventStore)
        let context = readContext(followedPubkeys: [author])
        let childPost = try #require(repository.post(eventID: child.id, context: context))

        let ancestors = repository.replyAncestors(
            for: childPost,
            limit: 10,
            context: context
        )
        let replies = repository.replies(
            for: childPost,
            limit: 10,
            context: context
        )

        #expect(ancestors.map(\.id) == [parent.id, root.id])
        #expect(replies.map(\.id) == [directReply.id])
    }

    @Test("List reads materialize cached NIP-51 follow and bookmark sets")
    func listReadsMaterializeCachedNIP51Sets() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b", count: 64)
        let followedAuthor = String(repeating: "c", count: 64)
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
        try eventStore.save(events: [
            followedNote,
            bookmarkedNote,
            unrelated,
            followSet,
            bookmarkSet
        ])
        let repository = HomeTimelineRepository(eventStore: eventStore)

        let entries = repository.listEntries(
            limit: 10,
            context: readContext(
                accountID: accountID,
                followedPubkeys: [accountID]
            )
        )

        #expect(entries.compactMap(\.post).map(\.id) == [
            followedNote.id,
            bookmarkedNote.id
        ])
    }

    @Test("Bookmark reads are account-scoped and safe without persistence")
    func bookmarkReadsAreAccountScopedAndSafeWithoutPersistence() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "e", count: 64)
        let eventID = String(repeating: "1", count: 64)
        try eventStore.saveLocalBookmark(
            NostrLocalBookmarkRecord(
                accountID: accountID,
                eventID: eventID,
                createdAt: 100
            )
        )
        let repository = HomeTimelineRepository(eventStore: eventStore)

        #expect(repository.isBookmarked(eventID: eventID, accountID: accountID))
        #expect(!repository.isBookmarked(eventID: eventID, accountID: nil))
        #expect(!repository.isBookmarked(
            eventID: eventID,
            accountID: String(repeating: "f", count: 64)
        ))
        #expect(!HomeTimelineRepository(eventStore: nil).isBookmarked(
            eventID: eventID,
            accountID: accountID
        ))
    }

    private func readContext(
        accountID: String? = nil,
        fallbackEntries: [TimelineFeedEntry] = [],
        followedPubkeys: Set<String> = [],
        resolvedRelayCount: Int = 0
    ) -> HomeTimelineReadContext {
        HomeTimelineReadContext(
            accountID: accountID,
            fallbackEntries: fallbackEntries,
            metadataEvents: [],
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            followedPubkeys: followedPubkeys,
            resolvedRelayCount: resolvedRelayCount,
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
