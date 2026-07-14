import Foundation
import AstrenzaCore

enum NostrTimelineMaterializer {
    private struct SortableTimelineEntry {
        let id: String
        let sortTimestamp: Int
        let entry: TimelineFeedEntry
    }

    static func entries(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        deletedEntries: [NostrDeletedFeedItemRecord] = [],
        gaps: [NostrFeedGapRecord] = [],
        relayCount: Int = 1,
        timeline: NostrFilterTimelineScope = .home,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> [TimelineFeedEntry] {
        let deletedTargetIDs = Set(deletedEntries.map(\.targetEventID))
        let postsByID = Dictionary(uniqueKeysWithValues: posts(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules,
            timeline: timeline,
            policy: policy
        )
        .filter { !deletedTargetIDs.contains($0.id) }
        .map { ($0.id, $0) })

        let postEntries = noteEvents.compactMap { event -> SortableTimelineEntry? in
            guard let post = postsByID[event.id] else { return nil }
            return SortableTimelineEntry(
                id: post.id,
                sortTimestamp: event.createdAt,
                entry: .post(post)
            )
        }
        let deletedRows = deletedEntries.map { deletedEntry in
            SortableTimelineEntry(
                id: deletedEntry.targetEventID,
                sortTimestamp: deletedEntry.sortTimestamp,
                entry: .deleted(TimelineDeletedEntry(id: "deleted-\(deletedEntry.targetEventID)"))
            )
        }

        let sortedEntries = (postEntries + deletedRows)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }

        let visibleGaps = gaps.filter { $0.state != .resolved }
        guard !visibleGaps.isEmpty else {
            return sortedEntries.map(\.entry)
        }

        return insertingGapRows(
            into: sortedEntries,
            gaps: visibleGaps,
            relayCount: relayCount
        )
        .map(\.entry)
    }

    static func posts(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        profileResolutionStates: [String: NostrProfileResolutionState] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        timeline: NostrFilterTimelineScope = .home,
        now: Int = Int(Date().timeIntervalSince1970),
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> [TimelinePost] {
        var eventsByID: [String: NostrEvent] = [:]
        for event in contextEvents + noteEvents {
            eventsByID[event.id] = event
        }
        let directPosts = NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            filterRules: filterRules,
            timeline: timeline,
            now: now
        )
        .compactMap { item -> SortableTimelinePost? in
            guard let event = eventsByID[item.id] else { return nil }
            return SortableTimelinePost(
                id: event.id,
                sortTimestamp: event.createdAt,
                post: NostrTimelinePostProjection.post(
                    for: item,
                    event: event,
                    eventsByID: eventsByID,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    profileResolutionStates: profileResolutionStates,
                    followedPubkeys: followedPubkeys,
                    mediaAssets: mediaAssetsByEventID[event.id] ?? [],
                    linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                    policy: policy
                )
            )
        }
        let reposts = repostPosts(
            from: noteEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            profileResolutionStates: profileResolutionStates,
            followedPubkeys: followedPubkeys,
            eventsByID: eventsByID,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            policy: policy
        )

        return (directPosts + reposts)
            .sorted { lhs, rhs in
                if lhs.sortTimestamp == rhs.sortTimestamp {
                    return lhs.id < rhs.id
                }
                return lhs.sortTimestamp > rhs.sortTimestamp
            }
            .map(\.post)
    }

    static func post(for item: NostrHomeTimelineItem) -> TimelinePost {
        NostrTimelinePostProjection.post(for: item)
    }

    private static func insertingGapRows(
        into sortedEntries: [SortableTimelineEntry],
        gaps: [NostrFeedGapRecord],
        relayCount: Int
    ) -> [SortableTimelineEntry] {
        let orderedPostIDs = sortedEntries.compactMap { entry -> String? in
            guard case .post = entry.entry else { return nil }
            return entry.id
        }
        let postIndexByID = Dictionary(uniqueKeysWithValues: orderedPostIDs.enumerated().map { ($0.element, $0.offset) })
        var gapStateByPair: [GapPair: TimelineGap.State] = [:]
        for gap in gaps {
            guard let newerIndex = postIndexByID[gap.newerEventID],
                  let olderIndex = postIndexByID[gap.olderEventID],
                  newerIndex < olderIndex
            else { continue }
            let state: TimelineGap.State = gap.state == .requested ? .fetching : .needsBackfill
            for index in newerIndex..<olderIndex {
                let pair = GapPair(newerPostID: orderedPostIDs[index], olderPostID: orderedPostIDs[index + 1])
                if gapStateByPair[pair] != .fetching {
                    gapStateByPair[pair] = state
                }
            }
        }

        var output: [SortableTimelineEntry] = []

        for index in sortedEntries.indices {
            let entry = sortedEntries[index]
            output.append(entry)

            if case .post = entry.entry,
               let nextPostID = nearestPostID(in: sortedEntries, after: index),
               let state = gapStateByPair[GapPair(newerPostID: entry.id, olderPostID: nextPostID)] {
                output.append(gapEntry(
                    newerPostID: entry.id,
                    olderPostID: nextPostID,
                    sortTimestamp: entry.sortTimestamp - 1,
                    relayCount: relayCount,
                    state: state
                ))
            }
        }

        return output
    }

    private static func nearestPostID(in entries: [SortableTimelineEntry], after index: Int) -> String? {
        let nextIndex = index + 1
        guard nextIndex < entries.endIndex else { return nil }
        for candidateIndex in nextIndex..<entries.endIndex {
            if case .post = entries[candidateIndex].entry {
                return entries[candidateIndex].id
            }
        }
        return nil
    }

    private static func gapEntry(
        newerPostID: String,
        olderPostID: String,
        sortTimestamp: Int,
        relayCount: Int,
        state: TimelineGap.State
    ) -> SortableTimelineEntry {
        let gapID = "gap-\(newerPostID)-\(olderPostID)"
        return SortableTimelineEntry(
            id: gapID,
            sortTimestamp: sortTimestamp,
            entry: .gap(TimelineGap(
                id: gapID,
                newerPostID: newerPostID,
                olderPostID: olderPostID,
                missingEstimate: 1,
                relayCount: max(1, relayCount),
                state: state,
                backfilledPosts: []
            ))
        )
    }

    private struct GapPair: Hashable {
        let newerPostID: String
        let olderPostID: String
    }

    private struct SortableTimelinePost {
        let id: String
        let sortTimestamp: Int
        let post: TimelinePost
    }

    private static func repostPosts(
        from events: [NostrEvent],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution],
        profileResolutionStates: [String: NostrProfileResolutionState],
        followedPubkeys: Set<String>,
        eventsByID: [String: NostrEvent],
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord],
        policy: NostrSyncPolicy
    ) -> [SortableTimelinePost] {
        events
            .filter { $0.kind == 6 }
            .compactMap { repostEvent -> SortableTimelinePost? in
                guard let targetID = NostrTimelineRepostProjection.targetID(from: repostEvent) else { return nil }

                let attribution = NostrTimelineRepostProjection.attribution(
                    for: repostEvent,
                    metadataEvents: metadataEvents,
                    nip05Resolutions: nip05Resolutions,
                    profileResolutionStates: profileResolutionStates,
                    followedPubkeys: followedPubkeys,
                    avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
                )
                guard let targetEvent = eventsByID[targetID],
                      targetEvent.kind == 1
                else {
                    return SortableTimelinePost(
                        id: repostEvent.id,
                        sortTimestamp: repostEvent.createdAt,
                        post: NostrTimelineRepostProjection.missingTargetPost(
                            repostEvent: repostEvent,
                            targetID: targetID,
                            attribution: attribution
                        )
                    )
                }

                let targetItem = NostrHomeTimelineMaterializer.items(
                    noteEvents: [targetEvent],
                    metadataEvents: metadataEvents,
                    followedPubkeys: followedPubkeys,
                    nip05Resolutions: nip05Resolutions,
                    profileResolutionStates: profileResolutionStates
                ).first
                guard let targetItem else { return nil }

                return SortableTimelinePost(
                    id: repostEvent.id,
                    sortTimestamp: repostEvent.createdAt,
                    post: NostrTimelinePostProjection.post(
                        for: targetItem,
                        event: targetEvent,
                        eventsByID: eventsByID,
                        metadataEvents: metadataEvents,
                        nip05Resolutions: nip05Resolutions,
                        profileResolutionStates: profileResolutionStates,
                        followedPubkeys: followedPubkeys,
                        mediaAssets: mediaAssetsByEventID[targetEvent.id] ?? [],
                        linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
                        idOverride: repostEvent.id,
                        repostedBy: attribution,
                        policy: policy
                    )
                )
            }
    }
}
