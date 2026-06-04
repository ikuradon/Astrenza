import SwiftUI

struct HomeTimelineView: View {
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var isComposerPresented = false
    @State private var composeSheetMode: ComposeSheetMode = .post
    @State private var didCompleteInitialAppearance = false
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var postNavigationPath: [SelectedPostRoute] = []
    @State private var unreadBadgeFrame: CGRect = .zero
    @State private var fullscreenMedia: TimelineMedia?
    @State private var browserDestination: TimelineBrowserDestination?

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
        !postNavigationPath.isEmpty
    }

    var body: some View {
        ZStack {
            Color.astrenzaBackground.ignoresSafeArea()

            nativeTabs
                .simultaneousGesture(
                    TapGesture().onEnded(dismissFloatingMenus)
                )

            if !isPostDetailPresented {
                VStack {
                    HomeTimelineTopBar(
                        visibleTab: visibleTab,
                        selectedTimeline: $selectedTimeline,
                        isTimelineMenuPresented: $isTimelineMenuPresented,
                        isUserSwitcherPresented: $isUserSwitcherPresented,
                        collapseProgress: topChromeCollapseProgress,
                        onDismissFloatingMenus: dismissFloatingMenus
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
        .sheet(isPresented: $isComposerPresented) {
            ComposeSheetView(mode: composeSheetMode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: isFullscreenMediaPresented) {
            if let fullscreenMedia {
                TimelineFullscreenMediaViewer(media: fullscreenMedia) {
                    self.fullscreenMedia = nil
                }
            }
        }
        .sheet(item: $browserDestination) { destination in
            TimelineInAppBrowserView(url: destination.url)
                .ignoresSafeArea()
        }
    }

    private var nativeTabs: some View {
        UIKitTimelineTabView(
            selectedTab: $selectedTab,
            previousTab: $previousTab,
            minimizeDirection: tabBarMinimizeDirection,
            isTabBarHidden: isPostDetailPresented,
            timelineList: timelineList,
            onMinimizeDirectionChanged: updateTabBarMinimizeDirection,
            onComposeTap: presentComposer
        )
    }

    private var timelineList: some View {
        NavigationStack(path: $postNavigationPath) {
            TimelineFeedView(
                posts: MockTimelineData.posts,
                actionMenuTopClearance: actionMenuTopClearance,
                onOpenPost: openPost,
                onOpenMedia: openMedia,
                onOpenURL: openURL
            ) { offset in
                handleTimelineScrollOffset(offset)
            }
            .navigationDestination(for: SelectedPostRoute.self) { route in
                PostDetailView(
                    post: route.post,
                    onOpenPost: openPost,
                    onOpenMedia: openMedia,
                    onOpenURL: openURL
                )
            }
        }
    }

    private func completeInitialAppearanceIfNeeded() {
        guard !didCompleteInitialAppearance else { return }
        if selectedTab == .compose {
            selectedTab = previousTab
        }
        DispatchQueue.main.async {
            didCompleteInitialAppearance = true
        }
    }

    private func handleTimelineScrollOffset(_ offset: CGFloat) {
        if isUserSwitcherPresented || isTimelineMenuPresented {
            let didScroll = abs(offset - timelineScrollOffset) > 1
            if didScroll {
                dismissFloatingMenus()
            }
        }
        timelineScrollOffset = offset
    }

    private func openPost(_ post: TimelinePost) {
        dismissFloatingMenus()
        postNavigationPath.append(SelectedPostRoute(post: post))
    }

    private func openMedia(_ media: TimelineMedia) {
        dismissFloatingMenus()
        fullscreenMedia = media
    }

    private func openURL(_ url: URL) {
        dismissFloatingMenus()
        browserDestination = TimelineBrowserDestination(url: url)
    }

    private var isFullscreenMediaPresented: Binding<Bool> {
        Binding(
            get: { fullscreenMedia != nil },
            set: { isPresented in
                if !isPresented {
                    fullscreenMedia = nil
                }
            }
        )
    }

    private func dismissFloatingMenus() {
        guard isUserSwitcherPresented || isTimelineMenuPresented else { return }
        withAnimation(.spring(duration: 0.28, bounce: 0.14)) {
            isUserSwitcherPresented = false
            isTimelineMenuPresented = false
        }
    }

    private func handleTabSelection(_ newValue: TimelineTab) {
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

    private func presentComposer() {
        presentComposer(mode: .post)
    }

    private func presentReplyComposer() {
        presentComposer(mode: .reply)
    }

    private func presentComposer(mode: ComposeSheetMode) {
        dismissFloatingMenus()
        guard didCompleteInitialAppearance, !isComposerPresented else { return }
        composeSheetMode = mode
        DispatchQueue.main.async {
            isComposerPresented = true
        }
    }

    private func updateTabBarMinimizeDirection(_ nextDirection: TabBarMinimizeDirection) {
        guard tabBarMinimizeDirection != nextDirection else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tabBarMinimizeDirection = nextDirection
        }
    }
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
