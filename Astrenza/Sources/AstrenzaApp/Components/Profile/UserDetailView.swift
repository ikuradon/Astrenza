import SwiftUI

private struct ProfileNavigationChromeLayout {
    let height: CGFloat

    var backdropHeight: CGFloat {
        height
    }
}

struct ProfileAvatarTransitionMetrics: Equatable {
    let renderSize: CGFloat
    let displaySize: CGFloat
    let scale: CGFloat

    init(
        progress: CGFloat,
        expandedSize: CGFloat,
        compactSize: CGFloat
    ) {
        let clampedProgress = min(max(progress, 0), 1)
        let stableRenderSize = max(expandedSize, 1)
        let resolvedDisplaySize = stableRenderSize
            + (compactSize - stableRenderSize) * clampedProgress

        renderSize = stableRenderSize
        displaySize = resolvedDisplaySize
        scale = resolvedDisplaySize / stableRenderSize
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
    private let profileHeroHeight: CGFloat = 268
    private let expandedAvatarSize: CGFloat = 132
    private let compactAvatarSize: CGFloat = 42
    private let navigationChromeLayout = ProfileNavigationChromeLayout(height: 60)

    private var normalizedScrollOffset: CGFloat {
        max(0, scrollOffset)
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
        TimelineFeedCollectionView(
            configuration: timelineConfiguration
        )
        .overlay(alignment: .top) {
            navigationBlurBackdrop(chromeLayout: navigationChromeLayout)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
        }
        .overlay {
            GeometryReader { proxy in
                shrinkingProfileAvatar(
                    chromeLayout: navigationChromeLayout,
                    containerWidth: proxy.size.width,
                    expandedCenterY:
                        profileHeroHeight - normalizedScrollOffset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile hero image")
            .accessibilityIdentifier("profile.hero")
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
    }

    private func shrinkingProfileAvatar(
        chromeLayout: ProfileNavigationChromeLayout,
        containerWidth: CGFloat,
        expandedCenterY: CGFloat
    ) -> some View {
        let progress = compactChromeProgress
        let transition = ProfileAvatarTransitionMetrics(
            progress: progress,
            expandedSize: expandedAvatarSize,
            compactSize: compactAvatarSize
        )
        let compactCenterY = -chromeLayout.backdropHeight / 2
        let centerY = expandedCenterY + (compactCenterY - expandedCenterY) * progress
        let strokeWidth = 5 * (1 - progress)

        return ProfileAvatarMediaButton(
            profile: profile,
            size: transition.renderSize,
            label: "Open profile avatar",
            onOpenMedia: onOpenMedia
        )
        .scaleEffect(transition.scale)
        .frame(width: transition.displaySize, height: transition.displaySize)
        .overlay {
            Circle()
                .stroke(Color.astrenzaBackground.opacity(1 - progress), lineWidth: strokeWidth)
                .allowsHitTesting(false)
        }
        .position(x: containerWidth / 2, y: centerY)
        .opacity(1 - toolbarAvatarProgress)
        .disabled(toolbarAvatarProgress > 0.85)
        .accessibilityHidden(toolbarAvatarProgress > 0.85)
    }

    private var profileSummary: some View {
        VStack(spacing: AstrenzaSpacing.point9) {
            Text(profile.author.primaryText)
                .font(.astrenza(.point31, weight: .black, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)

            TimelineAuthorSecondaryIdentity(
                author: profile.author,
                iconFont: .astrenza(.point16, weight: .bold),
                textFont: .astrenza(.point22, weight: .semibold, design: .rounded),
                iconWidth: 20,
                minimumScaleFactor: 1
            )

            ProfileAboutText(text: profile.bio)
                .padding(.top, AstrenzaSpacing.point4)

            HStack(spacing: AstrenzaSpacing.point10) {
                relayPill
                followButton
            }
            .padding(.top, AstrenzaSpacing.point10)
        }
    }

    private var relayPill: some View {
        HStack(spacing: AstrenzaSpacing.point6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text("\(profile.relayCount) relays")
        }
        .font(.astrenza(.point13, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.astrenzaAccent)
        .padding(.horizontal, AstrenzaSpacing.point11)
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
                .font(.astrenza(.point16, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, AstrenzaSpacing.point24)
                .frame(height: 42)
                .background(Color.white.opacity(profile.isFollowed || profile.isCurrentUser ? 0.18 : 0.86), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.isCurrentUser ? "Edit profile" : profile.isFollowed ? "Following" : "Follow")
    }

    @ViewBuilder
    private var latestFollowers: some View {
        if !profile.latestFollowers.isEmpty {
            VStack(spacing: AstrenzaSpacing.point10) {
                Text("LATEST FOLLOWERS")
                    .font(.astrenza(.point15, weight: .heavy, design: .rounded))
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
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous)
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
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var featuredHashtags: some View {
        if !profile.featuredHashtags.isEmpty {
            VStack(alignment: .leading, spacing: AstrenzaSpacing.point10) {
                Text("FEATURED HASHTAGS")
                    .font(.astrenza(.point15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, AstrenzaSpacing.point2)

                VStack(spacing: 0) {
                    ForEach(Array(profile.featuredHashtags.enumerated()), id: \.element.id) { index, hashtag in
                        if index > 0 {
                            Divider().overlay(Color.astrenzaSeparator).padding(.leading, AstrenzaSpacing.point16)
                        }
                        UserFeaturedHashtagRow(hashtag: hashtag)
                    }
                }
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous)
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

    private var profileTimelineHeader: some View {
        VStack(spacing: 0) {
            profileHero

            VStack(spacing: AstrenzaSpacing.point22) {
                profileSummary
                latestFollowers
                statsCard
                profileLinksCard
                featuredHashtags
                timelineTabs
            }
            .padding(.horizontal, AstrenzaSpacing.point18)
            .padding(.bottom, AstrenzaSpacing.point22)
        }
        .background(Color.astrenzaBackground)
    }

    private var timelineConfiguration:
        TimelineFeedCollectionConfiguration {
        let entries = filteredPosts.map(TimelineFeedEntry.post)
        return TimelineFeedCollectionConfiguration(
            entries: entries,
            leadingContent: TimelineFeedLeadingContent(
                renderRevision: profileHeaderRenderRevision,
                geometryRevision: profileHeaderGeometryRevision,
                rootView: AnyView(
                    profileTimelineHeader
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .topLeading
                        )
                )
            ),
            metrics: .profile,
            sourceIdentity: "profile-\(profile.id)",
            sourceRevision: timelineRevision(for: entries),
            viewportIdentity: TimelineFeedViewportIdentity(
                accountID: profile.id,
                timelineKey: "profile"
            ),
            swipeSettings: swipeSettings,
            viewportState: nil,
            scrollCommand: nil,
            viewportRestoreProtectionActive: false,
            followsRealtimeEntries: false,
            layoutCache: TimelineLayoutCache(),
            unreadCountAnchorPostID: nil,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onPostActionChoice: { _, _ in },
            onRefresh: nil,
            onLoadOlderPost: nil,
            onBackfillGap: nil,
            onScrollOffsetChanged: { scrollOffset = $0 },
            onScrollActivityChanged: { _ in },
            onInitialViewportReady: {},
            onViewportRestoreCompleted: { _ in },
            onViewportStateChanged: { _ in },
            onPostsCrossedReadLineTowardNewer: { _ in },
            onUnreadPillPlacementChanged: { _ in },
            onLayoutCacheChanged: { _ in },
            onPullRefreshPresentationChanged: { _ in }
        )
    }

    private var profileHeaderRenderRevision: Int {
        var hasher = Hasher()
        hasher.combine(selectedTab.id)
        combineProfileHeaderGeometry(into: &hasher)
        hasher.combine(profile.author.nip05)
        hasher.combine(String(describing: profile.author.nip05Status))
        hasher.combine(profile.author.profileResolutionState)
        hasher.combine(profile.avatar.symbolName)
        hasher.combine(profile.avatar.primary)
        hasher.combine(profile.avatar.secondary)
        hasher.combine(String(describing: profile.avatar.pictureState))
        hasher.combine(profile.avatar.imageURL?.absoluteString)
        hasher.combine(profile.banner.symbolName)
        for color in profile.banner.colors {
            hasher.combine(color)
        }
        hasher.combine(profile.banner.imageURL?.absoluteString)
        for avatar in profile.latestFollowers {
            hasher.combine(avatar.symbolName)
            hasher.combine(avatar.primary)
            hasher.combine(avatar.secondary)
            hasher.combine(String(describing: avatar.pictureState))
            hasher.combine(avatar.imageURL?.absoluteString)
        }
        return hasher.finalize()
    }

    private var profileHeaderGeometryRevision: Int {
        var hasher = Hasher()
        combineProfileHeaderGeometry(into: &hasher)
        return hasher.finalize()
    }

    private func combineProfileHeaderGeometry(into hasher: inout Hasher) {
        hasher.combine(profile.id)
        hasher.combine(profile.author.displayName)
        hasher.combine(profile.author.primaryText)
        hasher.combine(profile.author.secondaryText)
        hasher.combine(profile.bio)
        hasher.combine(profile.isCurrentUser)
        hasher.combine(profile.isFollowed)
        hasher.combine(profile.followerCount)
        hasher.combine(profile.followingCount)
        hasher.combine(profile.postCount)
        hasher.combine(profile.relayCount)
        hasher.combine(profile.latestFollowers.count)
        for hashtag in profile.featuredHashtags {
            hasher.combine(hashtag.tag)
            hasher.combine(hashtag.lastUsed)
            hasher.combine(hashtag.count)
        }
    }

    private func timelineRevision(
        for entries: [TimelineFeedEntry]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(selectedTab.id)
        for entry in entries {
            hasher.combine(TimelineRenderFingerprint.entry(entry))
        }
        return hasher.finalize()
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

struct ProfileAboutText: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.astrenza(.point18, weight: .medium))
            .lineSpacing(3)
            .foregroundStyle(Color.astrenzaText)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("profile.about")
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
