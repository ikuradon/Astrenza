@MainActor
struct HomeTimelineNavigationProjectionResolver {
    private let post: (String) -> TimelinePost?
    private let replyAncestors: (TimelinePost) -> [TimelinePost]
    private let replies: (TimelinePost) -> [TimelinePost]
    private let profileProjection: (String) -> HomeTimelineProfileProjection
    private let mockProfileProjection:
        (TimelinePost) -> HomeTimelineProfileProjection

    init(timelineStore: NostrHomeTimelineStore) {
        self.init(
            post: { timelineStore.post(eventID: $0) },
            replyAncestors: { timelineStore.replyAncestors(for: $0) },
            replies: { timelineStore.replies(for: $0) },
            profileProjection: {
                timelineStore.profileProjection(pubkey: $0)
            },
            mockProfileProjection: { post in
                let profile = MockTimelineData.profile(for: post)
                return HomeTimelineProfileProjection(
                    profile: profile,
                    posts: MockTimelineData.profilePosts(for: profile)
                )
            }
        )
    }

    init(
        post: @escaping (String) -> TimelinePost?,
        replyAncestors: @escaping (TimelinePost) -> [TimelinePost],
        replies: @escaping (TimelinePost) -> [TimelinePost],
        profileProjection: @escaping (String) -> HomeTimelineProfileProjection,
        mockProfileProjection: @escaping (TimelinePost) -> HomeTimelineProfileProjection
    ) {
        self.post = post
        self.replyAncestors = replyAncestors
        self.replies = replies
        self.profileProjection = profileProjection
        self.mockProfileProjection = mockProfileProjection
    }

    func postDetail(
        fallbackPost: TimelinePost,
        hasLiveAccount: Bool
    ) -> HomeTimelinePostDetailProjection {
        guard hasLiveAccount else {
            return HomeTimelinePostDetailProjection(
                post: fallbackPost,
                replyAncestors: nil,
                replies: nil
            )
        }

        let resolvedPost = post(fallbackPost.id) ?? fallbackPost
        return HomeTimelinePostDetailProjection(
            post: resolvedPost,
            replyAncestors: replyAncestors(resolvedPost),
            replies: replies(resolvedPost)
        )
    }

    func profile(
        for post: TimelinePost,
        hasLiveAccount: Bool
    ) -> HomeTimelineProfileProjection {
        guard hasLiveAccount else {
            return mockProfileProjection(post)
        }
        return profileProjection(post.author.pubkey)
    }
}

struct HomeTimelinePostDetailProjection {
    let post: TimelinePost
    let replyAncestors: [TimelinePost]?
    let replies: [TimelinePost]?
}
