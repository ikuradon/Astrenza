@MainActor
struct HomeTimelineNavigationProjectionResolver {
    private let post: (String) -> TimelinePost?
    private let replyAncestors: (TimelinePost) -> [TimelinePost]
    private let replies: (TimelinePost) -> [TimelinePost]
    private let profileProjection: (String) -> HomeTimelineProfileProjection
    private let resolveProfilePage: (String) async -> Void
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
            resolveProfilePage: {
                await timelineStore.resolveProfilePage(pubkey: $0)
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
        resolveProfilePage: @escaping (String) async -> Void = { _ in },
        mockProfileProjection: @escaping (TimelinePost) -> HomeTimelineProfileProjection
    ) {
        self.post = post
        self.replyAncestors = replyAncestors
        self.replies = replies
        self.profileProjection = profileProjection
        self.resolveProfilePage = resolveProfilePage
        self.mockProfileProjection = mockProfileProjection
    }

    func postDetail(
        fallbackPost: TimelinePost,
        hasLiveAccount: Bool
    ) -> HomeTimelinePostDetailProjection {
        guard hasLiveAccount else {
            return HomeTimelinePostDetailProjection(
                post: fallbackPost,
                replyAncestors: MockTimelineData.replyAncestors(
                    for: fallbackPost
                ),
                replies: MockTimelineData.detailReplies(for: fallbackPost)
            )
        }

        let resolvedPost = (post(fallbackPost.id) ?? fallbackPost)
            .preservingAvailableQuotedPost(from: fallbackPost)
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

    func resolveProfilePage(for post: TimelinePost) async {
        await resolveProfilePage(post.author.pubkey)
    }
}

struct HomeTimelinePostDetailProjection {
    let post: TimelinePost
    let replyAncestors: [TimelinePost]
    let replies: [TimelinePost]
}

private extension TimelinePost {
    func preservingAvailableQuotedPost(
        from fallbackPost: TimelinePost
    ) -> TimelinePost {
        guard let fallbackQuotedPost = fallbackPost.quotedPost,
              fallbackQuotedPost.isAvailable,
              quotedPost?.isAvailable != true
        else {
            return self
        }

        return TimelinePost(
            id: id,
            author: author,
            avatar: avatar,
            body: body,
            richBody: richBody,
            createdAt: createdAt,
            replyCount: replyCount,
            boostCount: boostCount,
            favoriteCount: favoriteCount,
            isLocked: isLocked,
            media: media,
            context: context,
            repostedBy: repostedBy,
            quotedPost: fallbackQuotedPost,
            replyContext: replyContext,
            replyMention: replyMention,
            contentWarning: contentWarning,
            bodyPresentation: bodyPresentation,
            linkSummary: linkSummary,
            actionState: actionState
        )
    }
}
