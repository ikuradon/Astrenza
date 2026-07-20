import Testing
@testable import Astrenza

@Suite("Home timeline profile projection cache")
@MainActor
struct HomeTimelineProfileProjectionCacheTests {
    @Test("Matching profile keys reuse materialized projections")
    func matchingKeysReuseProjection() {
        let cache = HomeTimelineProfileProjectionCache()
        let key = makeKey()
        var materializationCount = 0

        let first = cache.projection(for: key) {
            materializationCount += 1
            return projection(id: "first")
        }
        let second = cache.projection(for: key) {
            materializationCount += 1
            return projection(id: "unexpected")
        }

        #expect(first.profile.id == "first")
        #expect(second.profile.id == "first")
        #expect(materializationCount == 1)
    }

    @Test(
        "Every profile cache key field participates in lookup",
        arguments: [
            HomeTimelineProfileProjectionCache.Key(
                accountID: "other-account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "other-profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: true,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 40,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 8,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 3,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 5,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 4,
                syncPolicy: .default(networkType: .wifi)
            ),
            HomeTimelineProfileProjectionCache.Key(
                accountID: "account",
                pubkey: "profile",
                isCurrentUser: false,
                postsLimit: 80,
                homeContentRevision: 7,
                listContentRevision: 2,
                profileDataRevision: 4,
                resolvedRelayCount: 3,
                syncPolicy: .default(networkType: .cellular)
            )
        ]
    )
    func cacheKeyFields(
        mismatchedKey: HomeTimelineProfileProjectionCache.Key
    ) {
        let cache = HomeTimelineProfileProjectionCache()
        var materializationCount = 0
        _ = cache.projection(for: makeKey()) {
            materializationCount += 1
            return projection(id: "first")
        }

        let replacement = cache.projection(for: mismatchedKey) {
            materializationCount += 1
            return projection(id: "replacement")
        }

        #expect(replacement.profile.id == "replacement")
        #expect(materializationCount == 2)
    }

    @Test("Bounded cache evicts the least recently used projection")
    func boundedCacheEvictsLeastRecentProjection() {
        let cache = HomeTimelineProfileProjectionCache(capacity: 2)
        let firstKey = makeKey(pubkey: "first")
        let secondKey = makeKey(pubkey: "second")
        let thirdKey = makeKey(pubkey: "third")
        var materializationCount = 0

        func project(_ id: String) -> HomeTimelineProfileProjection {
            materializationCount += 1
            return projection(id: id)
        }

        _ = cache.projection(for: firstKey) { project("first") }
        _ = cache.projection(for: secondKey) { project("second") }
        _ = cache.projection(for: firstKey) { project("unexpected") }
        _ = cache.projection(for: thirdKey) { project("third") }
        let reloaded = cache.projection(for: secondKey) { project("reloaded") }

        #expect(reloaded.profile.id == "reloaded")
        #expect(materializationCount == 4)
    }

    private func makeKey(
        pubkey: String = "profile"
    ) -> HomeTimelineProfileProjectionCache.Key {
        HomeTimelineProfileProjectionCache.Key(
            accountID: "account",
            pubkey: pubkey,
            isCurrentUser: false,
            postsLimit: 80,
            homeContentRevision: 7,
            listContentRevision: 2,
            profileDataRevision: 4,
            resolvedRelayCount: 3,
            syncPolicy: .default(networkType: .wifi)
        )
    }

    private func projection(
        id: String
    ) -> HomeTimelineProfileProjection {
        let post = TimelinePost(
            id: id,
            author: .unresolved(pubkey: id),
            avatar: AvatarStyle(
                primary: .clear,
                secondary: .clear,
                symbolName: "person"
            ),
            body: id,
            createdAt: 1,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
        return HomeTimelineProfileProjection(
            profile: UserProfile(
                id: id,
                author: post.author,
                avatar: post.avatar,
                banner: ProfileBannerStyle(colors: [], symbolName: "person"),
                bio: "",
                isCurrentUser: false,
                isFollowed: false,
                followerCount: 0,
                followingCount: 0,
                postCount: 1,
                relayCount: 1,
                latestFollowers: [],
                featuredHashtags: []
            ),
            posts: [post]
        )
    }
}
