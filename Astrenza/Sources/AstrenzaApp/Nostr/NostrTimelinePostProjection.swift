import Foundation
import AstrenzaCore

struct NostrTimelinePostProjection {
    static func post(
        for item: NostrHomeTimelineItem,
        event: NostrEvent? = nil,
        eventsByID: [String: NostrEvent] = [:],
        metadataEvents: [NostrEvent] = [],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String> = [],
        mediaAssets: [NostrMediaAssetRecord] = [],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        idOverride: String? = nil,
        repostedBy: TimelineRepostAttribution? = nil
    ) -> TimelinePost {
        let author = NostrTimelineAuthorProjection.author(for: item)
        let contentProjection = event.map(NostrTimelineContentProjection.init(event:))
        let mediaAttachments = contentProjection?.mediaAttachments ?? []
        let linkURLs = contentProjection?.linkURLs ?? []
        let richBody = contentProjection?.richBody
        let bodyText = richBody?.displayText ?? item.body
        let contentWarning = event.flatMap(NostrTimelineAuthorProjection.contentWarning(from:))
        let replyProjection = event.map {
            NostrTimelineReplyProjection(
                event: $0,
                eventsByID: eventsByID,
                author: author,
                avatarForParent: NostrTimelineAuthorProjection.avatar(for:),
                relativeTimestamp: { NostrTimelineAuthorProjection.relativeTimestamp(from: $0) }
            )
        }

        return TimelinePost(
            id: idOverride ?? item.id,
            author: author,
            avatar: NostrTimelineAuthorProjection.avatar(for: item),
            body: bodyText,
            richBody: richBody,
            timestamp: NostrTimelineAuthorProjection.relativeTimestamp(from: item.createdAt),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: NostrTimelineMediaProjection.media(
                assets: mediaAssets,
                mediaAttachments: mediaAttachments,
                linkURLs: linkURLs,
                linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                palette: NostrTimelineAuthorProjection.avatarPalette(for: item.pubkey)
            ),
            context: nil,
            repostedBy: repostedBy,
            quotedPost: event.flatMap {
                NostrTimelineQuoteProjection.quotedPost(
                    from: $0,
                    eventsByID: eventsByID,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    followedPubkeys: followedPubkeys,
                    avatarForItem: NostrTimelineAuthorProjection.avatar(for:),
                    relativeTimestamp: { NostrTimelineAuthorProjection.relativeTimestamp(from: $0) }
                )
            },
            replyContext: replyProjection?.replyContext,
            replyMention: replyProjection?.replyMention,
            contentWarning: contentWarning,
            bodyPresentation: NostrTimelinePresentationProjection.bodyPresentation(
                body: bodyText,
                linkURLs: linkURLs,
                isFollowed: item.isFollowed,
                filterMatch: item.filterMatch
            ),
            linkSummary: NostrTimelinePresentationProjection.linkSummary(from: linkURLs),
            actionState: .none
        )
    }
}
