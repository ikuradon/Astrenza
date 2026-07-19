import UIKit

enum TimelinePostActionKind: Hashable {
    case repost
    case favorite
    case more
}

enum TimelinePostActionMenuSelection: Hashable {
    case repost(RepostChoice)
    case favorite(FavoriteChoice)
    case more(PostActionChoice)
}

protocol TimelinePostActionMenuChoice: CaseIterable, Hashable {
    var title: String { get }
    var systemName: String { get }
}

enum PostActionChoice: TimelinePostActionMenuChoice {
    case report
    case mute
    case translate
    case bookmark
    case copyLink
    case shareLink
    case viewDetails

    var title: String {
        switch self {
        case .report:
            "Report"
        case .mute:
            "Mute"
        case .translate:
            "Translate"
        case .bookmark:
            "Bookmark"
        case .copyLink:
            "Copy Link"
        case .shareLink:
            "Share Link"
        case .viewDetails:
            "View Details"
        }
    }

    var systemName: String {
        switch self {
        case .report:
            "exclamationmark.bubble"
        case .mute:
            "speaker.slash"
        case .translate:
            "character.bubble"
        case .bookmark:
            "bookmark"
        case .copyLink:
            "link"
        case .shareLink:
            "square.and.arrow.up"
        case .viewDetails:
            "info.circle"
        }
    }

    static let menuGroups: [[PostActionChoice]] = [
        [.report, .mute],
        [.translate, .bookmark],
        [.copyLink, .shareLink],
        [.viewDetails],
    ]
}

enum RepostChoice: TimelinePostActionMenuChoice {
    case repost
    case quotedRepost

    var title: String {
        switch self {
        case .repost:
            "Repost"
        case .quotedRepost:
            "Quoted Repost"
        }
    }

    var systemName: String {
        switch self {
        case .repost:
            "arrow.triangle.2.circlepath"
        case .quotedRepost:
            "quote.bubble"
        }
    }
}

enum FavoriteChoice: TimelinePostActionMenuChoice {
    case favorite
    case customReaction
    case bookmark

    var title: String {
        switch self {
        case .favorite:
            "Favorite"
        case .customReaction:
            "Custom Reaction"
        case .bookmark:
            "Bookmark"
        }
    }

    var systemName: String {
        switch self {
        case .favorite:
            "star"
        case .customReaction:
            "face.smiling"
        case .bookmark:
            "bookmark"
        }
    }
}

@MainActor
enum TimelinePostActionMenuBuilder {
    static func make(
        kind: TimelinePostActionKind,
        onSelect: @escaping (TimelinePostActionMenuSelection) -> Void
    ) -> UIMenu {
        let children: [UIMenuElement]
        switch kind {
        case .repost:
            children = RepostChoice.allCases.map { choice in
                action(choice, selection: .repost(choice), onSelect: onSelect)
            }
        case .favorite:
            children = FavoriteChoice.allCases.map { choice in
                action(choice, selection: .favorite(choice), onSelect: onSelect)
            }
        case .more:
            children = PostActionChoice.menuGroups.map { choices in
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: choices.map { choice in
                        action(
                            choice,
                            selection: .more(choice),
                            onSelect: onSelect
                        )
                    }
                )
            }
        }
        return UIMenu(title: "", children: children)
    }

    private static func action<Choice: TimelinePostActionMenuChoice>(
        _ choice: Choice,
        selection: TimelinePostActionMenuSelection,
        onSelect: @escaping (TimelinePostActionMenuSelection) -> Void
    ) -> UIAction {
        UIAction(
            title: choice.title,
            image: UIImage(systemName: choice.systemName)
        ) { _ in
            onSelect(selection)
        }
    }
}
