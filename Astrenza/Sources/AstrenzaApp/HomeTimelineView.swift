import AstrenzaCore
import SwiftUI

struct HomeTimelineView: View {
    @ObservedObject var sessionStore: NostrSessionStore
    let liveTimelineStore: NostrHomeTimelineStore
    let onInitialPresentationReady: () -> Void
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var presentation = HomeTimelinePresentationState()
    @State private var didCompleteInitialAppearance = false
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var isTimelineAtNewestWindow = true
    @State private var isViewportRestoreProtectionActive: Bool
    @State private var isTimelineDetachedFromLiveEdge: Bool
    @State private var homeReturnAnchor: TimelineViewportState?
    @State private var homeScrollCommand: TimelineScrollCommand?
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var navigation = HomeTimelineNavigationState()
    @State private var unreadBadgeFrame: CGRect = .zero
    @State private var swipeSettings = TimelineSwipeSettings()
    @State private var timelineRestoreStore = TimelineRestoreStore()
    @State private var homeViewportState: TimelineViewportState?
    @State private var homeLayoutCache: TimelineLayoutCache

    private var accountID: String {
        sessionStore.account?.pubkey ?? "mock-account"
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
        navigation.isPresentingDetail
    }

    private var composeSubmitHandler: ((ComposeSubmitRequest) async -> Bool)? {
        guard sessionStore.account != nil else { return nil }
        return { request in
            await submitCompose(request)
        }
    }

    private var timelineNavigationActions:
        HomeTimelineNavigationDestinationActions {
        HomeTimelineNavigationDestinationActions(
            onOpenPost: openPost,
            onOpenProfile: openProfile,
            onReply: presentReplyComposer,
            onOpenMedia: openMedia,
            onOpenURL: openURL
        )
    }

    private var profileNavigationActions:
        HomeTimelineNavigationDestinationActions {
        HomeTimelineNavigationDestinationActions(
            onOpenPost: openProfilePost,
            onOpenProfile: openProfileFromProfile,
            onReply: presentReplyComposer,
            onOpenMedia: openMedia,
            onOpenURL: openURL
        )
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
        let initialViewportState = restoreStore.viewportState(
            accountID: initialAccountID,
            timelineKey: TimelineKind.home.id
        ) ?? liveTimelineStore.restoredViewportState(
            accountID: initialAccountID,
            timelineKey: TimelineKind.home.id
        )
        let initialLayoutCache = restoreStore.layoutCache(
            accountID: initialAccountID,
            timelineKey: TimelineKind.home.id
        )
        _timelineRestoreStore = State(initialValue: restoreStore)
        _homeViewportState = State(initialValue: initialViewportState)
        _homeLayoutCache = State(initialValue: initialLayoutCache)
        _isTimelineAtNewestWindow = State(initialValue: initialViewportState == nil)
        _isViewportRestoreProtectionActive = State(initialValue: initialViewportState != nil)
        _isTimelineDetachedFromLiveEdge = State(initialValue: initialViewportState != nil)
    }

    var body: some View {
        ZStack {
            Color.astrenzaBackground.ignoresSafeArea()

            nativeTabs
                .simultaneousGesture(
                    TapGesture().onEnded(dismissFloatingMenus)
                )

            HomeTimelineChromeView(
                timelineStore: liveTimelineStore,
                visibleTab: visibleTab,
                isPostDetailPresented: isPostDetailPresented,
                collapseProgress: topChromeCollapseProgress,
                onDismissFloatingMenus: dismissFloatingMenus,
                onRelayStatusTap: presentRelayStatus,
                onSettingsTap: presentSettings,
                onSelectAccount: selectAccountFromSwitcher,
                onOpenFilters: presentFiltersSettings,
                sessionStore: sessionStore,
                selectedTimeline: $selectedTimeline,
                isTimelineMenuPresented: $isTimelineMenuPresented,
                isUserSwitcherPresented: $isUserSwitcherPresented
            )

            if isPostDetailPresented {
                HomeTimelineReplyButton(action: presentReplyComposer)
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
        .onDisappear {
            timelineRestoreStore.flushPendingSaves()
        }
        .homeTimelinePresentations(
            timelineStore: liveTimelineStore,
            sessionStore: sessionStore,
            presentation: $presentation,
            swipeSettings: $swipeSettings,
            actions: HomeTimelinePresentationActions(
                onSelectAccount: selectAccountFromSwitcher,
                onRemoveAccount: removeAccountFromSettings,
                onAddAccount: presentSettings,
                onComposeSubmit: composeSubmitHandler
            )
        )
    }
}

private extension HomeTimelineView {
    var nativeTabs: some View {
        HomeTimelineTabContentView(
            timelineStore: liveTimelineStore,
            minimizeDirection: tabBarMinimizeDirection,
            isTabBarHidden: isPostDetailPresented,
            isHomeReturnMode: homeReturnAnchor != nil,
            timelineList: timelineList,
            profileView: profileView,
            onMinimizeDirectionChanged: updateTabBarMinimizeDirection,
            onHomeRetap: handleHomeTabRetap,
            onComposeTap: presentComposer,
            selectedTab: $selectedTab,
            previousTab: $previousTab
        )
    }

    var timelineList: some View {
        NavigationStack(path: $navigation.timelinePath) {
            HomeTimelineFeedContentView(
                store: liveTimelineStore,
                hasLiveAccount: sessionStore.account != nil,
                selectedTimeline: selectedTimeline,
                sourceIdentity: "\(accountID)/\(selectedTimeline.id)",
                actionMenuTopClearance: actionMenuTopClearance,
                swipeSettings: swipeSettings,
                viewportState: homeViewportState,
                scrollCommand: homeScrollCommand,
                viewportRestoreProtectionActive: isViewportRestoreProtectionActive,
                isTimelineAtNewestWindow: isTimelineAtNewestWindow,
                isTimelineDetachedFromLiveEdge: isTimelineDetachedFromLiveEdge,
                layoutCache: homeLayoutCache,
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
                onBackfillGap: backfillVisibleTimelineGap,
                onScrollOffsetChanged: handleTimelineScrollOffset,
                onScrollActivityChanged: handleTimelineScrollActivityChanged,
                onViewportRestoreCompleted: handleTimelineViewportRestoreCompleted,
                onViewportStateChanged: saveTimelineViewportState,
                onReadablePostIDsChanged: { ids in
                    guard sessionStore.account != nil, selectedTimeline == .home else { return }
                    liveTimelineStore.markMaterializedPostsRead(visiblePostIDs: ids)
                },
                onLayoutCacheChanged: saveTimelineLayoutCache
            )
            .id("\(accountID)/\(selectedTimeline.id)")
            .navigationDestination(
                for: HomeTimelineNavigationRoute.self
            ) { route in
                HomeTimelineNavigationDestinationView(
                    route: route,
                    timelineStore: liveTimelineStore,
                    hasLiveAccount: sessionStore.account != nil,
                    swipeSettings: swipeSettings,
                    actions: timelineNavigationActions
                )
            }
        }
    }

    var profileView: some View {
        NavigationStack(path: $navigation.profilePath) {
            HomeTimelineProfileContentView(
                timelineStore: liveTimelineStore,
                account: sessionStore.account,
                swipeSettings: swipeSettings,
                onOpenPost: openProfilePost,
                onOpenProfile: openProfileFromProfile,
                onReplyPost: { _ in
                    presentReplyComposer()
                },
                onOpenMedia: openMedia,
                onOpenURL: openURL
            )
            .navigationDestination(
                for: HomeTimelineNavigationRoute.self
            ) { route in
                HomeTimelineNavigationDestinationView(
                    route: route,
                    timelineStore: liveTimelineStore,
                    hasLiveAccount: sessionStore.account != nil,
                    swipeSettings: swipeSettings,
                    actions: profileNavigationActions
                )
            }
        }
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

        synchronizeTimelineNewestWindowState(for: offset)
    }

    func handleTimelineScrollActivityChanged(_ isActive: Bool) {
        guard sessionStore.account != nil, selectedTimeline == .home else { return }
        liveTimelineStore.setTimelineScrollActive(isActive)
    }

    func handleTimelineViewportRestoreCompleted(_ restoredOffset: CGFloat) {
        guard isViewportRestoreProtectionActive else { return }
        isViewportRestoreProtectionActive = false
        synchronizeTimelineNewestWindowState(for: restoredOffset, forceStoreSync: true)
    }

    func synchronizeTimelineNewestWindowState(
        for offset: CGFloat,
        forceStoreSync: Bool = false
    ) {
        guard sessionStore.account != nil, selectedTimeline == .home else { return }
        let nextIsNewestWindow = HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: offset,
            isRestoreProtected: isViewportRestoreProtectionActive,
            isDetachedFromLiveEdge: isTimelineDetachedFromLiveEdge
        )
        if nextIsNewestWindow {
            liveTimelineStore.markNewestMaterializedWindowRead()
        }
        guard forceStoreSync || isTimelineAtNewestWindow != nextIsNewestWindow else { return }
        isTimelineAtNewestWindow = nextIsNewestWindow
        liveTimelineStore.setTimelineAtNewestWindow(nextIsNewestWindow)
    }

    func openPost(_ post: TimelinePost) {
        dismissFloatingMenus()
        clearHomeReturnAnchor()
        navigation.openPost(post, on: .timeline)
    }

    func openProfile(_ post: TimelinePost) {
        dismissFloatingMenus()
        navigation.openProfile(from: post, on: .timeline)
    }

    func openProfilePost(_ post: TimelinePost) {
        dismissFloatingMenus()
        navigation.openPost(post, on: .profile)
    }

    func openProfileFromProfile(_ post: TimelinePost) {
        dismissFloatingMenus()
        navigation.openProfile(from: post, on: .profile)
    }

    func openMedia(_ media: TimelineMedia, initialTileIndex: Int = 0) {
        dismissFloatingMenus()
        presentation.presentFullscreenMedia(
            media,
            initialTileIndex: initialTileIndex
        )
    }

    func openURL(_ url: URL) {
        dismissFloatingMenus()
        presentation.presentBrowser(url: url)
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
        let currentViewportState = homeViewportState
        releaseViewportRestoreProtection(clearViewportState: true)
        if let returnAnchor = homeReturnAnchor {
            // DBの表示windowを復元対象へ切り替えてからSwiftUIへscrollを指示する。
            isTimelineDetachedFromLiveEdge = true
            isTimelineAtNewestWindow = false
            liveTimelineStore.setTimelineAtNewestWindow(false)
            liveTimelineStore.setRestoreProjectionAnchor(returnAnchor.anchorPostID)
            homeScrollCommand = TimelineScrollCommand(target: .viewport(returnAnchor))
            homeReturnAnchor = nil
        } else {
            isTimelineDetachedFromLiveEdge = false
            homeReturnAnchor = timelineRestoreStore.latestViewportState(
                accountID: accountID,
                timelineKey: selectedTimeline.id
            ) ?? currentViewportState
            liveTimelineStore.markNewestMaterializedWindowRead()
            // ページング後の先頭Rowは最新とは限らないため、Generic Feedの最新windowを先に復元する。
            liveTimelineStore.setRestoreProjectionAnchor(nil)
            isTimelineAtNewestWindow = true
            liveTimelineStore.setTimelineAtNewestWindow(true)
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
        presentation.requestSettings()
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
        presentation.requestFiltersSettings()
    }

    func presentRelayStatus() {
        dismissFloatingMenus()
        presentation.requestRelayStatus()
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

    func refreshVisibleTimeline() async -> Bool {
        guard sessionStore.account != nil, selectedTimeline == .home else { return false }
        clearHomeReturnAnchor()
        releaseViewportRestoreProtection(clearViewportState: true)
        isTimelineDetachedFromLiveEdge = false
        synchronizeTimelineNewestWindowState(for: timelineScrollOffset, forceStoreSync: true)
        return await liveTimelineStore.applyPendingNewEvents()
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
        guard presentation.prepareComposer(
            mode: mode,
            isInitialPresentationReady: didCompleteInitialAppearance
        ) else { return }
        DispatchQueue.main.async {
            presentation.activatePreparedComposer()
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
        timelineRestoreStore.flushPendingSaves()
        let restoredViewportState = timelineRestoreStore.viewportState(
            accountID: accountID,
            timelineKey: selectedTimeline.id
        ) ?? liveTimelineStore.restoredViewportState(
            accountID: accountID,
            timelineKey: selectedTimeline.id
        )
        homeViewportState = restoredViewportState
        isViewportRestoreProtectionActive = restoredViewportState != nil
        isTimelineDetachedFromLiveEdge = restoredViewportState != nil
        isTimelineAtNewestWindow = restoredViewportState == nil
        homeLayoutCache = timelineRestoreStore.layoutCache(accountID: accountID, timelineKey: selectedTimeline.id)
        if sessionStore.account != nil, selectedTimeline == .home {
            liveTimelineStore.setRestoreProjectionAnchor(restoredViewportState?.anchorPostID)
            liveTimelineStore.setTimelineAtNewestWindow(restoredViewportState == nil)
        }
    }

    func releaseViewportRestoreProtection(clearViewportState: Bool) {
        isViewportRestoreProtectionActive = false
        if clearViewportState {
            homeViewportState = nil
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

        timelineRestoreStore.scheduleViewportStateSave(nextState)
    }

    func saveTimelineLayoutCache(_ cache: TimelineLayoutCache) {
        guard homeLayoutCache != cache else { return }
        homeLayoutCache = cache
        timelineRestoreStore.scheduleLayoutCacheSave(
            cache,
            accountID: accountID,
            timelineKey: selectedTimeline.id
        )
    }
}

enum HomeTimelineViewportRestorePolicy {
    static func isAtNewestWindow(
        offset: CGFloat,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        !isRestoreProtected && !isDetachedFromLiveEdge && offset <= 6
    }

    static func followsRealtimeEntries(
        isRealtime: Bool,
        isAtNewestWindow: Bool,
        isRestoreProtected: Bool,
        isDetachedFromLiveEdge: Bool
    ) -> Bool {
        isRealtime && !isRestoreProtected && !isDetachedFromLiveEdge && isAtNewestWindow
    }
}

#Preview {
    HomeTimelineView()
        .preferredColorScheme(.dark)
}
