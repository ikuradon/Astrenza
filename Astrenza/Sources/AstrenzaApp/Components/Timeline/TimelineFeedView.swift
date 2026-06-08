import Foundation
import SwiftUI

struct TimelineFeedView: View {
    let entries: [TimelineFeedEntry]
    let actionMenuTopClearance: CGFloat
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let scrollCommand: TimelineScrollCommand?
    let followsNewestEntries: Bool
    let layoutCache: TimelineLayoutCache
    let emptyState: TimelineEmptyState
    let onEmptyStatePrimaryAction: () -> Void
    let onEmptyStateSecondaryAction: (() -> Void)?
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia, Int) -> Void
    let onOpenURL: (URL) -> Void
    let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
    let onRefresh: (() async -> Void)?
    let onLoadOlderPost: ((TimelinePost.ID) -> Void)?
    let onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)?
    let onScrollOffsetChanged: (CGFloat) -> Void
    let onViewportStateChanged: (TimelineViewportState) -> Void
    let onReadablePostIDsChanged: ([TimelinePost.ID]) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void
    @State private var menuState = TimelinePostMenuState()
    @State private var didRestoreViewport = false
    @State private var measuredLayoutCache = TimelineLayoutCache()
    @State private var scrollPosition = ScrollPosition(idType: TimelinePost.ID.self)
    @State private var isRestoringViewport = false
    @State private var displayedEntries: [TimelineFeedEntry]
    @State private var fetchingGapDirections: [TimelineGap.ID: TimelineGapFillDirection] = [:]
    @State private var insertedPostDirections: [TimelinePost.ID: TimelineGapFillDirection] = [:]
    @State private var scrollRuntime = TimelineFeedScrollRuntime()
    @State private var isPullRefreshing = false
    @State private var pullRefreshProgress: CGFloat = 0
    @State private var isPullRefreshArmed = false
    @State private var isUserPullingToRefresh = false
    private let actionMenuGap: CGFloat = 12
    private let bottomChromeClearance: CGFloat = 116
    private let rowAnchorLineY: CGFloat = 72
    private let topContentPadding: CGFloat = 72
    private let pullRefreshTriggerOffset: CGFloat = -96
    private let viewportSaveInterval: TimeInterval = 0.25
    private let viewportSaveOffsetThreshold: CGFloat = 48
    private var posts: [TimelinePost] {
        displayedEntries.compactMap(\.post)
    }

    init(
        posts: [TimelinePost],
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        followsNewestEntries: Bool = false,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onPostActionChoice: @escaping (TimelinePost, PostActionChoice) -> Void = { _, _ in },
        onRefresh: (() async -> Void)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onReadablePostIDsChanged: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.init(
            entries: posts.map(TimelineFeedEntry.post),
            actionMenuTopClearance: actionMenuTopClearance,
            swipeSettings: swipeSettings,
            viewportState: viewportState,
            scrollCommand: scrollCommand,
            followsNewestEntries: followsNewestEntries,
            layoutCache: layoutCache,
            emptyState: emptyState,
            onEmptyStatePrimaryAction: onEmptyStatePrimaryAction,
            onEmptyStateSecondaryAction: onEmptyStateSecondaryAction,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onPostActionChoice: onPostActionChoice,
            onRefresh: onRefresh,
            onLoadOlderPost: onLoadOlderPost,
            onBackfillGap: onBackfillGap,
            onScrollOffsetChanged: onScrollOffsetChanged,
            onViewportStateChanged: onViewportStateChanged,
            onReadablePostIDsChanged: onReadablePostIDsChanged,
            onLayoutCacheChanged: onLayoutCacheChanged
        )
    }

    init(
        entries: [TimelineFeedEntry],
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        followsNewestEntries: Bool = false,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia, Int) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onPostActionChoice: @escaping (TimelinePost, PostActionChoice) -> Void = { _, _ in },
        onRefresh: (() async -> Void)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onReadablePostIDsChanged: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.entries = entries
        self.actionMenuTopClearance = actionMenuTopClearance
        self.swipeSettings = swipeSettings
        self.viewportState = viewportState
        self.scrollCommand = scrollCommand
        self.followsNewestEntries = followsNewestEntries
        self.layoutCache = layoutCache
        self.emptyState = emptyState
        self.onEmptyStatePrimaryAction = onEmptyStatePrimaryAction
        self.onEmptyStateSecondaryAction = onEmptyStateSecondaryAction
        self.onOpenPost = onOpenPost
        self.onOpenProfile = onOpenProfile
        self.onReplyPost = onReplyPost
        self.onOpenMedia = onOpenMedia
        self.onOpenURL = onOpenURL
        self.onPostActionChoice = onPostActionChoice
        self.onRefresh = onRefresh
        self.onLoadOlderPost = onLoadOlderPost
        self.onBackfillGap = onBackfillGap
        self.onScrollOffsetChanged = onScrollOffsetChanged
        self.onViewportStateChanged = onViewportStateChanged
        self.onReadablePostIDsChanged = onReadablePostIDsChanged
        self.onLayoutCacheChanged = onLayoutCacheChanged
        _displayedEntries = State(initialValue: entries)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if displayedEntries.isEmpty {
                    TimelineEmptyStateView(
                        state: emptyState,
                        onPrimaryAction: onEmptyStatePrimaryAction,
                        onSecondaryAction: onEmptyStateSecondaryAction
                    )
                } else {
                    ForEach(displayedEntries) { entry in
                        switch entry {
                        case .post(let post):
                            TimelinePostRow(
                                post: post,
                                isActionMenuPresented: menuState.openedMenu?.postID == post.id && menuState.openedMenu?.kind == .more,
                                swipeSettings: swipeSettings,
                                onActionEvent: handlePostActionEvent,
                                onOpenPost: { selectedPost in
                                    if menuState.isOpen {
                                        closeFloatingPostMenus()
                                    } else {
                                        onOpenPost(selectedPost)
                                    }
                                },
                                onOpenProfile: { selectedPost in
                                    if menuState.isOpen {
                                        closeFloatingPostMenus()
                                    } else {
                                        onOpenProfile(selectedPost)
                                    }
                                },
                                onReplyPost: onReplyPost,
                                onOpenMedia: openMedia,
                                onOpenURL: openURL,
                                onDismissActionMenu: {
                                    if menuState.isOpen {
                                        closeFloatingPostMenus()
                                    }
                                }
                            )
                            .id(post.id)
                            .transition(postInsertionTransition(for: post))
                            .zIndex(menuState.openedMenu?.postID == post.id ? 20 : 0)
                            .background(postFrameReader(postID: post.id))
                            .onAppear {
                                handlePostAppear(post)
                            }
                        case .gap(let gap):
                            TimelineGapRow(gap: displayGap(gap), direction: displayDirection(for: gap)) {
                                requestBackfill(for: gap)
                            }
                            .id(gap.id)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(gapFrameReader(gapID: gap.id))
                            .transition(.scale(scale: 0.96, anchor: .center).combined(with: .opacity))
                        case .deleted(let deletedEntry):
                            TimelineDeletedRow(entry: deletedEntry)
                                .id(deletedEntry.id)
                        }
                    }
                }
            }
            .padding(.top, topContentPadding)
            .padding(.bottom, 124)
        }
        .scrollPosition($scrollPosition)
        .overlay(alignment: .top) {
            TimelinePullRefreshIndicator(isRefreshing: isPullRefreshing, progress: pullRefreshProgress)
                .padding(.top, topContentPadding + 8)
        }
        .coordinateSpace(name: "timelineFeedOverlay")
        .coordinateSpace(name: "timelineFeedViewport")
        .background(viewportSizeReader)
        .onAppear {
            measuredLayoutCache = layoutCache
            updateLayoutSnapshot()
            restoreViewportIfNeeded()
        }
        .onPreferenceChange(TimelineGapFramePreferenceKey.self) { frames in
            scrollRuntime.gapFrames = frames
        }
        .onPreferenceChange(TimelineViewportSizePreferenceKey.self) { size in
            scrollRuntime.viewportSize = size
        }
        .onChange(of: entries.map(\.id)) { _, _ in
            syncDisplayedEntriesFromSource()
        }
        .onChange(of: viewportState) { _, _ in
            restoreViewportIfNeeded()
        }
        .onChange(of: scrollCommand?.id) { _, _ in
            handleScrollCommand()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            handleObservedContentOffset(offset)
        }
        .onScrollPhaseChange { _, newPhase in
            handleScrollPhaseChange(newPhase)
        }
        .scrollDisabled(menuState.isOpen)
        .scrollIndicators(.visible)
        .background(Color.astrenzaBackground)
        .accessibilityIdentifier("timeline.feed")
        .overlayPreferenceValue(TimelinePostActionAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ZStack {
                    if let openedPostMenu = menuState.openedMenu,
                       let anchor = anchors[
                        TimelinePostActionAnchorID(postID: openedPostMenu.postID, kind: openedPostMenu.kind)
                       ] {
                        let sourceFrame = proxy[anchor]
                        let menuPlacement = actionMenuPlacement(
                            gearFrame: sourceFrame,
                            menuSize: openedPostMenu.size,
                            containerSize: proxy.size
                        )
                        let menuFrame = CGRect(
                            x: menuPlacement.center.x - openedPostMenu.size.width / 2,
                            y: menuPlacement.center.y - openedPostMenu.size.height / 2,
                            width: openedPostMenu.size.width,
                            height: openedPostMenu.size.height
                        )

                        floatingPostMenu(openedPostMenu, menuFrame: menuFrame)
                        .position(
                            x: menuPlacement.center.x,
                            y: menuPlacement.center.y
                        )
                        .transition(.scale(scale: 0.72, anchor: menuPlacement.transitionAnchor).combined(with: .opacity))
                        .gesture(choiceSelectionGesture)
                        .zIndex(40)
                        .onAppear {
                            menuState.setFrame(menuFrame)
                        }
                        .onChange(of: menuFrame) { _, newValue in
                            menuState.setFrame(newValue)
                        }
                    }
                }
                .onAppear {
                    menuState.setOverlayGlobalFrame(proxy.frame(in: .global))
                }
                .onChange(of: proxy.frame(in: .global)) { _, newValue in
                    menuState.setOverlayGlobalFrame(newValue)
                }
            }
            .allowsHitTesting(menuState.isOpen)
        }
    }
}

private extension TimelineFeedView {
    var viewportSizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TimelineViewportSizePreferenceKey.self,
                value: proxy.size
            )
        }
    }

    func gapFrameReader(gapID: TimelineGap.ID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TimelineGapFramePreferenceKey.self,
                value: [gapID: proxy.frame(in: .named("timelineFeedViewport"))]
            )
        }
    }

    func postFrameReader(postID: TimelinePost.ID) -> some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("timelineFeedViewport"))
            } action: { _, frame in
                updateMeasuredPostFrame(postID: postID, frame: frame)
                notifyReadablePostIDs()
            }
    }

    func updateMeasuredPostFrame(postID: TimelinePost.ID, frame: CGRect) {
        scrollRuntime.postFrames[postID] = frame

        guard frame.height > 0 else { return }
        let previousHeight = measuredLayoutCache.measuredHeights[postID]
        guard previousHeight == nil || abs((previousHeight ?? 0) - frame.height) > 0.5 else { return }

        measuredLayoutCache.measuredHeights[postID] = frame.height
        updateLayoutSnapshot()
        onLayoutCacheChanged(measuredLayoutCache)
    }

    func postInsertionTransition(for post: TimelinePost) -> AnyTransition {
        switch insertedPostDirections[post.id] {
        case .newer:
            .move(edge: .top).combined(with: .opacity)
        case .older:
            .move(edge: .bottom).combined(with: .opacity)
        case nil:
            .identity
        }
    }

    func restoreViewportIfNeeded() {
        guard !didRestoreViewport,
              let viewportState,
              posts.contains(where: { $0.id == viewportState.anchorPostID })
        else { return }

        didRestoreViewport = true
        isRestoringViewport = true
        let targetOffsetY = TimelineViewportResolver.restoredContentOffsetY(
            entries: displayedEntries,
            state: viewportState,
            layoutCache: measuredLayoutCache,
            topContentPadding: topContentPadding,
            anchorLineY: rowAnchorLineY
        )

        DispatchQueue.main.async {
            if let targetOffsetY {
                scrollPosition.scrollTo(y: targetOffsetY)
            } else {
                scrollPosition.scrollTo(id: viewportState.anchorPostID, anchor: .top)
            }

            DispatchQueue.main.async {
                isRestoringViewport = false
            }
        }
    }

    func estimatedViewportAnchor(at contentOffset: CGFloat) -> TimelineViewportAnchor? {
        scrollRuntime.layoutSnapshot?.anchor(at: contentOffset, anchorLineY: rowAnchorLineY)
    }

    func updateLayoutSnapshot() {
        scrollRuntime.layoutSnapshot = TimelineLayoutSnapshot(
            entries: displayedEntries,
            layoutCache: measuredLayoutCache,
            topContentPadding: topContentPadding
        )
    }

    func saveViewportStateIfPossible(force: Bool = false) {
        guard !isRestoringViewport else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let offsetDelta = abs(scrollRuntime.currentContentOffset - scrollRuntime.lastSavedViewportOffset)
        if !force,
           offsetDelta < viewportSaveOffsetThreshold,
           now - scrollRuntime.lastViewportSaveTime < viewportSaveInterval {
            return
        }

        guard let currentViewportAnchor = estimatedViewportAnchor(at: scrollRuntime.currentContentOffset)
        else { return }

        let isSameAnchor = scrollRuntime.lastSavedViewportAnchor?.postID == currentViewportAnchor.postID
        let anchorDelta = abs((scrollRuntime.lastSavedViewportAnchor?.offset ?? currentViewportAnchor.offset) - currentViewportAnchor.offset)
        if !force,
           isSameAnchor,
           anchorDelta < 1,
           offsetDelta < viewportSaveOffsetThreshold {
            return
        }

        scrollRuntime.currentViewportAnchor = currentViewportAnchor
        scrollRuntime.lastSavedViewportAnchor = currentViewportAnchor
        scrollRuntime.lastSavedViewportOffset = scrollRuntime.currentContentOffset
        scrollRuntime.lastViewportSaveTime = now
        onViewportStateChanged(
            TimelineViewportState(
                accountID: viewportState?.accountID ?? "mock-account",
                timelineKey: viewportState?.timelineKey ?? "home",
                anchorPostID: currentViewportAnchor.postID,
                anchorOffset: currentViewportAnchor.offset,
                contentOffset: scrollRuntime.currentContentOffset,
                updatedAt: Date()
            )
        )
    }

    func handleObservedContentOffset(_ offset: CGFloat) {
        scrollRuntime.currentContentOffset = offset
        updatePullRefreshState(offset: offset)
        onScrollOffsetChanged(offset)
        saveViewportStateIfPossible()
        notifyReadablePostIDs()
    }

    func notifyReadablePostIDs() {
        let readLineY = topContentPadding + 24
        let readableIDs = posts
            .map(\.id)
            .filter { postID in
                guard let frame = scrollRuntime.postFrames[postID] else { return false }
                return frame.minY <= readLineY && frame.maxY > 0
            }
        guard readableIDs != scrollRuntime.lastReadablePostIDs else { return }
        scrollRuntime.lastReadablePostIDs = readableIDs
        DispatchQueue.main.async {
            onReadablePostIDsChanged(readableIDs)
        }
    }

    func handleScrollCommand() {
        guard let scrollCommand else { return }
        switch scrollCommand.target {
        case .top:
            scrollPosition.scrollTo(y: 0)
        case .viewport(let state):
            let targetOffsetY = TimelineViewportResolver.restoredContentOffsetY(
                entries: displayedEntries,
                state: state,
                layoutCache: measuredLayoutCache,
                topContentPadding: topContentPadding,
                anchorLineY: rowAnchorLineY
            )
            if let targetOffsetY {
                scrollPosition.scrollTo(y: targetOffsetY)
            } else {
                scrollPosition.scrollTo(id: state.anchorPostID, anchor: .top)
            }
        }
    }

    func syncDisplayedEntriesFromSource() {
        if !fetchingGapDirections.isEmpty {
            let sourceGapIDs = Set(entries.compactMap { entry -> TimelineGap.ID? in
                guard case .gap(let gap) = entry else { return nil }
                return gap.id
            })
            fetchingGapDirections = fetchingGapDirections.filter { sourceGapIDs.contains($0.key) }
            guard fetchingGapDirections.isEmpty else { return }
        }

        let oldIDs = displayedEntries.map(\.id)
        let newIDs = entries.map(\.id)
        guard oldIDs != newIDs else { return }

        let shouldPreserveAnchorForPullRefresh = isPullRefreshing || isPullRefreshArmed || isUserPullingToRefresh || pullRefreshProgress > 0
        let shouldFollowNewestEntries = !shouldPreserveAnchorForPullRefresh && followsNewestEntries && entriesDidPrependNewest(oldIDs: oldIDs, newIDs: newIDs)
        let anchor = estimatedViewportAnchor(at: scrollRuntime.currentContentOffset)
        let preservedOffset = preservedContentOffset(
            oldIDs: oldIDs,
            newIDs: newIDs,
            anchor: anchor
        )

        if shouldFollowNewestEntries {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedEntries = entries
                updateLayoutSnapshot()
                scrollPosition.scrollTo(y: 0)
            }
            scrollRuntime.currentContentOffset = 0
        } else if let preservedOffset {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedEntries = entries
                updateLayoutSnapshot()
                scrollPosition.scrollTo(y: preservedOffset)
            }
            scrollRuntime.currentContentOffset = preservedOffset
        } else {
            withAnimation(.spring(duration: 0.26, bounce: 0.08)) {
                displayedEntries = entries
            }
            updateLayoutSnapshot()
        }

        restoreViewportIfNeeded()
    }

    func entriesDidPrependNewest(oldIDs: [TimelineFeedEntry.ID], newIDs: [TimelineFeedEntry.ID]) -> Bool {
        guard let firstOldID = oldIDs.first,
              let firstOldIndexInNewEntries = newIDs.firstIndex(of: firstOldID)
        else { return false }
        return firstOldIndexInNewEntries > 0
    }

    func updatePullRefreshState(offset: CGFloat) {
        guard onRefresh != nil else { return }
        let progress = min(max(abs(min(offset, 0)) / abs(pullRefreshTriggerOffset), 0), 1)
        DispatchQueue.main.async {
            if !isPullRefreshing {
                pullRefreshProgress = progress
            }

            if isUserPullingToRefresh && offset <= pullRefreshTriggerOffset {
                isPullRefreshArmed = true
            }
        }
    }

    func handleScrollPhaseChange(_ phase: ScrollPhase) {
        guard onRefresh != nil else { return }
        switch phase {
        case .interacting, .tracking:
            isUserPullingToRefresh = true
        case .decelerating, .animating, .idle:
            let shouldRefresh = isPullRefreshArmed && !isPullRefreshing
            isUserPullingToRefresh = false
            isPullRefreshArmed = false
            if shouldRefresh {
                requestPullRefresh()
            } else if !isPullRefreshing {
                withAnimation(.snappy(duration: 0.16)) {
                    pullRefreshProgress = 0
                }
            }
        @unknown default:
            isUserPullingToRefresh = false
            isPullRefreshArmed = false
        }
    }

    func requestPullRefresh() {
        guard let onRefresh else { return }
        isPullRefreshing = true
        pullRefreshProgress = 1
        Task {
            await onRefresh()
            await MainActor.run {
                withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
                    isPullRefreshing = false
                    pullRefreshProgress = 0
                }
            }
        }
    }

    func preservedContentOffset(
        oldIDs: [TimelineFeedEntry.ID],
        newIDs: [TimelineFeedEntry.ID],
        anchor: TimelineViewportAnchor?
    ) -> CGFloat? {
        guard let anchor,
              let oldIndex = oldIDs.firstIndex(of: anchor.postID),
              let newIndex = newIDs.firstIndex(of: anchor.postID),
              newIndex > oldIndex
        else {
            return nil
        }

        return TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: entries,
            anchor: anchor,
            layoutCache: measuredLayoutCache,
            topContentPadding: topContentPadding,
            anchorLineY: rowAnchorLineY
        )
    }

    func handlePostAppear(_ post: TimelinePost) {
        guard post.id == posts.last?.id else { return }
        onLoadOlderPost?(post.id)
    }

    func closeFloatingPostMenus() {
        withAnimation(.spring(duration: 0.26, bounce: 0.14)) {
            menuState.reset()
        }
    }

    func openMedia(_ media: TimelineMedia, initialTileIndex: Int) {
        closeFloatingPostMenus()
        onOpenMedia(media, initialTileIndex)
    }

    func openURL(_ url: URL) {
        closeFloatingPostMenus()
        onOpenURL(url)
    }

    func handlePostActionEvent(_ event: TimelinePostActionEvent) {
        switch event.phase {
        case .tap:
            handlePostActionTap(event)
        case .longPressBegan:
            showFloatingPostMenu(postID: event.postID, kind: event.kind)
        case .dragChanged(let location):
            menuState.setWindowDragLocation(location)
        case .dragEnded(let location):
            let normalizedLocation = location.map(menuState.normalizedWindowLocation)
            if shouldFinishChoiceMenu(
                endLocation: normalizedLocation,
                menuFrame: menuState.frame,
                selectedChoice: menuState.selectedChoice
            ) {
                finishSelectedChoiceIfNeeded()
            }
        }
    }

    var choiceSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineFeedOverlay"))
            .onChanged { value in
                menuState.setLocalDragLocation(value.location)
            }
            .onEnded { value in
                if shouldFinishChoiceMenu(
                    endLocation: value.location,
                    menuFrame: menuState.frame,
                    selectedChoice: menuState.selectedChoice
                ) {
                    finishSelectedChoiceIfNeeded()
                } else {
                    menuState.clearDragSelection()
                }
            }
    }

    func handlePostActionTap(_ event: TimelinePostActionEvent) {
        switch event.kind {
        case .more:
            withAnimation(.spring(duration: 0.32, bounce: 0.22)) {
                let menu = OpenedPostMenu(postID: event.postID, kind: .more)
                menuState.toggle(menu)
            }
        case .repost, .favorite:
            break
        }
    }

    func showFloatingPostMenu(postID: TimelinePost.ID, kind: TimelinePostActionKind) {
        DispatchQueue.main.async {
            let menu = OpenedPostMenu(postID: postID, kind: kind)
            guard menuState.openedMenu != menu else { return }

            withAnimation(.spring(duration: 0.32, bounce: 0.22)) {
                menuState.open(menu)
            }
        }
    }

    @ViewBuilder
    func floatingPostMenu(_ menu: OpenedPostMenu, menuFrame: CGRect) -> some View {
        switch menu.kind {
        case .more:
            let currentChoice = postActionChoice(at: menuState.dragLocation, in: menuFrame)

            PostActionMenu(selectedChoice: currentChoice) { choice in
                handlePostActionChoice(choice, postID: menu.postID)
            }
            .onChange(of: currentChoice) { _, newValue in
                menuState.selectedChoice = newValue.map(FloatingPostMenuSelection.more)
            }
        case .repost:
            let currentChoice = repostChoice(at: menuState.dragLocation, in: menuFrame)

            RepostChoiceMenu(selectedChoice: currentChoice) {
                closeFloatingPostMenus()
            }
            .onChange(of: currentChoice) { _, newValue in
                menuState.selectedChoice = newValue.map(FloatingPostMenuSelection.repost)
            }
        case .favorite:
            let currentChoice = choice(at: menuState.dragLocation, in: menuFrame, as: FavoriteChoice.self)

            FavoriteChoiceMenu(selectedChoice: currentChoice) {
                closeFloatingPostMenus()
            }
            .onChange(of: currentChoice) { _, newValue in
                menuState.selectedChoice = newValue.map(FloatingPostMenuSelection.favorite)
            }
        }
    }

    func finishSelectedChoiceIfNeeded() {
        guard let openedMenu = menuState.openedMenu,
              let selectedChoice = menuState.selectedChoice
        else {
            closeFloatingPostMenus()
            return
        }

        switch selectedChoice {
        case .more(let choice):
            handlePostActionChoice(choice, postID: openedMenu.postID)
        case .repost, .favorite:
            closeFloatingPostMenus()
        }
    }

    func handlePostActionChoice(_ choice: PostActionChoice, postID: TimelinePost.ID) {
        switch choice {
        case .viewDetails:
            guard let post = posts.first(where: { $0.id == postID }) else {
                closeFloatingPostMenus()
                return
            }

            closeFloatingPostMenus()
            onOpenPost(post)
        case .mute, .bookmark:
            guard let post = posts.first(where: { $0.id == postID }) else {
                closeFloatingPostMenus()
                return
            }

            closeFloatingPostMenus()
            onPostActionChoice(post, choice)
        case .report, .translate, .copyLink, .shareLink:
            closeFloatingPostMenus()
        }
    }

    func displayGap(_ gap: TimelineGap) -> TimelineGap {
        if fetchingGapDirections[gap.id] != nil {
            return gap.replacingState(.fetching)
        }

        return gap
    }

    func displayDirection(for gap: TimelineGap) -> TimelineGapFillDirection {
        fetchingGapDirections[gap.id] ?? fillDirection(for: gap)
    }

    func fillDirection(for gap: TimelineGap) -> TimelineGapFillDirection {
        guard scrollRuntime.viewportSize.height > 0,
              let frame = scrollRuntime.gapFrames[gap.id]
        else { return .older }

        return frame.midY < scrollRuntime.viewportSize.height / 2 ? .newer : .older
    }

    func requestBackfill(for gap: TimelineGap) {
        guard fetchingGapDirections[gap.id] == nil,
              displayedEntries.contains(where: { entry in
                  guard case .gap(let currentGap) = entry else { return false }
                  return currentGap.id == gap.id
              })
        else { return }

        let direction = fillDirection(for: gap)

        withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
            fetchingGapDirections[gap.id] = direction
        }

        if let onBackfillGap {
            Task {
                let didStartBackfill = await onBackfillGap(gap, direction)
                try? await Task.sleep(nanoseconds: 750_000_000)
                await MainActor.run {
                    if didStartBackfill {
                        fetchingGapDirections[gap.id] = nil
                        syncDisplayedEntriesFromSource()
                    } else {
                        fetchingGapDirections[gap.id] = nil
                    }
                }
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if direction == .newer {
                replaceGapWithBackfilledPosts(gap, direction: direction)
            } else {
                withAnimation(.spring(duration: 0.28, bounce: 0.14)) {
                    fetchingGapDirections[gap.id] = nil
                    replaceGapWithBackfilledPosts(gap, direction: direction)
                }
            }
        }
    }

    func replaceGapWithBackfilledPosts(_ gap: TimelineGap, direction: TimelineGapFillDirection) {
        if direction == .newer {
            replaceGapPreservingLowerAnchor(gap)
        } else {
            replaceGapPreservingUpperAnchor(gap, direction: direction)
        }
    }

    func replaceGapPreservingLowerAnchor(_ gap: TimelineGap) {
        guard let index = displayedEntries.firstIndex(where: { entry in
            guard case .gap(let currentGap) = entry else { return false }
            return currentGap.id == gap.id
        }) else { return }

        let targetOffset = scrollRuntime.currentContentOffset + TimelineLayoutEstimator.estimatedReplacementDelta(
            for: gap,
            layoutCache: measuredLayoutCache
        )
        let insertedEntries = gap.backfilledPosts.map(TimelineFeedEntry.post)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil

        withTransaction(transaction) {
            fetchingGapDirections[gap.id] = nil
            displayedEntries.replaceSubrange(index...index, with: insertedEntries)
            if targetOffset > scrollRuntime.currentContentOffset {
                scrollPosition.scrollTo(y: targetOffset)
            }
        }
    }

    func replaceGapPreservingUpperAnchor(_ gap: TimelineGap, direction: TimelineGapFillDirection) {
        guard let index = displayedEntries.firstIndex(where: { entry in
            guard case .gap(let currentGap) = entry else { return false }
            return currentGap.id == gap.id
        }) else { return }

        for post in gap.backfilledPosts {
            insertedPostDirections[post.id] = direction
        }

        let insertedEntries = gap.backfilledPosts.map(TimelineFeedEntry.post)
        displayedEntries.replaceSubrange(index...index, with: insertedEntries)
    }

    func actionMenuPlacement(gearFrame: CGRect, menuSize: CGSize, containerSize: CGSize) -> ActionMenuPlacement {
        let rightInset: CGFloat = 16
        let availableTop = actionMenuTopClearance
        let availableBottom = containerSize.height - bottomChromeClearance
        let menuX = min(
            max(gearFrame.maxX - menuSize.width / 2, menuSize.width / 2 + rightInset),
            containerSize.width - menuSize.width / 2 - rightInset
        )
        let preferredBelowTop = gearFrame.maxY + actionMenuGap

        if preferredBelowTop + menuSize.height <= availableBottom {
            return ActionMenuPlacement(
                center: CGPoint(x: menuX, y: preferredBelowTop + menuSize.height / 2),
                transitionAnchor: .topTrailing
            )
        }

        let preferredAboveTop = gearFrame.minY - actionMenuGap - menuSize.height
        let preferredAboveBottom = gearFrame.minY - actionMenuGap
        let aboveOverflow = max(availableTop - preferredAboveTop, 0)
        let belowOverflow = max(preferredAboveBottom - availableBottom, 0)
        let adjustedAboveTop = preferredAboveTop + aboveOverflow - belowOverflow

        return ActionMenuPlacement(
            center: CGPoint(x: menuX, y: adjustedAboveTop + menuSize.height / 2),
            transitionAnchor: .bottomTrailing
        )
    }

    func repostChoice(at location: CGPoint?, in menuFrame: CGRect) -> RepostChoice? {
        choice(at: location, in: menuFrame, as: RepostChoice.self)
    }

    func postActionChoice(at location: CGPoint?, in menuFrame: CGRect) -> PostActionChoice? {
        guard let location, menuFrame.contains(location) else { return nil }

        var localY = location.y - menuFrame.minY - FloatingMenuMetrics.verticalPadding
        guard localY >= 0 else { return nil }

        for choice in PostActionChoice.allCases {
            if localY < FloatingMenuMetrics.actionRowHeight {
                return choice
            }

            localY -= FloatingMenuMetrics.actionRowHeight

            if choice.followsDivider {
                guard localY >= FloatingMenuMetrics.dividerHeight else { return nil }
                localY -= FloatingMenuMetrics.dividerHeight
            }
        }

        return nil
    }

    func choice<Choice: FloatingChoiceItem>(
        at location: CGPoint?,
        in menuFrame: CGRect,
        as choiceType: Choice.Type
    ) -> Choice? {
        guard let location, menuFrame.contains(location) else { return nil }
        let choices = Array(choiceType.allCases)
        let rowHeight = menuFrame.height / CGFloat(choices.count)
        let index = min(max(Int((location.y - menuFrame.minY) / rowHeight), 0), choices.count - 1)
        return choices[index]
    }

    func shouldFinishChoiceMenu<Choice>(
        endLocation: CGPoint?,
        menuFrame: CGRect?,
        selectedChoice: Choice?
    ) -> Bool {
        guard let endLocation, let menuFrame else {
            return selectedChoice != nil
        }

        return selectedChoice != nil || !menuFrame.contains(endLocation)
    }
}

private struct TimelineGapFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TimelineGap.ID: CGRect] = [:]

    static func reduce(value: inout [TimelineGap.ID: CGRect], nextValue: () -> [TimelineGap.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TimelineViewportSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct TimelinePullRefreshIndicator: View {
    let isRefreshing: Bool
    let progress: CGFloat

    var body: some View {
        let visibleProgress = isRefreshing ? 1 : progress
        HStack(spacing: 8) {
            ProgressView(value: isRefreshing ? nil : visibleProgress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(Color.astrenzaAccent)
                .frame(width: 18, height: 18)

            Text(isRefreshing ? "Updating" : "Pull to update")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .astrenzaGlass(tint: Color.white.opacity(0.06), in: Capsule())
        .scaleEffect(0.92 + visibleProgress * 0.08)
        .opacity(isRefreshing || progress > 0.08 ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.22, bounce: 0.12), value: isRefreshing)
        .animation(.snappy(duration: 0.12), value: progress)
    }
}

private final class TimelineFeedScrollRuntime {
    var currentContentOffset: CGFloat = 0
    var currentViewportAnchor: TimelineViewportAnchor?
    var layoutSnapshot: TimelineLayoutSnapshot?
    var postFrames: [TimelinePost.ID: CGRect] = [:]
    var gapFrames: [TimelineGap.ID: CGRect] = [:]
    var lastReadablePostIDs: [TimelinePost.ID] = []
    var viewportSize: CGSize = .zero
    var lastSavedViewportAnchor: TimelineViewportAnchor?
    var lastSavedViewportOffset: CGFloat = 0
    var lastViewportSaveTime: TimeInterval = 0
}

private struct ActionMenuPlacement {
    let center: CGPoint
    let transitionAnchor: UnitPoint
}
