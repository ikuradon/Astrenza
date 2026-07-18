import SwiftUI
import UIKit

@MainActor
final class TimelineFeedMenuCoordinator {
    typealias PostProvider = (TimelinePost.ID) -> TimelinePost?

    private weak var owner: UIViewController?
    private weak var containerView: UIView?
    private var hostingController: UIHostingController<TimelineHostedPostMenu>?
    private var menu: OpenedPostMenu?
    private var selectedChoice: FloatingPostMenuSelection?
    private var sourceFrame: CGRect?
    private var actionMenuTopClearance: CGFloat = 96
    private var postProvider: PostProvider = { _ in nil }
    private var onPostActionChoice: (TimelinePost, PostActionChoice) -> Void = { _, _ in }
    private var onOpenStateChanged: (Bool, Set<TimelinePost.ID>) -> Void = { _, _ in }

    init(owner: UIViewController, containerView: UIView) {
        self.owner = owner
        self.containerView = containerView
    }

    var isOpen: Bool {
        menu != nil
    }

    var openedPostID: TimelinePost.ID? {
        menu?.postID
    }

    func configure(
        actionMenuTopClearance: CGFloat,
        postProvider: @escaping PostProvider,
        onPostActionChoice: @escaping (TimelinePost, PostActionChoice) -> Void,
        onOpenStateChanged: @escaping (Bool, Set<TimelinePost.ID>) -> Void
    ) {
        self.actionMenuTopClearance = actionMenuTopClearance
        self.postProvider = postProvider
        self.onPostActionChoice = onPostActionChoice
        self.onOpenStateChanged = onOpenStateChanged
        relayout()
    }

    func handle(
        _ event: TimelinePostActionEvent,
        sourceFrame: CGRect?
    ) {
        switch event.phase {
        case .tap:
            guard event.kind == .more else { return }
            let nextMenu = OpenedPostMenu(postID: event.postID, kind: event.kind)
            if menu == nextMenu {
                close()
            } else {
                open(nextMenu, sourceFrame: sourceFrame)
            }
        case .longPressBegan:
            open(
                OpenedPostMenu(postID: event.postID, kind: event.kind),
                sourceFrame: sourceFrame
            )
        case .dragChanged(let windowLocation):
            updateDragSelection(windowLocation: windowLocation)
        case .dragEnded(let windowLocation):
            finishDrag(windowLocation: windowLocation)
        }
    }

    func close() {
        guard let menu else { return }
        let affectedPostIDs = Set([menu.postID])
        self.menu = nil
        selectedChoice = nil
        sourceFrame = nil

        if let hostingController {
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
        }
        hostingController = nil
        onOpenStateChanged(false, affectedPostIDs)
    }

    func relayout() {
        guard let menu,
              let sourceFrame,
              let hostingController,
              let containerView
        else { return }
        hostingController.view.frame = menuFrame(
            menu: menu,
            sourceFrame: sourceFrame,
            containerSize: containerView.bounds.size
        )
    }

    private func open(_ nextMenu: OpenedPostMenu, sourceFrame: CGRect?) {
        let previousPostID = menu?.postID
        menu = nextMenu
        selectedChoice = nil
        if let sourceFrame {
            self.sourceFrame = sourceFrame
        }

        installOrUpdateHostedMenu()
        var affectedPostIDs = Set([nextMenu.postID])
        if let previousPostID {
            affectedPostIDs.insert(previousPostID)
        }
        onOpenStateChanged(true, affectedPostIDs)
    }

    private func installOrUpdateHostedMenu() {
        guard let owner, let containerView, let menu else { return }
        let rootView = hostedMenu(menu)
        let hostingController: UIHostingController<TimelineHostedPostMenu>
        if let current = self.hostingController {
            current.rootView = rootView
            hostingController = current
        } else {
            let next = UIHostingController(rootView: rootView)
            next.view.backgroundColor = .clear
            next.view.clipsToBounds = false
            owner.addChild(next)
            containerView.addSubview(next.view)
            next.didMove(toParent: owner)
            self.hostingController = next
            hostingController = next
        }
        hostingController.view.frame = menuFrame(
            menu: menu,
            sourceFrame: sourceFrame ?? .zero,
            containerSize: containerView.bounds.size
        )
        containerView.bringSubviewToFront(hostingController.view)
    }

    private func hostedMenu(_ menu: OpenedPostMenu) -> TimelineHostedPostMenu {
        TimelineHostedPostMenu(
            menu: menu,
            selection: selectedChoice,
            onSelectPostAction: { [weak self] choice in
                self?.selectPostAction(choice)
            },
            onSelectChoice: { [weak self] in
                self?.close()
            }
        )
    }

    private func selectPostAction(_ choice: PostActionChoice) {
        guard let menu,
              let post = postProvider(menu.postID)
        else {
            close()
            return
        }
        close()
        switch choice {
        case .viewDetails, .mute, .bookmark:
            onPostActionChoice(post, choice)
        case .report, .translate, .copyLink, .shareLink:
            break
        }
    }

    private func updateDragSelection(windowLocation: CGPoint) {
        guard let menu,
              let containerView,
              let hostingController
        else { return }
        let location = containerView.convert(windowLocation, from: nil)
        selectedChoice = selection(
            for: menu,
            location: location,
            menuFrame: hostingController.view.frame
        )
        hostingController.rootView = hostedMenu(menu)
    }

    private func finishDrag(windowLocation: CGPoint?) {
        guard let menu,
              let hostingController
        else {
            close()
            return
        }

        if let selectedChoice {
            switch selectedChoice {
            case .more(let choice):
                selectPostAction(choice)
            case .repost, .favorite:
                close()
            }
            return
        }

        guard let windowLocation, let containerView else {
            close()
            return
        }
        let location = containerView.convert(windowLocation, from: nil)
        if !hostingController.view.frame.contains(location) {
            close()
        } else {
            hostingController.rootView = hostedMenu(menu)
        }
    }

    private func selection(
        for menu: OpenedPostMenu,
        location: CGPoint,
        menuFrame: CGRect
    ) -> FloatingPostMenuSelection? {
        guard menuFrame.contains(location) else { return nil }
        switch menu.kind {
        case .more:
            guard let choice = postActionChoice(
                at: location,
                in: menuFrame
            ) else { return nil }
            return .more(choice)
        case .repost:
            let choices = Array(RepostChoice.allCases)
            let index = choiceIndex(
                at: location,
                in: menuFrame,
                count: choices.count
            )
            return .repost(choices[index])
        case .favorite:
            let choices = Array(FavoriteChoice.allCases)
            let index = choiceIndex(
                at: location,
                in: menuFrame,
                count: choices.count
            )
            return .favorite(choices[index])
        }
    }

    private func postActionChoice(
        at location: CGPoint,
        in menuFrame: CGRect
    ) -> PostActionChoice? {
        var localY = location.y - menuFrame.minY -
            FloatingMenuMetrics.verticalPadding
        guard localY >= 0 else { return nil }

        for choice in PostActionChoice.allCases {
            if localY < FloatingMenuMetrics.actionRowHeight {
                return choice
            }
            localY -= FloatingMenuMetrics.actionRowHeight
            if choice.followsDivider {
                guard localY >= FloatingMenuMetrics.dividerHeight else {
                    return nil
                }
                localY -= FloatingMenuMetrics.dividerHeight
            }
        }
        return nil
    }

    private func choiceIndex(
        at location: CGPoint,
        in menuFrame: CGRect,
        count: Int
    ) -> Int {
        let rowHeight = menuFrame.height / CGFloat(count)
        return min(
            max(Int((location.y - menuFrame.minY) / rowHeight), 0),
            count - 1
        )
    }

    private func menuFrame(
        menu: OpenedPostMenu,
        sourceFrame: CGRect,
        containerSize: CGSize
    ) -> CGRect {
        let menuSize = menu.size
        let rightInset: CGFloat = 16
        let bottomChromeClearance: CGFloat = 116
        let availableTop = actionMenuTopClearance
        let availableBottom = containerSize.height - bottomChromeClearance
        let centerX = min(
            max(
                sourceFrame.maxX - menuSize.width / 2,
                menuSize.width / 2 + rightInset
            ),
            containerSize.width - menuSize.width / 2 - rightInset
        )
        let preferredBelowTop = sourceFrame.maxY + 12
        let originY: CGFloat
        if preferredBelowTop + menuSize.height <= availableBottom {
            originY = preferredBelowTop
        } else {
            let preferredAboveTop = sourceFrame.minY - 12 - menuSize.height
            let preferredAboveBottom = sourceFrame.minY - 12
            let aboveOverflow = max(availableTop - preferredAboveTop, 0)
            let belowOverflow = max(preferredAboveBottom - availableBottom, 0)
            originY = preferredAboveTop + aboveOverflow - belowOverflow
        }

        return CGRect(
            x: centerX - menuSize.width / 2,
            y: originY,
            width: menuSize.width,
            height: menuSize.height
        )
    }
}

struct TimelineHostedPostMenu: View {
    let menu: OpenedPostMenu
    let selection: FloatingPostMenuSelection?
    let onSelectPostAction: (PostActionChoice) -> Void
    let onSelectChoice: () -> Void

    var body: some View {
        switch menu.kind {
        case .more:
            PostActionMenu(
                selectedChoice: moreSelection,
                onSelect: onSelectPostAction
            )
        case .repost:
            RepostChoiceMenu(
                selectedChoice: repostSelection,
                onSelect: onSelectChoice
            )
        case .favorite:
            FavoriteChoiceMenu(
                selectedChoice: favoriteSelection,
                onSelect: onSelectChoice
            )
        }
    }

    private var moreSelection: PostActionChoice? {
        guard case .more(let choice) = selection else { return nil }
        return choice
    }

    private var repostSelection: RepostChoice? {
        guard case .repost(let choice) = selection else { return nil }
        return choice
    }

    private var favoriteSelection: FavoriteChoice? {
        guard case .favorite(let choice) = selection else { return nil }
        return choice
    }
}
