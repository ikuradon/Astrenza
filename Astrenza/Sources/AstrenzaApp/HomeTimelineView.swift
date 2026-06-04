import SwiftUI

struct HomeTimelineView: View {
    @State private var selectedTab: TimelineTab = .home
    @State private var previousTab: TimelineTab = .home
    @State private var selectedTimeline: TimelineKind = .home
    @State private var isTimelineMenuPresented = false
    @State private var isUserSwitcherPresented = false
    @State private var isComposerPresented = false
    @State private var didCompleteInitialAppearance = false
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var tabBarMinimizeDirection: TabBarMinimizeDirection = .towardNewer
    @State private var unreadBadgeFrame: CGRect = .zero

    private var actionMenuTopClearance: CGFloat {
        max(unreadBadgeFrame.maxY + 10, 96)
    }

    private var visibleTab: TimelineTab {
        selectedTab == .compose ? previousTab : selectedTab
    }

    private var topChromeCollapseProgress: CGFloat {
        min(max(timelineScrollOffset / 72, 0), 1)
    }

    var body: some View {
        ZStack {
            Color.astrenzaBackground.ignoresSafeArea()

            nativeTabs
                .simultaneousGesture(
                    TapGesture().onEnded(dismissFloatingMenus)
                )

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

            if visibleTab == .home {
                HomeUnreadBadge(onTap: dismissFloatingMenus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 70)
                    .padding(.trailing, 16)
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
            ComposeSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private var nativeTabs: some View {
        UIKitTimelineTabView(
            selectedTab: $selectedTab,
            previousTab: $previousTab,
            minimizeDirection: tabBarMinimizeDirection,
            timelineList: timelineList,
            onMinimizeDirectionChanged: updateTabBarMinimizeDirection,
            onComposeTap: presentComposer
        )
    }

    private var timelineList: some View {
        TimelineFeedView(
            posts: MockTimelineData.posts,
            actionMenuTopClearance: actionMenuTopClearance
        ) { offset in
            handleTimelineScrollOffset(offset)
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
        dismissFloatingMenus()
        guard didCompleteInitialAppearance, !isComposerPresented else { return }
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

#Preview {
    HomeTimelineView()
        .preferredColorScheme(.dark)
}
