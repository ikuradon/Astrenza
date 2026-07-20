import AstrenzaCore
import Foundation

enum NostrTimelineRichContentResolver {
    static func resolve(
        _ richContent: NostrRichContent,
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: Set<String>
    ) -> NostrRichContent {
        richContent.resolving(
            profileDisplayNamesByPubkey: profileDisplayNames(
                for: richContent,
                metadataEvents: metadataEvents,
                nip05Resolutions: nip05Resolutions,
                profileResolutionStates: profileResolutionStates,
                followedPubkeys: followedPubkeys
            ),
            eventDisplayTextByID: eventDisplayTexts(
                for: richContent,
                eventsByID: eventsByID,
                metadataEvents: metadataEvents,
                nip05Resolutions: nip05Resolutions,
                profileResolutionStates: profileResolutionStates,
                followedPubkeys: followedPubkeys
            )
        )
    }

    static func profileDisplayNames(
        for richContent: NostrRichContent,
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> [String: String] {
        let metadataByPubkey = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)
        let profilePubkeys = Set(richContent.references.compactMap { reference -> String? in
            if case .profile(let pubkey, _) = reference {
                return pubkey
            }
            return nil
        })

        return profilePubkeys.reduce(into: [String: String]()) { result, pubkey in
            guard let displayName = displayName(
                for: pubkey,
                metadataByPubkey: metadataByPubkey,
                nip05Resolutions: nip05Resolutions,
                profileResolutionStates: profileResolutionStates,
                followedPubkeys: followedPubkeys
            ) else { return }
            result[pubkey] = displayName
        }
    }

    private static func eventDisplayTexts(
        for richContent: NostrRichContent,
        eventsByID: [String: NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> [String: String] {
        let metadataByPubkey = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)
        let eventIDs = Set(richContent.references.compactMap { reference -> String? in
            if case .event(let eventID, _, _, _) = reference {
                return eventID
            }
            return nil
        })

        return eventIDs.reduce(into: [String: String]()) { result, eventID in
            guard let event = eventsByID[eventID],
                  let displayName = displayName(
                    for: event.pubkey,
                    metadataByPubkey: metadataByPubkey,
                    nip05Resolutions: nip05Resolutions,
                    profileResolutionStates: profileResolutionStates,
                    followedPubkeys: followedPubkeys
                  )
            else { return }
            result[eventID] = "note:@\(displayName)"
        }
    }

    private static func displayName(
        for pubkey: String,
        metadataByPubkey: [String: NostrProfileMetadata],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>
    ) -> String? {
        let metadata = metadataByPubkey[pubkey]
        let item = NostrHomeTimelineItem(
            id: "rich-profile-\(pubkey)",
            pubkey: pubkey,
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: nip05Status(metadata: metadata, resolution: nip05Resolutions[pubkey]),
            isFollowed: followedPubkeys.contains(pubkey),
            body: "",
            createdAt: 0,
            avatarPictureState: metadata == nil ? .metadataPending : (metadata?.pictureURL == nil ? .missing : .resolved),
            avatarImageURL: metadata?.pictureURL,
            profileResolutionState: metadata == nil
                ? profileResolutionStates[pubkey] ?? .unknown
                : .resolved
        )
        let author = NostrTimelineAuthorProjection.author(for: item)
        guard author.isMetadataResolved else { return nil }
        return author.primaryText
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
