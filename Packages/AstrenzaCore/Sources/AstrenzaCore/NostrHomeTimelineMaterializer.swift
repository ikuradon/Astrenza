import Foundation

public struct NostrHomeTimelineItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let pubkey: String
    public let displayName: String?
    public let nip05: String?
    public let isFollowed: Bool
    public let body: String
    public let createdAt: Int
    public let avatarPictureState: NostrAvatarPictureState
    public let avatarImageURL: URL?

    public init(
        id: String,
        pubkey: String,
        displayName: String?,
        nip05: String?,
        isFollowed: Bool,
        body: String,
        createdAt: Int,
        avatarPictureState: NostrAvatarPictureState,
        avatarImageURL: URL?
    ) {
        self.id = id
        self.pubkey = pubkey
        self.displayName = displayName
        self.nip05 = nip05
        self.isFollowed = isFollowed
        self.body = body
        self.createdAt = createdAt
        self.avatarPictureState = avatarPictureState
        self.avatarImageURL = avatarImageURL
    }
}

public enum NostrAvatarPictureState: Equatable, Sendable {
    case resolved
    case missing
    case metadataPending
}

public enum NostrHomeTimelineMaterializer {
    public static func items(
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        followedPubkeys: Set<String>
    ) -> [NostrHomeTimelineItem] {
        let metadataByPubkey = latestMetadataByPubkey(metadataEvents)
        return noteEvents
            .filter { $0.kind == 1 && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { event in
                item(
                    for: event,
                    metadata: metadataByPubkey[event.pubkey],
                    isFollowed: followedPubkeys.contains(event.pubkey)
                )
            }
    }

    public static func latestMetadataByPubkey(_ events: [NostrEvent]) -> [String: NostrProfileMetadata] {
        var latestEvents: [String: NostrEvent] = [:]
        for event in events where event.kind == 0 {
            guard let current = latestEvents[event.pubkey] else {
                latestEvents[event.pubkey] = event
                continue
            }
            if event.createdAt > current.createdAt || (event.createdAt == current.createdAt && event.id < current.id) {
                latestEvents[event.pubkey] = event
            }
        }

        var result: [String: NostrProfileMetadata] = [:]
        for (pubkey, event) in latestEvents {
            guard let data = event.content.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
            else { continue }
            result[pubkey] = metadata
        }
        return result
    }

    private static func item(
        for event: NostrEvent,
        metadata: NostrProfileMetadata?,
        isFollowed: Bool
    ) -> NostrHomeTimelineItem {
        let pictureURL = metadata?.pictureURL
        let pictureState: NostrAvatarPictureState
        if metadata == nil {
            pictureState = .metadataPending
        } else if pictureURL == nil {
            pictureState = .missing
        } else {
            pictureState = .resolved
        }

        return NostrHomeTimelineItem(
            id: event.id,
            pubkey: event.pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            isFollowed: isFollowed,
            body: event.content,
            createdAt: event.createdAt,
            avatarPictureState: pictureState,
            avatarImageURL: pictureURL
        )
    }
}
