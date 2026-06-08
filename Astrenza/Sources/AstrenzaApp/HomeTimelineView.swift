import AstrenzaCore
import SwiftUI

struct HomeTimelineView: View {
    @ObservedObject var sessionStore: NostrSessionStore
    @ObservedObject var liveTimelineStore: NostrHomeTimelineStore
    let onInitialPresentationReady: () -> Void
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var isComposerPresented = false
    @State private var isSettingsPresented = false
    @State private var isFiltersSettingsPresented = false
    @State private var isRelayStatusPresented = false
    @State private var composeSheetMode: ComposeSheetMode = .post
    @State private var didCompleteInitialAppearance = false
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var isTimelineAtNewestWindow = true
    @State private var homeReturnAnchor: TimelineViewportState?
    @State private var homeScrollCommand: TimelineScrollCommand?
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var postNavigationPath: [TimelineNavigationRoute] = []
    @State private var profileNavigationPath: [TimelineNavigationRoute] = []
    @State private var unreadBadgeFrame: CGRect = .zero
    @State private var fullscreenMedia: TimelineFullscreenMediaRequest?
    @State private var browserDestination: TimelineBrowserDestination?
    @State private var swipeSettings = TimelineSwipeSettings()
    @State private var timelineRestoreStore = TimelineRestoreStore()
    @State private var homeViewportState: TimelineViewportState?
    @State private var homeLayoutCache: TimelineLayoutCache

    private var accountID: String {
        sessionStore.account?.pubkey ?? "mock-account"
    }

    init(
        sessionStore: NostrSessionStore = NostrSessionStore(restoreAccount: false),
        liveTimelineStore: NostrHomeTimelineStore = NostrHomeTimelineStore(),
        onInitialPresentationReady: @escaping () -> Void = {}
    ) {
        self.sessionStore = sessionStore
        self.liveTimelineStore = liveTimelineStore
        self.onInitialPresentationReady = onInitialPresentationReady

        let restoreStore = TimelineRestoreStore()
        let initialAccountID = sessionStore.account?.pubkey ?? "mock-account"
        _timelineRestoreStore = State(initialValue: restoreStore)
        _homeViewportState = State(initialValue: restoreStore.viewportState(accountID: initialAccountID, timelineKey: TimelineKind.home.id))
        _homeLayoutCache = State(initialValue: restoreStore.layoutCache(accountID: initialAccountID, timelineKey: TimelineKind.home.id))
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

    private var isComposeSubmitAvailable: Bool {
        sessionStore.account == nil || sessionStore.signer != nil
    }

    private var accountSummaries: [NostrAccountSummary] {
        _ = liveTimelineStore.resolvedContentRevision
        return sessionStore.accountSummaries(eventStore: liveTimelineStore.relayStatusEventStore)
    }

    private var currentAccountSummary: NostrAccountSummary? {
        guard let currentPubkey = sessionStore.account?.pubkey else { return nil }
        return accountSummaries.first { $0.id == currentPubkey }
    }

    private var composeSubmitHandler: ((ComposeSubmitRequest) async -> Bool)? {
        guard sessionStore.account != nil else { return nil }
        return { request in
            await submitCompose(request)
        }
    }

    private var timelineEntries: [TimelineFeedEntry] {
        guard sessionStore.account != nil else {
            return MockTimelineData.entries(for: selectedTimeline)
        }

        switch selectedTimeline {
        case .home:
            return liveTimelineStore.entries
        case .relays:
            return MockTimelineData.entries(for: selectedTimeline)
        case .lists:
            let listEntries = liveTimelineStore.listEntries()
            return listEntries.isEmpty ? MockTimelineData.entries(for: selectedTimeline) : listEntries
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
        return liveTimelineStore.relayStatusCounts.connected
    }

    private var relayPlannedCount: Int {
        guard sessionStore.account != nil else {
            return RelayMockStore.plannedCount
        }
        return liveTimelineStore.relayStatusCounts.planned
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
                        currentAccount: currentAccountSummary,
                        accounts: accountSummaries,
                        onSelectAccount: selectAccountFromSwitcher,
                        onAddAccount: presentSettings,
                        relayConnectedCount: relayConnectedCount,
                        relayPlannedCount: relayPlannedCount,
                        isRelayProcessing: liveTimelineStore.isRelayProcessing
                    )
                    .zIndex(30)

                    Spacer(minLength: 0)
                }
            }

            if visibleTab == .home && !isPostDetailPresented && liveTimelineStore.visibleUnreadBadgeCount > 0 {
                HomeUnreadBadge(count: liveTimelineStore.visibleUnreadBadgeCount) {
                    liveTimelineStore.dismissUnreadBadge()
                    dismissFloatingMenus()
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 88)
                    .padding(.trailing, 22)
            }

            if visibleTab == .home && !isPostDetailPresented && liveTimelineStore.filterStatus.isVisible {
                HomeFilterIndicator(
                    status: liveTimelineStore.filterStatus,
                    onOpenFilters: presentFiltersSettings,
                    onClear: liveTimelineStore.suspendTimelineFilters,
                    onResume: liveTimelineStore.resumeTimelineFilters
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 72)
                .padding(.leading, 16)
                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                .zIndex(32)
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
        .onPreferenceChange(UnreadBadgeFramePreferenceKey.self) { frame in
            unreadBadgeFrame = frame
        }
        .onAppear(perform: completeInitialAppearanceIfNeeded)
        .onChange(of: selectedTab) { _, newValue in
            handleTabSelection(newValue)
        }
        .onChange(of: selectedTimeline) { _, _ in
            clearHomeReturnAnchor()
            loadTimelineRestoreState()
        }
        .onChange(of: sessionStore.account?.pubkey) { _, _ in
            clearHomeReturnAnchor()
            loadTimelineRestoreState()
        }
        .homeTimelinePresentations(
            isComposerPresented: $isComposerPresented,
            isSettingsPresented: $isSettingsPresented,
            isFiltersSettingsPresented: $isFiltersSettingsPresented,
            isRelayStatusPresented: $isRelayStatusPresented,
            composeSheetMode: $composeSheetMode,
            fullscreenMedia: $fullscreenMedia,
            browserDestination: $browserDestination,
            swipeSettings: $swipeSettings,
            relayURLs: sessionStore.account == nil ? [] : liveTimelineStore.resolvedRelays,
            relayRuntimeStates: sessionStore.account == nil ? [:] : liveTimelineStore.relayRuntimeStates,
            accountID: sessionStore.account?.pubkey,
            eventStore: sessionStore.account == nil ? nil : liveTimelineStore.relayStatusEventStore,
            accountSummaries: accountSummaries,
            onSelectAccount: selectAccountFromSwitcher,
            onRemoveAccount: removeAccountFromSettings,
            onAddAccount: presentSettings,
            isComposeSubmitAvailable: isComposeSubmitAvailable,
            onComposeSubmit: composeSubmitHandler
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
            hasUnmaterializedHomeEvents: liveTimelineStore.unmaterializedNewCount > 0,
            isHomeReturnMode: homeReturnAnchor != nil,
            timelineList: timelineList,
            profileView: profileView,
            onMinimizeDirectionChanged: updateTabBarMinimizeDirection,
            onHomeRetap: handleHomeTabRetap,
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
                scrollCommand: homeScrollCommand,
                followsNewestEntries: isTimelineAtNewestWindow,
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
                onPostActionChoice: handlePostActionChoice,
                onRefresh: refreshVisibleTimeline,
                onLoadOlderPost: loadOlderVisibleTimeline,
                onBackfillGap: backfillVisibleTimelineGap
            ) { offset in
                handleTimelineScrollOffset(offset)
            } onViewportStateChanged: { state in
                saveTimelineViewportState(state)
            } onReadablePostIDsChanged: { ids in
                guard sessionStore.account != nil, selectedTimeline == .home else { return }
                liveTimelineStore.markMaterializedPostsRead(visiblePostIDs: ids)
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
                profile: currentUserProfile,
                posts: currentUserProfilePosts,
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
            let post = detailPost(for: selectedPost.post)
            PostDetailView(
                post: post,
                replyAncestors: liveReplyAncestors(for: post),
                replies: liveReplies(for: post),
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
            let post = detailPost(for: selectedPost.post)
            PostDetailView(
                post: post,
                replyAncestors: liveReplyAncestors(for: post),
                replies: liveReplies(for: post),
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
        let profile = userProfile(for: post)

        return UserDetailView(
            profile: profile,
            posts: userProfilePosts(for: profile),
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

    var currentUserProfile: UserProfile {
        guard let account = sessionStore.account else {
            return MockTimelineData.selfProfile
        }

        return liveTimelineStore.profile(pubkey: account.pubkey, isCurrentUser: true)
    }

    var currentUserProfilePosts: [TimelinePost] {
        guard let account = sessionStore.account else {
            return MockTimelineData.selfProfilePosts
        }

        return liveTimelineStore.profilePosts(pubkey: account.pubkey)
    }

    func detailPost(for post: TimelinePost) -> TimelinePost {
        guard sessionStore.account != nil else { return post }
        return liveTimelineStore.post(eventID: post.id) ?? post
    }

    func liveReplyAncestors(for post: TimelinePost) -> [TimelinePost]? {
        guard sessionStore.account != nil else { return nil }
        return liveTimelineStore.replyAncestors(for: post)
    }

    func liveReplies(for post: TimelinePost) -> [TimelinePost]? {
        guard sessionStore.account != nil else { return nil }
        return liveTimelineStore.replies(for: post)
    }

    func userProfile(for post: TimelinePost) -> UserProfile {
        guard sessionStore.account != nil else {
            return MockTimelineData.profile(for: post)
        }

        return liveTimelineStore.profile(pubkey: post.author.pubkey)
    }

    func userProfilePosts(for profile: UserProfile) -> [TimelinePost] {
        guard sessionStore.account != nil else {
            return MockTimelineData.profilePosts(for: profile)
        }

        return liveTimelineStore.profilePosts(pubkey: profile.author.pubkey)
    }

    func completeInitialAppearanceIfNeeded() {
        guard !didCompleteInitialAppearance else { return }
        loadTimelineRestoreState()
        if selectedTab == .compose {
            selectedTab = previousTab
        }
        DispatchQueue.main.async {
            didCompleteInitialAppearance = true
            onInitialPresentationReady()
        }
    }

    func handleTimelineScrollOffset(_ offset: CGFloat) {
        if isUserSwitcherPresented || isTimelineMenuPresented {
            let didScroll = abs(offset - timelineScrollOffset) > 1
            if didScroll {
                dismissFloatingMenus()
            }
        }
        let oldChromeOffset = min(max(timelineScrollOffset, 0), 72)
        let newChromeOffset = min(max(offset, 0), 72)
        if abs(newChromeOffset - oldChromeOffset) >= 2 || (timelineScrollOffset <= 72) != (offset <= 72) {
            timelineScrollOffset = newChromeOffset
        }

        if sessionStore.account != nil, selectedTimeline == .home {
            let nextIsNewestWindow = offset <= 6
            if isTimelineAtNewestWindow != nextIsNewestWindow {
                isTimelineAtNewestWindow = nextIsNewestWindow
                liveTimelineStore.setTimelineAtNewestWindow(nextIsNewestWindow)
            }
        }
    }

    func openPost(_ post: TimelinePost) {
        dismissFloatingMenus()
        clearHomeReturnAnchor()
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

    func openMedia(_ media: TimelineMedia, initialTileIndex: Int = 0) {
        dismissFloatingMenus()
        fullscreenMedia = TimelineFullscreenMediaRequest(
            media: media,
            initialTileIndex: initialTileIndex
        )
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
            if newValue != .home {
                clearHomeReturnAnchor()
            }
            previousTab = newValue
        }
    }

    func handleHomeTabRetap() {
        guard selectedTab == .home, selectedTimeline == .home, sessionStore.account != nil else { return }
        dismissFloatingMenus()
        if let returnAnchor = homeReturnAnchor {
            homeScrollCommand = TimelineScrollCommand(target: .viewport(returnAnchor))
            homeReturnAnchor = nil
        } else {
            homeReturnAnchor = homeViewportState
            homeScrollCommand = TimelineScrollCommand(target: .top)
        }
    }

    func clearHomeReturnAnchor() {
        homeReturnAnchor = nil
    }

    func presentComposer() {
        presentComposer(mode: .post)
    }

    func presentReplyComposer() {
        presentComposer(mode: .reply)
    }

    func presentSettings() {
        dismissFloatingMenus()
        guard !isComposerPresented && !isFiltersSettingsPresented && !isRelayStatusPresented && browserDestination == nil && fullscreenMedia == nil else { return }
        isSettingsPresented = true
    }

    func selectAccountFromSwitcher(_ pubkey: String) {
        dismissFloatingMenus()
        guard sessionStore.account?.pubkey != pubkey else { return }
        sessionStore.selectAccount(pubkey)
    }

    func removeAccountFromSettings(_ pubkey: String) {
        sessionStore.removeAccount(pubkey)
    }

    func presentFiltersSettings() {
        dismissFloatingMenus()
        guard !isComposerPresented && !isSettingsPresented && !isRelayStatusPresented && browserDestination == nil && fullscreenMedia == nil else { return }
        isFiltersSettingsPresented = true
    }

    func presentRelayStatus() {
        dismissFloatingMenus()
        guard !isComposerPresented && !isSettingsPresented && !isFiltersSettingsPresented && browserDestination == nil && fullscreenMedia == nil else { return }
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
        clearHomeReturnAnchor()
        if liveTimelineStore.unmaterializedNewCount > 0 {
            await liveTimelineStore.applyPendingNewEvents()
            return
        }
        await liveTimelineStore.refreshLatest()
    }

    func loadOlderVisibleTimeline(_ postID: TimelinePost.ID) {
        guard sessionStore.account != nil, selectedTimeline == .home else { return }
        liveTimelineStore.loadOlder()
    }

    func backfillVisibleTimelineGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        guard sessionStore.account != nil, selectedTimeline == .home else { return false }
        return await liveTimelineStore.backfillGap(gap, direction: direction)
    }

    func handlePostActionChoice(_ post: TimelinePost, choice: PostActionChoice) {
        guard sessionStore.account != nil else { return }

        switch choice {
        case .mute:
            liveTimelineStore.muteAuthor(of: post)
        case .bookmark:
            liveTimelineStore.bookmark(post)
        case .report, .translate, .copyLink, .shareLink, .viewDetails:
            break
        }
    }

    func submitCompose(_ request: ComposeSubmitRequest) async -> Bool {
        guard let signer = sessionStore.signer else { return false }
        var tags: [[String]] = []
        if request.isSensitive {
            tags.append(["content-warning", request.sensitiveReason])
        }

        do {
            switch request.mode {
            case .post:
                try await liveTimelineStore.enqueuePublish(
                    .post(content: request.text, tags: tags),
                    signer: signer
                )
            case .reply:
                try await liveTimelineStore.enqueuePublish(
                    .post(content: request.text, tags: tags),
                    signer: signer
                )
            }
            return true
        } catch {
            return false
        }
    }

    func presentComposer(mode: ComposeSheetMode) {
        dismissFloatingMenus()
        guard didCompleteInitialAppearance, !isComposerPresented, !isSettingsPresented, !isFiltersSettingsPresented else { return }
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
        if sessionStore.account != nil, selectedTimeline == .home {
            liveTimelineStore.setRestoreProjectionAnchor(homeViewportState?.anchorPostID)
        }
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
