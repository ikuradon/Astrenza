import SwiftUI

enum TimelineReplyContextStyle {
    case timeline
}

struct TimelineReplyContextView: View {
    let context: TimelineReplyContext
    let style: TimelineReplyContextStyle

    var body: some View {
        HStack(spacing: 7) {
            AvatarView(style: context.avatar, size: avatarSize)

            Text(context.author.primaryText)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Image(systemName: context.isSelfReply ? "arrow.turn.down.right" : "bubble.left.and.bubble.right")
                .font(.system(size: iconSize, weight: .black))

        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(context.author.primaryText) reply context")
    }

    private var avatarSize: CGFloat {
        switch style {
        case .timeline: 24
        }
    }

    private var fontSize: CGFloat {
        switch style {
        case .timeline: 13
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .timeline: 12
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .timeline:
            Color.white.opacity(0.07)
        }
    }
}

struct TimelineReplyMarker: View {
    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reply")
    }
}

struct TimelinePostBodyText: View {
    let text: String
    let mention: TimelineReplyMention?
    var fontSize: CGFloat = 18
    var lineLimit: Int?

    var bodyView: some View {
        Text(attributedText)
            .font(.system(size: fontSize, weight: .regular))
            .lineSpacing(3)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        bodyView
    }

    private var attributedText: AttributedString {
        var result = AttributedString()

        if let mention {
            var mentionPart = AttributedString("\(mention.text) ")
            mentionPart.foregroundColor = mention.isExternal ? Color.astrenzaAccent : Color.astrenzaText
            result += mentionPart
        }

        var bodyPart = AttributedString(text)
        bodyPart.foregroundColor = Color.astrenzaText
        result += bodyPart

        return result
    }
}
