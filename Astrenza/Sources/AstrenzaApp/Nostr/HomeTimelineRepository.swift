import Foundation
import AstrenzaCore

struct HomeTimelineMaterializedSnapshot {
    var entries: [TimelineFeedEntry]
    var filterStatus: TimelineFilterStatus
    var renderFingerprint: [Int]
}

struct HomeTimelineRepository {
    let eventStore: NostrEventStore?

    func materialize(
        account: NostrAccount?,
        noteEvents: [NostrEvent],
        feedWindow: NostrFeedWindow? = nil,
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: [String],
        resolvedRelays: [String],
        filterRules: NostrFilterRuleSet?,
        filterStatus: TimelineFilterStatus,
        timelineKey: String = "home",
        timeline: NostrFilterTimelineScope = .home,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> HomeTimelineMaterializedSnapshot {
        let projectedEvents = feedWindow?.events ?? noteEvents
        let materialReferenceEvents = projectedEvents + contextEvents
        let entries = NostrTimelineMaterializer.entries(
            noteEvents: projectedEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: Set(followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: materialReferenceEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: materialReferenceEvents),
            filterRules: filterRules,
            deletedEntries: feedWindow?.deletedItems ?? [],
            gaps: feedWindow?.gaps ?? [],
            relayCount: max(1, resolvedRelays.count),
            timeline: timeline,
            policy: policy
        )

        return HomeTimelineMaterializedSnapshot(
            entries: entries,
            filterStatus: filterStatus,
            renderFingerprint: entriesRenderFingerprint(for: entries)
        )
    }

    private func mediaAssetsByEventID(for events: [NostrEvent]) -> [String: [NostrMediaAssetRecord]] {
        guard let eventStore else { return [:] }
        return (try? eventStore.mediaAssets(eventIDs: events.map(\.id))) ?? [:]
    }

    private func linkPreviewsByNormalizedURL(for events: [NostrEvent]) -> [String: NostrLinkPreviewRecord] {
        guard let eventStore else { return [:] }
        let urls = events.flatMap { NostrLinkParser.webURLs(in: $0.content) }
        return (try? eventStore.linkPreviews(urls: urls)) ?? [:]
    }

    func entriesRenderFingerprint(for entries: [TimelineFeedEntry]) -> [Int] {
        TimelineRenderFingerprint.entries(entries)
    }
}
