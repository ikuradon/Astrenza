import Foundation
import AstrenzaCore

struct NostrTimelineContentProjection {
    let attachments: [NostrClassifiedAttachment]
    let mediaAttachments: [NostrClassifiedAttachment]
    let linkURLs: [URL]
    let quotedEventID: String?
    let richBody: NostrRichContent

    init(event: NostrEvent) {
        let attachments = NostrContentAttachmentClassifier.attachments(from: event)
        let linkURLs = attachments
            .filter { $0.kind == .linkPreview }
            .map(\.url)
        let quotedEventID = Self.quotedPostID(from: event)

        self.attachments = attachments
        self.mediaAttachments = attachments.filter { $0.kind == .media }
        self.linkURLs = linkURLs
        self.quotedEventID = quotedEventID
        self.richBody = NostrRichContentParser.parse(
            event: event,
            attachments: attachments,
            promotedLinkURLs: linkURLs,
            hiddenEventIDs: Set([quotedEventID].compactMap { $0 })
        )
    }

    static func quotedPostID(from event: NostrEvent) -> String? {
        if let quotedTagID = event.tags.last(where: { $0.first == "q" && $0.count >= 2 })?[1] {
            return quotedTagID
        }
        if let contentReference = nip19EventReference(in: event.content) {
            return contentReference
        }
        return quoteLikeEventID(from: event.tags)
    }

    private static func nip19EventReference(in content: String) -> String? {
        content
            .split(whereSeparator: \.isWhitespace)
            .lazy
            .compactMap { token -> String? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                return try? NostrNIP19.eventReference(from: trimmed).eventID
            }
            .first
    }

    private static func quoteLikeEventID(from tags: [[String]]) -> String? {
        tags.last { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "mention"
        }?[1]
    }
}
