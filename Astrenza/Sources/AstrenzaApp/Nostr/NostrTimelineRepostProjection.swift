import Foundation
import SwiftUI
import AstrenzaCore

struct NostrTimelineRepostProjection {
    static func targetID(from event: NostrEvent) -> String? {
        event.tags.last { tag in
            tag.count >= 2 && tag[0] == "e"
        }?[1]
    }

    static func attribution(
        for repostEvent: NostrEvent,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: Set<String>,
        avatarForItem: (NostrHomeTimelineItem) -> AvatarStyle
    ) -> TimelineRepostAttribution {
        let metadata = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)[repostEvent.pubkey]
        let hasMetadataEvent = metadataEvents.contains { $0.kind == 0 && $0.pubkey == repostEvent.pubkey }
        let resolutionState: NostrProfileResolutionState = hasMetadataEvent
            ? .resolved
            : profileResolutionStates[repostEvent.pubkey] ?? .unknown
        let repostItem = NostrHomeTimelineItem(
            id: repostEvent.id,
            pubkey: repostEvent.pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: coreNIP05Status(metadata: metadata, resolution: nip05Resolutions[repostEvent.pubkey]),
            isFollowed: followedPubkeys.contains(repostEvent.pubkey),
            body: "",
            createdAt: repostEvent.createdAt,
            avatarPictureState: avatarPictureState(for: metadata, resolutionState: resolutionState),
            avatarImageURL: metadata?.pictureURL,
            profileResolutionState: resolutionState
        )
        return TimelineRepostAttribution(
            author: NostrTimelineAuthorProjection.author(for: repostItem),
            avatar: avatarForItem(repostItem),
            createdAt: repostEvent.createdAt
        )
    }

    static func missingTargetPost(
        repostEvent: NostrEvent,
        targetID: String,
        attribution: TimelineRepostAttribution
    ) -> TimelinePost {
        let targetPubkey = repostEvent.tags.first { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1].count == 64
        }?[1] ?? TimelineAuthor.mockPubkey(for: targetID)
        let author = TimelineAuthor.unresolved(pubkey: targetPubkey)
        let avatar = AvatarStyle(
            primary: .secondary,
            secondary: .gray,
            symbolName: "arrow.triangle.2.circlepath",
            pictureState: .metadataPending,
            placeholderSeed: targetPubkey
        )
        return TimelinePost(
            id: repostEvent.id,
            author: author,
            avatar: avatar,
            body: "Reposted post unavailable",
            createdAt: repostEvent.createdAt,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            repostedBy: attribution,
            bodyPresentation: .collapsed(lineLimit: 1, reason: .longText),
            actionState: .none
        )
    }

    private static func avatarPictureState(
        for metadata: NostrProfileMetadata?,
        resolutionState: NostrProfileResolutionState
    ) -> NostrAvatarPictureState {
        guard resolutionState == .resolved else { return .metadataPending }
        return metadata?.pictureURL == nil ? .missing : .resolved
    }

    private static func coreNIP05Status(
        metadata: NostrProfileMetadata?,
        resolution: NostrNIP05Resolution?
    ) -> NostrNIP05Status {
        guard let identifier = metadata?.nip05, !identifier.isEmpty else { return .absent }
        guard let resolution, resolution.identifier == identifier else { return .unchecked }
        return resolution.status
    }
}
