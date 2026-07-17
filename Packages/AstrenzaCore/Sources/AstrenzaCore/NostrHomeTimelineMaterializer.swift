import Foundation
import NostrProtocol

public struct NostrHomeTimelineItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let pubkey: String
    public let displayName: String?
    public let nip05: String?
    public let nip05Status: NostrNIP05Status
    public let isFollowed: Bool
    public let body: String
    public let createdAt: Int
    public let avatarPictureState: NostrAvatarPictureState
    public let avatarImageURL: URL?
    public let profileResolutionState: NostrProfileResolutionState
    public let filterMatch: NostrFilterMatchReason?

    public init(
        id: String,
        pubkey: String,
        displayName: String?,
        nip05: String?,
        nip05Status: NostrNIP05Status,
        isFollowed: Bool,
        body: String,
        createdAt: Int,
        avatarPictureState: NostrAvatarPictureState,
        avatarImageURL: URL?,
        profileResolutionState: NostrProfileResolutionState = .unknown,
        filterMatch: NostrFilterMatchReason? = nil
    ) {
        self.id = id
        self.pubkey = pubkey
        self.displayName = displayName
        self.nip05 = nip05
        self.nip05Status = nip05Status
        self.isFollowed = isFollowed
        self.body = body
        self.createdAt = createdAt
        self.avatarPictureState = avatarPictureState
        self.avatarImageURL = avatarImageURL
        self.profileResolutionState = profileResolutionState
        self.filterMatch = filterMatch
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
        followedPubkeys: Set<String>,
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        timeline: NostrFilterTimelineScope = .home,
        now: Int = Int(Date().timeIntervalSince1970)
    ) -> [NostrHomeTimelineItem] {
        let metadataByPubkey = latestMetadataByPubkey(metadataEvents)
        let metadataEventPubkeys = Set(metadataEvents.lazy.filter { $0.kind == 0 }.map(\.pubkey))
        return noteEvents
            .filter { $0.kind == 1 && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap { event in
                let filterMatch = filterRules?.matchDetail(event: event, timeline: timeline, now: now)
                if filterMatch?.rule.presentation == .hide {
                    return nil
                }
                return item(
                    for: event,
                    metadata: metadataByPubkey[event.pubkey],
                    profileResolutionState: metadataEventPubkeys.contains(event.pubkey)
                        ? .resolved
                        : profileResolutionStates[event.pubkey] ?? .unknown,
                    nip05Resolution: nip05Resolutions[event.pubkey],
                    isFollowed: followedPubkeys.contains(event.pubkey),
                    filterMatch: filterMatch?.reason
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
        profileResolutionState: NostrProfileResolutionState,
        nip05Resolution: NostrNIP05Resolution?,
        isFollowed: Bool,
        filterMatch: NostrFilterMatchReason?
    ) -> NostrHomeTimelineItem {
        let pictureURL = metadata?.pictureURL
        let pictureState: NostrAvatarPictureState
        if profileResolutionState != .resolved {
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
            nip05Status: nip05Status(metadata: metadata, resolution: nip05Resolution),
            isFollowed: isFollowed,
            body: event.content,
            createdAt: event.createdAt,
            avatarPictureState: pictureState,
            avatarImageURL: pictureURL,
            profileResolutionState: profileResolutionState,
            filterMatch: filterMatch
        )
    }

    private static func nip05Status(
        metadata: NostrProfileMetadata?,
        resolution: NostrNIP05Resolution?
    ) -> NostrNIP05Status {
        guard let identifier = metadata?.nip05, !identifier.isEmpty else { return .absent }
        guard let resolution, resolution.identifier == identifier else { return .unchecked }
        return resolution.status
    }
}
