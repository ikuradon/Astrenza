import SwiftUI

struct HomeTimelineNavigationDestinationActions {
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReply: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
}

struct HomeTimelineNavigationDestinationView: View {
    let route: HomeTimelineNavigationRoute
    let hasLiveAccount: Bool
    let swipeSettings: TimelineSwipeSettings
    let actions: HomeTimelineNavigationDestinationActions
    private let timelineStore: NostrHomeTimelineStore
    private let resolver: HomeTimelineNavigationProjectionResolver

    init(
        route: HomeTimelineNavigationRoute,
        timelineStore: NostrHomeTimelineStore,
        hasLiveAccount: Bool,
        swipeSettings: TimelineSwipeSettings,
        actions: HomeTimelineNavigationDestinationActions
    ) {
        self.route = route
        self.hasLiveAccount = hasLiveAccount
        self.swipeSettings = swipeSettings
        self.actions = actions
        self.timelineStore = timelineStore
        resolver = HomeTimelineNavigationProjectionResolver(
            timelineStore: timelineStore
        )
    }

    @ViewBuilder
    var body: some View {
        switch route {
        case .post(let route):
            HomeTimelinePostDestinationView(
                fallbackPost: route.post,
                hasLiveAccount: hasLiveAccount,
                swipeSettings: swipeSettings,
                actions: actions,
                resolver: resolver
            )
        case .profile(let route):
            HomeTimelineProfileDestinationView(
                selectedPost: route.post,
                hasLiveAccount: hasLiveAccount,
                swipeSettings: swipeSettings,
                actions: actions,
                resolver: resolver
            )
        case .hashtag(let route):
            HashtagTimelineView(
                route: route,
                accountID: timelineStore.account?.pubkey ?? "mock-account",
                timelineStore: timelineStore,
                swipeSettings: swipeSettings,
                actions: actions
            )
        }
    }
}

private struct HomeTimelinePostDestinationView: View {
    let fallbackPost: TimelinePost
    let hasLiveAccount: Bool
    let swipeSettings: TimelineSwipeSettings
    let actions: HomeTimelineNavigationDestinationActions
    let resolver: HomeTimelineNavigationProjectionResolver

    var body: some View {
        let projection = resolver.postDetail(
            fallbackPost: fallbackPost,
            hasLiveAccount: hasLiveAccount
        )
        PostDetailView(
            post: projection.post,
            replyAncestors: projection.replyAncestors,
            replies: projection.replies,
            swipeSettings: swipeSettings,
            onOpenPost: actions.onOpenPost,
            onOpenProfile: actions.onOpenProfile,
            onReplyPost: actions.onReply,
            onOpenMedia: actions.onOpenMedia,
            onOpenURL: actions.onOpenURL
        )
    }
}

private struct HomeTimelineProfileDestinationView: View {
    let selectedPost: TimelinePost
    let hasLiveAccount: Bool
    let swipeSettings: TimelineSwipeSettings
    let actions: HomeTimelineNavigationDestinationActions
    let resolver: HomeTimelineNavigationProjectionResolver

    var body: some View {
        let projection = resolver.profile(
            for: selectedPost,
            hasLiveAccount: hasLiveAccount
        )
        UserDetailView(
            profile: projection.profile,
            posts: projection.posts,
            swipeSettings: swipeSettings,
            onOpenPost: actions.onOpenPost,
            onOpenProfile: actions.onOpenProfile,
            onReplyPost: actions.onReply,
            onOpenMedia: actions.onOpenMedia,
            onOpenURL: actions.onOpenURL
        )
        .task(id: selectedPost.author.pubkey) {
            await resolver.resolveProfilePage(for: selectedPost)
        }
    }
}
