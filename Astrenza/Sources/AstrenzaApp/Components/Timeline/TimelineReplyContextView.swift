import AstrenzaCore
import SwiftUI

enum TimelineReplyContextStyle {
    case timeline
}

struct TimelineReplyContextView: View {
    let context: TimelineReplyContext
    let style: TimelineReplyContextStyle

    var body: some View {
        HStack(spacing: 6) {
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
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(backgroundColor, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(context.author.primaryText) reply context")
    }

    private var avatarSize: CGFloat {
        switch style {
        case .timeline: AstrenzaTimelineMetrics.contextAvatarSize
        }
    }

    private var fontSize: CGFloat {
        switch style {
        case .timeline: 12
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .timeline: 11
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
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reply")
    }
}

enum TimelineBodySummaryProminence {
    case normal
    case muted
    case warning
}

struct TimelineBodySummaryPill: View {
    let systemName: String
    let text: String
    var prominence: TimelineBodySummaryProminence = .normal

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .black))

            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        }
        .fixedSize()
    }

    private var foregroundStyle: Color {
        switch prominence {
        case .normal:
            Color.astrenzaAccent
        case .muted:
            .secondary
        case .warning:
            .orange
        }
    }

    private var backgroundColor: Color {
        switch prominence {
        case .normal:
            Color.astrenzaAccent.opacity(0.12)
        case .muted:
            Color.white.opacity(0.06)
        case .warning:
            Color.orange.opacity(0.13)
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .normal:
            Color.astrenzaAccent.opacity(0.18)
        case .muted:
            Color.white.opacity(0.08)
        case .warning:
            Color.orange.opacity(0.24)
        }
    }
}

struct TimelinePostBodyText: View {
    let text: String
    var richContent: NostrRichContent? = nil
    let mention: TimelineReplyMention?
    var lineLimit: Int?

    var bodyView: some View {
        Text(attributedText)
            .font(.system(size: AstrenzaTimelineMetrics.bodyFontSize, weight: .regular))
            .lineSpacing(AstrenzaTimelineMetrics.bodyLineSpacing)
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

        if let richContent {
            for token in richContent.tokens {
                result += attributedToken(token)
            }
        } else {
            var bodyPart = AttributedString(text)
            bodyPart.foregroundColor = Color.astrenzaText
            result += bodyPart
        }

        return result
    }

    private func attributedToken(_ token: NostrRichContentToken) -> AttributedString {
        var part = AttributedString(token.displayText)
        switch token {
        case .text:
            part.foregroundColor = Color.astrenzaText
        case .url(let url):
            part.foregroundColor = Color.astrenzaAccent
            part.link = url
        case .hashtag(let hashtag):
            part.foregroundColor = Color.astrenzaAccent
            part.link = URL(string: "astrenza://hashtag/\(hashtag)")
        case .profile(let pubkey, _):
            part.foregroundColor = Color.astrenzaAccent
            part.link = URL(string: "astrenza://profile/\(pubkey)")
        case .event(let eventID, _, _, _):
            part.foregroundColor = Color.astrenzaAccent
            part.link = URL(string: "astrenza://event/\(eventID)")
        case .customEmoji:
            part.foregroundColor = Color.astrenzaAccent
        }
        return part
    }
}
