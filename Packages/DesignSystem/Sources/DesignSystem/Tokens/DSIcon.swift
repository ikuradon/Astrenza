import SwiftUI

public enum DSIconContext: String, Codable, Sendable {
    case timelineAction
    case compactBadge
    case composeFAB
    case tab
}

public enum DSIcon: String, CaseIterable, Codable, Sendable {
    case reply = "bubble.left"
    case repost = "arrow.triangle.2.circlepath"
    case reaction = "heart"
    case reactionFilled = "heart.fill"
    case share = "square.and.arrow.up"
    case more = "ellipsis"
    case warning = "exclamationmark.triangle.fill"
    case sensitive = "eye.slash.fill"
    case link = "link"
    case quote = "quote.bubble"
    case compose = "square.and.pencil"
    case newPosts = "arrow.up"
    case avatarPlaceholder = "person.crop.circle"
    case lock = "lock.fill"

    public var systemName: String {
        rawValue
    }

    public func visualSize(for context: DSIconContext) -> Double {
        switch context {
        case .timelineAction:
            22
        case .compactBadge:
            12
        case .composeFAB:
            22
        case .tab:
            26
        }
    }

    public func font(for context: DSIconContext, weight: Font.Weight = .semibold) -> Font {
        font(size: visualSize(for: context), weight: weight)
    }

    public func font(size pointSize: Double, weight: Font.Weight = .semibold) -> Font {
        .system(size: CGFloat(pointSize), weight: weight)
    }
}
