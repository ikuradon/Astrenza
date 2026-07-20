import SwiftUI

struct UserProfile: Identifiable {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let banner: ProfileBannerStyle
    let bio: String
    let isCurrentUser: Bool
    let isFollowed: Bool
    let followerCount: Int
    let followingCount: Int
    let postCount: Int
    let relayCount: Int
    let latestFollowers: [AvatarStyle]
    let featuredHashtags: [UserFeaturedHashtag]
}

struct ProfileBannerStyle {
    let colors: [Color]
    let symbolName: String
    let imageURL: URL?

    init(
        colors: [Color],
        symbolName: String,
        imageURL: URL? = nil
    ) {
        self.colors = colors
        self.symbolName = symbolName
        self.imageURL = imageURL
    }
}

struct UserFeaturedHashtag: Identifiable {
    let id = UUID()
    let tag: String
    let lastUsed: String
    let count: Int
}

enum UserProfileTimelineTab: String, CaseIterable, Identifiable {
    case posts = "Posts"
    case postsAndReplies = "Posts & Replies"
    case boosts = "Boosts"

    var id: String { rawValue }
}
