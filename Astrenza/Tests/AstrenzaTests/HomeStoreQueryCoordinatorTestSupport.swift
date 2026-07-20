import AstrenzaCore
import Testing
@testable import Astrenza

@MainActor
func expectPublicQueryResults(
    fixture: StoreQueryFixture,
    post: TimelinePost
) {
    #expect(fixture.coordinator.isBookmarked(post))
    #expect(fixture.coordinator.listEntries(limit: 12).map(\.id) == [
        post.id
    ])
    #expect(fixture.coordinator.post(eventID: post.id)?.id == post.id)
    #expect(fixture.coordinator.profile(
        pubkey: "author",
        isCurrentUser: true
    ).id == "author")
    #expect(fixture.coordinator.profileProjection(
        pubkey: "author",
        isCurrentUser: true,
        postsLimit: 34
    ).posts.map(\.id) == [post.id])
    #expect(fixture.coordinator.profilePosts(
        pubkey: "author",
        limit: 56
    ).map(\.id) == [post.id])
    #expect(fixture.coordinator.replyAncestors(
        for: post,
        limit: 7
    ).map(\.id) == [post.id])
    #expect(fixture.coordinator.replies(
        for: post,
        limit: 8
    ).map(\.id) == [post.id])
}

@MainActor
final class StoreQueryEventSourceSpy: HomeStoreQueryEventSourcing {
    var preferredEvents: [NostrEvent]

    init(preferredEvents: [NostrEvent]) {
        self.preferredEvents = preferredEvents
    }
}

@MainActor
final class StoreQuerySourceSpy: HomeStoreQuerySourcing {
    var account: NostrAccount?
    var entries: [TimelineFeedEntry]
    var resolvedRelays: [String]
    var syncPolicy: NostrSyncPolicy
    var resolvedContentRevision: Int
    var listContentRevision: Int
    var profileDataRevision: Int
    var preferredEvents: [NostrEvent]
    private(set) var snapshotCount = 0

    init(
        account: NostrAccount?,
        entries: [TimelineFeedEntry],
        resolvedRelays: [String],
        syncPolicy: NostrSyncPolicy,
        resolvedContentRevision: Int,
        listContentRevision: Int,
        profileDataRevision: Int = 0,
        preferredEvents: [NostrEvent]
    ) {
        self.account = account
        self.entries = entries
        self.resolvedRelays = resolvedRelays
        self.syncPolicy = syncPolicy
        self.resolvedContentRevision = resolvedContentRevision
        self.listContentRevision = listContentRevision
        self.profileDataRevision = profileDataRevision
        self.preferredEvents = preferredEvents
    }

    func snapshot() -> HomeTimelineQueryStoreSnapshot {
        snapshotCount += 1
        return HomeTimelineQueryStoreSnapshot(
            accountID: account?.pubkey,
            fallbackEntries: entries,
            resolvedRelayCount: resolvedRelays.count,
            syncPolicy: syncPolicy,
            homeContentRevision: resolvedContentRevision,
            listContentRevision: listContentRevision,
            profileDataRevision: profileDataRevision
        )
    }
}

struct StoreQuerySnapshotRecord: Equatable {
    let accountID: String?
    let fallbackEntryIDs: [String]
    let resolvedRelayCount: Int
    let syncPolicy: NostrSyncPolicy
    let homeContentRevision: Int
    let listContentRevision: Int
    let profileDataRevision: Int

    init(
        accountID: String?,
        fallbackEntryIDs: [String],
        resolvedRelayCount: Int,
        syncPolicy: NostrSyncPolicy,
        homeContentRevision: Int,
        listContentRevision: Int,
        profileDataRevision: Int
    ) {
        self.accountID = accountID
        self.fallbackEntryIDs = fallbackEntryIDs
        self.resolvedRelayCount = resolvedRelayCount
        self.syncPolicy = syncPolicy
        self.homeContentRevision = homeContentRevision
        self.listContentRevision = listContentRevision
        self.profileDataRevision = profileDataRevision
    }

    @MainActor
    init(source: StoreQuerySourceSpy) {
        self.init(
            accountID: source.account?.pubkey,
            fallbackEntryIDs: source.entries.map(\.id),
            resolvedRelayCount: source.resolvedRelays.count,
            syncPolicy: source.syncPolicy,
            homeContentRevision: source.resolvedContentRevision,
            listContentRevision: source.listContentRevision,
            profileDataRevision: source.profileDataRevision
        )
    }

    init(snapshot: HomeTimelineQueryStoreSnapshot) {
        self.init(
            accountID: snapshot.accountID,
            fallbackEntryIDs: snapshot.fallbackEntries.map(\.id),
            resolvedRelayCount: snapshot.resolvedRelayCount,
            syncPolicy: snapshot.syncPolicy,
            homeContentRevision: snapshot.homeContentRevision,
            listContentRevision: snapshot.listContentRevision,
            profileDataRevision: snapshot.profileDataRevision
        )
    }

}

struct StoreQueryEventRequest: Equatable {
    let eventID: String
    let preferredEventIDs: [String]
}

struct StoreQueryBackfillRecord: Equatable {
    let accountID: String
    let followedPubkeys: [String]
    let currentEventIDs: [String]
    let limit: Int
}

@MainActor
final class StoreQueryInteractionSpy: HomeStoreQueryInteracting {
    private(set) var routes: [String] = []
    private(set) var snapshots: [StoreQuerySnapshotRecord] = []
    private(set) var eventRequests: [StoreQueryEventRequest] = []
    private(set) var backfillQueries: [StoreQueryBackfillRecord] = []
    private(set) var invalidationCount = 0

    let postResult = MockTimelineData.posts[0]
    let eventResult = StoreQueryFixture.makeEvent(
        id: "stored",
        pubkey: "author"
    )

    private lazy var profileResult = UserProfile(
        id: "author",
        author: postResult.author,
        avatar: postResult.avatar,
        banner: ProfileBannerStyle(colors: [], symbolName: "person"),
        bio: "bio",
        isCurrentUser: false,
        isFollowed: false,
        followerCount: 0,
        followingCount: 0,
        postCount: 1,
        relayCount: 1,
        latestFollowers: [],
        featuredHashtags: []
    )

    func isBookmarked(eventID: String, accountID: String?) -> Bool {
        routes.append("bookmark:\(eventID):\(accountID ?? "nil")")
        return true
    }

    func listEntries(
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelineFeedEntry] {
        record(snapshot)
        routes.append("list:\(limit)")
        return [.post(postResult)]
    }

    func post(
        eventID: String,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> TimelinePost? {
        record(snapshot)
        routes.append("post:\(eventID)")
        return postResult
    }

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> UserProfile {
        record(snapshot)
        routes.append("profile:\(pubkey):\(isCurrentUser)")
        return profileResult
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> HomeTimelineProfileProjection {
        record(snapshot)
        routes.append(
            "profile-projection:\(pubkey):\(isCurrentUser):\(postsLimit)"
        )
        return HomeTimelineProfileProjection(
            profile: profileResult,
            posts: [postResult]
        )
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        record(snapshot)
        routes.append("profile-posts:\(pubkey):\(limit)")
        return [postResult]
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        record(snapshot)
        routes.append("ancestors:\(post.id):\(limit)")
        return [postResult]
    }

    func replies(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        record(snapshot)
        routes.append("replies:\(post.id):\(limit)")
        return [postResult]
    }

    func event(
        id: String,
        preferring inMemoryEvents: [NostrEvent]
    ) -> NostrEvent? {
        eventRequests.append(
            StoreQueryEventRequest(
                eventID: id,
                preferredEventIDs: inMemoryEvents.map(\.id)
            )
        )
        return eventResult
    }

    func olderBackfillEvents(
        _ query: HomeTimelineOlderBackfillQuery
    ) -> [NostrEvent]? {
        backfillQueries.append(
            StoreQueryBackfillRecord(
                accountID: query.accountID,
                followedPubkeys: query.followedPubkeys,
                currentEventIDs: query.currentEvents.map(\.id),
                limit: query.limit
            )
        )
        return [eventResult]
    }

    func invalidateListEntries() -> HomeTimelineListProjectionInvalidation {
        invalidationCount += 1
        return HomeTimelineListProjectionInvalidation(revision: 29)
    }

    private func record(_ snapshot: HomeTimelineQueryStoreSnapshot) {
        snapshots.append(StoreQuerySnapshotRecord(snapshot: snapshot))
    }
}

@MainActor
struct StoreQueryFixture {
    let account = Self.makeAccount(character: "a")
    let replacementAccount = Self.makeAccount(character: "b")
    let interaction = StoreQueryInteractionSpy()
    let source: StoreQuerySourceSpy
    let coordinator: HomeStoreQueryCoordinator

    init() {
        let account = Self.makeAccount(character: "a")
        let post = interaction.postResult
        let source = StoreQuerySourceSpy(
            account: account,
            entries: [
                .post(post),
                .deleted(TimelineDeletedEntry(id: "deleted"))
            ],
            resolvedRelays: [
                "wss://one.example",
                "wss://two.example"
            ],
            syncPolicy: .default(
                networkType: .wifi,
                lowPowerMode: true
            ),
            resolvedContentRevision: 17,
            listContentRevision: 19,
            profileDataRevision: 23,
            preferredEvents: []
        )
        self.source = source
        coordinator = HomeStoreQueryCoordinator(
            source: source,
            interaction: interaction
        )
    }

    static func makeAccount(character: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: character, count: 64),
            displayIdentifier: "query-\(character)",
            readOnly: true
        )
    }

    static func makeEvent(id: String, pubkey: String) -> NostrEvent {
        NostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: id,
            sig: "signature"
        )
    }
}
