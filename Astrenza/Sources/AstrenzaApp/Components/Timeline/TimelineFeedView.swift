import SwiftUI

struct TimelineFeedView: View {
    let entries: [TimelineFeedEntry]
    let actionMenuTopClearance: CGFloat
    let swipeSettings: TimelineSwipeSettings
    let viewportState: TimelineViewportState?
    let layoutCache: TimelineLayoutCache
    let emptyState: TimelineEmptyState
    let onEmptyStatePrimaryAction: () -> Void
    let onEmptyStateSecondaryAction: (() -> Void)?
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
    let onOpenURL: (URL) -> Void
    let onRefresh: (() async -> Void)?
    let onLoadOlderPost: ((TimelinePost.ID) -> Void)?
    let onScrollOffsetChanged: (CGFloat) -> Void
    let onViewportStateChanged: (TimelineViewportState) -> Void
    let onLayoutCacheChanged: (TimelineLayoutCache) -> Void
    @State private var menuState = TimelinePostMenuState()
    @State private var didRestoreViewport = false
    @State private var currentContentOffset: CGFloat = 0
    @State private var measuredLayoutCache = TimelineLayoutCache()
    @State private var scrollPosition = ScrollPosition(idType: TimelinePost.ID.self)
    @State private var isRestoringViewport = false
    @State private var currentViewportAnchor: TimelineViewportAnchor?
    @State private var displayedEntries: [TimelineFeedEntry]
    @State private var fetchingGapDirections: [TimelineGap.ID: TimelineGapFillDirection] = [:]
    @State private var insertedPostDirections: [TimelinePost.ID: TimelineGapFillDirection] = [:]
    @State private var gapFrames: [TimelineGap.ID: CGRect] = [:]
    @State private var viewportSize: CGSize = .zero
    private let actionMenuGap: CGFloat = 12
    private let bottomChromeClearance: CGFloat = 116
    private let rowAnchorLineY: CGFloat = 72
    private let topContentPadding: CGFloat = 72
    private var posts: [TimelinePost] {
        displayedEntries.compactMap(\.post)
    }

    init(
        posts: [TimelinePost],
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onRefresh: (() async -> Void)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.init(
            entries: posts.map(TimelineFeedEntry.post),
            actionMenuTopClearance: actionMenuTopClearance,
            swipeSettings: swipeSettings,
            viewportState: viewportState,
            layoutCache: layoutCache,
            emptyState: emptyState,
            onEmptyStatePrimaryAction: onEmptyStatePrimaryAction,
            onEmptyStateSecondaryAction: onEmptyStateSecondaryAction,
            onOpenPost: onOpenPost,
            onOpenProfile: onOpenProfile,
            onReplyPost: onReplyPost,
            onOpenMedia: onOpenMedia,
            onOpenURL: onOpenURL,
            onRefresh: onRefresh,
            onLoadOlderPost: onLoadOlderPost,
            onScrollOffsetChanged: onScrollOffsetChanged,
            onViewportStateChanged: onViewportStateChanged,
            onLayoutCacheChanged: onLayoutCacheChanged
        )
    }

    init(
        entries: [TimelineFeedEntry],
        actionMenuTopClearance: CGFloat,
        swipeSettings: TimelineSwipeSettings,
        viewportState: TimelineViewportState?,
        layoutCache: TimelineLayoutCache,
        emptyState: TimelineEmptyState = .home,
        onEmptyStatePrimaryAction: @escaping () -> Void = {},
        onEmptyStateSecondaryAction: (() -> Void)? = nil,
        onOpenPost: @escaping (TimelinePost) -> Void,
        onOpenProfile: @escaping (TimelinePost) -> Void,
        onReplyPost: @escaping (TimelinePost) -> Void,
        onOpenMedia: @escaping (TimelineMedia) -> Void,
        onOpenURL: @escaping (URL) -> Void,
        onRefresh: (() async -> Void)? = nil,
        onLoadOlderPost: ((TimelinePost.ID) -> Void)? = nil,
        onScrollOffsetChanged: @escaping (CGFloat) -> Void,
        onViewportStateChanged: @escaping (TimelineViewportState) -> Void,
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.entries = entries
        self.actionMenuTopClearance = actionMenuTopClearance
        self.swipeSettings = swipeSettings
        self.viewportState = viewportState
        self.layoutCache = layoutCache
        self.emptyState = emptyState
        self.onEmptyStatePrimaryAction = onEmptyStatePrimaryAction
        self.onEmptyStateSecondaryAction = onEmptyStateSecondaryAction
        self.onOpenPost = onOpenPost
        self.onOpenProfile = onOpenProfile
        self.onReplyPost = onReplyPost
        self.onOpenMedia = onOpenMedia
        self.onOpenURL = onOpenURL
        self.onRefresh = onRefresh
        self.onLoadOlderPost = onLoadOlderPost
        self.onScrollOffsetChanged = onScrollOffsetChanged
        self.onViewportStateChanged = onViewportStateChanged
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
                            .background(rowFrameReader(postID: post.id))
                            .transition(postInsertionTransition(for: post))
                            .zIndex(menuState.openedMenu?.postID == post.id ? 20 : 0)
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
        .refreshable {
            await onRefresh?()
        }
        .coordinateSpace(name: "timelineFeedOverlay")
        .coordinateSpace(name: "timelineFeedViewport")
        .background(viewportSizeReader)
        .onAppear {
            measuredLayoutCache = layoutCache
            restoreViewportIfNeeded()
        }
        .onPreferenceChange(TimelinePostFramePreferenceKey.self, perform: handleRowFrames)
        .onPreferenceChange(TimelineGapFramePreferenceKey.self) { frames in
            gapFrames = frames
        }
        .onPreferenceChange(TimelineViewportSizePreferenceKey.self) { size in
            viewportSize = size
        }
        .onChange(of: entries.map(\.id)) { _, _ in
            syncDisplayedEntriesFromSource()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            handleObservedContentOffset(offset)
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

    func rowFrameReader(postID: TimelinePost.ID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TimelinePostFramePreferenceKey.self,
                value: [postID: proxy.frame(in: .named("timelineFeedViewport"))]
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

    func handleRowFrames(_ frames: [TimelinePost.ID: CGRect]) {
        guard !frames.isEmpty else { return }

        var nextCache = measuredLayoutCache
        nextCache.merge(measuredFrames: frames)

        if nextCache != measuredLayoutCache {
            measuredLayoutCache = nextCache
            onLayoutCacheChanged(nextCache)
        }

        guard let anchor = viewportAnchor(from: frames) else { return }
        currentViewportAnchor = anchor

        guard !isRestoringViewport
        else { return }

        saveViewportStateIfPossible()
    }

    func viewportAnchor(from frames: [TimelinePost.ID: CGRect]) -> TimelineViewportAnchor? {
        let containingAnchorLine = frames.filter { _, frame in
            frame.minY <= rowAnchorLineY && frame.maxY > rowAnchorLineY
        }

        if let anchor = containingAnchorLine.max(by: { lhs, rhs in lhs.value.minY < rhs.value.minY }) {
            return TimelineViewportAnchor(postID: anchor.key, offset: max(0, rowAnchorLineY - anchor.value.minY))
        }

        if let nextVisible = frames
            .filter({ _, frame in frame.minY > rowAnchorLineY })
            .min(by: { lhs, rhs in lhs.value.minY < rhs.value.minY }) {
            return TimelineViewportAnchor(postID: nextVisible.key, offset: 0)
        }

        return frames
            .max(by: { lhs, rhs in lhs.value.maxY < rhs.value.maxY })
            .map { postID, frame in
                TimelineViewportAnchor(postID: postID, offset: max(0, rowAnchorLineY - frame.minY))
            }
    }

    func saveViewportStateIfPossible() {
        guard !isRestoringViewport,
              let currentViewportAnchor
        else { return }

        onViewportStateChanged(
            TimelineViewportState(
                accountID: viewportState?.accountID ?? "mock-account",
                timelineKey: viewportState?.timelineKey ?? "home",
                anchorPostID: currentViewportAnchor.postID,
                anchorOffset: currentViewportAnchor.offset,
                contentOffset: currentContentOffset,
                updatedAt: Date()
            )
        )
    }

    func handleObservedContentOffset(_ offset: CGFloat) {
        currentContentOffset = offset
        onScrollOffsetChanged(offset)
        saveViewportStateIfPossible()
    }

    func syncDisplayedEntriesFromSource() {
        guard fetchingGapDirections.isEmpty else { return }

        let oldIDs = displayedEntries.map(\.id)
        let newIDs = entries.map(\.id)
        guard oldIDs != newIDs else { return }

        withAnimation(.spring(duration: 0.26, bounce: 0.08)) {
            displayedEntries = entries
        }

        restoreViewportIfNeeded()
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

    func openMedia(_ media: TimelineMedia) {
        closeFloatingPostMenus()
        onOpenMedia(media)
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
        case .report, .mute, .translate, .bookmark, .copyLink, .shareLink:
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
        guard viewportSize.height > 0,
              let frame = gapFrames[gap.id]
        else { return .older }

        return frame.midY < viewportSize.height / 2 ? .newer : .older
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

        let targetOffset = currentContentOffset + TimelineLayoutEstimator.estimatedReplacementDelta(
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
            if targetOffset > currentContentOffset {
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

private struct TimelinePostFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TimelinePost.ID: CGRect] = [:]

    static func reduce(value: inout [TimelinePost.ID: CGRect], nextValue: () -> [TimelinePost.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
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

private struct ActionMenuPlacement {
    let center: CGPoint
    let transitionAnchor: UnitPoint
}
