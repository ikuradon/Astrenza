import SwiftUI

enum TimelineSwipeMetrics {
    static let shortThreshold: CGFloat = 58
    static let longThreshold: CGFloat = 146
}

enum TimelineSwipeDirection {
    case left
    case right
}

enum TimelineSwipeLength {
    case short
    case long
}

struct TimelineSwipeClassification {
    let direction: TimelineSwipeDirection
    let length: TimelineSwipeLength
}

struct TimelineSwipeAction: Equatable {
    let title: String

    var kind: Kind {
        switch title {
        case "Favorite":
            .favorite
        case "Repost", "Boost":
            .repost
        case "Quote":
            .quote
        case "Bookmark":
            .bookmark
        case "Open Link to Post":
            .openLink
        case "Copy Link to Post":
            .copyLink
        case "Copy Post":
            .copyPost
        case "Share Post":
            .sharePost
        case "Add to Read Later":
            .readLater
        case "Translate":
            .translate
        case "Reply":
            .reply
        case "View Detail":
            .viewDetail
        default:
            .noAction
        }
    }

    var systemName: String {
        switch kind {
        case .favorite:
            "star.fill"
        case .repost:
            "arrow.triangle.2.circlepath"
        case .quote:
            "quote.bubble.fill"
        case .bookmark:
            "bookmark.fill"
        case .openLink:
            "safari.fill"
        case .copyLink:
            "link"
        case .copyPost:
            "doc.on.doc.fill"
        case .sharePost:
            "square.and.arrow.up.fill"
        case .readLater:
            "clock.fill"
        case .translate:
            "character.bubble.fill"
        case .reply:
            "bubble.left.fill"
        case .viewDetail:
            "info.circle.fill"
        case .noAction:
            "xmark"
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .favorite:
            .yellow
        case .repost:
            .green
        case .quote, .reply, .openLink:
            .blue
        case .bookmark, .readLater:
            .orange
        case .copyLink, .copyPost, .sharePost:
            .cyan
        case .translate:
            .purple
        case .viewDetail:
            Color.astrenzaAccent
        case .noAction:
            .gray
        }
    }

    enum Kind {
        case favorite
        case repost
        case quote
        case bookmark
        case openLink
        case copyLink
        case copyPost
        case sharePost
        case readLater
        case translate
        case reply
        case viewDetail
        case noAction
    }
}

struct TimelineSwipeActionIndicator: View {
    let action: TimelineSwipeAction
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Image(systemName: action.systemName)
                .font(.system(size: 24, weight: .black))
            Text(action.title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(.white)
        .frame(width: 104, alignment: alignment == .leading ? .leading : .trailing)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

struct TimelineSwipeFeedbackView: View {
    let action: TimelineSwipeAction

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: action.systemName)
            Text(action.title)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(action.backgroundColor.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
    }
}
