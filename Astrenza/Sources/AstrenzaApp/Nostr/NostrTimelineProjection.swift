import Foundation
import AstrenzaCore

enum NostrTimelineProjection {
    static func entries(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        deletedEntries: [NostrDeletedTimelineEntryRecord] = [],
        timelineEntries: [NostrTimelineEntryRecord] = [],
        relayCount: Int = 1,
        timeline: NostrFilterTimelineScope = .home,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> [TimelineFeedEntry] {
        NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules,
            deletedEntries: deletedEntries,
            timelineEntries: timelineEntries,
            relayCount: relayCount,
            timeline: timeline,
            policy: policy
        )
    }

    static func posts(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        timeline: NostrFilterTimelineScope = .home,
        now: Int = Int(Date().timeIntervalSince1970),
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> [TimelinePost] {
        NostrTimelineMaterializer.posts(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules,
            timeline: timeline,
            now: now,
            policy: policy
        )
    }

    static func post(for item: NostrHomeTimelineItem) -> TimelinePost {
        NostrTimelineMaterializer.post(for: item)
    }
}
