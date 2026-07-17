import Foundation
import NostrProtocol
import NostrStoreAPI

public struct NostrRichContent: Equatable, Sendable {
    public let displayText: String
    public let tokens: [NostrRichContentToken]
    public let references: [NostrRichContentReference]
    public let profileDisplayNamesByPubkey: [String: String]
    public let eventDisplayTextByID: [String: String]

    public init(
        displayText: String,
        tokens: [NostrRichContentToken],
        references: [NostrRichContentReference],
        profileDisplayNamesByPubkey: [String: String] = [:],
        eventDisplayTextByID: [String: String] = [:]
    ) {
        self.displayText = displayText
        self.tokens = tokens
        self.references = references
        self.profileDisplayNamesByPubkey = profileDisplayNamesByPubkey
        self.eventDisplayTextByID = eventDisplayTextByID
    }

    public func displayText(for token: NostrRichContentToken) -> String {
        token.displayText(
            profileDisplayNamesByPubkey: profileDisplayNamesByPubkey,
            eventDisplayTextByID: eventDisplayTextByID
        )
    }

    public func resolving(
        profileDisplayNamesByPubkey newProfileDisplayNames: [String: String] = [:],
        eventDisplayTextByID newEventDisplayTextByID: [String: String] = [:]
    ) -> NostrRichContent {
        let profileDisplayNames = profileDisplayNamesByPubkey.merging(newProfileDisplayNames) { _, new in new }
        let eventDisplayText = eventDisplayTextByID.merging(newEventDisplayTextByID) { _, new in new }
        return NostrRichContent(
            displayText: Self.displayText(
                from: tokens,
                profileDisplayNamesByPubkey: profileDisplayNames,
                eventDisplayTextByID: eventDisplayText
            ),
            tokens: tokens,
            references: references,
            profileDisplayNamesByPubkey: profileDisplayNames,
            eventDisplayTextByID: eventDisplayText
        )
    }

    private static func displayText(
        from tokens: [NostrRichContentToken],
        profileDisplayNamesByPubkey: [String: String],
        eventDisplayTextByID: [String: String]
    ) -> String {
        tokens.map {
            $0.displayText(
                profileDisplayNamesByPubkey: profileDisplayNamesByPubkey,
                eventDisplayTextByID: eventDisplayTextByID
            )
        }.joined()
    }
}

public enum NostrRichContentToken: Equatable, Sendable {
    case text(String)
    case url(url: URL)
    case hashtag(String)
    case profile(pubkey: String, relays: [String])
    case event(eventID: String, relays: [String], author: String?, kind: Int?)
    case customEmoji(shortcode: String, url: URL)

    public var displayText: String {
        switch self {
        case .text(let text):
            text
        case .url(let url):
            url.absoluteString
        case .hashtag(let value):
            "#\(value)"
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

    fileprivate func displayText(
        profileDisplayNamesByPubkey: [String: String],
        eventDisplayTextByID: [String: String]
    ) -> String {
        switch self {
        case .profile(let pubkey, _):
            if let displayName = profileDisplayNamesByPubkey[pubkey], !displayName.isEmpty {
                return "@\(displayName)"
            }
            return displayText
        case .event(let eventID, _, _, _):
            return eventDisplayTextByID[eventID] ?? displayText
        case .text, .url, .hashtag, .customEmoji:
            return displayText
        }
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
        promotedLinkURLs: [URL] = [],
        hiddenEventIDs: Set<String> = []
    ) -> NostrRichContent {
        let customEmojis = customEmojiMap(from: event.tags)
        let hiddenURLs = Set(
            attachments.filter { $0.kind == .media }.map(\.normalizedURL)
                + promotedLinkURLs.map(NostrLinkParser.normalizedURLString)
        )

        var tokens: [NostrRichContentToken] = []
        var references: [NostrRichContentReference] = []
        var skipWhitespaceAfterHiddenToken = false

        for rawToken in lexicalTokens(from: event.content) {
            if rawToken.allSatisfy(\.isWhitespace) {
                if skipWhitespaceAfterHiddenToken {
                    skipWhitespaceAfterHiddenToken = false
                    continue
                }
                appendText(rawToken, to: &tokens)
                continue
            }
            skipWhitespaceAfterHiddenToken = false

            let token = trimmedToken(rawToken)
            guard !token.value.isEmpty else { continue }

            if let url = URL(string: token.value),
               url.scheme == "http" || url.scheme == "https"
            {
                let normalizedURL = NostrLinkParser.normalizedURLString(url)
                guard !hiddenURLs.contains(normalizedURL) else {
                    appendTrailing(token.trailing, to: &tokens)
                    skipWhitespaceAfterHiddenToken = true
                    continue
                }
                tokens.append(.url(url: url))
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            if let hashtag = hashtag(from: token.value) {
                tokens.append(.hashtag(hashtag))
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            if let emojiTokens = customEmojiTokens(
                from: token.value,
                customEmojis: customEmojis
            ) {
                tokens.append(contentsOf: emojiTokens)
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            if let profile = profileReference(from: token.value) {
                tokens.append(.profile(pubkey: profile.pubkey, relays: profile.relays))
                references.append(.profile(pubkey: profile.pubkey, relays: profile.relays))
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            if let eventReference = eventReference(from: token.value) {
                guard !hiddenEventIDs.contains(eventReference.eventID) else {
                    appendTrailing(token.trailing, to: &tokens)
                    skipWhitespaceAfterHiddenToken = true
                    continue
                }
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
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            if let indexedReference = indexedReference(from: token.value, event: event) {
                tokens.append(indexedReference.token)
                if let reference = indexedReference.reference {
                    references.append(reference)
                }
                appendTrailing(token.trailing, to: &tokens)
                continue
            }

            appendText(rawToken, to: &tokens)
        }

        removeTrailingWhitespaceText(from: &tokens)

        return NostrRichContent(
            displayText: displayText(from: tokens),
            tokens: tokens,
            references: references
        )
    }

    private static func lexicalTokens(from content: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for character in content {
            let isWhitespace = character.isWhitespace
            if currentIsWhitespace == nil || currentIsWhitespace == isWhitespace {
                current.append(character)
                currentIsWhitespace = isWhitespace
            } else {
                result.append(current)
                current = String(character)
                currentIsWhitespace = isWhitespace
            }
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func displayText(from tokens: [NostrRichContentToken]) -> String {
        tokens.map(\.displayText).joined()
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

    private static func customEmojiTokens(
        from token: String,
        customEmojis: [String: URL]
    ) -> [NostrRichContentToken]? {
        guard !customEmojis.isEmpty else { return nil }

        var tokens: [NostrRichContentToken] = []
        var plainTextStart = token.startIndex
        var cursor = token.startIndex
        var openingColon: String.Index?
        var foundEmoji = false

        while cursor < token.endIndex {
            if token[cursor] == ":" {
                if let candidateStart = openingColon {
                    let shortcodeStart = token.index(after: candidateStart)
                    let shortcode = String(token[shortcodeStart..<cursor])
                    if let url = customEmojis[shortcode] {
                        appendText(String(token[plainTextStart..<candidateStart]), to: &tokens)
                        tokens.append(.customEmoji(shortcode: shortcode, url: url))
                        foundEmoji = true
                        plainTextStart = token.index(after: cursor)
                        openingColon = nil
                    } else {
                        openingColon = cursor
                    }
                } else {
                    openingColon = cursor
                }
            }
            cursor = token.index(after: cursor)
        }

        guard foundEmoji else { return nil }
        appendText(String(token[plainTextStart...]), to: &tokens)
        return tokens
    }

    private static func hashtag(from token: String) -> String? {
        guard token.hasPrefix("#"), token.count > 1 else { return nil }
        let value = String(token.dropFirst())
        guard value.unicodeScalars.allSatisfy({ scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }) else { return nil }
        return value
    }

    private static func profileReference(from token: String) -> NostrNIP19ProfileReference? {
        guard isNIP19Token(token, prefixes: ["npub", "nprofile"]) else { return nil }
        return try? NostrNIP19.profileReference(from: token)
    }

    private static func eventReference(from token: String) -> NostrNIP19EventReference? {
        guard isNIP19Token(token, prefixes: ["note", "nevent"]) else { return nil }
        return try? NostrNIP19.eventReference(from: token)
    }

    private static func indexedReference(
        from token: String,
        event: NostrEvent
    ) -> (token: NostrRichContentToken, reference: NostrRichContentReference?)? {
        guard isCompleteIndexedReference(token) else { return nil }
        let indexText = token.dropFirst(2).dropLast()
        guard let index = Int(indexText),
              event.tags.indices.contains(index)
        else { return nil }

        let tag = event.tags[index]
        guard tag.count >= 2 else { return nil }
        let relays = relayHint(from: tag, at: 2).map { [$0] } ?? []
        switch tag[0] {
        case "p":
            let pubkey = tag[1]
            return (
                .profile(pubkey: pubkey, relays: relays),
                .profile(pubkey: pubkey, relays: relays)
            )
        case "e", "q":
            let eventID = tag[1]
            return (
                .event(eventID: eventID, relays: relays, author: nil, kind: nil),
                .event(eventID: eventID, relays: relays, author: nil, kind: nil)
            )
        default:
            return nil
        }
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
            if last == "]", isCompleteIndexedReference(value) {
                break
            }
            trailing = String(last) + trailing
            value.removeLast()
        }
        return (value, trailing)
    }

    private static func isCompleteIndexedReference(_ value: String) -> Bool {
        guard value.hasPrefix("#["),
              value.hasSuffix("]"),
              value.count > 3
        else { return false }
        let digits = value.dropFirst(2).dropLast()
        return digits.allSatisfy(\.isNumber)
    }

    private static func relayHint(from tag: [String], at index: Int) -> String? {
        guard tag.count > index else { return nil }
        let trimmed = tag[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              components.host?.isEmpty == false
        else { return nil }

        var normalized = components
        normalized.scheme = scheme
        normalized.host = components.host?.lowercased()
        return normalized.string
    }

    private static func appendTrailing(_ trailing: String, to tokens: inout [NostrRichContentToken]) {
        guard !trailing.isEmpty else { return }
        appendText(trailing, to: &tokens)
    }

    private static func appendText(_ text: String, to tokens: inout [NostrRichContentToken]) {
        guard !text.isEmpty else { return }
        if text.allSatisfy(\.isWhitespace),
           let last = tokens.last,
           case .text(let previousText) = last,
           previousText.allSatisfy(\.isWhitespace)
        {
            return
        }
        tokens.append(.text(text))
    }

    private static func removeTrailingWhitespaceText(from tokens: inout [NostrRichContentToken]) {
        guard let last = tokens.last,
              case .text(let text) = last,
              text.allSatisfy(\.isWhitespace)
        else { return }
        tokens.removeLast()
    }

    private static var trailingPunctuation: CharacterSet {
        CharacterSet(charactersIn: ".,;!?)]}>\n")
    }
}
