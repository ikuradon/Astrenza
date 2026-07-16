import AstrenzaCore

@MainActor
protocol HomeStoreQueryInteracting: AnyObject {
    func isBookmarked(eventID: String, accountID: String?) -> Bool

    func listEntries(
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelineFeedEntry]

    func post(
        eventID: String,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> TimelinePost?

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> UserProfile

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> HomeTimelineProfileProjection

    func profilePosts(
        pubkey: String,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost]

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost]

    func replies(
        for post: TimelinePost,
        limit: Int,
        snapshot: HomeTimelineQueryStoreSnapshot
    ) -> [TimelinePost]

    func event(
        id: String,
        preferring inMemoryEvents: [NostrEvent]
    ) -> NostrEvent?

    func olderBackfillEvents(
        _ query: HomeTimelineOlderBackfillQuery
    ) -> [NostrEvent]?

    func invalidateListEntries() -> HomeTimelineListProjectionInvalidation
}

extension HomeTimelineQueryInteractionWorkflow: HomeStoreQueryInteracting {}

@MainActor
protocol HomeStoreQuerySourcing: AnyObject {
    var preferredEvents: [NostrEvent] { get }

    func snapshot() -> HomeTimelineQueryStoreSnapshot
}

@MainActor
protocol HomeStoreQueryEventSourcing: AnyObject {
    var preferredEvents: [NostrEvent] { get }
}

extension HomeTimelineDataInteractionWorkflow: HomeStoreQueryEventSourcing {
    var preferredEvents: [NostrEvent] {
        contentState.noteEvents
    }
}

@MainActor
final class HomeStoreQuerySource: HomeStoreQuerySourcing {
    private let publishedState: HomeTimelinePublishedStateCoordinator
    private let events: any HomeStoreQueryEventSourcing

    init(
        publishedState: HomeTimelinePublishedStateCoordinator,
        events: any HomeStoreQueryEventSourcing
    ) {
        self.publishedState = publishedState
        self.events = events
    }

    var preferredEvents: [NostrEvent] {
        events.preferredEvents
    }

    func snapshot() -> HomeTimelineQueryStoreSnapshot {
        HomeTimelineQueryStoreSnapshot(
            accountID: publishedState.account?.pubkey,
            fallbackEntries: publishedState.entries,
            resolvedRelayCount: publishedState.resolvedRelays.count,
            syncPolicy: publishedState.syncPolicy,
            homeContentRevision: publishedState.resolvedContentRevision,
            listContentRevision: publishedState.listProjectionRevision
        )
    }
}

@MainActor
final class HomeStoreQueryCoordinator {
    private let source: any HomeStoreQuerySourcing
    private let interaction: any HomeStoreQueryInteracting

    init(
        source: any HomeStoreQuerySourcing,
        interaction: any HomeStoreQueryInteracting
    ) {
        self.source = source
        self.interaction = interaction
    }

    static func live(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreQueryCoordinator {
        HomeStoreQueryCoordinator(
            source: HomeStoreQuerySource(
                publishedState: components.publishedStateCoordinator,
                events: components.dataInteractionWorkflow
            ),
            interaction: components.queryInteractionWorkflow
        )
    }

    func timelineEvent(id: String) -> NostrEvent? {
        interaction.event(
            id: id,
            preferring: source.preferredEvents
        )
    }

    func olderBackfillEvents(
        account: NostrAccount,
        current: NostrHomeTimelineState
    ) -> [NostrEvent]? {
        interaction.olderBackfillEvents(
            HomeTimelineOlderBackfillQuery(
                accountID: account.pubkey,
                followedPubkeys: current.followedPubkeys,
                currentEvents: current.noteEvents,
                limit: 1_000
            )
        )
    }

    func isBookmarked(_ post: TimelinePost) -> Bool {
        interaction.isBookmarked(
            eventID: post.id,
            accountID: currentSnapshot().accountID
        )
    }

    func listEntries(limit: Int) -> [TimelineFeedEntry] {
        interaction.listEntries(
            limit: limit,
            snapshot: currentSnapshot()
        )
    }

    func post(eventID: String) -> TimelinePost? {
        interaction.post(
            eventID: eventID,
            snapshot: currentSnapshot()
        )
    }

    func profile(
        pubkey: String,
        isCurrentUser: Bool
    ) -> UserProfile {
        interaction.profile(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            snapshot: currentSnapshot()
        )
    }

    func profileProjection(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int
    ) -> HomeTimelineProfileProjection {
        interaction.profileProjection(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit,
            snapshot: currentSnapshot()
        )
    }

    func profilePosts(
        pubkey: String,
        limit: Int
    ) -> [TimelinePost] {
        interaction.profilePosts(
            pubkey: pubkey,
            limit: limit,
            snapshot: currentSnapshot()
        )
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int
    ) -> [TimelinePost] {
        interaction.replyAncestors(
            for: post,
            limit: limit,
            snapshot: currentSnapshot()
        )
    }

    func replies(
        for post: TimelinePost,
        limit: Int
    ) -> [TimelinePost] {
        interaction.replies(
            for: post,
            limit: limit,
            snapshot: currentSnapshot()
        )
    }

    func invalidateListEntries() -> HomeTimelineListProjectionInvalidation {
        interaction.invalidateListEntries()
    }

    private func currentSnapshot() -> HomeTimelineQueryStoreSnapshot {
        source.snapshot()
    }
}
