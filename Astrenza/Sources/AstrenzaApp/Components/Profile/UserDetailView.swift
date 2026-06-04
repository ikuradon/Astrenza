import SwiftUI

struct UserDetailView: View {
    let profile: UserProfile
    let posts: [TimelinePost]
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
    let onOpenURL: (URL) -> Void
    @State private var selectedTab: UserProfileTimelineTab = .posts
    @State private var scrollOffset: CGFloat = 0

    private var compactChromeProgress: CGFloat {
        min(max((scrollOffset - 118) / 96, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    profileHero

                    VStack(spacing: 22) {
                        profileSummary
                        latestFollowers
                        statsCard
                        profileLinksCard
                        featuredHashtags
                        timelineTabs
                        timelineRows
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 132)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, nextOffset in
                scrollOffset = nextOffset
            }
            .scrollIndicators(.visible)

            compactProfileChrome
        }
        .background(Color.astrenzaBackground)
        .accessibilityIdentifier("user.detail")
        .preferredColorScheme(.dark)
    }

    private var profileHero: some View {
        ZStack(alignment: .bottom) {
            ProfileBannerView(style: profile.banner)
                .frame(height: 268)
                .overlay(alignment: .topLeading) {
                    AvatarView(style: profile.avatar, size: 42)
                        .padding(.leading, 18)
                        .padding(.top, 58)
                        .opacity(1 - compactChromeProgress)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                    } label: {
                        Image(systemName: profile.isCurrentUser ? "pencil" : "gearshape")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .astrenzaGlass(tint: Color.black.opacity(0.18), in: Circle())
                    .padding(.trailing, 18)
                    .padding(.top, 58)
                    .accessibilityLabel(profile.isCurrentUser ? "Edit profile" : "Profile options")
                }

            AvatarView(style: profile.avatar, size: 132)
                .overlay {
                    Circle()
                        .stroke(Color.astrenzaBackground, lineWidth: 5)
                }
                .offset(y: 66)
        }
        .padding(.bottom, 76)
    }

    private var compactProfileChrome: some View {
        HStack(spacing: 10) {
            AvatarView(style: profile.avatar, size: 38)
                .scaleEffect(0.86 + compactChromeProgress * 0.14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(profile.author.primaryText)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if profile.author.nip05Status == .valid {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color.green)
                    }
                }

                Text(profile.author.secondaryText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 190, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 50)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.82 * compactChromeProgress)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.astrenzaSeparator)
                .opacity(compactChromeProgress)
        }
        .opacity(compactChromeProgress)
        .offset(y: -18 + compactChromeProgress * 18)
        .allowsHitTesting(compactChromeProgress > 0.9)
        .animation(.spring(duration: 0.24, bounce: 0.12), value: compactChromeProgress)
    }

    private var profileSummary: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text(profile.author.primaryText)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if profile.author.nip05Status == .valid {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.green)
                        .accessibilityLabel("NIP-05 resolved")
                }
            }
            .frame(maxWidth: .infinity)

            Text(profile.author.secondaryText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(profile.bio)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(Color.astrenzaText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            HStack(spacing: 10) {
                relayPill
                followButton
            }
            .padding(.top, 10)
        }
    }

    private var relayPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text("\(profile.relayCount) relays")
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.astrenzaAccent)
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Color.astrenzaAccent.opacity(0.13), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.astrenzaAccent.opacity(0.2), lineWidth: 1)
        }
    }

    private var followButton: some View {
        Button {
        } label: {
            Text(profile.isCurrentUser ? "Edit Profile" : profile.isFollowed ? "Following" : "Follow")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .frame(height: 42)
                .background(Color.white.opacity(profile.isFollowed || profile.isCurrentUser ? 0.18 : 0.86), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.isCurrentUser ? "Edit profile" : profile.isFollowed ? "Following" : "Follow")
    }

    @ViewBuilder
    private var latestFollowers: some View {
        if !profile.latestFollowers.isEmpty {
            VStack(spacing: 10) {
                Text("LATEST FOLLOWERS")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: -8) {
                    ForEach(Array(profile.latestFollowers.prefix(9).enumerated()), id: \.offset) { _, avatar in
                        AvatarView(style: avatar, size: 44)
                            .overlay {
                                Circle()
                                    .stroke(Color.astrenzaBackground, lineWidth: 2)
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            UserProfileMetricCell(title: "FOLLOWERS", value: profile.followerCount.formatted())
            Divider().overlay(Color.astrenzaSeparator)
            UserProfileMetricCell(title: "FOLLOWING", value: profile.followingCount.formatted())
        }
        .frame(height: 94)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    private var profileLinksCard: some View {
        VStack(spacing: 0) {
            UserProfileLinkRow(systemName: "bubble.left", title: "Posts", value: profile.postCount.formatted())

            if profile.isCurrentUser {
                Divider().overlay(Color.astrenzaSeparator).padding(.leading, 58)
                UserProfileLinkRow(systemName: "star", title: "Favorites", value: nil)
                Divider().overlay(Color.astrenzaSeparator).padding(.leading, 58)
                UserProfileLinkRow(systemName: "bookmark", title: "Bookmarks", value: nil)
            }
        }
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var featuredHashtags: some View {
        if !profile.featuredHashtags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED HASHTAGS")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                VStack(spacing: 0) {
                    ForEach(Array(profile.featuredHashtags.enumerated()), id: \.element.id) { index, hashtag in
                        if index > 0 {
                            Divider().overlay(Color.astrenzaSeparator).padding(.leading, 16)
                        }
                        UserFeaturedHashtagRow(hashtag: hashtag)
                    }
                }
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
            }
        }
    }

    private var timelineTabs: some View {
        Picker("Profile timeline", selection: $selectedTab) {
            ForEach(UserProfileTimelineTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.astrenzaAccent)
    }

    private var timelineRows: some View {
        VStack(spacing: 0) {
            ForEach(filteredPosts) { post in
                TimelinePostRow(
                    post: post,
                    isActionMenuPresented: false,
                    swipeSettings: swipeSettings,
                    onActionEvent: { _ in },
                    onOpenPost: onOpenPost,
                    onOpenProfile: onOpenProfile,
                    onReplyPost: onReplyPost,
                    onOpenMedia: onOpenMedia,
                    onOpenURL: onOpenURL,
                    onDismissActionMenu: {}
                )
            }
        }
        .background(Color.astrenzaBackground)
    }

    private var filteredPosts: [TimelinePost] {
        let selectedPosts: [TimelinePost]
        switch selectedTab {
        case .posts:
            selectedPosts = posts.filter { $0.replyContext == nil && $0.repostedBy == nil }
        case .postsAndReplies:
            selectedPosts = posts.filter { $0.repostedBy == nil }
        case .boosts:
            selectedPosts = posts.filter { $0.repostedBy != nil }
        }

        return selectedPosts.isEmpty ? posts : selectedPosts
    }
}

private struct ProfileBannerView: View {
    let style: ProfileBannerStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: style.symbolName)
                .font(.system(size: 118, weight: .black))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 96, y: 34)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.18)

            LinearGradient(
                colors: [.clear, Color.astrenzaBackground.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

private struct UserProfileMetricCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UserProfileLinkRow: View {
    let systemName: String
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: systemName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34)

            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}

private struct UserFeaturedHashtagRow: View {
    let hashtag: UserFeaturedHashtag

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hashtag.tag)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(hashtag.lastUsed)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(hashtag.count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .contentShape(Rectangle())
    }
}

#Preview {
    UserDetailView(
        profile: MockTimelineData.selfProfile,
        posts: MockTimelineData.selfProfilePosts,
        swipeSettings: TimelineSwipeSettings(),
        onOpenPost: { _ in },
        onOpenProfile: { _ in },
        onReplyPost: { _ in },
        onOpenMedia: { _ in },
        onOpenURL: { _ in }
    )
    .preferredColorScheme(.dark)
}
