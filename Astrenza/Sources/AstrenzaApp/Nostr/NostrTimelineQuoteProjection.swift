import Foundation
import SwiftUI
import AstrenzaCore

struct NostrTimelineQuoteProjection {
    static func quotedPost(
        from event: NostrEvent,
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        followedPubkeys: Set<String>,
        avatarForItem: (NostrHomeTimelineItem) -> AvatarStyle
    ) -> QuotedTimelinePost? {
        guard let quotedID = NostrTimelineContentProjection.quotedPostID(from: event) else { return nil }
        guard let quoted = eventsByID[quotedID] else {
            return missingQuotedPost(quotedID: quotedID)
        }

        let item = NostrHomeTimelineMaterializer.items(
            noteEvents: [quoted],
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions
        ).first ?? fallbackItem(for: quoted, followedPubkeys: followedPubkeys)
        let contentProjection = NostrTimelineContentProjection(event: quoted)
        let richBody = NostrTimelineRichContentResolver.resolve(
            contentProjection.richBody,
            eventsByID: eventsByID,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys
        )

        return QuotedTimelinePost(
            author: NostrTimelineAuthorProjection.author(for: item),
            avatar: avatarForItem(item),
            body: richBody.displayText,
            richBody: richBody,
            createdAt: quoted.createdAt,
            isAvailable: true
        )
    }

    private static func fallbackItem(
        for event: NostrEvent,
        followedPubkeys: Set<String>
    ) -> NostrHomeTimelineItem {
        NostrHomeTimelineItem(
            id: event.id,
            pubkey: event.pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: followedPubkeys.contains(event.pubkey),
            body: event.content,
            createdAt: event.createdAt,
            avatarPictureState: .metadataPending,
            avatarImageURL: nil
        )
    }

    private static func missingQuotedPost(quotedID: String) -> QuotedTimelinePost {
        QuotedTimelinePost(
            author: .unresolved(pubkey: quotedID),
            avatar: AvatarStyle(
                primary: .secondary,
                secondary: .gray,
                symbolName: "quote.bubble.fill",
                pictureState: .metadataPending,
                placeholderSeed: quotedID
            ),
            body: "Quoted note is not cached yet.",
            richBody: nil,
            createdAt: nil,
            isAvailable: false
        )
    }
}
