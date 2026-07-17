import SwiftUI
import UIKit

enum TimelineKind: String, CaseIterable, Identifiable {
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

    var emptyState: TimelineEmptyState {
        switch self {
        case .home: .home
        case .relays: .relays
        case .lists: .lists
        }
    }
}

enum TimelineTab: String, CaseIterable, Identifiable {
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

    func systemName(isSelected: Bool, isReturnMode: Bool) -> String {
        if self == .home, isReturnMode {
            return "arrow.down"
        }
        return systemName(isSelected: isSelected)
    }
}

enum TabBarMinimizeDirection: Equatable {
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

struct UnreadBadgeFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

enum HomeUnreadPillPlacement: Equatable {
    case hidden
    case pinned
    case attachedToAnchor

    var isPinned: Bool {
        self == .pinned
    }

    var isAttachedToAnchor: Bool {
        self == .attachedToAnchor
    }
}

enum HomeUnreadPillLayout {
    static let pinLineY: CGFloat = 72
    static let chromeTopInset: CGFloat = 88
    static let trailingInset: CGFloat = 22
    static let rowTopInset = chromeTopInset - pinLineY
}

enum HomeUnreadPillPlacementPolicy {
    private static let pinLineTolerance: CGFloat = 0.5

    static func resolve(
        anchorPostID: TimelinePost.ID?,
        anchorMinY: CGFloat?,
        postOrderByID: [TimelinePost.ID: Int],
        readablePostIDs: [TimelinePost.ID],
        pinLineY: CGFloat
    ) -> HomeUnreadPillPlacement {
        guard let anchorPostID,
              let anchorIndex = postOrderByID[anchorPostID]
        else { return .hidden }

        if let anchorMinY {
            return anchorMinY < pinLineY - pinLineTolerance
                ? .attachedToAnchor
                : .pinned
        }

        let readableIndexes = readablePostIDs.compactMap { postOrderByID[$0] }
        guard let newestReadableIndex = readableIndexes.min() else {
            return .hidden
        }

        return newestReadableIndex > anchorIndex
            ? .hidden
            : .pinned
    }
}
