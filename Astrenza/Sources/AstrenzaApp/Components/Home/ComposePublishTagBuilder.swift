import AstrenzaCore
import Foundation

struct ComposePreparedPublish: Equatable, Sendable {
    let input: NostrPublishInput
    let taggedUserReadRelays: [String]
}

struct ComposePublishTagBuilder {
    private let eventStore: NostrEventStore?

    init(eventStore: NostrEventStore?) {
        self.eventStore = eventStore
    }

    func prepare(
        _ request: ComposeSubmitRequest,
        uploadedMedia: [ComposeUploadedMedia] = [],
        authorPubkey: String? = nil
    ) -> ComposePreparedPublish {
        var tags = commonTags(
            for: request,
            uploadedMedia: uploadedMedia,
            authorPubkey: authorPubkey
        )
        let textWithMedia = content(
            request.text,
            uploadedMedia: uploadedMedia
        )
        let content: String
        let recipientPubkeys: Set<String>
        let explicitRelayHints: Set<String>
        let input: NostrPublishInput

        switch request.context {
        case .post:
            content = textWithMedia
            recipientPubkeys = recipients(
                mentionedPubkeys(in: request.text),
                excluding: authorPubkey
            )
            explicitRelayHints = mentionRelayHints(in: request.text)
            input = .post(content: content, tags: tags)

        case .reply(let context):
            let replyRecipients = recipients(
                Set(context.recipientPubkeys)
                    .union(mentionedPubkeys(in: request.text)),
                excluding: authorPubkey
            )
            tags.append(contentsOf: replyRecipients.sorted().map { ["p", $0] })
            content = textWithMedia
            recipientPubkeys = replyRecipients
            explicitRelayHints = mentionRelayHints(in: request.text)
            input = .reply(
                content: content,
                root: context.root.nostrReference,
                parent: context.parent.nostrReference,
                tags: deduplicated(tags)
            )

        case .quote(let context):
            tags.append(eventTag(name: "q", reference: context.target))
            if let pubkey = context.target.pubkey, pubkey != authorPubkey {
                tags.append(["p", pubkey])
            }
            content = quoteContent(textWithMedia, target: context.target)
            recipientPubkeys = recipients(
                Set([context.target.pubkey].compactMap { $0 })
                    .union(mentionedPubkeys(in: request.text)),
                excluding: authorPubkey
            )
            explicitRelayHints = Set([context.target.relayHint].compactMap { $0 })
                .union(mentionRelayHints(in: request.text))
            input = .post(content: content, tags: deduplicated(tags))
        }

        return ComposePreparedPublish(
            input: input,
            taggedUserReadRelays: relayDestinations(
                for: recipientPubkeys,
                explicitRelayHints: explicitRelayHints
            )
        )
    }

    private func commonTags(
        for request: ComposeSubmitRequest,
        uploadedMedia: [ComposeUploadedMedia],
        authorPubkey: String?
    ) -> [[String]] {
        var tags: [[String]] = []
        if request.isSensitive {
            tags.append(["content-warning", request.sensitiveReason])
        }
        tags.append(contentsOf: request.customEmojis.map { emoji in
            var tag = ["emoji", emoji.shortcode, emoji.url]
            if let emojiSetAddress = emoji.emojiSetAddress {
                tag.append(emojiSetAddress)
            }
            return tag
        })
        tags.append(contentsOf: hashtags(in: request.text).map { ["t", $0] })
        tags.append(contentsOf: recipients(
            mentionedPubkeys(in: request.text),
            excluding: authorPubkey
        ).sorted().map { ["p", $0] })
        tags.append(contentsOf: uploadedMedia.map(imetaTag))
        return deduplicated(tags)
    }

    private func content(
        _ text: String,
        uploadedMedia: [ComposeUploadedMedia]
    ) -> String {
        let urls = uploadedMedia.map { $0.url.absoluteString }
            .filter { !text.contains($0) }
        guard !urls.isEmpty else { return text }
        return ([text].filter { !$0.isEmpty } + urls).joined(separator: "\n")
    }

    private func imetaTag(_ media: ComposeUploadedMedia) -> [String] {
        var tag = [
            "imeta",
            "url \(media.url.absoluteString)",
            "m \(media.mimeType)",
            "x \(media.sha256)"
        ]
        if let width = media.width, let height = media.height {
            tag.append("dim \(width)x\(height)")
        }
        if let altText = media.altText, !altText.isEmpty {
            tag.append("alt \(altText)")
        }
        return tag
    }

    private func quoteContent(
        _ text: String,
        target: ComposeEventReference
    ) -> String {
        guard let reference = try? NostrNIP19.encodeEventReference(
            eventID: target.eventID,
            relays: [target.relayHint].compactMap { $0 },
            author: target.pubkey,
            kind: 1
        ) else { return text }
        let nostrURI = "nostr:\(reference)"
        guard !text.contains(nostrURI) else { return text }
        return text.isEmpty ? nostrURI : "\(text)\n\n\(nostrURI)"
    }

    private func eventTag(
        name: String,
        reference: ComposeEventReference
    ) -> [String] {
        var tag = [name, reference.eventID, reference.relayHint ?? ""]
        if let pubkey = reference.pubkey {
            tag.append(pubkey)
        }
        return tag
    }

    private func hashtags(in text: String) -> [String] {
        matches(pattern: #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}_]+)"#, in: text)
    }

    private func mentionedPubkeys(in text: String) -> Set<String> {
        Set(nostrTokens(in: text).compactMap {
            try? NostrNIP19.profileReference(from: $0).pubkey
        })
    }

    private func recipients(
        _ pubkeys: Set<String>,
        excluding authorPubkey: String?
    ) -> Set<String> {
        guard let authorPubkey else { return pubkeys }
        return pubkeys.subtracting([authorPubkey])
    }

    private func mentionRelayHints(in text: String) -> Set<String> {
        Set(nostrTokens(in: text).flatMap {
            (try? NostrNIP19.profileReference(from: $0).relays) ?? []
        })
    }

    private func nostrTokens(in text: String) -> [String] {
        matches(pattern: #"(?:nostr:)?((?:npub|nprofile)1[023456789acdefghjklmnpqrstuvwxyz]+)"#, in: text)
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let range = Range(result.range(at: 1), in: text)
            else { return nil }
            return String(text[range])
        }
    }

    private func relayDestinations(
        for pubkeys: Set<String>,
        explicitRelayHints: Set<String>
    ) -> [String] {
        var relays = explicitRelayHints
        if let eventStore, !pubkeys.isEmpty {
            let relayListEvents = (try? eventStore.latestReplaceableEvents(
                pubkeys: pubkeys,
                kind: 10_002
            )) ?? []
            for event in relayListEvents {
                relays.formUnion(NostrRelayList.parse(from: event).readRelays)
            }
            let observed = (try? eventStore.observedRelayURLsByAuthor(
                authors: pubkeys,
                limitPerAuthor: 2
            )) ?? [:]
            relays.formUnion(observed.values.flatMap { $0 })
        }
        return relays.sorted()
    }

    private func deduplicated(_ tags: [[String]]) -> [[String]] {
        var seen = Set<String>()
        return tags.filter { tag in
            seen.insert(tag.joined(separator: "\u{1f}")).inserted
        }
    }
}

private extension ComposeEventReference {
    var nostrReference: NostrReplyReference {
        NostrReplyReference(
            eventID: eventID,
            relayHint: relayHint,
            pubkey: pubkey
        )
    }
}
