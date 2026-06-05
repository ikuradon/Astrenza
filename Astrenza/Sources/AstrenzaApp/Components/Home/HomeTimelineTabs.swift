import SwiftUI
import UIKit

struct UIKitTimelineTabView<TimelineContent: View, ProfileContent: View>: UIViewControllerRepresentable {
    @Binding var selectedTab: TimelineTab
    @Binding var previousTab: TimelineTab
    let minimizeDirection: TabBarMinimizeDirection
    let isTabBarHidden: Bool
    let timelineList: TimelineContent
    let profileView: ProfileContent
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
        context.coordinator.setTabBarHidden(isTabBarHidden, on: controller, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.parent = self
        controller.tabBarMinimizeBehavior = minimizeDirection.uiKitBehavior
        configureAppearance(for: controller)
        context.coordinator.updateHostedViews()
        context.coordinator.select(selectedTab, on: controller)
        context.coordinator.setTabBarHidden(isTabBarHidden, on: controller, animated: true)
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
            let currentRootView = rootView(for: parent.selectedTab)
            hosts.values.forEach { host in
                host.rootView = currentRootView
            }
        }

        func select(_ tab: TimelineTab, on controller: UITabBarController) {
            guard tab != .compose, let uiTab = tabs[tab] else { return }
            guard controller.selectedTab !== uiTab else { return }
            controller.selectedTab = uiTab
        }

        func setTabBarHidden(_ isHidden: Bool, on controller: UITabBarController, animated: Bool) {
            guard controller.tabBar.isHidden != isHidden || controller.tabBar.alpha != (isHidden ? 0 : 1) else { return }

            let updates = {
                controller.tabBar.alpha = isHidden ? 0 : 1
            }

            controller.tabBar.isUserInteractionEnabled = !isHidden
            if !isHidden {
                controller.tabBar.isHidden = false
            }

            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    updates()
                } completion: { _ in
                    controller.tabBar.isHidden = isHidden
                }
            } else {
                updates()
                controller.tabBar.isHidden = isHidden
            }
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
                AnyView(parent.profileView)
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

private final class TabBarDirectionProbeGestureRecognizer: UIGestureRecognizer {
    var onDirectionResolved: ((TabBarMinimizeDirection) -> Void)?

    private var initialLocation: CGPoint?
    private var didResolveDirection = false
    private var shouldIgnoreCurrentTouch = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let firstTouch = touches.first
        initialLocation = firstTouch?.location(in: view)
        didResolveDirection = false
        shouldIgnoreCurrentTouch = firstTouch.map(touchBeginsInControl) ?? false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        defer {
            super.touchesMoved(touches, with: event)
        }

        guard !shouldIgnoreCurrentTouch,
              !didResolveDirection,
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
        shouldIgnoreCurrentTouch = false
        super.reset()
    }

    private func touchBeginsInControl(_ touch: UITouch) -> Bool {
        guard let view else { return false }
        let location = touch.location(in: view)
        var hitView = view.hitTest(location, with: nil)

        while let currentView = hitView {
            if currentView is UIControl {
                return true
            }
            hitView = currentView.superview
        }

        return false
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
