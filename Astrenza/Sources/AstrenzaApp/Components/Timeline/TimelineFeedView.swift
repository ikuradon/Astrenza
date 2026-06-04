import SwiftUI

struct TimelineFeedView: View {
    let posts: [TimelinePost]
    let actionMenuTopClearance: CGFloat
    let swipeSettings: TimelineSwipeSettings
    let onOpenPost: (TimelinePost) -> Void
    let onOpenProfile: (TimelinePost) -> Void
    let onReplyPost: (TimelinePost) -> Void
    let onOpenMedia: (TimelineMedia) -> Void
    let onOpenURL: (URL) -> Void
    let onScrollOffsetChanged: (CGFloat) -> Void
    @State private var menuState = TimelinePostMenuState()
    private let actionMenuGap: CGFloat = 12
    private let bottomChromeClearance: CGFloat = 116

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
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
                    .zIndex(menuState.openedMenu?.postID == post.id ? 20 : 0)
                }
            }
            .padding(.top, 72)
            .padding(.bottom, 124)
        }
        .coordinateSpace(name: "timelineFeedOverlay")
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            onScrollOffsetChanged(offset)
        }
        .scrollDisabled(menuState.isOpen)
        .scrollIndicators(.visible)
        .background(Color.astrenzaBackground)
        .accessibilityIdentifier("timeline.feed")
        .overlayPreferenceValue(TimelinePostActionAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ZStack {
                    if let openedPostMenu = menuState.openedMenu,
                       let anchor = anchors[TimelinePostActionAnchorID(postID: openedPostMenu.postID, kind: openedPostMenu.kind)] {
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

    private func closeFloatingPostMenus() {
        withAnimation(.spring(duration: 0.26, bounce: 0.14)) {
            menuState.reset()
        }
    }

    private func openMedia(_ media: TimelineMedia) {
        closeFloatingPostMenus()
        onOpenMedia(media)
    }

    private func openURL(_ url: URL) {
        closeFloatingPostMenus()
        onOpenURL(url)
    }

    private func handlePostActionEvent(_ event: TimelinePostActionEvent) {
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

    private var choiceSelectionGesture: some Gesture {
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

    private func handlePostActionTap(_ event: TimelinePostActionEvent) {
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

    private func showFloatingPostMenu(postID: TimelinePost.ID, kind: TimelinePostActionKind) {
        DispatchQueue.main.async {
            let menu = OpenedPostMenu(postID: postID, kind: kind)
            guard menuState.openedMenu != menu else { return }

            withAnimation(.spring(duration: 0.32, bounce: 0.22)) {
                menuState.open(menu)
            }
        }
    }

    @ViewBuilder
    private func floatingPostMenu(_ menu: OpenedPostMenu, menuFrame: CGRect) -> some View {
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

    private func finishSelectedChoiceIfNeeded() {
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

    private func handlePostActionChoice(_ choice: PostActionChoice, postID: TimelinePost.ID) {
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

    private func actionMenuPlacement(gearFrame: CGRect, menuSize: CGSize, containerSize: CGSize) -> ActionMenuPlacement {
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

    private func repostChoice(at location: CGPoint?, in menuFrame: CGRect) -> RepostChoice? {
        choice(at: location, in: menuFrame, as: RepostChoice.self)
    }

    private func postActionChoice(at location: CGPoint?, in menuFrame: CGRect) -> PostActionChoice? {
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

    private func choice<Choice: FloatingChoiceItem>(at location: CGPoint?, in menuFrame: CGRect, as choiceType: Choice.Type) -> Choice? {
        guard let location, menuFrame.contains(location) else { return nil }
        let choices = Array(choiceType.allCases)
        let rowHeight = menuFrame.height / CGFloat(choices.count)
        let index = min(max(Int((location.y - menuFrame.minY) / rowHeight), 0), choices.count - 1)
        return choices[index]
    }

    private func shouldFinishChoiceMenu<Choice>(
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

private struct ActionMenuPlacement {
    let center: CGPoint
    let transitionAnchor: UnitPoint
}
