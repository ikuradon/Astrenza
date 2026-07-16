import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline local mutation coordinator")
struct HomeTimelineLocalMutationCoordinatorTests {
    @Test("Mute persists a deterministic account-scoped author rule")
    func mutePersistsAccountScopedRule() throws {
        let eventStore = try NostrEventStore.inMemory()
        let coordinator = HomeTimelineLocalMutationCoordinator(persistence: eventStore)
        let accountID = String(repeating: "a", count: 64)
        let authorPubkey = String(repeating: "b", count: 64)

        let rule = try coordinator.muteAuthor(
            accountID: accountID,
            authorPubkey: authorPubkey,
            at: 100
        )

        #expect(rule == NostrFilterRuleRecord(
            ruleID: "local:mute-pubkey:\(accountID):\(authorPubkey)",
            accountID: accountID,
            kind: .mutedPubkey,
            value: authorPubkey,
            createdAt: 100,
            updatedAt: 100
        ))
        #expect(try eventStore.filterRules(accountID: accountID) == [rule])
        #expect(try eventStore.filterRules(
            accountID: String(repeating: "c", count: 64)
        ).isEmpty)
    }

    @Test("Bookmark persists an account-scoped event reference")
    func bookmarkPersistsAccountScopedEvent() throws {
        let eventStore = try NostrEventStore.inMemory()
        let coordinator = HomeTimelineLocalMutationCoordinator(persistence: eventStore)
        let accountID = String(repeating: "d", count: 64)
        let eventID = String(repeating: "1", count: 64)

        let bookmark = try coordinator.bookmarkPost(
            accountID: accountID,
            eventID: eventID,
            at: 200
        )

        #expect(bookmark == NostrLocalBookmarkRecord(
            accountID: accountID,
            eventID: eventID,
            createdAt: 200
        ))
        #expect(try eventStore.localBookmarks(accountID: accountID) == [bookmark])
        #expect(try eventStore.localBookmarks(
            accountID: String(repeating: "e", count: 64)
        ).isEmpty)
    }

    @Test("Persistence failures propagate for both local mutations")
    func persistenceFailuresPropagate() {
        let coordinator = HomeTimelineLocalMutationCoordinator(
            persistence: FailingLocalMutationPersistence()
        )

        #expect(throws: LocalMutationPersistenceError.unavailable) {
            try coordinator.muteAuthor(
                accountID: "account",
                authorPubkey: "author",
                at: 300
            )
        }
        #expect(throws: LocalMutationPersistenceError.unavailable) {
            try coordinator.bookmarkPost(
                accountID: "account",
                eventID: "event",
                at: 300
            )
        }
    }

    @Test("Store preserves mutation-specific failure presentation")
    @MainActor
    func storePreservesFailurePresentation() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "f", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let definition = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: account.pubkey,
            followedPubkeys: [account.pubkey],
            existingDefinition: nil,
            now: 400
        )?.definition)
        let store = HomeTimelineStoreFactory.make(
            eventStore: eventStore,
            localMutationPersistence: FailingLocalMutationPersistence()
        )
        await store.testingActivateHomeFeed(
            account: account,
            definition: definition,
            sourceAuthors: [account.pubkey]
        )
        defer { store.cancel() }
        let post = TimelinePost(
            id: String(repeating: "2", count: 64),
            author: .unresolved(pubkey: String(repeating: "a", count: 64)),
            avatar: AvatarStyle(
                primary: .clear,
                secondary: .clear,
                symbolName: "person"
            ),
            body: "post",
            createdAt: 400,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )

        store.muteAuthor(authorPubkey: post.author.pubkey)
        #expect(store.phase == .failed("Mute failed: local mutation persistence failed"))

        store.bookmark(eventID: post.id)
        #expect(store.phase == .failed("Bookmark failed: local mutation persistence failed"))
    }

    @Test("Store exposes bookmarks and rematerializes muted authors")
    @MainActor
    func storeAppliesSuccessfulMutations() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "account",
            readOnly: true
        )
        let authorPubkey = String(repeating: "c", count: 64)
        let event = NostrEvent(
            id: String(repeating: "3", count: 64),
            pubkey: authorPubkey,
            createdAt: 500,
            kind: 1,
            tags: [],
            content: "visible post",
            sig: String(repeating: "4", count: 128)
        )
        let definition = try #require(HomeFeedProjectionBuilder.definitionPlan(
            accountID: account.pubkey,
            followedPubkeys: [authorPubkey],
            existingDefinition: nil,
            now: 500
        )?.definition)
        try eventStore.saveHomeFeedState(
            NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [authorPubkey],
                noteEvents: [event],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey,
            definition: definition,
            memberships: HomeFeedProjectionBuilder.memberships(
                events: [event],
                feedID: definition.feedID,
                feedRevision: definition.revision,
                reason: "test",
                insertedAt: 500
            ),
            savedAt: 500
        )
        let store = HomeTimelineStoreFactory.make(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: CancellableLocalMutationRelayFetcher(),
                bootstrapRelays: ["wss://relay.example"]
            ),
            eventStore: eventStore
        )
        store.start(account: account)
        defer { store.cancel() }
        let post = try await waitForPost(in: store) {
            $0.bodyPresentation.collapseReason == nil
        }
        #expect(post.bodyPresentation.collapseReason == nil)

        store.bookmark(eventID: post.id)
        #expect(store.isBookmarked(post))

        store.muteAuthor(authorPubkey: post.author.pubkey)
        let mutedPost = try await waitForPost(in: store) {
            $0.bodyPresentation.collapseReason == .filtered
        }
        #expect(mutedPost.id == post.id)
        #expect(mutedPost.bodyPresentation.collapseReason == .filtered)
        #expect(store.filterStatus.activeRuleCount == 1)
        #expect(store.filterStatus.warningMatchCount == 1)
    }
}

@MainActor
private func waitForPost(
    in store: NostrHomeTimelineStore,
    matching predicate: (TimelinePost) -> Bool
) async throws -> TimelinePost {
    for _ in 0..<200 {
        if let post = store.entries.compactMap(\.post).first,
           predicate(post) {
            return post
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return try #require(store.entries.compactMap(\.post).first)
}

private struct FailingLocalMutationPersistence: HomeTimelineLocalMutationPersisting {
    func saveFilterRule(_ rule: NostrFilterRuleRecord) throws {
        throw LocalMutationPersistenceError.unavailable
    }

    func saveLocalBookmark(_ bookmark: NostrLocalBookmarkRecord) throws {
        throw LocalMutationPersistenceError.unavailable
    }
}

private enum LocalMutationPersistenceError: LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? {
        "local mutation persistence failed"
    }
}

private actor CancellableLocalMutationRelayFetcher: NostrRelayFetching {
    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }
}
