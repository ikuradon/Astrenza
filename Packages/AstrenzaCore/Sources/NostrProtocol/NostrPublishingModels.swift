public struct NostrUnsignedEvent: Equatable, Sendable {
    public let pubkey: String
    public let createdAt: Int
    public let kind: Int
    public let tags: [[String]]
    public let content: String

    public init(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) {
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
    }

    public var eventID: String {
        NostrEvent(
            id: String(repeating: "0", count: 64),
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        ).computedID
    }
}

public struct NostrReplyReference: Equatable, Sendable {
    public let eventID: String
    public let relayHint: String?
    public let pubkey: String?

    public init(eventID: String, relayHint: String? = nil, pubkey: String? = nil) {
        self.eventID = eventID
        self.relayHint = relayHint
        self.pubkey = pubkey
    }
}

public enum NostrPublishInput: Equatable, Sendable {
    case post(content: String, tags: [[String]] = [])
    case reply(content: String, root: NostrReplyReference, parent: NostrReplyReference, tags: [[String]] = [])
    case delete(eventIDs: [String], reason: String = "")

    public func unsignedEvent(pubkey: String, createdAt: Int) -> NostrUnsignedEvent {
        switch self {
        case .post(let content, let tags):
            return NostrUnsignedEvent(pubkey: pubkey, createdAt: createdAt, kind: 1, tags: tags, content: content)

        case .reply(let content, let root, let parent, let tags):
            return NostrUnsignedEvent(
                pubkey: pubkey,
                createdAt: createdAt,
                kind: 1,
                tags: replyTags(root: root, parent: parent, extraTags: tags),
                content: content
            )

        case .delete(let eventIDs, let reason):
            let tags = eventIDs.map { ["e", $0] }
            return NostrUnsignedEvent(pubkey: pubkey, createdAt: createdAt, kind: 5, tags: tags, content: reason)
        }
    }

    private func replyTags(
        root: NostrReplyReference,
        parent: NostrReplyReference,
        extraTags: [[String]]
    ) -> [[String]] {
        var tags = extraTags
        tags.append(eventTag(reference: root, marker: "root"))
        if parent.eventID != root.eventID {
            tags.append(eventTag(reference: parent, marker: "reply"))
        }
        if let parentPubkey = parent.pubkey {
            tags.append(["p", parentPubkey])
        }
        return tags
    }

    private func eventTag(reference: NostrReplyReference, marker: String) -> [String] {
        var tag = ["e", reference.eventID]
        tag.append(reference.relayHint ?? "")
        tag.append(marker)
        return tag
    }
}
