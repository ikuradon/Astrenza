import AstrenzaCore
import Foundation
import SwiftUI

struct NostrEmojiSetReference: Hashable, Sendable {
    let pubkey: String
    let dTag: String
    let relayHint: String?

    var address: String {
        "30030:\(pubkey):\(dTag)"
    }

    static func references(in event: NostrEvent?) -> [NostrEmojiSetReference] {
        guard let event, event.kind == 10_030 else { return [] }
        var seen = Set<String>()
        return event.tags.compactMap { tag in
            guard tag.count >= 2,
                  tag[0] == "a",
                  let reference = parse(
                    address: tag[1],
                    relayHint: tag.count >= 3 ? tag[2] : nil
                  ),
                  seen.insert(reference.address).inserted
            else { return nil }
            return reference
        }
    }

    static func parse(
        address: String,
        relayHint: String? = nil
    ) -> NostrEmojiSetReference? {
        let parts = address.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard parts.count == 3,
              parts[0] == "30030"
        else { return nil }
        let pubkey = String(parts[1]).lowercased()
        let dTag = String(parts[2])
        guard NostrHex.isLowercaseHex(pubkey, byteCount: 32),
              !dTag.isEmpty
        else { return nil }
        return NostrEmojiSetReference(
            pubkey: pubkey,
            dTag: dTag,
            relayHint: relayHint.flatMap { NostrRelayURL($0)?.rawValue }
        )
    }
}

struct ComposeCustomEmojiCandidate: Identifiable, Equatable {
    let shortcode: String
    let glyph: String
    let tint: Color
    let imageURL: URL?
    let emojiSetAddress: String?

    init(
        shortcode: String,
        glyph: String,
        tint: Color,
        imageURL: URL? = nil,
        emojiSetAddress: String? = nil
    ) {
        self.shortcode = shortcode
        self.glyph = glyph
        self.tint = tint
        self.imageURL = imageURL
        self.emojiSetAddress = emojiSetAddress
    }

    var id: String {
        "\(emojiSetAddress ?? "direct")\u{1f}\(shortcode.lowercased())"
    }
}

struct ComposeCustomEmojiSet: Identifiable, Equatable {
    let id: String
    let title: String
    let imageURL: URL?
    let detail: String?
    let emojis: [ComposeCustomEmojiCandidate]
}

enum ComposeEmojiCatalogProjection {
    static func project(
        emojiListEvent: NostrEvent?,
        emojiSetEvents: [NostrEvent]
    ) -> [ComposeCustomEmojiSet] {
        guard let emojiListEvent,
              emojiListEvent.kind == 10_030
        else { return [] }

        var sections: [ComposeCustomEmojiSet] = []
        let directEmojis = candidates(
            in: emojiListEvent,
            defaultSetAddress: nil
        )
        if !directEmojis.isEmpty {
            sections.append(ComposeCustomEmojiSet(
                id: "kind-10030-direct",
                title: "MY EMOJIS",
                imageURL: nil,
                detail: nil,
                emojis: directEmojis
            ))
        }

        let newestEventByAddress = newestAddressableEvents(emojiSetEvents)
        for reference in NostrEmojiSetReference.references(in: emojiListEvent) {
            guard let event = newestEventByAddress[reference.address] else {
                continue
            }
            let emojis = candidates(
                in: event,
                defaultSetAddress: reference.address
            )
            guard !emojis.isEmpty else { continue }
            sections.append(ComposeCustomEmojiSet(
                id: reference.address,
                title: tagValue("title", in: event) ?? reference.dTag,
                imageURL: tagValue("image", in: event).flatMap(webURL),
                detail: tagValue("description", in: event),
                emojis: emojis
            ))
        }
        return sections
    }

    private static func newestAddressableEvents(
        _ events: [NostrEvent]
    ) -> [String: NostrEvent] {
        var result: [String: NostrEvent] = [:]
        for event in events where event.kind == 30_030 {
            guard let dTag = tagValue("d", in: event) else { continue }
            let address = "30030:\(event.pubkey.lowercased()):\(dTag)"
            guard let current = result[address] else {
                result[address] = event
                continue
            }
            if event.createdAt > current.createdAt ||
                (event.createdAt == current.createdAt && event.id > current.id) {
                result[address] = event
            }
        }
        return result
    }

    private static func candidates(
        in event: NostrEvent,
        defaultSetAddress: String?
    ) -> [ComposeCustomEmojiCandidate] {
        var seen = Set<String>()
        return event.tags.compactMap { tag in
            guard tag.count >= 3,
                  tag[0] == "emoji"
            else { return nil }
            let name = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            guard isValidShortcode(name),
                  seen.insert(key).inserted,
                  let imageURL = webURL(tag[2])
            else { return nil }
            let taggedSetAddress = tag.count >= 4
                ? NostrEmojiSetReference.parse(address: tag[3])?.address
                : nil
            return ComposeCustomEmojiCandidate(
                shortcode: ":\(name):",
                glyph: String(name.prefix(1)).uppercased(),
                tint: .astrenzaAccent,
                imageURL: imageURL,
                emojiSetAddress: taggedSetAddress ?? defaultSetAddress
            )
        }
    }

    private static func tagValue(
        _ name: String,
        in event: NostrEvent
    ) -> String? {
        event.tags.first(where: { tag in
            tag.count >= 2 && tag[0] == name
        })?[1].trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private static func isValidShortcode(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45
                || byte == 95
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
