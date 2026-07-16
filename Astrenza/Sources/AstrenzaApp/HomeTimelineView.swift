import AstrenzaCore
import SwiftUI

struct HomeTimelineView: View {
    @ObservedObject var sessionStore: NostrSessionStore
    let liveTimelineStore: NostrHomeTimelineStore
    let onInitialPresentationReady: () -> Void
    private let emptyStateActions: HomeTimelineEmptyStateActionCoordinator
    private let feedActions: HomeTimelineFeedActionCoordinator
    private let userActions: HomeTimelineUserActionCoordinator
    private let viewportStoreSynchronizer: HomeTimelineViewportStoreSynchronizer
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var presentation = HomeTimelinePresentationState()
    @State private var didCompleteInitialAppearance = false
    @State private var viewport: HomeTimelineViewportState
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var navigation = HomeTimelineNavigationState()
    @State private var unreadBadgeFrame: CGRect = .zero
    @State private var swipeSettings = TimelineSwipeSettings()
    @State private var viewportPersistence: HomeViewportPersistenceCoordinator

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
        viewport.topChromeCollapseProgress
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

    private var timelineInteractionContext: HomeTimelineInteractionContext {
        HomeTimelineInteractionContext(
            hasLiveAccount: sessionStore.account != nil,
            timeline: selectedTimeline
        )
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
        liveTimelineStore: NostrHomeTimelineStore = HomeTimelineStoreFactory.make(),
        onInitialPresentationReady: @escaping () -> Void = {}
    ) {
        self.sessionStore = sessionStore
        self.liveTimelineStore = liveTimelineStore
        self.onInitialPresentationReady = onInitialPresentationReady
        self.emptyStateActions = HomeTimelineEmptyStateActionCoordinator(
            actions: liveTimelineStore
        )
        self.feedActions = HomeTimelineFeedActionCoordinator(
            actions: liveTimelineStore
        )
        self.userActions = HomeTimelineUserActionCoordinator(
            actions: liveTimelineStore
        )
        self.viewportStoreSynchronizer = HomeTimelineViewportStoreSynchronizer(
            store: liveTimelineStore
        )

        let viewportPersistence = HomeViewportPersistenceCoordinator(
            persistence: TimelineRestoreStore(),
            fallbackViewportLoader: { accountID, timelineKey in
                liveTimelineStore.restoredViewportState(
                    accountID: accountID,
                    timelineKey: timelineKey
                )
            }
        )
        let initialAccountID = sessionStore.account?.pubkey ?? "mock-account"
        let initialSnapshot = viewportPersistence.restoreSnapshot(
            accountID: initialAccountID,
            timelineKey: TimelineKind.home.id
        )
        _viewportPersistence = State(initialValue: viewportPersistence)
        _viewport = State(initialValue: HomeTimelineViewportState(
            restoredViewportState: initialSnapshot.viewportState,
            layoutCache: initialSnapshot.layoutCache
        ))
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
            viewportPersistence.flushPendingSaves()
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
            isHomeReturnMode: viewport.isHomeReturnMode,
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
                viewportState: viewport.viewportState,
                scrollCommand: viewport.scrollCommand,
                viewportRestoreProtectionActive: viewport.isRestoreProtectionActive,
                isTimelineAtNewestWindow: viewport.isAtNewestWindow,
                isTimelineDetachedFromLiveEdge: viewport.isDetachedFromLiveEdge,
                layoutCache: viewport.layoutCache,
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
                onReadablePostIDsChanged: handleReadablePostIDsChanged,
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
            if viewport.shouldDismissFloatingMenus(for: offset) {
                dismissFloatingMenus()
            }
        }
        if let newChromeOffset = viewport.scrollOffsetUpdate(for: offset) {
            viewport.applyScrollOffset(newChromeOffset)
        }

        synchronizeTimelineNewestWindowState(for: offset)
    }

    func handleTimelineScrollActivityChanged(_ isActive: Bool) {
        feedActions.setTimelineScrollActive(
            isActive,
            context: timelineInteractionContext
        )
    }

    func handleReadablePostIDsChanged(_ ids: [TimelinePost.ID]) {
        feedActions.markMaterializedPostsRead(
            visiblePostIDs: ids,
            context: timelineInteractionContext
        )
    }

    func handleTimelineViewportRestoreCompleted(_ restoredOffset: CGFloat) {
        guard viewport.completeRestore() else { return }
        synchronizeTimelineNewestWindowState(
            for: restoredOffset,
            forceStoreSync: true
        )
    }

    func synchronizeTimelineNewestWindowState(
        for offset: CGFloat,
        forceStoreSync: Bool = false
    ) {
        guard timelineInteractionContext.canMutateLiveHome else { return }
        let update = viewport.updateNewestWindow(
            for: offset,
            forceStoreSync: forceStoreSync
        )
        viewportStoreSynchronizer.applyNewestWindowUpdate(
            update,
            context: timelineInteractionContext
        )
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
        let latestSavedViewportState = viewport.isHomeReturnMode ? nil :
            viewportPersistence.latestViewportState(
                accountID: accountID,
                timelineKey: selectedTimeline.id
            )
        let action = viewport.prepareHomeRetap(
            latestSavedViewportState: latestSavedViewportState
        )
        viewportStoreSynchronizer.applyHomeRetap(
            action,
            context: timelineInteractionContext
        )
    }

    func clearHomeReturnAnchor() {
        viewport.clearReturnAnchor()
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
        emptyStateActions.performPrimaryAction(
            interaction: timelineInteractionContext,
            presentRelayStatus: presentRelayStatus,
            presentSettings: presentSettings
        )
    }

    func handleTimelineEmptyStateSecondaryAction() {
        emptyStateActions.performSecondaryAction(
            interaction: timelineInteractionContext,
            selectExplore: { selectedTab = .explore }
        )
    }

    func refreshVisibleTimeline() async -> Bool {
        await feedActions.refresh(context: timelineInteractionContext) {
            viewportStoreSynchronizer.applyNewestWindowUpdate(
                viewport.prepareRefresh(),
                context: timelineInteractionContext
            )
        }
    }

    func loadOlderVisibleTimeline(_: TimelinePost.ID) {
        feedActions.loadOlder(context: timelineInteractionContext)
    }

    func backfillVisibleTimelineGap(_ gap: TimelineGap, direction: TimelineGapFillDirection) async -> Bool {
        await feedActions.backfillGap(
            gap,
            direction: direction,
            context: timelineInteractionContext
        )
    }

    func handlePostActionChoice(_ post: TimelinePost, choice: PostActionChoice) {
        guard sessionStore.account != nil else { return }
        userActions.perform(choice, on: post)
    }

    func submitCompose(_ request: ComposeSubmitRequest) async -> Bool {
        await userActions.submit(request, signer: sessionStore.signer)
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
        let snapshot = viewportPersistence.restoreSnapshot(
            accountID: accountID,
            timelineKey: selectedTimeline.id
        )
        viewport.load(
            restoredViewportState: snapshot.viewportState,
            layoutCache: snapshot.layoutCache
        )
        viewportStoreSynchronizer.applyRestoreSnapshot(
            snapshot,
            context: timelineInteractionContext
        )
    }

    func saveTimelineViewportState(_ state: TimelineViewportState) {
        viewportPersistence.scheduleViewportStateSave(
            state,
            accountID: accountID,
            timelineKey: selectedTimeline.id
        )
    }

    func saveTimelineLayoutCache(_ cache: TimelineLayoutCache) {
        guard viewport.shouldUpdateLayoutCache(cache) else { return }
        viewport.applyLayoutCache(cache)
        viewportPersistence.scheduleLayoutCacheSave(
            cache,
            accountID: accountID,
            timelineKey: selectedTimeline.id
        )
    }
}

#Preview {
    HomeTimelineView()
        .preferredColorScheme(.dark)
}
