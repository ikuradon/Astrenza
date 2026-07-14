import Foundation
import SwiftUI

struct TimelineFeedView: View {
    let entries: [TimelineFeedEntry]
    let sourceIdentity: String
    let sourceRevision: Int
    let actionMenuTopClearance: CGFloat
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let scrollCommand: TimelineScrollCommand?
    let viewportRestoreProtectionActive: Bool
    let followsRealtimeEntries: Bool
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
    let onRefresh: (() async -> Bool)?
    let onLoadOlderPost: ((TimelinePost.ID) -> Void)?
    let onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)?
    let onScrollOffsetChanged: (CGFloat) -> Void
    let onScrollActivityChanged: (Bool) -> Void
    let onViewportRestoreCompleted: (CGFloat) -> Void
    let onViewportStateChanged: (TimelineViewportState) -> Void
    let onReadablePostIDsChanged: ([TimelinePost.ID]) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void
    @State private var menuState = TimelinePostMenuState()
    @State private var didRestoreViewport = false
    @State private var scrollPosition = ScrollPosition(idType: TimelinePost.ID.self)
    @State private var isRestoringViewport = false
    @State private var viewportRestoreGeneration: UInt64 = 0
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
    private var sourceChangeToken: TimelineFeedSourceChangeToken {
        TimelineFeedSourceChangeToken(
            sourceIdentity: sourceIdentity,
            revision: sourceRevision,
            entryCount: entries.count,
            firstEntryID: entries.first?.id,
            lastEntryID: entries.last?.id
        )
    }

    init(
        posts: [TimelinePost],
        sourceIdentity: String = "timeline",
        sourceRevision: Int = 0,
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        viewportRestoreProtectionActive: Bool = false,
        followsRealtimeEntries: Bool = false,
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
        onRefresh: (() async -> Bool)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onScrollActivityChanged: @escaping (Bool) -> Void = { _ in },
        onViewportRestoreCompleted: @escaping (CGFloat) -> Void = { _ in },
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onReadablePostIDsChanged: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.init(
            entries: posts.map(TimelineFeedEntry.post),
            sourceIdentity: sourceIdentity,
            sourceRevision: sourceRevision,
            actionMenuTopClearance: actionMenuTopClearance,
            swipeSettings: swipeSettings,
            viewportState: viewportState,
            scrollCommand: scrollCommand,
            viewportRestoreProtectionActive: viewportRestoreProtectionActive,
            followsRealtimeEntries: followsRealtimeEntries,
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
            onScrollActivityChanged: onScrollActivityChanged,
            onViewportRestoreCompleted: onViewportRestoreCompleted,
            onViewportStateChanged: onViewportStateChanged,
            onReadablePostIDsChanged: onReadablePostIDsChanged,
            onLayoutCacheChanged: onLayoutCacheChanged
        )
    }

    init(
        entries: [TimelineFeedEntry],
        sourceIdentity: String = "timeline",
        sourceRevision: Int = 0,
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        scrollCommand: TimelineScrollCommand? = nil,
        viewportRestoreProtectionActive: Bool = false,
        followsRealtimeEntries: Bool = false,
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
        onRefresh: (() async -> Bool)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onBackfillGap: ((TimelineGap, TimelineGapFillDirection) async -> Bool)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onScrollActivityChanged: @escaping (Bool) -> Void = { _ in },
        onViewportRestoreCompleted: @escaping (CGFloat) -> Void = { _ in },
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onReadablePostIDsChanged: @escaping ([TimelinePost.ID]) -> Void = { _ in },
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.entries = entries
        self.sourceIdentity = sourceIdentity
        self.sourceRevision = sourceRevision
        self.actionMenuTopClearance = actionMenuTopClearance
        self.swipeSettings = swipeSettings
        self.viewportState = viewportState
        self.scrollCommand = scrollCommand
        self.viewportRestoreProtectionActive = viewportRestoreProtectionActive
        self.followsRealtimeEntries = followsRealtimeEntries
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
        self.onScrollActivityChanged = onScrollActivityChanged
        self.onViewportRestoreCompleted = onViewportRestoreCompleted
        self.onViewportStateChanged = onViewportStateChanged
        self.onReadablePostIDsChanged = onReadablePostIDsChanged
        self.onLayoutCacheChanged = onLayoutCacheChanged
        _displayedEntries = State(initialValue: entries)
        let initialScrollRuntime = TimelineFeedScrollRuntime()
        initialScrollRuntime.rebuildPostIndex(entries: entries)
        initialScrollRuntime.layoutSnapshot = TimelineLayoutSnapshot(
            entries: entries,
            layoutCache: layoutCache,
            topContentPadding: 72
        )
        _scrollRuntime = State(initialValue: initialScrollRuntime)
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
                            .background(
                                postFrameReader(
                                    postID: post.id,
                                    measurementGeneration: scrollRuntime.measurementGenerationByPostID[post.id] ?? 0
                                )
                                .id(scrollRuntime.measurementGenerationByPostID[post.id] ?? 0)
                            )
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
            scrollRuntime.measuredLayoutCache = layoutCache
            scrollRuntime.latestSourceChangeToken = sourceChangeToken
            refreshPostOrderAndPruneRuntimeState()
            updateLayoutSnapshot()
            restoreViewportIfNeeded()
        }
        .onPreferenceChange(TimelineGapFramePreferenceKey.self) { frames in
            scrollRuntime.gapFrames = frames
        }
        .onPreferenceChange(TimelineViewportSizePreferenceKey.self) { size in
            scrollRuntime.viewportSize = size
        }
        .onChange(of: sourceChangeToken) { _, newToken in
            syncDisplayedEntriesFromSource(forceContentUpdate: true, sourceToken: newToken)
        }
        .onChange(of: viewportState) { _, _ in
            if viewportRestoreProtectionActive, viewportState != nil {
                prepareViewportRestoreForNewRequest()
            }
            restoreViewportIfNeeded()
        }
        .onChange(of: viewportRestoreProtectionActive) { _, isActive in
            if isActive {
                restoreViewportIfNeeded()
            } else {
                cancelInitialViewportRestore()
            }
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
        .onDisappear {
            cancelPendingContentHeightAnchorCorrection()
            cancelInitialViewportRestore()
            if scrollRuntime.isUserScrollActive {
                scrollRuntime.isUserScrollActive = false
                onScrollActivityChanged(false)
            }
            flushPendingLayoutCacheChanges()
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

    func postFrameReader(
        postID: TimelinePost.ID,
        measurementGeneration: UInt64
    ) -> some View {
        Color.clear
            .onGeometryChange(for: TimelinePostGeometryState.self) { proxy in
                let frame = proxy.frame(in: .named("timelineFeedViewport"))
                return TimelinePostGeometryState(
                    height: frame.height,
                    isReadable: frame.minY <= topContentPadding + 24 && frame.maxY > 0
                )
            } action: { _, geometryState in
                updateMeasuredPostGeometry(
                    postID: postID,
                    measurementGeneration: measurementGeneration,
                    geometryState: geometryState
                )
            }
    }

    func updateMeasuredPostGeometry(
        postID: TimelinePost.ID,
        measurementGeneration: UInt64,
        geometryState: TimelinePostGeometryState
    ) {
        guard scrollRuntime.postOrderByID[postID] != nil else { return }
        let expectedMeasurementGeneration = scrollRuntime.measurementGenerationByPostID[postID] ?? 0
        if measurementGeneration == expectedMeasurementGeneration,
           scrollRuntime.measuredLayoutCache.recordMeasuredHeight(geometryState.height, for: postID) {
            if scrollRuntime.layoutSnapshot?.recordMeasuredHeight(geometryState.height, for: postID) != true {
                updateLayoutSnapshot()
            }
            scheduleLayoutCachePublish()
            handleContentHeightRemeasurement(
                postID: postID,
                measurementGeneration: measurementGeneration
            )
        }

        let membershipChanged: Bool
        if geometryState.isReadable {
            membershipChanged = scrollRuntime.readablePostIDs.insert(postID).inserted
        } else {
            membershipChanged = scrollRuntime.readablePostIDs.remove(postID) != nil
        }
        if membershipChanged {
            notifyReadablePostIDs()
        }
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
        guard viewportRestoreProtectionActive,
              !didRestoreViewport,
              !isRestoringViewport,
              let viewportState,
              scrollRuntime.postOrderByID[viewportState.anchorPostID] != nil
        else { return }

        cancelPendingContentHeightAnchorCorrection()
        isRestoringViewport = true
        viewportRestoreGeneration &+= 1
        let restoreGeneration = viewportRestoreGeneration
        let targetOffsetY = scrollRuntime.layoutSnapshot.flatMap { snapshot in
            TimelineViewportResolver.restoredContentOffsetY(
                snapshot: snapshot,
                state: viewportState,
                anchorLineY: rowAnchorLineY
            )
        }

        DispatchQueue.main.async {
            guard viewportRestoreGeneration == restoreGeneration else { return }
            if let targetOffsetY {
                scrollPosition.scrollTo(y: targetOffsetY)
            } else {
                scrollPosition.scrollTo(id: viewportState.anchorPostID, anchor: .top)
            }
            didRestoreViewport = true

            DispatchQueue.main.async {
                guard viewportRestoreGeneration == restoreGeneration else { return }
                isRestoringViewport = false
                onViewportRestoreCompleted(targetOffsetY ?? viewportState.contentOffset)
            }
        }
    }

    func cancelInitialViewportRestore() {
        viewportRestoreGeneration &+= 1
        isRestoringViewport = false
        if viewportRestoreProtectionActive {
            return
        }
        didRestoreViewport = true
    }

    func estimatedViewportAnchor(at contentOffset: CGFloat) -> TimelineViewportAnchor? {
        scrollRuntime.layoutSnapshot?.anchor(at: contentOffset, anchorLineY: rowAnchorLineY)
    }

    func updateLayoutSnapshot() {
        scrollRuntime.layoutSnapshot = TimelineLayoutSnapshot(
            entries: displayedEntries,
            layoutCache: scrollRuntime.measuredLayoutCache,
            topContentPadding: topContentPadding
        )
    }

    func saveViewportStateIfPossible(force: Bool = false) {
        guard TimelineFeedViewportRestorePolicy.canSaveViewport(
            isRestoreProtected: viewportRestoreProtectionActive,
            didRestoreViewport: didRestoreViewport,
            isRestoringViewport: isRestoringViewport
        ) else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let offsetDelta = abs(scrollRuntime.currentContentOffset - scrollRuntime.lastSavedViewportOffset)
        if !force,
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
    }

    func notifyReadablePostIDs() {
        let readableIDs = scrollRuntime.readablePostIDs.sorted { lhs, rhs in
            let lhsOrder = scrollRuntime.postOrderByID[lhs] ?? .max
            let rhsOrder = scrollRuntime.postOrderByID[rhs] ?? .max
            return lhsOrder == rhsOrder ? lhs < rhs : lhsOrder < rhsOrder
        }
        guard readableIDs != scrollRuntime.lastReadablePostIDs else { return }
        scrollRuntime.lastReadablePostIDs = readableIDs
        DispatchQueue.main.async {
            onReadablePostIDsChanged(readableIDs)
        }
    }

    func handleScrollCommand() {
        guard let scrollCommand else { return }
        cancelPendingContentHeightAnchorCorrection()
        viewportRestoreGeneration &+= 1
        isRestoringViewport = false
        didRestoreViewport = true
        switch scrollCommand.target {
        case .top:
            scrollPosition.scrollTo(y: 0)
        case .viewport(let state):
            let targetOffsetY = scrollRuntime.layoutSnapshot.flatMap { snapshot in
                TimelineViewportResolver.restoredContentOffsetY(
                    snapshot: snapshot,
                    state: state,
                    anchorLineY: rowAnchorLineY
                )
            }
            if let targetOffsetY {
                scrollPosition.scrollTo(y: targetOffsetY)
            } else {
                scrollPosition.scrollTo(id: state.anchorPostID, anchor: .top)
            }
        }
    }

    func syncDisplayedEntriesFromSource(
        forceContentUpdate: Bool = false,
        sourceToken: TimelineFeedSourceChangeToken? = nil
    ) {
        let incomingSourceToken = sourceToken ?? sourceChangeToken
        if let previousSourceIdentity = scrollRuntime.latestSourceChangeToken?.sourceIdentity,
           previousSourceIdentity != incomingSourceToken.sourceIdentity {
            clearPullRefreshAnchor()
            prepareViewportRestoreForNewRequest()
        }
        if scrollRuntime.latestSourceChangeToken != incomingSourceToken {
            cancelPendingContentHeightAnchorCorrection()
            scrollRuntime.latestSourceChangeToken = incomingSourceToken
        }

        if !fetchingGapDirections.isEmpty {
            let sourceGapIDs = Set(entries.compactMap { entry -> TimelineGap.ID? in
                guard case .gap(let gap) = entry else { return nil }
                return gap.id
            })
            fetchingGapDirections = fetchingGapDirections.filter { sourceGapIDs.contains($0.key) }
            guard fetchingGapDirections.isEmpty else { return }
        }

        let hasSameEntryIDs = displayedEntries.count == entries.count &&
            zip(displayedEntries, entries).allSatisfy { oldEntry, newEntry in
                oldEntry.id == newEntry.id
            }
        guard !hasSameEntryIDs || forceContentUpdate else { return }

        if hasSameEntryIDs {
            let anchor = scrollRuntime.isScrollActive || isRestoringViewport
                ? nil
                : estimatedViewportAnchor(at: scrollRuntime.currentContentOffset)
            let changedPostIDs = TimelineContentHeightAnchorPlanner.changedPostIDs(
                oldEntries: displayedEntries,
                newEntries: entries
            )
            let correctionGeneration = prepareContentHeightAnchorCorrection(
                entries: entries,
                anchor: anchor,
                changedPostIDs: changedPostIDs,
                sourceToken: incomingSourceToken
            )
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedEntries = entries
                if scrollRuntime.layoutSnapshot == nil {
                    updateLayoutSnapshot()
                }
            }
            if let correctionGeneration {
                scheduleContentHeightAnchorCorrection(generation: correctionGeneration)
                scheduleContentHeightAnchorCorrectionSettle(generation: correctionGeneration)
            }
            restoreViewportIfNeeded()
            return
        }

        let oldIDs = displayedEntries.map(\.id)
        let newIDs = entries.map(\.id)
        let pullRefreshGeneration = scrollRuntime.pullRefreshGeneration
        let isPullRefreshSourceChange = scrollRuntime.pullRefreshAnchor != nil &&
            scrollRuntime.pullRefreshSourceToken != incomingSourceToken
        let pullRefreshAnchor = isPullRefreshSourceChange
            ? scrollRuntime.pullRefreshAnchor.flatMap { anchor in
                TimelinePullRefreshAnchorPolicy.prependedAnchor(
                    anchor,
                    oldIDs: oldIDs,
                    newIDs: newIDs
                )
            }
            : nil
        let shouldPreserveAnchorForPullRefresh = scrollRuntime.pullRefreshAnchor != nil ||
            isPullRefreshing || isPullRefreshArmed || isUserPullingToRefresh || pullRefreshProgress > 0
        let shouldFollowNewestEntries = TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: followsRealtimeEntries,
            isPullRefreshProtected: shouldPreserveAnchorForPullRefresh,
            isRestoreProtected: viewportRestoreProtectionActive,
            didRestoreViewport: didRestoreViewport,
            isRestoringViewport: isRestoringViewport
        ) &&
            entriesDidPrependNewest(oldIDs: oldIDs, newIDs: newIDs)
        let anchor = pullRefreshAnchor ?? estimatedViewportAnchor(at: scrollRuntime.currentContentOffset)
        let anchorToPreserve: TimelineViewportAnchor?
        if !shouldFollowNewestEntries,
           let anchor,
           let oldAnchorIndex = oldIDs.firstIndex(of: anchor.postID),
           let newAnchorIndex = newIDs.firstIndex(of: anchor.postID),
           newAnchorIndex > oldAnchorIndex {
            anchorToPreserve = anchor
        } else {
            anchorToPreserve = nil
        }
        var structurallyChangedPostIDs = anchorToPreserve.map { anchor in
            TimelineContentHeightAnchorPlanner.changedCommonPostIDsAffectingAnchor(
                oldEntries: displayedEntries,
                newEntries: entries,
                anchorPostID: anchor.postID
            )
        } ?? []
        if let anchorToPreserve {
            structurallyChangedPostIDs.formUnion(
                TimelineContentHeightAnchorPlanner.insertedPostIDsAffectingAnchor(
                    oldEntries: displayedEntries,
                    newEntries: entries,
                    anchorPostID: anchorToPreserve.postID
                )
            )
        }
        let correctionGeneration = prepareContentHeightAnchorCorrection(
            entries: entries,
            anchor: anchorToPreserve,
            changedPostIDs: structurallyChangedPostIDs,
            sourceToken: incomingSourceToken
        )
        let preservedOffset = preservedContentOffset(
            oldIDs: oldIDs,
            newIDs: newIDs,
            anchor: anchorToPreserve
        )

        if shouldFollowNewestEntries {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedEntries = entries
                didUpdateDisplayedEntries()
                scrollPosition.scrollTo(y: 0)
            }
            scrollRuntime.currentContentOffset = 0
        } else if let preservedOffset {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            transaction.scrollContentOffsetAdjustmentBehavior = .disabled
            withTransaction(transaction) {
                displayedEntries = entries
                didUpdateDisplayedEntries()
                scrollPosition.scrollTo(y: preservedOffset)
            }
            scrollRuntime.currentContentOffset = preservedOffset
        } else {
            withAnimation(.spring(duration: 0.26, bounce: 0.08)) {
                displayedEntries = entries
            }
            didUpdateDisplayedEntries()
        }

        if isPullRefreshSourceChange {
            clearPullRefreshAnchor(generation: pullRefreshGeneration)
        }

        if let correctionGeneration {
            scheduleContentHeightAnchorCorrection(generation: correctionGeneration)
            scheduleContentHeightAnchorCorrectionSettle(generation: correctionGeneration)
        }

        restoreViewportIfNeeded()
    }

    func prepareViewportRestoreForNewRequest() {
        viewportRestoreGeneration &+= 1
        isRestoringViewport = false
        didRestoreViewport = !viewportRestoreProtectionActive
    }

    func prepareContentHeightAnchorCorrection(
        entries newEntries: [TimelineFeedEntry],
        anchor: TimelineViewportAnchor?,
        changedPostIDs: Set<TimelinePost.ID>,
        sourceToken: TimelineFeedSourceChangeToken
    ) -> UInt64? {
        guard !changedPostIDs.isEmpty else { return nil }

        cancelPendingContentHeightAnchorCorrection()
        let generation = scrollRuntime.contentHeightCorrectionGeneration
        for postID in changedPostIDs {
            scrollRuntime.measurementGenerationByPostID[postID] = generation
        }

        if scrollRuntime.measuredLayoutCache.invalidate(postIDs: changedPostIDs) {
            scheduleLayoutCachePublish()
        }
        if scrollRuntime.layoutSnapshot != nil {
            for entry in newEntries {
                guard case .post(let post) = entry,
                      changedPostIDs.contains(post.id)
                else { continue }
                _ = scrollRuntime.layoutSnapshot?.recordMeasuredHeight(
                    scrollRuntime.measuredLayoutCache.height(for: post),
                    for: post.id
                )
            }
        }

        guard let anchor,
              !scrollRuntime.isScrollActive,
              !scrollRuntime.isUserScrollActive,
              !isRestoringViewport,
              newEntries.contains(where: { $0.post?.id == anchor.postID })
        else { return nil }

        let affectingPostIDs = TimelineContentHeightAnchorPlanner.changedPostIDsAffectingAnchor(
            entries: newEntries,
            changedPostIDs: changedPostIDs,
            anchorPostID: anchor.postID
        )
        guard !affectingPostIDs.isEmpty else { return nil }

        scrollRuntime.pendingContentHeightAnchorCorrection = TimelinePendingContentHeightAnchorCorrection(
            generation: generation,
            sourceToken: sourceToken,
            anchor: anchor,
            awaitingPostIDs: affectingPostIDs
        )
        return generation
    }

    func handleContentHeightRemeasurement(
        postID: TimelinePost.ID,
        measurementGeneration: UInt64
    ) {
        guard var pendingCorrection = scrollRuntime.pendingContentHeightAnchorCorrection,
              pendingCorrection.generation == measurementGeneration,
              pendingCorrection.awaitingPostIDs.remove(postID) != nil
        else { return }

        scrollRuntime.pendingContentHeightAnchorCorrection = pendingCorrection
        scheduleContentHeightAnchorCorrection(generation: pendingCorrection.generation)
        scheduleContentHeightAnchorCorrectionSettle(generation: pendingCorrection.generation)
    }

    func scheduleContentHeightAnchorCorrection(generation: UInt64) {
        guard !scrollRuntime.isContentHeightAnchorCorrectionScheduled,
              scrollRuntime.pendingContentHeightAnchorCorrection?.generation == generation
        else { return }

        let runtime = scrollRuntime
        runtime.isContentHeightAnchorCorrectionScheduled = true
        DispatchQueue.main.async {
            guard runtime.contentHeightCorrectionGeneration == generation,
                  runtime.pendingContentHeightAnchorCorrection?.generation == generation
            else { return }

            runtime.isContentHeightAnchorCorrectionScheduled = false
            applyContentHeightAnchorCorrection(generation: generation)
        }
    }

    func scheduleContentHeightAnchorCorrectionSettle(generation: UInt64) {
        scrollRuntime.contentHeightAnchorCorrectionSettleTask?.cancel()
        let runtime = scrollRuntime
        runtime.contentHeightAnchorCorrectionSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled,
                  runtime.contentHeightCorrectionGeneration == generation,
                  runtime.pendingContentHeightAnchorCorrection?.generation == generation
            else { return }

            applyContentHeightAnchorCorrection(generation: generation, finish: true)
        }
    }

    func applyContentHeightAnchorCorrection(
        generation: UInt64,
        finish: Bool = false
    ) {
        guard let pendingCorrection = scrollRuntime.pendingContentHeightAnchorCorrection,
              pendingCorrection.generation == generation,
              scrollRuntime.contentHeightCorrectionGeneration == generation,
              scrollRuntime.latestSourceChangeToken == pendingCorrection.sourceToken,
              !scrollRuntime.isUserScrollActive
        else { return }

        if let snapshot = scrollRuntime.layoutSnapshot,
           let targetOffset = TimelineViewportResolver.contentOffsetPreservingAnchor(
            snapshot: snapshot,
            anchor: pendingCorrection.anchor,
            anchorLineY: rowAnchorLineY
           ), abs(targetOffset - scrollRuntime.currentContentOffset) > 0.5 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                scrollPosition.scrollTo(y: targetOffset)
            }
            scrollRuntime.currentContentOffset = targetOffset
        }

        if finish {
            scrollRuntime.contentHeightAnchorCorrectionSettleTask = nil
            scrollRuntime.pendingContentHeightAnchorCorrection = nil
        }
    }

    func cancelPendingContentHeightAnchorCorrection() {
        scrollRuntime.contentHeightCorrectionGeneration &+= 1
        scrollRuntime.isContentHeightAnchorCorrectionScheduled = false
        scrollRuntime.pendingContentHeightAnchorCorrection = nil
        scrollRuntime.contentHeightAnchorCorrectionSettleTask?.cancel()
        scrollRuntime.contentHeightAnchorCorrectionSettleTask = nil
    }

    func entriesDidPrependNewest(oldIDs: [TimelineFeedEntry.ID], newIDs: [TimelineFeedEntry.ID]) -> Bool {
        guard let firstOldID = oldIDs.first,
              let firstOldIndexInNewEntries = newIDs.firstIndex(of: firstOldID)
        else { return false }
        return firstOldIndexInNewEntries > 0
    }

    func didUpdateDisplayedEntries() {
        refreshPostOrderAndPruneRuntimeState()
        updateLayoutSnapshot()
    }

    func refreshPostOrderAndPruneRuntimeState() {
        let validPostIDs = scrollRuntime.rebuildPostIndex(entries: displayedEntries)

        let previousHeightCount = scrollRuntime.measuredLayoutCache.measuredHeights.count
        scrollRuntime.measuredLayoutCache.prune(keeping: validPostIDs)
        if scrollRuntime.measuredLayoutCache.measuredHeights.count != previousHeightCount {
            scheduleLayoutCachePublish()
        }

        scrollRuntime.readablePostIDs.formIntersection(validPostIDs)
        notifyReadablePostIDs()

        scrollRuntime.measurementGenerationByPostID = scrollRuntime.measurementGenerationByPostID.filter {
            validPostIDs.contains($0.key)
        }

        let retainedInsertionDirections = insertedPostDirections.filter { validPostIDs.contains($0.key) }
        if retainedInsertionDirections.count != insertedPostDirections.count {
            insertedPostDirections = retainedInsertionDirections
        }
    }

    func scheduleLayoutCachePublish() {
        scrollRuntime.hasPendingLayoutCacheChanges = true
        scrollRuntime.layoutCachePublishTask?.cancel()
        scrollRuntime.layoutCachePublishTask = nil
        guard !scrollRuntime.isScrollActive else { return }

        let runtime = scrollRuntime
        let callback = onLayoutCacheChanged
        runtime.layoutCachePublishTask = Task { @MainActor [weak runtime] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let runtime,
                  runtime.hasPendingLayoutCacheChanges,
                  !runtime.isScrollActive
            else { return }

            runtime.hasPendingLayoutCacheChanges = false
            runtime.layoutCachePublishTask = nil
            callback(runtime.measuredLayoutCache)
        }
    }

    func flushPendingLayoutCacheChanges() {
        scrollRuntime.layoutCachePublishTask?.cancel()
        scrollRuntime.layoutCachePublishTask = nil
        guard scrollRuntime.hasPendingLayoutCacheChanges else { return }
        scrollRuntime.hasPendingLayoutCacheChanges = false
        onLayoutCacheChanged(scrollRuntime.measuredLayoutCache)
    }

    func updateLayoutCacheScrollActivity(_ phase: ScrollPhase) {
        let isScrollActive: Bool
        switch phase {
        case .idle:
            isScrollActive = false
        case .tracking, .interacting, .decelerating, .animating:
            isScrollActive = true
        @unknown default:
            isScrollActive = true
        }

        guard scrollRuntime.isScrollActive != isScrollActive else { return }
        scrollRuntime.isScrollActive = isScrollActive
        if isScrollActive {
            scrollRuntime.layoutCachePublishTask?.cancel()
            scrollRuntime.layoutCachePublishTask = nil
        } else if scrollRuntime.hasPendingLayoutCacheChanges {
            scheduleLayoutCachePublish()
        }
    }

    func updateContentHeightAnchorCorrectionScrollActivity(_ phase: ScrollPhase) {
        let wasUserScrollActive = scrollRuntime.isUserScrollActive
        switch phase {
        case .idle:
            scrollRuntime.isUserScrollActive = false
        case .tracking, .interacting, .decelerating:
            scrollRuntime.isUserScrollActive = true
            cancelPendingContentHeightAnchorCorrection()
        case .animating:
            break
        @unknown default:
            scrollRuntime.isUserScrollActive = true
            cancelPendingContentHeightAnchorCorrection()
        }
        if scrollRuntime.isUserScrollActive != wasUserScrollActive {
            onScrollActivityChanged(scrollRuntime.isUserScrollActive)
        }
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
        updateContentHeightAnchorCorrectionScrollActivity(phase)
        updateLayoutCacheScrollActivity(phase)
        if phase == .idle {
            saveViewportStateIfPossible(force: true)
        }
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
        let pullRefreshGeneration = beginPullRefreshAnchor()
        isPullRefreshing = true
        pullRefreshProgress = 1
        Task { @MainActor in
            let expectsSourceChange = await onRefresh()
            if !expectsSourceChange {
                clearPullRefreshAnchor(generation: pullRefreshGeneration)
            }
            withAnimation(.spring(duration: 0.24, bounce: 0.12)) {
                isPullRefreshing = false
                pullRefreshProgress = 0
            }
        }
    }

    func beginPullRefreshAnchor() -> UInt64 {
        scrollRuntime.pullRefreshGeneration &+= 1
        scrollRuntime.pullRefreshAnchor = estimatedViewportAnchor(
            at: max(scrollRuntime.currentContentOffset, 0)
        )
        scrollRuntime.pullRefreshSourceToken = scrollRuntime.latestSourceChangeToken ?? sourceChangeToken
        return scrollRuntime.pullRefreshGeneration
    }

    func clearPullRefreshAnchor(generation: UInt64? = nil) {
        if let generation, generation != scrollRuntime.pullRefreshGeneration {
            return
        }
        scrollRuntime.pullRefreshAnchor = nil
        scrollRuntime.pullRefreshSourceToken = nil
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
            layoutCache: scrollRuntime.measuredLayoutCache,
            topContentPadding: topContentPadding,
            anchorLineY: rowAnchorLineY
        )
    }

    func handlePostAppear(_ post: TimelinePost) {
        guard post.id == scrollRuntime.lastPostID else { return }
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
            guard let post = displayedPost(id: postID) else {
                closeFloatingPostMenus()
                return
            }

            closeFloatingPostMenus()
            onOpenPost(post)
        case .mute, .bookmark:
            guard let post = displayedPost(id: postID) else {
                closeFloatingPostMenus()
                return
            }

            closeFloatingPostMenus()
            onPostActionChoice(post, choice)
        case .report, .translate, .copyLink, .shareLink:
            closeFloatingPostMenus()
        }
    }

    func displayedPost(id postID: TimelinePost.ID) -> TimelinePost? {
        for entry in displayedEntries {
            guard case .post(let post) = entry else { continue }
            if post.id == postID {
                return post
            }
        }
        return nil
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
            layoutCache: scrollRuntime.measuredLayoutCache
        )
        let insertedEntries = gap.backfilledPosts.map(TimelineFeedEntry.post)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil

        withTransaction(transaction) {
            fetchingGapDirections[gap.id] = nil
            displayedEntries.replaceSubrange(index...index, with: insertedEntries)
            didUpdateDisplayedEntries()
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
        didUpdateDisplayedEntries()
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

enum TimelineFeedViewportRestorePolicy {
    static func canSaveViewport(
        isRestoreProtected: Bool,
        didRestoreViewport: Bool,
        isRestoringViewport: Bool
    ) -> Bool {
        !isRestoringViewport && (!isRestoreProtected || didRestoreViewport)
    }

    static func canFollowRealtimeEntries(
        isRealtimeEnabled: Bool,
        isPullRefreshProtected: Bool,
        isRestoreProtected: Bool,
        didRestoreViewport: Bool,
        isRestoringViewport: Bool
    ) -> Bool {
        isRealtimeEnabled &&
            !isPullRefreshProtected &&
            !isRestoringViewport &&
            (!isRestoreProtected || didRestoreViewport)
    }
}

private final class TimelineFeedScrollRuntime {
    var currentContentOffset: CGFloat = 0
    var currentViewportAnchor: TimelineViewportAnchor?
    var layoutSnapshot: TimelineLayoutSnapshot?
    var measuredLayoutCache = TimelineLayoutCache()
    var postOrderByID: [TimelinePost.ID: Int] = [:]
    var readablePostIDs = Set<TimelinePost.ID>()
    var gapFrames: [TimelineGap.ID: CGRect] = [:]
    var lastReadablePostIDs: [TimelinePost.ID] = []
    var viewportSize: CGSize = .zero
    var lastSavedViewportAnchor: TimelineViewportAnchor?
    var lastSavedViewportOffset: CGFloat = 0
    var lastViewportSaveTime: TimeInterval = 0
    var hasPendingLayoutCacheChanges = false
    var isScrollActive = false
    var layoutCachePublishTask: Task<Void, Never>?
    var latestSourceChangeToken: TimelineFeedSourceChangeToken?
    var contentHeightCorrectionGeneration: UInt64 = 0
    var measurementGenerationByPostID: [TimelinePost.ID: UInt64] = [:]
    var pendingContentHeightAnchorCorrection: TimelinePendingContentHeightAnchorCorrection?
    var isContentHeightAnchorCorrectionScheduled = false
    var contentHeightAnchorCorrectionSettleTask: Task<Void, Never>?
    var isUserScrollActive = false
    var lastPostID: TimelinePost.ID?
    var pullRefreshGeneration: UInt64 = 0
    var pullRefreshAnchor: TimelineViewportAnchor?
    var pullRefreshSourceToken: TimelineFeedSourceChangeToken?

    @discardableResult
    func rebuildPostIndex(entries: [TimelineFeedEntry]) -> Set<TimelinePost.ID> {
        var nextPostOrderByID: [TimelinePost.ID: Int] = [:]
        var validPostIDs = Set<TimelinePost.ID>()
        var nextLastPostID: TimelinePost.ID?
        nextPostOrderByID.reserveCapacity(entries.count)
        validPostIDs.reserveCapacity(entries.count)
        for entry in entries {
            guard case .post(let post) = entry else { continue }
            nextPostOrderByID[post.id] = nextPostOrderByID.count
            validPostIDs.insert(post.id)
            nextLastPostID = post.id
        }
        postOrderByID = nextPostOrderByID
        lastPostID = nextLastPostID
        return validPostIDs
    }
}

private struct TimelinePendingContentHeightAnchorCorrection {
    let generation: UInt64
    let sourceToken: TimelineFeedSourceChangeToken
    let anchor: TimelineViewportAnchor
    var awaitingPostIDs: Set<TimelinePost.ID>
}

private struct TimelinePostGeometryState: Equatable {
    let height: CGFloat
    let isReadable: Bool
}

private struct TimelineFeedSourceChangeToken: Equatable {
    let sourceIdentity: String
    let revision: Int
    let entryCount: Int
    let firstEntryID: TimelineFeedEntry.ID?
    let lastEntryID: TimelineFeedEntry.ID?
}

private struct ActionMenuPlacement {
    let center: CGPoint
    let transitionAnchor: UnitPoint
}
