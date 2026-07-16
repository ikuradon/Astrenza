import AstrenzaCore
import SwiftUI

struct HomeTimelineProfileContentView: View {
    let timelineStore: NostrHomeTimelineStore
    let account: NostrAccount?
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void

    private var projection: HomeTimelineProfileProjection {
        guard let account else {
            return HomeTimelineProfileProjection(
                profile: MockTimelineData.selfProfile,
                posts: MockTimelineData.selfProfilePosts
            )
        }
        return timelineStore.profileProjection(
            pubkey: account.pubkey,
            isCurrentUser: true
        )
    }

    var body: some View {
        UserDetailView(
            profile: projection.profile,
            posts: projection.posts,
            swipeSettings: swipeSettings,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL
        )
    }
}
