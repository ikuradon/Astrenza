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

    @Test("Projection support reads resolve stored events and exclude visible context")
    func projectionSupportReadsResolveStoredEventsAndExcludeVisibleContext() throws {
        let eventStore = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let storedContext = event(id: "6", pubkey: author, createdAt: 100)
        let visibleContext = event(id: "7", pubkey: author, createdAt: 200)
        let storedDependency = event(
            id: "8",
            pubkey: author,
            createdAt: 300,
            tags: [["e", storedContext.id, "", "reply"]]
        )
        let visibleDependency = event(
            id: "9",
            pubkey: author,
            createdAt: 400,
            tags: [["e", visibleContext.id, "", "reply"]]
        )
        try eventStore.save(events: [storedContext, visibleContext])
        let repository = HomeTimelineRepository(eventStore: eventStore)

        #expect(repository.event(id: storedContext.id) == storedContext)
        #expect(repository.event(id: String(repeating: "f", count: 64)) == nil)
        #expect(repository.contextEvents(for: [
            storedDependency,
            visibleDependency,
            visibleContext
        ]) == [storedContext])
        #expect(HomeTimelineRepository(eventStore: nil).contextEvents(
            for: [storedDependency]
        ).isEmpty)
    }

    @Test("Relay cursor reads keep only persisted newest boundaries")
    func relayCursorReadsKeepOnlyPersistedNewestBoundaries() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b", count: 64)
        let firstRelay = "wss://first.example"
        let secondRelay = "wss://second.example"
        try eventStore.saveSyncCursor(NostrSyncCursorRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: firstRelay,
            newestCreatedAt: 300,
            oldestCreatedAt: 100,
            lastEOSEAt: 400,
            lastNegentropyAt: nil
        ))
        try eventStore.saveSyncCursor(NostrSyncCursorRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: secondRelay,
            newestCreatedAt: nil,
            oldestCreatedAt: 50,
            lastEOSEAt: 500,
            lastNegentropyAt: nil
        ))
        let repository = HomeTimelineRepository(eventStore: eventStore)

        #expect(repository.newestCreatedAtByRelay(
            accountID: accountID,
            timelineKey: "home",
            relayURLs: [firstRelay, secondRelay, "wss://missing.example"]
        ) == [firstRelay: 300])
        #expect(HomeTimelineRepository(eventStore: nil).newestCreatedAtByRelay(
            accountID: accountID,
            timelineKey: "home",
            relayURLs: [firstRelay]
        ) == nil)
    }

    @Test("Older backfill reads honor the oldest boundary and follow scope")
    func olderBackfillReadsHonorBoundaryAndFollowScope() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let followedAuthor = String(repeating: "b", count: 64)
        let foreignAuthor = String(repeating: "c", count: 64)
        let currentBoundary = event(
            id: "a",
            pubkey: followedAuthor,
            createdAt: 200
        )
        let followedOlder = event(
            id: "b",
            pubkey: followedAuthor,
            createdAt: 199
        )
        let followedAtBoundary = event(
            id: "c",
            pubkey: followedAuthor,
            createdAt: 200
        )
        let accountOlder = event(
            id: "d",
            pubkey: accountID,
            createdAt: 190
        )
        let foreignOlder = event(
            id: "e",
            pubkey: foreignAuthor,
            createdAt: 180
        )
        let followedRepost = event(
            id: "f",
            pubkey: followedAuthor,
            createdAt: 170,
            kind: 6
        )
        try eventStore.save(events: [
            followedOlder,
            followedAtBoundary,
            accountOlder,
            foreignOlder,
            followedRepost
        ])
        let repository = HomeTimelineRepository(eventStore: eventStore)

        #expect(repository.olderBackfillEvents(
            accountID: accountID,
            followedPubkeys: [followedAuthor],
            currentEvents: [currentBoundary],
            limit: 10
        ) == [followedOlder])
        #expect(repository.olderBackfillEvents(
            accountID: accountID,
            followedPubkeys: [],
            currentEvents: [currentBoundary],
            limit: 10
        ) == [accountOlder])
        #expect(repository.olderBackfillEvents(
            accountID: accountID,
            followedPubkeys: [followedAuthor],
            currentEvents: [],
            limit: 10
        ) == nil)
        #expect(HomeTimelineRepository(eventStore: nil).olderBackfillEvents(
            accountID: accountID,
            followedPubkeys: [followedAuthor],
            currentEvents: [currentBoundary],
            limit: 10
        ) == nil)
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
