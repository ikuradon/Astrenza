import SwiftUI

struct TimelinePostMenuState {
    var openedMenu: OpenedPostMenu?
    var dragLocation: CGPoint?
    var selectedChoice: FloatingPostMenuSelection?
    var frame: CGRect?
    var overlayGlobalOrigin: CGPoint = .zero

    var isOpen: Bool {
        openedMenu != nil
    }

    mutating func reset() {
        openedMenu = nil
        dragLocation = nil
        selectedChoice = nil
        frame = nil
    }

    mutating func clearDragSelection() {
        dragLocation = nil
        selectedChoice = nil
    }

    mutating func open(_ menu: OpenedPostMenu) {
        openedMenu = menu
        dragLocation = nil
        selectedChoice = nil
        frame = nil
    }

    mutating func toggle(_ menu: OpenedPostMenu) {
        if openedMenu == menu {
            reset()
        } else {
            open(menu)
        }
    }

    mutating func setFrame(_ newFrame: CGRect) {
        frame = newFrame
    }

    mutating func setOverlayGlobalFrame(_ newFrame: CGRect) {
        overlayGlobalOrigin = newFrame.origin
    }

    mutating func setWindowDragLocation(_ location: CGPoint) {
        dragLocation = normalizedWindowLocation(location)
    }

    mutating func setLocalDragLocation(_ location: CGPoint) {
        dragLocation = location
    }

    func normalizedWindowLocation(_ location: CGPoint) -> CGPoint {
        CGPoint(
            x: location.x - overlayGlobalOrigin.x,
            y: location.y - overlayGlobalOrigin.y
        )
    }
}

struct OpenedPostMenu: Equatable {
    let postID: TimelinePost.ID
    let kind: TimelinePostActionKind

    var size: CGSize {
        switch kind {
        case .more:
            FloatingMenuMetrics.actionMenuSize
        case .repost:
            FloatingMenuMetrics.repostMenuSize
        case .favorite:
            FloatingMenuMetrics.favoriteMenuSize
        }
    }
}

enum FloatingPostMenuSelection: Equatable {
    case more(PostActionChoice)
    case repost(RepostChoice)
    case favorite(FavoriteChoice)
}
