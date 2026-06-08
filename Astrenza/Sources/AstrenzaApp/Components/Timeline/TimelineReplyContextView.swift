import AstrenzaCore
import SwiftUI
import UIKit

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
        Group {
            if let richContent, richContent.hasCustomEmoji {
                TimelineRichPostBodyText(
                    richContent: richContent,
                    mention: mention,
                    lineLimit: lineLimit
                )
            } else {
                Text(attributedText)
                    .font(.system(size: AstrenzaTimelineMetrics.bodyFontSize, weight: .regular))
                    .lineSpacing(AstrenzaTimelineMetrics.bodyLineSpacing)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

private struct TimelineRichPostBodyText: View {
    let richContent: NostrRichContent
    let mention: TimelineReplyMention?
    let lineLimit: Int?
    @Environment(\.openURL) private var openURL
    @State private var emojiImages: [URL: UIImage] = [:]

    private var emojiURLs: [URL] {
        var seen = Set<URL>()
        return richContent.tokens.compactMap { token in
            guard case .customEmoji(_, let url) = token,
                  !seen.contains(url)
            else { return nil }
            seen.insert(url)
            return url
        }
    }

    var body: some View {
        TimelineRichPostBodyTextRepresentable(
            richContent: richContent,
            mention: mention,
            lineLimit: lineLimit,
            emojiImages: emojiImages,
            openURL: { url in
                openURL(url)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .task(id: emojiURLs) {
            await loadEmojiImages()
        }
    }

    private func loadEmojiImages() async {
        for url in emojiURLs where emojiImages[url] == nil {
            if let cachedImage = NostrImageCache.shared.cachedImage(for: url) {
                emojiImages[url] = cachedImage
                continue
            }

            do {
                let image = try await NostrImageCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                emojiImages[url] = image
            } catch {
                continue
            }
        }
    }
}

private struct TimelineRichPostBodyTextRepresentable: UIViewRepresentable {
    let richContent: NostrRichContent
    let mention: TimelineReplyMention?
    let lineLimit: Int?
    let emojiImages: [URL: UIImage]
    let openURL: (URL) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(Color.astrenzaAccent)
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        textView.attributedText = attributedString
        textView.textContainer.maximumNumberOfLines = lineLimit ?? 0
        textView.textContainer.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: fittingSize.height)
    }

    private var attributedString: NSAttributedString {
        let result = NSMutableAttributedString()
        let baseAttributes = textAttributes(color: UIColor(Color.astrenzaText))
        let accentAttributes = textAttributes(color: UIColor(Color.astrenzaAccent))

        if let mention {
            var attributes = mention.isExternal ? accentAttributes : baseAttributes
            attributes[.foregroundColor] = UIColor(mention.isExternal ? Color.astrenzaAccent : Color.astrenzaText)
            result.append(NSAttributedString(string: "\(mention.text) ", attributes: attributes))
        }

        for token in richContent.tokens {
            switch token {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .url(let url):
                var attributes = accentAttributes
                attributes[.link] = url
                result.append(NSAttributedString(string: url.absoluteString, attributes: attributes))
            case .hashtag(let hashtag):
                var attributes = accentAttributes
                attributes[.link] = URL(string: "astrenza://hashtag/\(hashtag)")
                result.append(NSAttributedString(string: "#\(hashtag)", attributes: attributes))
            case .profile(let pubkey, _):
                var attributes = accentAttributes
                attributes[.link] = URL(string: "astrenza://profile/\(pubkey)")
                result.append(NSAttributedString(string: token.displayText, attributes: attributes))
            case .event(let eventID, _, _, _):
                var attributes = accentAttributes
                attributes[.link] = URL(string: "astrenza://event/\(eventID)")
                result.append(NSAttributedString(string: token.displayText, attributes: attributes))
            case .customEmoji(let shortcode, let url):
                result.append(customEmojiAttachment(shortcode: shortcode, url: url))
            }
        }

        return result
    }

    private func textAttributes(color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = AstrenzaTimelineMetrics.bodyLineSpacing
        paragraphStyle.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail

        return [
            .font: UIFont.systemFont(ofSize: AstrenzaTimelineMetrics.bodyFontSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func customEmojiAttachment(shortcode: String, url: URL) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let size = AstrenzaTimelineMetrics.bodyFontSize + 4
        attachment.bounds = CGRect(x: 0, y: -3, width: size, height: size)
        attachment.image = emojiImages[url] ?? Self.placeholderImage(shortcode: shortcode, size: size)
        return NSAttributedString(attachment: attachment)
    }

    private static func placeholderImage(shortcode: String, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            UIColor(Color.astrenzaAccent.opacity(0.22)).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: size * 0.28).fill()

            UIColor(Color.astrenzaAccent).setStroke()
            UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: size * 0.28).stroke()

            let symbol = String(shortcode.prefix(1)).uppercased()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.52, weight: .bold),
                .foregroundColor: UIColor(Color.astrenzaAccent)
            ]
            let symbolSize = symbol.size(withAttributes: attributes)
            symbol.draw(
                at: CGPoint(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2),
                withAttributes: attributes
            )

            _ = context
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: (URL) -> Void

        init(openURL: @escaping (URL) -> Void) {
            self.openURL = openURL
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else {
                return defaultAction
            }

            return UIAction { [weak self] _ in
                self?.openURL(url)
            }
        }
    }
}

private extension NostrRichContent {
    var hasCustomEmoji: Bool {
        tokens.contains { token in
            if case .customEmoji = token {
                return true
            }
            return false
        }
    }
}
