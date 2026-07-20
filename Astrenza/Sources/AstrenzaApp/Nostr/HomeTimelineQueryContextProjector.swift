import AstrenzaCore

struct HomeTimelineListProjectionQuery {
    let accountID: String
    let limit: Int
    let homeContentRevision: Int
    let contextInput: HomeTimelineReadContextInput
}

struct HomeTimelineProfileProjectionQuery {
    let pubkey: String
    let isCurrentUser: Bool
    let postsLimit: Int
    let homeContentRevision: Int
    let listContentRevision: Int
    let profileDataRevision: Int
    let contextInput: HomeTimelineReadContextInput
}

struct HomeTimelineQueryStoreSnapshot {
    let accountID: String?
    let fallbackEntries: [TimelineFeedEntry]
    let resolvedRelayCount: Int
    let syncPolicy: NostrSyncPolicy
    let homeContentRevision: Int
    let listContentRevision: Int
    let profileDataRevision: Int
}

struct HomeTimelineQueryContextProjection {
    let accountID: String?
    let homeContentRevision: Int
    let listContentRevision: Int
    let profileDataRevision: Int
    let readContextInput: HomeTimelineReadContextInput
}

struct HomeTimelineQueryContextProjector {
    func projection(
        from snapshot: HomeTimelineQueryStoreSnapshot
    ) -> HomeTimelineQueryContextProjection {
        HomeTimelineQueryContextProjection(
            accountID: snapshot.accountID,
            homeContentRevision: snapshot.homeContentRevision,
            listContentRevision: snapshot.listContentRevision,
            profileDataRevision: snapshot.profileDataRevision,
            readContextInput: HomeTimelineReadContextInput(
                accountID: snapshot.accountID,
                fallbackEntries: snapshot.fallbackEntries,
                resolvedRelayCount: snapshot.resolvedRelayCount,
                syncPolicy: snapshot.syncPolicy
            )
        )
    }

    func listProjectionQuery(
        limit: Int,
        from projection: HomeTimelineQueryContextProjection
    ) -> HomeTimelineListProjectionQuery? {
        guard let accountID = projection.accountID else { return nil }
        return HomeTimelineListProjectionQuery(
            accountID: accountID,
            limit: limit,
            homeContentRevision: projection.homeContentRevision,
            contextInput: projection.readContextInput
        )
    }

    func profileProjectionQuery(
        pubkey: String,
        isCurrentUser: Bool,
        postsLimit: Int,
        from projection: HomeTimelineQueryContextProjection
    ) -> HomeTimelineProfileProjectionQuery {
        HomeTimelineProfileProjectionQuery(
            pubkey: pubkey,
            isCurrentUser: isCurrentUser,
            postsLimit: postsLimit,
            homeContentRevision: projection.homeContentRevision,
            listContentRevision: projection.listContentRevision,
            profileDataRevision: projection.profileDataRevision,
            contextInput: projection.readContextInput
        )
    }
}
