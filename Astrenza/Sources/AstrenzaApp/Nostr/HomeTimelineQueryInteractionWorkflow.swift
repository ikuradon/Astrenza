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

struct HomeTimelineListProjectionQuery {
    let accountID: String
    let limit: Int
    let homeContentRevision: Int
    let context: HomeTimelineReadContext
}

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

    init(
        repository: any HomeTimelineQueryRepository,
        listProjectionCache: any HomeTimelineListProjectionCaching
    ) {
        self.repository = repository
        self.listProjectionCache = listProjectionCache
    }

    func isBookmarked(eventID: String, accountID: String?) -> Bool {
        repository.isBookmarked(
            eventID: eventID,
            accountID: accountID
        )
    }

    func listEntries(
        _ query: HomeTimelineListProjectionQuery
    ) -> [TimelineFeedEntry] {
        let cacheKey = HomeTimelineListProjectionCache.Key(
            accountID: query.accountID,
            limit: query.limit,
            homeContentRevision: query.homeContentRevision
        )
        return listProjectionCache.entries(for: cacheKey) {
            repository.listEntries(
                limit: query.limit,
                context: query.context
            )
        }
    }

    func post(
        eventID: String,
        context: HomeTimelineReadContext
    ) -> TimelinePost? {
        repository.post(eventID: eventID, context: context)
    }

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        context: HomeTimelineReadContext
    ) -> UserProfile {
        repository.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            context: context
        )
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        repository.profilePosts(
            pubkey: pubkey,
            limit: limit,
            context: context
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        repository.replyAncestors(
            for: post,
            limit: limit,
            context: context
        )
    }

    func replies(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        repository.replies(
            for: post,
            limit: limit,
            context: context
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
