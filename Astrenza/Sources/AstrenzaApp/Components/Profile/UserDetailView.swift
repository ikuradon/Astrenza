import SwiftUI

private struct ProfileNavigationChromeLayout {
    let height: CGFloat

    var backdropHeight: CGFloat {
        height
    }
}

private struct ProfileHeroBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct UserDetailView: View {
    let profile: UserProfile
    let posts: [TimelinePost]
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    @State private var selectedTab: UserProfileTimelineTab = .posts
    @State private var scrollOffset: CGFloat = 0
    @State private var initialScrollOffset: CGFloat?
    private let profileHeroHeight: CGFloat = 268
    private let expandedAvatarSize: CGFloat = 132
    private let compactAvatarSize: CGFloat = 42
    private let navigationChromeLayout = ProfileNavigationChromeLayout(height: 60)

    private var normalizedScrollOffset: CGFloat {
        scrollOffset - (initialScrollOffset ?? scrollOffset)
    }

    private var compactChromeProgress: CGFloat {
        min(max((normalizedScrollOffset - 118) / 96, 0), 1)
    }

    private var navigationBlurProgress: CGFloat {
        min(max((compactChromeProgress - 0.18) / 0.3, 0), 1)
    }

    private var toolbarAvatarProgress: CGFloat {
        min(max((compactChromeProgress - 0.72) / 0.2, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
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
                    .frame(width: proxy.size.width)
                    .clipped()
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, nextOffset in
                    if initialScrollOffset == nil {
                        initialScrollOffset = nextOffset
                    }
                    scrollOffset = nextOffset
                }
                .scrollIndicators(.visible)
                .ignoresSafeArea(edges: .top)
            }

            navigationBlurBackdrop(chromeLayout: navigationChromeLayout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

        }
        .overlayPreferenceValue(ProfileHeroBoundsPreferenceKey.self) { heroBounds in
            GeometryReader { proxy in
                let expandedCenterY = heroBounds.map { proxy[$0].maxY } ?? profileHeroHeight - normalizedScrollOffset

                shrinkingProfileAvatar(
                    chromeLayout: navigationChromeLayout,
                    containerWidth: proxy.size.width,
                    expandedCenterY: expandedCenterY
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color.astrenzaBackground)
        .accessibilityIdentifier("user.detail")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                compactProfileAvatarToolbarItem
            }

            ToolbarItem(placement: .topBarTrailing) {
                profileNavigationActionButton
            }
        }
    }

    private var profileHero: some View {
        ZStack(alignment: .bottom) {
            Button {
                onOpenMedia(profile.bannerMedia, 0)
            } label: {
                ProfileBannerView(style: profile.banner)
                    .frame(height: profileHeroHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .anchorPreference(key: ProfileHeroBoundsPreferenceKey.self, value: .bounds) { bounds in
                        bounds
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile hero image")
        }
        .padding(.bottom, 76)
    }

    private var profileNavigationActionButton: some View {
        Button {
        } label: {
            Image(systemName: profile.isCurrentUser ? "pencil" : "gearshape")
                .imageScale(.large)
        }
        .accessibilityLabel(profile.isCurrentUser ? "Edit profile" : "Profile options")
    }

    private var compactProfileAvatarToolbarItem: some View {
        ProfileAvatarMediaButton(
            profile: profile,
            size: compactAvatarSize,
            label: "Open compact profile avatar",
            onOpenMedia: onOpenMedia
        )
        .scaleEffect(0.92 + (0.08 * toolbarAvatarProgress))
        .opacity(toolbarAvatarProgress)
        .disabled(toolbarAvatarProgress < 0.85)
        .accessibilityHidden(toolbarAvatarProgress < 0.85)
        .animation(.spring(duration: 0.24, bounce: 0.12), value: toolbarAvatarProgress)
    }

    private func navigationBlurBackdrop(chromeLayout: ProfileNavigationChromeLayout) -> some View {
        let height = chromeLayout.backdropHeight

        return ProfileBannerView(style: profile.banner)
            .frame(height: profileHeroHeight)
            .offset(y: height - profileHeroHeight)
            .blur(radius: 14, opaque: true)
            .saturation(1.16)
            .overlay(Color.black.opacity(0.18))
            .frame(height: height, alignment: .top)
            .clipped()
            .opacity(navigationBlurProgress)
            .ignoresSafeArea(edges: .top)
            .animation(.easeOut(duration: 0.18), value: navigationBlurProgress)
    }

    private func shrinkingProfileAvatar(
        chromeLayout: ProfileNavigationChromeLayout,
        containerWidth: CGFloat,
        expandedCenterY: CGFloat
    ) -> some View {
        let progress = compactChromeProgress
        let avatarSize = expandedAvatarSize + (compactAvatarSize - expandedAvatarSize) * progress
        let compactCenterY = -chromeLayout.backdropHeight / 2
        let centerY = expandedCenterY + (compactCenterY - expandedCenterY) * progress
        let strokeWidth = 5 * (1 - progress)

        return ProfileAvatarMediaButton(
            profile: profile,
            size: avatarSize,
            label: "Open profile avatar",
            onOpenMedia: onOpenMedia
        ) {
            Circle()
                .stroke(Color.astrenzaBackground.opacity(1 - progress), lineWidth: strokeWidth)
        }
        .position(x: containerWidth / 2, y: centerY)
        .opacity(1 - toolbarAvatarProgress)
        .disabled(toolbarAvatarProgress > 0.85)
        .accessibilityHidden(toolbarAvatarProgress > 0.85)
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

#Preview {
    UserDetailView(
        profile: MockTimelineData.selfProfile,
        posts: MockTimelineData.selfProfilePosts,
        swipeSettings: TimelineSwipeSettings(),
        onOpenPost: { _ in },
        onOpenProfile: { _ in },
        onReplyPost: { _ in },
        onOpenMedia: { _, _ in },
        onOpenURL: { _ in }
    )
    .preferredColorScheme(.dark)
}
