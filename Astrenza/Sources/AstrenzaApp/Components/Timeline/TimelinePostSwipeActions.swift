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
        VStack(alignment: alignment, spacing: AstrenzaSpacing.point6) {
            Image(systemName: action.systemName)
                .font(.astrenza(.point24, weight: .black))
            Text(action.title)
                .font(.astrenza(.point13, weight: .heavy, design: .rounded))
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
        HStack(spacing: AstrenzaSpacing.point7) {
            Image(systemName: action.systemName)
            Text(action.title)
        }
        .font(.astrenza(.point13, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, AstrenzaSpacing.point12)
        .frame(height: 32)
        .background(action.backgroundColor.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
    }
}

struct TimelineSwipeContainer<Content: View>: View {
    let swipeSettings: TimelineSwipeSettings
    var isEnabled = true
    let onSwipeChanged: () -> Void
    let onSwipeAction: (TimelineSwipeAction) -> Bool
    @ViewBuilder let content: () -> Content
    @State private var swipeFeedback: TimelineSwipeAction?
    @State private var swipeTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            swipeActionBackdrop

            content()
                .offset(x: displayedSwipeOffset)
        }
        .clipped()
        .contentShape(Rectangle())
        .background {
            TimelineRowPanGestureHost(
                isEnabled: isEnabled,
                onChanged: handleSwipeChanged,
                onEnded: handleSwipeEnded
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if let swipeFeedback {
                TimelineSwipeFeedbackView(action: swipeFeedback)
                    .padding(.top, AstrenzaSpacing.point10)
                    .transition(.scale(scale: 0.84).combined(with: .opacity))
            }
        }
    }

    private var displayedSwipeOffset: CGFloat {
        guard abs(swipeTranslation) > 0 else { return 0 }
        let cappedOffset = min(abs(swipeTranslation), 178)
        return cappedOffset * (swipeTranslation < 0 ? -1 : 1)
    }

    private var swipeProgress: Double {
        min(max(abs(swipeTranslation) / TimelineSwipeMetrics.longThreshold, 0.18), 1)
    }

    private var currentSwipeAction: TimelineSwipeAction? {
        guard let classification = swipeClassification(for: swipeTranslation) else { return nil }
        return swipeAction(for: classification)
    }

    @ViewBuilder
    private var swipeActionBackdrop: some View {
        if let action = currentSwipeAction {
            HStack {
                if swipeTranslation > 0 {
                    TimelineSwipeActionIndicator(action: action, alignment: .leading)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    TimelineSwipeActionIndicator(action: action, alignment: .trailing)
                }
            }
            .padding(.horizontal, AstrenzaSpacing.point24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(action.backgroundColor.opacity(swipeProgress))
        }
    }

    private func handleSwipeChanged(_ translationWidth: CGFloat) {
        onSwipeChanged()
        swipeTranslation = translationWidth
    }

    private func handleSwipeEnded(_ translationWidth: CGFloat) {
        defer {
            withAnimation(.spring(duration: AstrenzaMotion.responsive, bounce: 0.1)) {
                swipeTranslation = 0
            }
        }

        guard let classification = swipeClassification(for: translationWidth) else {
            return
        }

        let action = swipeAction(for: classification)
        if onSwipeAction(action) {
            showSwipeFeedback(action)
        }
    }

    private func swipeClassification(for translationWidth: CGFloat) -> TimelineSwipeClassification? {
        let distance = abs(translationWidth)
        guard distance >= TimelineSwipeMetrics.shortThreshold else { return nil }

        let direction: TimelineSwipeDirection = translationWidth < 0 ? .left : .right
        let length: TimelineSwipeLength = distance >= TimelineSwipeMetrics.longThreshold ? .long : .short
        return TimelineSwipeClassification(direction: direction, length: length)
    }

    private func swipeAction(for classification: TimelineSwipeClassification) -> TimelineSwipeAction {
        let title: String
        switch (classification.direction, classification.length) {
        case (.left, .long):
            title = swipeSettings.longLeftSwipe
        case (.right, .long):
            title = swipeSettings.longRightSwipe
        case (.left, .short):
            title = swipeSettings.shortLeftSwipe
        case (.right, .short):
            title = swipeSettings.shortRightSwipe
        }

        return TimelineSwipeAction(title: title)
    }

    private func showSwipeFeedback(_ action: TimelineSwipeAction) {
        withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.16)) {
            swipeFeedback = action
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: AstrenzaMotion.fast)) {
                if swipeFeedback == action {
                    swipeFeedback = nil
                }
            }
        }
    }
}
