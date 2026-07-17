import Testing
@testable import Astrenza

@Suite("Home timeline navigation")
@MainActor
struct HomeTimelineNavigationTests {
    @Test("Timeline and profile paths remain independent")
    func stackPathsRemainIndependent() throws {
        let timelinePost = try #require(MockTimelineData.posts.first)
        let profilePost = try #require(MockTimelineData.posts.dropFirst().first)
        var state = HomeTimelineNavigationState()

        state.openPost(timelinePost, on: .timeline)
        state.openProfile(from: profilePost, on: .profile)

        #expect(state.timelinePath.count == 1)
        #expect(state.profilePath.count == 1)
        #expect(state.isPresentingDetail)

        state.timelinePath.removeAll()
        #expect(state.isPresentingDetail)

        state.profilePath.removeAll()
        #expect(!state.isPresentingDetail)
    }

    @Test("Route identity survives projection updates")
    func routeIdentityUsesStableDomainIDs() throws {
        let original = try #require(MockTimelineData.posts.first)
        let updated = makePost(
            id: original.id,
            author: original.author,
            body: "Updated projection"
        )
        let anotherPostByAuthor = makePost(
            id: "another-post",
            author: original.author,
            body: "Another post"
        )

        let originalPostRoute = HomeTimelinePostRoute(post: original)
        let updatedPostRoute = HomeTimelinePostRoute(post: updated)
        let originalProfileRoute = HomeTimelineProfileRoute(post: original)
        let updatedProfileRoute = HomeTimelineProfileRoute(
            post: anotherPostByAuthor
        )

        #expect(originalPostRoute == updatedPostRoute)
        #expect(Set([originalPostRoute, updatedPostRoute]).count == 1)
        #expect(originalProfileRoute == updatedProfileRoute)
        #expect(Set([originalProfileRoute, updatedProfileRoute]).count == 1)
    }

    @Test("Live post destination resolves the latest post before its thread")
    func livePostDestinationUsesResolvedPost() throws {
        let posts = MockTimelineData.posts
        let fallback = try #require(posts.first)
        let resolved = try #require(posts.dropFirst().first)
        let ancestor = try #require(posts.dropFirst(2).first)
        let reply = try #require(posts.dropFirst(3).first)
        var calls: [String] = []
        let resolver = HomeTimelineNavigationProjectionResolver(
            post: { eventID in
                calls.append("post:\(eventID)")
                return resolved
            },
            replyAncestors: { post in
                calls.append("ancestors:\(post.id)")
                return [ancestor]
            },
            replies: { post in
                calls.append("replies:\(post.id)")
                return [reply]
            },
            profileProjection: { _ in
                makeProfileProjection(for: resolved)
            },
            mockProfileProjection: {
                makeProfileProjection(for: $0)
            }
        )

        let projection = resolver.postDetail(
            fallbackPost: fallback,
            hasLiveAccount: true
        )

        #expect(projection.post.id == resolved.id)
        #expect(projection.replyAncestors.map(\.id) == [ancestor.id])
        #expect(projection.replies.map(\.id) == [reply.id])
        #expect(calls == [
            "post:\(fallback.id)",
            "ancestors:\(resolved.id)",
            "replies:\(resolved.id)"
        ])
    }

    @Test("Mock post destination keeps route data without live queries")
    func mockPostDestinationUsesFallback() throws {
        let fallback = try #require(MockTimelineData.posts.first)
        var liveQueryCount = 0
        let resolver = HomeTimelineNavigationProjectionResolver(
            post: { _ in
                liveQueryCount += 1
                return nil
            },
            replyAncestors: { _ in
                liveQueryCount += 1
                return []
            },
            replies: { _ in
                liveQueryCount += 1
                return []
            },
            profileProjection: { _ in
                liveQueryCount += 1
                return makeProfileProjection(for: fallback)
            },
            mockProfileProjection: {
                makeProfileProjection(for: $0)
            }
        )

        let projection = resolver.postDetail(
            fallbackPost: fallback,
            hasLiveAccount: false
        )

        #expect(projection.post.id == fallback.id)
        #expect(
            projection.replyAncestors.map(\.id) ==
                MockTimelineData.replyAncestors(for: fallback).map(\.id)
        )
        #expect(
            projection.replies.map(\.id) ==
                MockTimelineData.detailReplies(for: fallback).map(\.id)
        )
        #expect(liveQueryCount == 0)
    }

    @Test("Profile destination selects live or mock projection by account")
    func profileDestinationSelectsAccountSource() throws {
        let selectedPost = try #require(MockTimelineData.posts.first)
        let liveProjection = makeProfileProjection(
            for: try #require(MockTimelineData.posts.dropFirst().first)
        )
        let mockProjection = makeProfileProjection(for: selectedPost)
        var calls: [String] = []
        let resolver = HomeTimelineNavigationProjectionResolver(
            post: { _ in nil },
            replyAncestors: { _ in [] },
            replies: { _ in [] },
            profileProjection: { pubkey in
                calls.append("live:\(pubkey)")
                return liveProjection
            },
            mockProfileProjection: { post in
                calls.append("mock:\(post.id)")
                return mockProjection
            }
        )

        let live = resolver.profile(
            for: selectedPost,
            hasLiveAccount: true
        )
        let mock = resolver.profile(
            for: selectedPost,
            hasLiveAccount: false
        )

        #expect(live.profile.id == liveProjection.profile.id)
        #expect(mock.profile.id == mockProjection.profile.id)
        #expect(calls == [
            "live:\(selectedPost.author.pubkey)",
            "mock:\(selectedPost.id)"
        ])
    }

    private func makePost(
        id: String,
        author: TimelineAuthor,
        body: String
    ) -> TimelinePost {
        TimelinePost(
            id: id,
            author: author,
            avatar: AvatarStyle(
                primary: .blue,
                secondary: .purple,
                symbolName: "person"
            ),
            body: body,
            createdAt: 1,
            replyCount: 0,
            boostCount: 0,
            favoriteCount: 0,
            isLocked: false,
            media: nil,
            context: nil
        )
    }

    private func makeProfileProjection(
        for post: TimelinePost
    ) -> HomeTimelineProfileProjection {
        let profile = MockTimelineData.profile(for: post)
        return HomeTimelineProfileProjection(
            profile: profile,
            posts: MockTimelineData.profilePosts(for: profile)
        )
    }
}
