import Foundation
import AstrenzaCore

struct NostrTimelineReplyProjection {
    let replyContext: TimelineReplyContext?
    let replyMention: TimelineReplyMention?

    init(
        event: NostrEvent,
        eventsByID: [String: NostrEvent],
        author: TimelineAuthor,
        avatarForParent: (NostrEvent) -> AvatarStyle,
        relativeTimestamp: (Int) -> String
    ) {
        self.replyContext = Self.replyContext(
            from: event,
            eventsByID: eventsByID,
            fallbackAuthor: author,
            avatarForParent: avatarForParent,
            relativeTimestamp: relativeTimestamp
        )
        self.replyMention = Self.replyMention(from: event, author: author)
    }

    static func replyParentID(from tags: [[String]]) -> String? {
        let replyTag = tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        if let replyTag, replyTag.count >= 2 {
            return replyTag[1]
        }

        let eTags = tags.filter { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        let hasMarkedThreadTags = eTags.contains { $0.count >= 4 }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?[1]
    }

    static func replyParentID(from tags: [NostrStoredEventTag]) -> String? {
        let replyTag = tags.last { $0.name == "e" && $0.marker == "reply" }
        if let replyTag {
            return replyTag.value
        }

        let eTags = tags.filter { $0.name == "e" }
        let hasMarkedThreadTags = eTags.contains { $0.marker != nil }
        guard !hasMarkedThreadTags else { return nil }
        return eTags.last?.value
    }

    private static func replyContext(
        from event: NostrEvent,
        eventsByID: [String: NostrEvent],
        fallbackAuthor: TimelineAuthor,
        avatarForParent: (NostrEvent) -> AvatarStyle,
        relativeTimestamp: (Int) -> String
    ) -> TimelineReplyContext? {
        guard let parentID = replyParentID(from: event.tags),
              let parent = eventsByID[parentID]
        else { return nil }

        let parentAuthor = parent.pubkey == event.pubkey ? fallbackAuthor : TimelineAuthor.unresolved(pubkey: parent.pubkey)
        return TimelineReplyContext(
            author: parentAuthor,
            avatar: avatarForParent(parent),
            timestamp: relativeTimestamp(parent.createdAt),
            bodyPreview: parent.content,
            isSelfReply: parent.pubkey == event.pubkey
        )
    }

    private static func replyMention(from event: NostrEvent, author: TimelineAuthor) -> TimelineReplyMention? {
        guard replyParentID(from: event.tags) != nil,
              let pubkey = event.tags.first(where: { $0.first == "p" && $0.count >= 2 })?[1],
              pubkey != event.pubkey
        else { return nil }

        let display = "@\(pubkey.prefix(10))"
        return TimelineReplyMention(text: String(display), isExternal: pubkey != author.pubkey)
    }
}
