import Foundation
import AstrenzaCore

struct NostrTimelinePostProjection {
    static func post(
        for item: NostrHomeTimelineItem,
        event: NostrEvent? = nil,
        eventsByID: [String: NostrEvent] = [:],
        metadataEvents: [NostrEvent] = [],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: Set<String> = [],
        mediaAssets: [NostrMediaAssetRecord] = [],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        idOverride: String? = nil,
        repostedBy: TimelineRepostAttribution? = nil,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> TimelinePost {
        let author = NostrTimelineAuthorProjection.author(for: item)
        let contentProjection = event.map(NostrTimelineContentProjection.init(event:))
        let mediaAttachments = contentProjection?.mediaAttachments ?? []
        let linkURLs = contentProjection?.linkURLs ?? []
        let richBody = contentProjection?.richBody.resolvedForTimeline(
            eventsByID: eventsByID,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys
        )
        let bodyText = richBody?.displayText ?? item.body
        let contentWarning = event.flatMap(NostrTimelineAuthorProjection.contentWarning(from:))
        let media = NostrTimelineMediaProjection.media(
            assets: mediaAssets,
            mediaAttachments: mediaAttachments,
            linkURLs: linkURLs,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            palette: NostrTimelineAuthorProjection.avatarPalette(for: item.pubkey),
            policy: policy
        )
        let replyProjection = event.map {
            NostrTimelineReplyProjection(
                event: $0,
                eventsByID: eventsByID,
                author: author,
                authorForParent: { parent in
                    Self.author(
                        for: parent.pubkey,
                        event: parent,
                        metadataEvents: metadataEvents,
                        nip05Resolutions: nip05Resolutions,
                        profileResolutionStates: profileResolutionStates,
                        followedPubkeys: followedPubkeys
                    )
                },
                avatarForParent: { parent in
                    NostrTimelineAuthorProjection.avatar(for: Self.item(
                        for: parent,
                        metadataEvents: metadataEvents,
                        nip05Resolutions: nip05Resolutions,
                        profileResolutionStates: profileResolutionStates,
                        followedPubkeys: followedPubkeys
                    ))
                },
                mentionDisplayForPubkey: { pubkey in
                    Self.mentionDisplayName(
                        for: pubkey,
                        metadataEvents: metadataEvents,
                        nip05Resolutions: nip05Resolutions,
                        profileResolutionStates: profileResolutionStates,
                        followedPubkeys: followedPubkeys
                    )
                }
            )
        }

        return TimelinePost(
            id: idOverride ?? item.id,
            author: author,
            avatar: NostrTimelineAuthorProjection.avatar(for: item),
            body: bodyText,
            richBody: richBody,
            createdAt: item.createdAt,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: media,
            context: nil,
            repostedBy: repostedBy,
            quotedPost: event.flatMap {
                NostrTimelineQuoteProjection.quotedPost(
                    from: $0,
                    eventsByID: eventsByID,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    profileResolutionStates: profileResolutionStates,
                    followedPubkeys: followedPubkeys,
                    avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
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
            linkSummary: NostrTimelinePresentationProjection.linkSummary(
                from: linkURLs,
                media: media
            ),
            actionState: .none
        )
    }

    private static func author(
        for pubkey: String,
        event: NostrEvent?,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> TimelineAuthor {
        if let event {
            return NostrTimelineAuthorProjection.author(for: item(
                for: event,
                metadataEvents: metadataEvents,
                nip05Resolutions: nip05Resolutions,
                profileResolutionStates: profileResolutionStates,
                followedPubkeys: followedPubkeys
            ))
        }

        return NostrTimelineAuthorProjection.author(for: item(
            for: pubkey,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys
        ))
    }

    private static func mentionDisplayName(
        for pubkey: String,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> String? {
        let author = author(
            for: pubkey,
            event: nil,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys
        )
        guard author.isMetadataResolved else { return nil }
        return author.primaryText
    }

    private static func item(
        for event: NostrEvent,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> NostrHomeTimelineItem {
        NostrHomeTimelineMaterializer.items(
            noteEvents: [event],
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates
        ).first ?? item(
            for: event.pubkey,
            id: event.id,
            body: event.content,
            createdAt: event.createdAt,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys
        )
    }

    private static func item(
        for pubkey: String,
        id: String? = nil,
        body: String = "",
        createdAt: Int = 0,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> NostrHomeTimelineItem {
        let metadata = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)[pubkey]
        let hasMetadataEvent = metadataEvents.contains { $0.kind == 0 && $0.pubkey == pubkey }
        return NostrHomeTimelineItem(
            id: id ?? "profile-\(pubkey)",
            pubkey: pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: coreNIP05Status(metadata: metadata, resolution: nip05Resolutions[pubkey]),
            isFollowed: followedPubkeys.contains(pubkey),
            body: body,
            createdAt: createdAt,
            avatarPictureState: avatarPictureState(for: metadata),
            avatarImageURL: metadata?.pictureURL,
            profileResolutionState: hasMetadataEvent
                ? .resolved
                : profileResolutionStates[pubkey] ?? .unknown
        )
    }

    private static func coreNIP05Status(
        metadata: NostrProfileMetadata?,
        resolution: NostrNIP05Resolution?
    ) -> NostrNIP05Status {
        guard let identifier = metadata?.nip05, !identifier.isEmpty else { return .absent }
        guard let resolution, resolution.identifier == identifier else { return .unchecked }
        return resolution.status
    }

    private static func avatarPictureState(for metadata: NostrProfileMetadata?) -> NostrAvatarPictureState {
        guard let metadata else { return .metadataPending }
        return metadata.pictureURL == nil ? .missing : .resolved
    }
}

private extension NostrRichContent {
    func resolvedForTimeline(
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> NostrRichContent {
        NostrTimelineRichContentResolver.resolve(
            self,
            eventsByID: eventsByID,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys
        )
    }
}
