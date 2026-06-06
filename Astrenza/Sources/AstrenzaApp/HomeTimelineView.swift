import SwiftUI

struct HomeTimelineView: View {
    @ObservedObject var sessionStore: NostrSessionStore
    @ObservedObject var liveTimelineStore: NostrHomeTimelineStore
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var isComposerPresented = false
    @State private var isSettingsPresented = false
    @State private var isRelayStatusPresented = false
    @State private var composeSheetMode: ComposeSheetMode = .post
    @State private var didCompleteInitialAppearance = false
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var postNavigationPath: [TimelineNavigationRoute] = []
    @State private var profileNavigationPath: [TimelineNavigationRoute] = []
    @State private var unreadBadgeFrame: CGRect = .zero
    @State private var fullscreenMedia: TimelineMedia?
    @State private var browserDestination: TimelineBrowserDestination?
    @State private var swipeSettings = TimelineSwipeSettings()
    @State private var timelineRestoreStore = TimelineRestoreStore()
    @State private var homeViewportState = TimelineRestoreStore().viewportState(
        accountID: "mock-account",
        timelineKey: "home"
    )
    @State private var homeLayoutCache = TimelineRestoreStore().layoutCache(
        accountID: "mock-account",
        timelineKey: "home"
    )

    private var accountID: String {
        sessionStore.account?.pubkey ?? "mock-account"
    }

    init(
        sessionStore: NostrSessionStore = NostrSessionStore(restoreAccount: false),
        liveTimelineStore: NostrHomeTimelineStore = NostrHomeTimelineStore()
    ) {
        self.sessionStore = sessionStore
        self.liveTimelineStore = liveTimelineStore
    }

    private var actionMenuTopClearance: CGFloat {
        max(unreadBadgeFrame.maxY + 10, 96)
    }

    private var visibleTab: TimelineTab {
        selectedTab == .compose ? previousTab : selectedTab
    }

    private var topChromeCollapseProgress: CGFloat {
        min(max(timelineScrollOffset / 72, 0), 1)
    }

    private var isPostDetailPresented: Bool {
        !postNavigationPath.isEmpty || !profileNavigationPath.isEmpty
    }

    private var timelineEntries: [TimelineFeedEntry] {
        guard sessionStore.account != nil else {
            return MockTimelineData.entries(for: selectedTimeline)
        }

        switch selectedTimeline {
        case .home:
            return liveTimelineStore.entries
        case .relays, .lists:
            return MockTimelineData.entries(for: selectedTimeline)
        }
    }

    private var timelineEmptyState: TimelineEmptyState {
        guard sessionStore.account != nil, selectedTimeline == .home else {
            return selectedTimeline.emptyState
        }

        switch liveTimelineStore.phase {
        case .resolvingRelays, .resolvingContacts, .loadingHome:
            return .loadingHome(message: liveTimelineStore.phase.copy)
        case .failed(let message):
            return .liveError(message: message)
        case .idle, .loaded:
            if liveTimelineStore.followedPubkeys.isEmpty {
                return .noContacts
            }
            return .home
        }
    }

    private var relayConnectedCount: Int {
        guard sessionStore.account != nil else {
            return RelayMockStore.connectedCount
        }
        return liveTimelineStore.resolvedRelays.count
    }

    private var relayPlannedCount: Int {
        guard sessionStore.account != nil else {
            return RelayMockStore.plannedCount
        }
        return max(liveTimelineStore.resolvedRelays.count, 1)
    }

    var body: some View {
        ZStack {
            Color.astrenzaBackground.ignoresSafeArea()

            nativeTabs
                .simultaneousGesture(
                    TapGesture().onEnded(dismissFloatingMenus)
                )

            if visibleTab == .home && !isPostDetailPresented {
                VStack {
                    HomeTimelineTopBar(
                        visibleTab: visibleTab,
                        selectedTimeline: $selectedTimeline,
                        isTimelineMenuPresented: $isTimelineMenuPresented,
                        isUserSwitcherPresented: $isUserSwitcherPresented,
                        collapseProgress: topChromeCollapseProgress,
                        onDismissFloatingMenus: dismissFloatingMenus,
                        onRelayStatusTap: presentRelayStatus,
                        onSettingsTap: presentSettings,
                        relayConnectedCount: relayConnectedCount,
                        relayPlannedCount: relayPlannedCount,
                        isRelayProcessing: liveTimelineStore.phase.isProcessing
                    )
                    .zIndex(30)

                    Spacer(minLength: 0)
                }
            }

            if visibleTab == .home && !isPostDetailPresented {
                HomeUnreadBadge(onTap: dismissFloatingMenus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 70)
                    .padding(.trailing, 16)
            }

            if isPostDetailPresented {
                ReplyFloatingButton(action: presentReplyComposer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 18)
                    .padding(.bottom, 24)
                    .transition(.scale(scale: 0.78, anchor: .bottomTrailing).combined(with: .opacity))
                    .zIndex(40)
            }
        }
        .coordinateSpace(name: "homeTimelineChrome")
        .preferredColorScheme(.dark)
        .onPreferenceChange(UnreadBadgeFramePreferenceKey.self) { frame in
            unreadBadgeFrame = frame
        }
        .onAppear(perform: completeInitialAppearanceIfNeeded)
        .onChange(of: selectedTab) { _, newValue in
            handleTabSelection(newValue)
        }
        .onChange(of: selectedTimeline) { _, _ in
            loadTimelineRestoreState()
        }
        .onChange(of: sessionStore.account?.pubkey) { _, _ in
            loadTimelineRestoreState()
        }
        .homeTimelinePresentations(
            isComposerPresented: $isComposerPresented,
            isSettingsPresented: $isSettingsPresented,
            isRelayStatusPresented: $isRelayStatusPresented,
            composeSheetMode: $composeSheetMode,
            fullscreenMedia: $fullscreenMedia,
            browserDestination: $browserDestination,
            swipeSettings: $swipeSettings,
            relayURLs: sessionStore.account == nil ? [] : liveTimelineStore.resolvedRelays
        )
    }
}

private extension HomeTimelineView {
    var nativeTabs: some View {
        UIKitTimelineTabView(
            selectedTab: $selectedTab,
            previousTab: $previousTab,
            minimizeDirection: tabBarMinimizeDirection,
            isTabBarHidden: isPostDetailPresented,
            timelineList: timelineList,
            profileView: profileView,
            onMinimizeDirectionChanged: updateTabBarMinimizeDirection,
            onComposeTap: presentComposer
        )
    }

    var timelineList: some View {
        NavigationStack(path: $postNavigationPath) {
            TimelineFeedView(
                entries: timelineEntries,
                actionMenuTopClearance: actionMenuTopClearance,
                swipeSettings: swipeSettings,
                viewportState: homeViewportState,
                layoutCache: homeLayoutCache,
                emptyState: timelineEmptyState,
                onEmptyStatePrimaryAction: handleTimelineEmptyStatePrimaryAction,
                onEmptyStateSecondaryAction: handleTimelineEmptyStateSecondaryAction,
                onOpenPost: openPost,
                onOpenProfile: openProfile,
                onReplyPost: { _ in
                    presentReplyComposer()
                },
                onOpenMedia: openMedia,
                onOpenURL: openURL,
                onRefresh: refreshVisibleTimeline,
                onLoadOlderPost: loadOlderVisibleTimeline
            ) { offset in
                handleTimelineScrollOffset(offset)
            } onViewportStateChanged: { state in
                saveTimelineViewportState(state)
            } onLayoutCacheChanged: { cache in
                saveTimelineLayoutCache(cache)
            }
            .id(selectedTimeline.id)
            .navigationDestination(for: TimelineNavigationRoute.self) { route in
                timelineDestination(for: route)
            }
        }
    }

    var profileView: some View {
        NavigationStack(path: $profileNavigationPath) {
            UserDetailView(
                profile: MockTimelineData.selfProfile,
                posts: MockTimelineData.selfProfilePosts,
                swipeSettings: swipeSettings,
                onOpenPost: openProfilePost,
                onOpenProfile: openProfileFromProfile,
                onReplyPost: { _ in
                    presentReplyComposer()
                },
                onOpenMedia: openMedia,
                onOpenURL: openURL
            )
            .navigationDestination(for: TimelineNavigationRoute.self) { route in
                profileDestination(for: route)
            }
        }
    }

    @ViewBuilder
    func timelineDestination(for route: TimelineNavigationRoute) -> some View {
        switch route {
        case .post(let selectedPost):
            PostDetailView(
                post: selectedPost.post,
                swipeSettings: swipeSettings,
                onOpenPost: openPost,
                onReplyPost: { _ in
                    presentReplyComposer()
                },
                onOpenMedia: openMedia,
                onOpenURL: openURL
            )
        case .profile(let selectedProfile):
            userDetailView(
                for: selectedProfile.post,
                onOpenPost: openPost,
                onOpenProfile: openProfile
            )
        }
    }

    @ViewBuilder
    func profileDestination(for route: TimelineNavigationRoute) -> some View {
        switch route {
        case .post(let selectedPost):
            PostDetailView(
                post: selectedPost.post,
                swipeSettings: swipeSettings,
                onOpenPost: openProfilePost,
                onReplyPost: { _ in
                    presentReplyComposer()
                },
                onOpenMedia: openMedia,
                onOpenURL: openURL
            )
        case .profile(let selectedProfile):
            userDetailView(
                for: selectedProfile.post,
                onOpenPost: openProfilePost,
                onOpenProfile: openProfileFromProfile
            )
        }
    }

    func userDetailView(
        for post: TimelinePost,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void
    ) -> some View {
        let profile = MockTimelineData.profile(for: post)

        return UserDetailView(
            profile: profile,
            posts: MockTimelineData.profilePosts(for: profile),
            swipeSettings: swipeSettings,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: { _ in
                presentReplyComposer()
            },
            onOpenMedia: openMedia,
            onOpenURL: openURL
        )
    }

    func completeInitialAppearanceIfNeeded() {
        guard !didCompleteInitialAppearance else { return }
        loadTimelineRestoreState()
        if selectedTab == .compose {
            selectedTab = previousTab
        }
        DispatchQueue.main.async {
            didCompleteInitialAppearance = true
        }
    }

    func handleTimelineScrollOffset(_ offset: CGFloat) {
        if isUserSwitcherPresented || isTimelineMenuPresented {
            let didScroll = abs(offset - timelineScrollOffset) > 1
            if didScroll {
                dismissFloatingMenus()
            }
        }
        timelineScrollOffset = offset
    }

    func openPost(_ post: TimelinePost) {
        dismissFloatingMenus()
        postNavigationPath.append(.post(SelectedPostRoute(post: post)))
    }

    func openProfile(_ post: TimelinePost) {
        dismissFloatingMenus()
        postNavigationPath.append(.profile(SelectedProfileRoute(post: post)))
    }

    func openProfilePost(_ post: TimelinePost) {
        dismissFloatingMenus()
        profileNavigationPath.append(.post(SelectedPostRoute(post: post)))
    }

    func openProfileFromProfile(_ post: TimelinePost) {
        dismissFloatingMenus()
        profileNavigationPath.append(.profile(SelectedProfileRoute(post: post)))
    }

    func openMedia(_ media: TimelineMedia) {
        dismissFloatingMenus()
        fullscreenMedia = media
    }

    func openURL(_ url: URL) {
        dismissFloatingMenus()
        browserDestination = TimelineBrowserDestination(url: url)
    }

    func dismissFloatingMenus() {
        guard isUserSwitcherPresented || isTimelineMenuPresented else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0.14)) {
            isUserSwitcherPresented = false
            isTimelineMenuPresented = false
        }
    }

    func handleTabSelection(_ newValue: TimelineTab) {
        if newValue == .compose {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = previousTab
            }
            presentComposer()
        } else {
            previousTab = newValue
        }
    }

    func presentComposer() {
        presentComposer(mode: .post)
    }

    func presentReplyComposer() {
        presentComposer(mode: .reply)
    }

    func presentSettings() {
        dismissFloatingMenus()
        guard !isComposerPresented && !isRelayStatusPresented && browserDestination == nil && fullscreenMedia == nil else { return }
        isSettingsPresented = true
    }

    func presentRelayStatus() {
        dismissFloatingMenus()
        guard !isComposerPresented && !isSettingsPresented && browserDestination == nil && fullscreenMedia == nil else { return }
        isRelayStatusPresented = true
    }

    func handleTimelineEmptyStatePrimaryAction() {
        if sessionStore.account != nil, selectedTimeline == .home {
            switch liveTimelineStore.phase {
            case .failed:
                liveTimelineStore.refresh()
            case .loaded where liveTimelineStore.followedPubkeys.isEmpty:
                liveTimelineStore.refresh()
            case .resolvingRelays, .resolvingContacts, .loadingHome, .idle, .loaded:
                presentRelayStatus()
            }
            return
        }

        switch selectedTimeline {
        case .home, .relays:
            presentRelayStatus()
        case .lists:
            presentSettings()
        }
    }

    func handleTimelineEmptyStateSecondaryAction() {
        guard selectedTimeline == .home else { return }
        selectedTab = .explore
    }

    func refreshVisibleTimeline() async {
        guard sessionStore.account != nil, selectedTimeline == .home else { return }
        await liveTimelineStore.refreshLatest()
    }

    func loadOlderVisibleTimeline(_ postID: TimelinePost.ID) {
        guard sessionStore.account != nil, selectedTimeline == .home else { return }
        liveTimelineStore.loadOlder()
    }

    func presentComposer(mode: ComposeSheetMode) {
        dismissFloatingMenus()
        guard didCompleteInitialAppearance, !isComposerPresented, !isSettingsPresented else { return }
        composeSheetMode = mode
        DispatchQueue.main.async {
            isComposerPresented = true
        }
    }

    func updateTabBarMinimizeDirection(_ nextDirection: TabBarMinimizeDirection) {
        guard tabBarMinimizeDirection != nextDirection else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tabBarMinimizeDirection = nextDirection
        }
    }

    func loadTimelineRestoreState() {
        homeViewportState = timelineRestoreStore.viewportState(accountID: accountID, timelineKey: selectedTimeline.id)
        homeLayoutCache = timelineRestoreStore.layoutCache(accountID: accountID, timelineKey: selectedTimeline.id)
    }

    func saveTimelineViewportState(_ state: TimelineViewportState) {
        let nextState = TimelineViewportState(
            accountID: accountID,
            timelineKey: selectedTimeline.id,
            anchorPostID: state.anchorPostID,
            anchorOffset: state.anchorOffset,
            contentOffset: state.contentOffset,
            updatedAt: state.updatedAt
        )

        if let homeViewportState,
           homeViewportState.anchorPostID == nextState.anchorPostID,
           abs(homeViewportState.anchorOffset - nextState.anchorOffset) < 0.5,
           abs(homeViewportState.contentOffset - nextState.contentOffset) < 0.5 {
            return
        }

        homeViewportState = nextState
        timelineRestoreStore.saveViewportState(nextState)
    }

    func saveTimelineLayoutCache(_ cache: TimelineLayoutCache) {
        guard homeLayoutCache != cache else { return }
        homeLayoutCache = cache
        timelineRestoreStore.saveLayoutCache(cache, accountID: accountID, timelineKey: selectedTimeline.id)
    }
}

private enum TimelineNavigationRoute: Hashable {
    case post(SelectedPostRoute)
    case profile(SelectedProfileRoute)
}

private struct SelectedPostRoute: Identifiable, Hashable {
    let post: TimelinePost

    var id: TimelinePost.ID {
        post.id
    }

    static func == (lhs: SelectedPostRoute, rhs: SelectedPostRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct SelectedProfileRoute: Identifiable, Hashable {
    let post: TimelinePost

    var id: String {
        post.author.pubkey
    }

    static func == (lhs: SelectedProfileRoute, rhs: SelectedProfileRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    HomeTimelineView()
        .preferredColorScheme(.dark)
}

private struct ReplyFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .astrenzaGlass(tint: Color.white.opacity(0.08), in: Circle())
        .shadow(color: Color.black.opacity(0.26), radius: 18, y: 10)
        .accessibilityLabel("Reply")
    }
}
