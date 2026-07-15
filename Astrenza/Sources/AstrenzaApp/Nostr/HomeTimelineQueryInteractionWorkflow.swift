import AstrenzaCore

@MainActor
protocol HomeTimelineQueryRepository {
    func event(id: String) -> NostrEvent?

    func olderBackfillEvents(
        accountID: String,
        followedPubkeys: [String],
        currentEvents: [NostrEvent],
        limit: Int
    ) -> [NostrEvent]?

    func post(
        eventID: String,
        context: HomeTimelineReadContext
    ) -> TimelinePost?

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        context: HomeTimelineReadContext
    ) -> UserProfile

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        context: HomeTimelineReadContext
    ) -> HomeTimelineProfileProjection

    func profilePosts(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost]

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost]

    func replies(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost]

    func isBookmarked(eventID: String, accountID: String?) -> Bool

    func listEntries(
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelineFeedEntry]
}

extension HomeTimelineRepository: HomeTimelineQueryRepository {}

extension HomeTimelineQueryRepository {
    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        context: HomeTimelineReadContext
    ) -> HomeTimelineProfileProjection {
        HomeTimelineProfileProjection(
            profile: profile(
                pubkey: pubkey,
                isCurrentUser: isCurrentUser,
                context: context
            ),
            posts: profilePosts(
                pubkey: pubkey,
                limit: postsLimit,
                context: context
            )
        )
    }
}

@MainActor
protocol HomeTimelineListProjectionCaching: AnyObject {
    func entries(
        for key: HomeTimelineListProjectionCache.Key,
        materialize: () -> [TimelineFeedEntry]
    ) -> [TimelineFeedEntry]

    @discardableResult
    func invalidate() -> HomeTimelineListProjectionInvalidation
}

extension HomeTimelineListProjectionCache: HomeTimelineListProjectionCaching {}

@MainActor
protocol HomeTimelineProfileProjectionCaching: AnyObject {
    func projection(
        for key: HomeTimelineProfileProjectionCache.Key,
        materialize: () -> HomeTimelineProfileProjection
    ) -> HomeTimelineProfileProjection
}

extension HomeTimelineProfileProjectionCache:
    HomeTimelineProfileProjectionCaching {}

struct HomeTimelineOlderBackfillQuery {
    let accountID: String
    let followedPubkeys: [String]
    let currentEvents: [NostrEvent]
    let limit: Int
}

@MainActor
final class HomeTimelineQueryInteractionWorkflow {
    private let repository: any HomeTimelineQueryRepository
    private let listProjectionCache: any HomeTimelineListProjectionCaching
    private let profileProjectionCache:
        any HomeTimelineProfileProjectionCaching
    private let readContext: any HomeTimelineReadContextProviding
    private let contextProjector: HomeTimelineQueryContextProjector

    init(
        repository: any HomeTimelineQueryRepository,
        listProjectionCache: any HomeTimelineListProjectionCaching,
        profileProjectionCache: any HomeTimelineProfileProjectionCaching,
        readContext: any HomeTimelineReadContextProviding,
        contextProjector: HomeTimelineQueryContextProjector =
            HomeTimelineQueryContextProjector()
    ) {
        self.repository = repository
        self.listProjectionCache = listProjectionCache
        self.profileProjectionCache = profileProjectionCache
        self.readContext = readContext
        self.contextProjector = contextProjector
    }

    func isBookmarked(eventID: String, accountID: String?) -> Bool {
        repository.isBookmarked(
            eventID: eventID,
            accountID: accountID
        )
    }

    func listEntries(
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelineFeedEntry] {
        let projection = contextProjector.projection(from: snapshot)
        guard let query = contextProjector.listProjectionQuery(
            limit: limit,
            from: projection
        ) else { return [] }
        let cacheKey = HomeTimelineListProjectionCache.Key(
            accountID: query.accountID,
            limit: query.limit,
            homeContentRevision: query.homeContentRevision
        )
        return listProjectionCache.entries(for: cacheKey) {
            repository.listEntries(
                limit: query.limit,
                context: readContext.context(
                    for: query.contextInput,
                    applyingHomeFilters: false
                )
            )
        }
    }

    func post(
        eventID: String,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> TimelinePost? {
        let projection = contextProjector.projection(from: snapshot)
        return repository.post(
            eventID: eventID,
            context: readContext.context(
                for: projection.readContextInput,
                applyingHomeFilters: true
            )
        )
    }

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> UserProfile {
        let projection = contextProjector.projection(from: snapshot)
        return repository.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            context: readContext.context(
                for: projection.readContextInput,
                applyingHomeFilters: true
            )
        )
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> HomeTimelineProfileProjection {
        let projection = contextProjector.projection(from: snapshot)
        let query = contextProjector.profileProjectionQuery(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit,
            from: projection
        )
        let input = query.contextInput
        let key = HomeTimelineProfileProjectionCache.Key(
            accountID: input.accountID,
            pubkey: query.pubkey,
            isCurrentUser: query.isCurrentUser,
            postsLimit: query.postsLimit,
            homeContentRevision: query.homeContentRevision,
            listContentRevision: query.listContentRevision,
            resolvedRelayCount: input.resolvedRelayCount,
            syncPolicy: input.syncPolicy
        )
        return profileProjectionCache.projection(for: key) {
            repository.profileProjection(
                pubkey: query.pubkey,
                isCurrentUser: query.isCurrentUser,
                postsLimit: query.postsLimit,
                context: readContext.context(
                    for: input,
                    applyingHomeFilters: true
                )
            )
        }
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        let projection = contextProjector.projection(from: snapshot)
        return repository.profilePosts(
            pubkey: pubkey,
            limit: limit,
            context: readContext.context(
                for: projection.readContextInput,
                applyingHomeFilters: true
            )
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        let projection = contextProjector.projection(from: snapshot)
        return repository.replyAncestors(
            for: post,
            limit: limit,
            context: readContext.context(
                for: projection.readContextInput,
                applyingHomeFilters: true
            )
        )
    }

    func replies(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost] {
        let projection = contextProjector.projection(from: snapshot)
        return repository.replies(
            for: post,
            limit: limit,
            context: readContext.context(
                for: projection.readContextInput,
                applyingHomeFilters: true
            )
        )
    }

    func event(
        id: String,
        preferring inMemoryEvents: [NostrEvent]
    ) -> NostrEvent? {
        inMemoryEvents.first { $0.id == id } ?? repository.event(id: id)
    }

    func olderBackfillEvents(
        _ query: HomeTimelineOlderBackfillQuery
    ) -> [NostrEvent]? {
        repository.olderBackfillEvents(
            accountID: query.accountID,
            followedPubkeys: query.followedPubkeys,
            currentEvents: query.currentEvents,
            limit: query.limit
        )
    }

    func invalidateListEntries() -> HomeTimelineListProjectionInvalidation {
        listProjectionCache.invalidate()
    }
}
