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
protocol HomeStoreQueryTarget: AnyObject {
    var account: NostrAccount? { get }
    var entries: [TimelineFeedEntry] { get }
    var resolvedRelays: [String] { get }
    var syncPolicy: NostrSyncPolicy { get }
    var resolvedContentRevision: Int { get }
    var listContentRevision: Int { get }
    var queryPreferredEvents: [NostrEvent] { get }
}

@MainActor
final class HomeStoreQueryCoordinator {
    private let interaction: any HomeStoreQueryInteracting
    private weak var target: (any HomeStoreQueryTarget)?

    init(
        interaction: any HomeStoreQueryInteracting,
        target: (any HomeStoreQueryTarget)? = nil
    ) {
        self.interaction = interaction
        self.target = target
    }

    func bind(target: any HomeStoreQueryTarget) {
        self.target = target
    }

    func timelineEvent(id: String) -> NostrEvent? {
        interaction.event(
            id: id,
            preferring: target?.queryPreferredEvents ?? []
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
            accountID: target?.account?.pubkey
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
        guard let target else {
            return HomeTimelineQueryStoreSnapshot(
                accountID: nil,
                fallbackEntries: [],
                resolvedRelayCount: 0,
                syncPolicy: .default(),
                homeContentRevision: 0,
                listContentRevision: 0
            )
        }
        return HomeTimelineQueryStoreSnapshot(
            accountID: target.account?.pubkey,
            fallbackEntries: target.entries,
            resolvedRelayCount: target.resolvedRelays.count,
            syncPolicy: target.syncPolicy,
            homeContentRevision: target.resolvedContentRevision,
            listContentRevision: target.listContentRevision
        )
    }
}
