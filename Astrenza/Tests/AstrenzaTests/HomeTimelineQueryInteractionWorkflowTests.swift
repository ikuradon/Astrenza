import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline query interaction workflow")
@MainActor
struct HomeTimelineQueryInteractionTests {
    @Test("Public timeline queries preserve their repository arguments")
    func routesPublicQueries() {
        let repository = QueryRepositorySpy()
        let workflow = makeWorkflow(repository: repository)
        let snapshot = querySnapshot(accountID: "account")
        let post = repository.postResult

        let isBookmarked = workflow.isBookmarked(
            eventID: post.id,
            accountID: "account"
        )
        let resolvedPost = workflow.post(
            eventID: post.id,
            snapshot: snapshot
        )
        let profile = workflow.profile(
            pubkey: "author",
            isCurrentUser: true,
            snapshot: snapshot
        )
        let profilePosts = workflow.profilePosts(
            pubkey: "author",
            limit: 80,
            snapshot: snapshot
        )
        let ancestors = workflow.replyAncestors(
            for: post,
            limit: 8,
            snapshot: snapshot
        )
        let replies = workflow.replies(
            for: post,
            limit: 24,
            snapshot: snapshot
        )

        #expect(isBookmarked)
        #expect(resolvedPost?.id == post.id)
        #expect(profile.id == repository.profileResult.id)
        #expect(profilePosts.map(\.id) == [post.id])
        #expect(ancestors.map(\.id) == [post.id])
        #expect(replies.map(\.id) == [post.id])
        #expect(repository.events == [
            .isBookmarked(eventID: post.id, accountID: "account"),
            .post(eventID: post.id, accountID: "account"),
            .profile(
                pubkey: "author",
                isCurrentUser: true,
                accountID: "account"
            ),
            .profilePosts(pubkey: "author", limit: 80, accountID: "account"),
            .replyAncestors(postID: post.id, limit: 8, accountID: "account"),
            .replies(postID: post.id, limit: 24, accountID: "account")
        ])
    }

    @Test("Every list projection key field and invalidation control reuse")
    func listProjectionCacheBoundary() {
        let repository = QueryRepositorySpy()
        let cache = HomeTimelineListProjectionCache()
        let workflow = HomeTimelineQueryInteractionWorkflow(
            repository: repository,
            listProjectionCache: cache,
            profileProjectionCache: HomeTimelineProfileProjectionCache(),
            readContext: ReadContextProviderSpy()
        )
        let firstSnapshot = querySnapshot(
            accountID: "account-a",
            revision: 1
        )

        let first = workflow.listEntries(limit: 5, snapshot: firstSnapshot)
        let cached = workflow.listEntries(limit: 5, snapshot: firstSnapshot)
        let accountChanged = workflow.listEntries(
            limit: 5,
            snapshot: querySnapshot(accountID: "account-b", revision: 1)
        )
        let limitChanged = workflow.listEntries(
            limit: 6,
            snapshot: querySnapshot(accountID: "account-a", revision: 1)
        )
        let revisionChanged = workflow.listEntries(
            limit: 5,
            snapshot: querySnapshot(accountID: "account-a", revision: 2)
        )
        let invalidation = workflow.invalidateListEntries()
        let invalidated = workflow.listEntries(
            limit: 5,
            snapshot: querySnapshot(accountID: "account-a", revision: 2)
        )

        #expect(first.map(\.id) == ["list-1"])
        #expect(cached.map(\.id) == ["list-1"])
        #expect(accountChanged.map(\.id) == ["list-2"])
        #expect(limitChanged.map(\.id) == ["list-3"])
        #expect(revisionChanged.map(\.id) == ["list-4"])
        #expect(invalidated.map(\.id) == ["list-5"])
        #expect(invalidation.revision == 1)
        #expect(repository.events == [
            .listEntries(limit: 5, accountID: "account-a"),
            .listEntries(limit: 5, accountID: "account-b"),
            .listEntries(limit: 6, accountID: "account-a"),
            .listEntries(limit: 5, accountID: "account-a"),
            .listEntries(limit: 5, accountID: "account-a")
        ])
    }

    @Test("Signed-out list query bypasses context and repository work")
    func signedOutListQueryIsEmpty() {
        let repository = QueryRepositorySpy()
        let readContext = ReadContextProviderSpy()
        let workflow = makeWorkflow(
            repository: repository,
            readContext: readContext
        )

        let entries = workflow.listEntries(
            limit: 500,
            snapshot: querySnapshot(accountID: nil)
        )

        #expect(entries.isEmpty)
        #expect(repository.events.isEmpty)
        #expect(readContext.appliedHomeFilterValues.isEmpty)
    }

    @Test("In-memory events win while database fallback and backfill are routed")
    func routesProjectionSupportQueries() {
        let repository = QueryRepositorySpy()
        let workflow = makeWorkflow(repository: repository)
        let memoryEvent = event(id: "memory", createdAt: 300)
        let currentEvent = event(id: "current", createdAt: 200)

        let preferred = workflow.event(
            id: memoryEvent.id,
            preferring: [memoryEvent]
        )
        let stored = workflow.event(
            id: repository.eventResult.id,
            preferring: [memoryEvent]
        )
        let backfill = workflow.olderBackfillEvents(
            HomeTimelineOlderBackfillQuery(
                accountID: "account",
                followedPubkeys: ["author"],
                currentEvents: [currentEvent],
                limit: 1_000
            )
        )

        #expect(preferred == memoryEvent)
        #expect(stored == repository.eventResult)
        #expect(backfill == repository.olderBackfillResult)
        #expect(repository.events == [
            .event(id: repository.eventResult.id),
            .olderBackfill(
                accountID: "account",
                followedPubkeys: ["author"],
                currentEventIDs: [currentEvent.id],
                limit: 1_000
            )
        ])
    }

    private func makeWorkflow(
        repository: QueryRepositorySpy,
        readContext: ReadContextProviderSpy = ReadContextProviderSpy()
    ) -> HomeTimelineQueryInteractionWorkflow {
        HomeTimelineQueryInteractionWorkflow(
            repository: repository,
            listProjectionCache: HomeTimelineListProjectionCache(),
            profileProjectionCache: HomeTimelineProfileProjectionCache(),
            readContext: readContext
        )
    }

    private func querySnapshot(
        accountID: String?,
        revision: Int = 0
    ) -> HomeTimelineQueryStoreSnapshot {
        HomeTimelineQueryStoreSnapshot(
            accountID: accountID,
            fallbackEntries: [],
            resolvedRelayCount: 0,
            syncPolicy: .default(),
            homeContentRevision: revision,
            listContentRevision: 0
        )
    }

    private func event(id: String, createdAt: Int) -> NostrEvent {
        NostrEvent(
            id: id,
            pubkey: "author",
            createdAt: createdAt,
            kind: 1,
            tags: [],
            content: id,
            sig: "signature"
        )
    }
}

private enum QueryRepositoryEvent: Equatable {
    case isBookmarked(eventID: String, accountID: String?)
    case listEntries(limit: Int, accountID: String?)
    case post(eventID: String, accountID: String?)
    case profile(pubkey: String, isCurrentUser: Bool, accountID: String?)
    case profilePosts(pubkey: String, limit: Int, accountID: String?)
    case replyAncestors(postID: String, limit: Int, accountID: String?)
    case replies(postID: String, limit: Int, accountID: String?)
    case event(id: String)
    case olderBackfill(
        accountID: String,
        followedPubkeys: [String],
        currentEventIDs: [String],
        limit: Int
    )
}

@MainActor
private final class QueryRepositorySpy: HomeTimelineQueryRepository {
    private(set) var events: [QueryRepositoryEvent] = []
    private var listReadCount = 0

    let postResult = TimelinePost(
        id: "post",
        author: .unresolved(pubkey: "author"),
        avatar: AvatarStyle(
            primary: .clear,
            secondary: .clear,
            symbolName: "person"
        ),
        body: "body",
        createdAt: 100,
        replyCount: nil,
        boostCount: nil,
        favoriteCount: nil,
        isLocked: false,
        media: nil,
        context: nil
    )

    lazy var profileResult = UserProfile(
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

    let eventResult = NostrEvent(
        id: "stored",
        pubkey: "author",
        createdAt: 100,
        kind: 1,
        tags: [],
        content: "stored",
        sig: "signature"
    )

    lazy var olderBackfillResult = [eventResult]

    func event(id: String) -> NostrEvent? {
        events.append(.event(id: id))
        return eventResult
    }

    func olderBackfillEvents(
        accountID: String,
        followedPubkeys: [String],
        currentEvents: [NostrEvent],
        limit: Int
    ) -> [NostrEvent]? {
        events.append(.olderBackfill(
            accountID: accountID,
            followedPubkeys: followedPubkeys,
            currentEventIDs: currentEvents.map(\.id),
            limit: limit
        ))
        return olderBackfillResult
    }

    func post(
        eventID: String,
        context: HomeTimelineReadContext
    ) -> TimelinePost? {
        events.append(.post(eventID: eventID, accountID: context.accountID))
        return postResult
    }

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        context: HomeTimelineReadContext
    ) -> UserProfile {
        events.append(.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            accountID: context.accountID
        ))
        return profileResult
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        events.append(.profilePosts(
            pubkey: pubkey,
            limit: limit,
            accountID: context.accountID
        ))
        return [postResult]
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        events.append(.replyAncestors(
            postID: post.id,
            limit: limit,
            accountID: context.accountID
        ))
        return [postResult]
    }

    func replies(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        events.append(.replies(
            postID: post.id,
            limit: limit,
            accountID: context.accountID
        ))
        return [postResult]
    }

    func isBookmarked(eventID: String, accountID: String?) -> Bool {
        events.append(.isBookmarked(eventID: eventID, accountID: accountID))
        return true
    }

    func listEntries(
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelineFeedEntry] {
        events.append(.listEntries(limit: limit, accountID: context.accountID))
        listReadCount += 1
        return [.deleted(TimelineDeletedEntry(id: "list-\(listReadCount)"))]
    }
}

@MainActor
private final class ReadContextProviderSpy:
    HomeTimelineReadContextProviding {
    private(set) var appliedHomeFilterValues: [Bool] = []

    func context(
        for input: HomeTimelineReadContextInput,
        applyingHomeFilters: Bool
    ) -> HomeTimelineReadContext {
        appliedHomeFilterValues.append(applyingHomeFilters)
        return HomeTimelineReadContext(
            accountID: input.accountID,
            fallbackEntries: input.fallbackEntries,
            metadataEvents: [],
            nip05Resolutions: [:],
            profileResolutionStates: [:],
            followedPubkeys: [],
            resolvedRelayCount: input.resolvedRelayCount,
            filterRules: nil,
            syncPolicy: input.syncPolicy
        )
    }
}
