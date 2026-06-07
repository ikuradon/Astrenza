import Foundation

public struct NostrRichContent: Equatable, Sendable {
    public let displayText: String
    public let tokens: [NostrRichContentToken]
    public let references: [NostrRichContentReference]

    public init(
        displayText: String,
        tokens: [NostrRichContentToken],
        references: [NostrRichContentReference]
    ) {
        self.displayText = displayText
        self.tokens = tokens
        self.references = references
    }
}

public enum NostrRichContentToken: Equatable, Sendable {
    case text(String)
    case url(url: URL)
    case profile(pubkey: String, relays: [String])
    case event(eventID: String, relays: [String], author: String?, kind: Int?)
    case customEmoji(shortcode: String, url: URL)

    public var displayText: String {
        switch self {
        case .text(let text):
            text
        case .url(let url):
            url.absoluteString
        case .profile(let pubkey, _):
            profileDisplay(pubkey: pubkey)
        case .event(let eventID, _, _, _):
            eventDisplay(eventID: eventID)
        case .customEmoji(let shortcode, _):
            ":\(shortcode):"
        }
    }

    private func profileDisplay(pubkey: String) -> String {
        "@npub:\(pubkey.prefix(8))"
    }

    private func eventDisplay(eventID: String) -> String {
        "note:\(eventID.prefix(8))"
    }
}

public enum NostrRichContentReference: Equatable, Sendable {
    case profile(pubkey: String, relays: [String])
    case event(eventID: String, relays: [String], author: String?, kind: Int?)
}

public enum NostrRichContentParser {
    public static func parse(
        event: NostrEvent,
        attachments: [NostrClassifiedAttachment] = [],
        promotedLinkURLs: [URL] = []
    ) -> NostrRichContent {
        let customEmojis = customEmojiMap(from: event.tags)
        let hiddenURLs = Set(
            attachments.filter { $0.kind == .media }.map(\.normalizedURL)
                + promotedLinkURLs.map(NostrLinkParser.normalizedURLString)
        )

        var tokens: [NostrRichContentToken] = []
        var references: [NostrRichContentReference] = []

        for rawToken in event.content.split(whereSeparator: \.isWhitespace).map(String.init) {
            let token = trimmedToken(rawToken)
            guard !token.value.isEmpty else { continue }

            if let url = URL(string: token.value),
               url.scheme == "http" || url.scheme == "https"
            {
                let normalizedURL = NostrLinkParser.normalizedURLString(url)
                guard !hiddenURLs.contains(normalizedURL) else { continue }
                tokens.append(.url(url: url))
                continue
            }

            if let emojiToken = customEmojiToken(from: token.value, customEmojis: customEmojis, trailing: token.trailing) {
                tokens.append(emojiToken)
                continue
            }

            if let profile = profileReference(from: token.value) {
                tokens.append(.profile(pubkey: profile.pubkey, relays: profile.relays))
                references.append(.profile(pubkey: profile.pubkey, relays: profile.relays))
                continue
            }

            if let eventReference = eventReference(from: token.value) {
                tokens.append(.event(
                    eventID: eventReference.eventID,
                    relays: eventReference.relays,
                    author: eventReference.author,
                    kind: eventReference.kind
                ))
                references.append(.event(
                    eventID: eventReference.eventID,
                    relays: eventReference.relays,
                    author: eventReference.author,
                    kind: eventReference.kind
                ))
                continue
            }

            tokens.append(.text(rawToken))
        }

        return NostrRichContent(
            displayText: tokens.map(\.displayText).joined(separator: " "),
            tokens: tokens,
            references: references
        )
    }

    private static func customEmojiMap(from tags: [[String]]) -> [String: URL] {
        var result: [String: URL] = [:]
        for tag in tags where tag.count >= 3 && tag[0] == "emoji" {
            let shortcode = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcode.isEmpty,
                  let url = URL(string: tag[2]),
                  url.scheme == "http" || url.scheme == "https"
            else { continue }
            result[shortcode] = url
        }
        return result
    }

    private static func customEmojiToken(
        from token: String,
        customEmojis: [String: URL],
        trailing: String
    ) -> NostrRichContentToken? {
        guard token.hasPrefix(":"),
              token.hasSuffix(":"),
              token.count > 2
        else { return nil }
        let shortcode = String(token.dropFirst().dropLast())
        guard let url = customEmojis[shortcode] else { return nil }
        return .customEmoji(shortcode: shortcode, url: url)
    }

    private static func profileReference(from token: String) -> NostrNIP19ProfileReference? {
        guard isNIP19Token(token, prefixes: ["npub", "nprofile"]) else { return nil }
        return try? NostrNIP19.profileReference(from: token)
    }

    private static func eventReference(from token: String) -> NostrNIP19EventReference? {
        guard isNIP19Token(token, prefixes: ["note", "nevent"]) else { return nil }
        return try? NostrNIP19.eventReference(from: token)
    }

    private static func isNIP19Token(_ token: String, prefixes: [String]) -> Bool {
        let lowered = token.lowercased()
        let value = lowered.hasPrefix("nostr:") ? String(lowered.dropFirst("nostr:".count)) : lowered
        return prefixes.contains { value.hasPrefix($0 + "1") }
    }

    private static func trimmedToken(_ token: String) -> (value: String, trailing: String) {
        var value = token
        var trailing = ""
        while let last = value.unicodeScalars.last,
              trailingPunctuation.contains(last)
        {
            trailing = String(last) + trailing
            value.removeLast()
        }
        return (value, trailing)
    }

    private static var trailingPunctuation: CharacterSet {
        CharacterSet(charactersIn: ".,;!?)]}>\n")
    }
}
