import SwiftUI
import UIKit

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

            tabContent
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissFloatingMenus()
                    }
                )

            VStack {
                topBar
                    .zIndex(30)
                Spacer(minLength: 0)
            }

            if visibleTab == .home {
                unreadBadge
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
        .onAppear {
            guard !didCompleteInitialAppearance else { return }
            if selectedTab == .compose {
                selectedTab = previousTab
            }
            DispatchQueue.main.async {
                didCompleteInitialAppearance = true
            }
        }
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

    private var topBar: some View {
        ZStack {
            topTitleControl

            HStack {
                Button {
                    withAnimation(.spring(duration: 0.32, bounce: 0.22)) {
                        isUserSwitcherPresented.toggle()
                        isTimelineMenuPresented = false
                    }
                } label: {
                    UserSwitchButton(isExpanded: isUserSwitcherPresented)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if isUserSwitcherPresented {
                        UserSwitcherMenu()
                            .offset(y: 44)
                            .transition(.scale(scale: 0.72, anchor: .topLeading).combined(with: .opacity))
                            .zIndex(20)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    dismissFloatingMenus()
                } label: {
                    RelayStatusRingButton(
                        connected: 7,
                        planned: 12,
                        collapseProgress: topChromeCollapseProgress
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var topTitleControl: some View {
        if visibleTab == .home {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isTimelineMenuPresented.toggle()
                    isUserSwitcherPresented = false
                }
            } label: {
                HStack(spacing: 7) {
                    Text(selectedTimeline.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .rotationEffect(.degrees(isTimelineMenuPresented ? 180 : 0))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
                .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if isTimelineMenuPresented {
                    TimelineSwitcherMenu(selected: $selectedTimeline)
                        .offset(y: 34)
                        .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
        } else {
            Text(visibleTab.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
        }
    }

    private var tabContent: some View {
        nativeTabs
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
            if isUserSwitcherPresented || isTimelineMenuPresented {
                let didScroll = abs(offset - timelineScrollOffset) > 1
                if didScroll {
                    dismissFloatingMenus()
                }
            }
            timelineScrollOffset = offset
        }
    }

    private var unreadBadge: some View {
        Button {
            dismissFloatingMenus()
        } label: {
            Text("3996")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.astrenzaAccent, in: Capsule())
                .shadow(color: Color.astrenzaAccent.opacity(0.18), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3996 unread posts")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UnreadBadgeFramePreferenceKey.self,
                    value: proxy.frame(in: .named("homeTimelineChrome"))
                )
            }
        }
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

private struct UIKitTimelineTabView<TimelineContent: View>: UIViewControllerRepresentable {
    @Binding var selectedTab: TimelineTab
    @Binding var previousTab: TimelineTab
    let minimizeDirection: TabBarMinimizeDirection
    let timelineList: TimelineContent
    let onMinimizeDirectionChanged: (TabBarMinimizeDirection) -> Void
    let onComposeTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        controller.view.backgroundColor = UIColor(Color.astrenzaBackground)
        controller.tabBarMinimizeBehavior = minimizeDirection.uiKitBehavior
        configureAppearance(for: controller)

        context.coordinator.installTabs(on: controller)
        context.coordinator.installDirectionProbe(on: controller)
        context.coordinator.select(selectedTab, on: controller)
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.parent = self
        controller.tabBarMinimizeBehavior = minimizeDirection.uiKitBehavior
        configureAppearance(for: controller)
        context.coordinator.updateHostedViews()
        context.coordinator.select(selectedTab, on: controller)
    }

    private func configureAppearance(for controller: UITabBarController) {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.14)

        controller.tabBar.standardAppearance = appearance
        controller.tabBar.scrollEdgeAppearance = appearance
        controller.tabBar.tintColor = UIColor(Color.astrenzaAccent)
        controller.tabBar.unselectedItemTintColor = UIColor.secondaryLabel
        controller.tabBar.itemPositioning = .centered
        controller.tabBar.itemWidth = 46
        controller.tabBar.itemSpacing = 0
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UIGestureRecognizerDelegate {
        var parent: UIKitTimelineTabView
        private var tabs: [TimelineTab: UITab] = [:]
        private var hosts: [TimelineTab: UIHostingController<AnyView>] = [:]
        private weak var tabBarController: UITabBarController?
        private weak var directionProbeRecognizer: TabBarDirectionProbeGestureRecognizer?
        private weak var composeTapRecognizer: UITapGestureRecognizer?

        init(parent: UIKitTimelineTabView) {
            self.parent = parent
        }

        func installTabs(on controller: UITabBarController) {
            guard tabs.isEmpty else { return }

            let orderedTabs: [TimelineTab] = [.home, .notifications, .profile, .explore]
            var uiTabs = orderedTabs.map { tab in
                let host = makeHost(for: tab)
                hosts[tab] = host

                let uiTab = UITab(
                    title: tab.title,
                    image: UIImage(systemName: tab.systemName(isSelected: false)),
                    identifier: tab.rawValue
                ) { _ in
                    host
                }

                tabs[tab] = uiTab
                return uiTab
            }

            let composeHost = makeHost(for: .compose)
            hosts[.compose] = composeHost
            let composeTab = UISearchTab { _ in
                composeHost
            }
            composeTab.title = TimelineTab.compose.title
            composeTab.image = UIImage(systemName: TimelineTab.compose.systemName(isSelected: false))
            composeTab.preferredPlacement = .pinned
            composeTab.automaticallyActivatesSearch = false
            tabs[.compose] = composeTab
            uiTabs.append(composeTab)

            controller.setTabs(uiTabs, animated: false)
            tabBarController = controller
            installComposeTabTapRecognizer(on: controller)
        }

        func updateHostedViews() {
            hosts[.home]?.rootView = AnyView(parent.timelineList)
            hosts[.notifications]?.rootView = AnyView(PlaceholderTabView(tab: .notifications))
            hosts[.profile]?.rootView = AnyView(PlaceholderTabView(tab: .profile))
            hosts[.explore]?.rootView = AnyView(PlaceholderTabView(tab: .explore))
        }

        func select(_ tab: TimelineTab, on controller: UITabBarController) {
            guard tab != .compose, let uiTab = tabs[tab] else { return }
            guard controller.selectedTab !== uiTab else { return }
            controller.selectedTab = uiTab
        }

        func installDirectionProbe(on controller: UITabBarController) {
            guard directionProbeRecognizer == nil else { return }

            let recognizer = TabBarDirectionProbeGestureRecognizer()
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            recognizer.onDirectionResolved = { [weak self] direction in
                guard let self else { return }
                parent.onMinimizeDirectionChanged(direction)
                tabBarController?.tabBarMinimizeBehavior = direction.uiKitBehavior
            }
            controller.view.addGestureRecognizer(recognizer)
            directionProbeRecognizer = recognizer
        }

        func installComposeTabTapRecognizer(on controller: UITabBarController) {
            guard composeTapRecognizer == nil else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleComposeTabTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            controller.tabBar.addGestureRecognizer(recognizer)
            composeTapRecognizer = recognizer
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            if timelineTab(for: tab) == .compose {
                parent.onComposeTap()
                return false
            }

            return true
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if let tab = viewController.tab, timelineTab(for: tab) == .compose {
                parent.onComposeTap()
                return false
            }

            return true
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            guard let tab = timelineTab(for: selectedTab), tab != .compose else { return }
            parent.previousTab = tab
            parent.selectedTab = tab
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let selectedTab = viewController.tab else { return }
            guard let tab = timelineTab(for: selectedTab), tab != .compose else { return }
            parent.previousTab = tab
            parent.selectedTab = tab
        }

        @objc private func handleComposeTabTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let tabBar = recognizer.view else { return }

            let location = recognizer.location(in: tabBar)
            let composeHitWidth = min(max(tabBar.bounds.width * 0.24, 72), 108)
            let composeFrame = CGRect(
                x: tabBar.bounds.maxX - composeHitWidth,
                y: tabBar.bounds.minY,
                width: composeHitWidth,
                height: tabBar.bounds.height
            )
            guard composeFrame.contains(location) else { return }

            parent.onComposeTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func makeHost(for tab: TimelineTab) -> UIHostingController<AnyView> {
            let host = UIHostingController(rootView: rootView(for: tab))
            host.view.backgroundColor = UIColor(Color.astrenzaBackground)
            return host
        }

        private func rootView(for tab: TimelineTab) -> AnyView {
            switch tab {
            case .home:
                AnyView(parent.timelineList)
            case .notifications:
                AnyView(PlaceholderTabView(tab: .notifications))
            case .profile:
                AnyView(PlaceholderTabView(tab: .profile))
            case .explore:
                AnyView(PlaceholderTabView(tab: .explore))
            case .compose:
                AnyView(Color.astrenzaBackground)
            }
        }

        private func timelineTab(for tab: UITab) -> TimelineTab? {
            tabs.first { $0.value === tab }?.key
        }
    }
}

private enum TabBarMinimizeDirection: Equatable {
    case towardOlder
    case towardNewer

    var swiftUIBehavior: TabBarMinimizeBehavior {
        switch self {
        case .towardOlder: .onScrollDown
        case .towardNewer: .onScrollUp
        }
    }

    var uiKitBehavior: UITabBarController.MinimizeBehavior {
        switch self {
        case .towardOlder: .onScrollDown
        case .towardNewer: .onScrollUp
        }
    }
}

private final class TabBarDirectionProbeGestureRecognizer: UIGestureRecognizer {
    var onDirectionResolved: ((TabBarMinimizeDirection) -> Void)?

    private var initialLocation: CGPoint?
    private var didResolveDirection = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        initialLocation = touches.first?.location(in: view)
        didResolveDirection = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        defer {
            super.touchesMoved(touches, with: event)
        }

        guard !didResolveDirection,
              let initialLocation,
              let currentLocation = touches.first?.location(in: view)
        else { return }

        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y
        guard abs(deltaY) > abs(deltaX), abs(deltaY) > 3 else { return }

        didResolveDirection = true
        onDirectionResolved?(deltaY < 0 ? .towardOlder : .towardNewer)
        state = .failed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        initialLocation = nil
        didResolveDirection = false
        super.reset()
    }
}

private struct UnreadBadgeFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PreviousTabSnapshot<TimelineContent: View>: View {
    let tab: TimelineTab
    let timelineList: TimelineContent

    var body: some View {
        switch tab {
        case .home:
            timelineList
        case .notifications:
            PlaceholderTabView(tab: .notifications)
        case .profile:
            PlaceholderTabView(tab: .profile)
        case .explore:
            PlaceholderTabView(tab: .explore)
        case .compose:
            Color.astrenzaBackground
        }
    }
}

private struct ComposeSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AvatarView(style: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"), size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New note")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("Posting as ikuradon")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .black))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider().overlay(Color.astrenzaSeparator)

            VStack(alignment: .leading, spacing: 18) {
                Text("Nostrに投稿する内容を入力")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("ここはあとで実際の投稿エディタに差し替えます。今は下から出てくる標準モーダルの動きと、投稿タブの分離配置を確認するためのモックです。")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)
                    .lineSpacing(4)

                HStack(spacing: 10) {
                    Button {
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())

                    Button {
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Post")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Color.astrenzaAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(18)

            Spacer(minLength: 0)
        }
        .background(Color.astrenzaBackground)
        .preferredColorScheme(.dark)
    }
}

private struct PlaceholderTabView: View {
    let tab: TimelineTab

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab.systemName(isSelected: true))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.astrenzaAccent)
            Text(tab.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("この画面はあとで実装します")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 72)
        .padding(.bottom, 124)
        .background(Color.astrenzaBackground)
    }
}

private struct UserSwitchButton: View {
    let isExpanded: Bool

    var body: some View {
        AvatarView(style: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"), size: 34)
            .padding(4)
            .scaleEffect(isExpanded ? 1.06 : 1)
            .astrenzaGlass(tint: Color.white.opacity(isExpanded ? 0.1 : 0.05), in: Circle())
            .animation(.spring(duration: 0.28, bounce: 0.2), value: isExpanded)
            .accessibilityLabel("Switch user")
    }
}

private struct UserSwitcherMenu: View {
    var body: some View {
        VStack(spacing: 0) {
            UserSwitcherRow(
                title: "ユーザー1",
                subtitle: "@ikuradon",
                avatarStyle: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"),
                isSelected: true
            )

            UserSwitcherRow(
                title: "ユーザー2",
                subtitle: "@astral",
                avatarStyle: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
                isSelected: false
            )

            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.vertical, 2)

            Button {
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 28, height: 28)

                    Text("設定")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .frame(width: 178)
        .astrenzaGlass(tint: Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("User switcher")
    }
}

private struct UserSwitcherRow: View {
    let title: String
    let subtitle: String
    let avatarStyle: AvatarStyle
    let isSelected: Bool

    var body: some View {
        Button {
        } label: {
            HStack(spacing: 10) {
                AvatarView(style: avatarStyle, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.astrenzaAccent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RelayStatusRingButton: View {
    let connected: Int
    let planned: Int
    let collapseProgress: CGFloat

    private var progress: Double {
        guard planned > 0 else { return 0 }
        return min(Double(connected) / Double(planned), 1)
    }

    private var labelProgress: CGFloat {
        1 - collapseProgress
    }

    private var ringSize: CGFloat {
        30 - (2 * collapseProgress)
    }

    private var containerWidth: CGFloat {
        104 - (56 * collapseProgress)
    }

    var body: some View {
        HStack(spacing: 8 * labelProgress) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [Color.astrenzaAccent, .cyan, Color.astrenzaAccent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(connected)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: 0) {
                Text("Relays")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text("\(connected)/\(planned)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .scaleEffect(x: labelProgress, y: labelProgress, anchor: .leading)
            .frame(width: 45 * labelProgress, alignment: .leading)
            .clipped()
            .opacity(Double(labelProgress))
        }
        .padding(.leading, 9 - (2 * collapseProgress))
        .padding(.trailing, 11 - (3 * collapseProgress))
        .frame(width: containerWidth, height: 46 - (2 * collapseProgress))
        .astrenzaGlass(tint: Color.white.opacity(0.04), in: Capsule())
        .animation(.spring(duration: 0.36, bounce: 0.16), value: collapseProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Show relay information, \(connected) of \(planned) connected")
    }
}

private struct TimelineSwitcherMenu: View {
    @Binding var selected: TimelineKind

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TimelineKind.allCases) { kind in
                Button {
                    selected = kind
                } label: {
                    HStack {
                        Text(kind.title)
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                        Spacer()
                        Image(systemName: kind.systemName)
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .foregroundStyle(kind == selected ? .primary : .secondary)
                    .padding(.horizontal, 20)
                    .frame(height: 55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if kind != TimelineKind.allCases.last {
                    Divider().overlay(Color.astrenzaSeparator)
                }
            }
        }
        .frame(width: 286)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }
}

private enum TimelineKind: String, CaseIterable, Identifiable {
    case home
    case relays
    case lists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .relays: "Relays"
        case .lists: "Lists"
        }
    }

    var systemName: String {
        switch self {
        case .home: "house"
        case .relays: "globe.asia.australia"
        case .lists: "list.bullet.rectangle"
        }
    }
}

private enum TimelineTab: String, CaseIterable, Identifiable {
    case home
    case notifications
    case profile
    case explore
    case compose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .notifications: "Notifications"
        case .profile: "Profile"
        case .explore: "Explore"
        case .compose: "Post"
        }
    }

    func systemName(isSelected: Bool) -> String {
        switch self {
        case .home: isSelected ? "house.fill" : "house"
        case .notifications: "bell.badge"
        case .profile: "person.crop.square"
        case .explore: "binoculars"
        case .compose: "square.and.pencil"
        }
    }
}

#Preview {
    HomeTimelineView()
        .preferredColorScheme(.dark)
}
