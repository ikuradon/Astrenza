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
        let deletedTargetIDs = Set(deletedEntries.map(\.targetEventID))
        let timelineEntryByEventID = Dictionary(uniqueKeysWithValues: timelineEntries.map { ($0.eventID, $0) })
        let postsByID = Dictionary(uniqueKeysWithValues: posts(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
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

        guard !timelineEntryByEventID.isEmpty else {
            return sortedEntries.map(\.entry)
        }

        return insertingGapRows(
            into: sortedEntries,
            timelineEntryByEventID: timelineEntryByEventID,
            relayCount: relayCount
        )
        .map(\.entry)
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
        var eventsByID: [String: NostrEvent] = [:]
        for event in contextEvents + noteEvents {
            eventsByID[event.id] = event
        }
        let directPosts = NostrHomeTimelineMaterializer.items(
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            followedPubkeys: followedPubkeys,
            nip05Resolutions: nip05Resolutions,
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
        timelineEntryByEventID: [String: NostrTimelineEntryRecord],
        relayCount: Int
    ) -> [SortableTimelineEntry] {
        var output: [SortableTimelineEntry] = []

        for index in sortedEntries.indices {
            let entry = sortedEntries[index]
            let isPostEntry: Bool
            if case .post = entry.entry {
                isPostEntry = true
            } else {
                isPostEntry = false
            }

            if isPostEntry,
               let timelineEntry = timelineEntryByEventID[entry.id],
               timelineEntry.gapBefore,
               let previousPostID = nearestPostID(in: sortedEntries, before: index),
               timelineEntryByEventID[previousPostID]?.gapAfter != true {
                output.append(gapEntry(
                    newerPostID: previousPostID,
                    olderPostID: entry.id,
                    sortTimestamp: entry.sortTimestamp + 1,
                    relayCount: relayCount
                ))
            }

            output.append(entry)

            if isPostEntry,
               let timelineEntry = timelineEntryByEventID[entry.id],
               timelineEntry.gapAfter,
               let nextPostID = nearestPostID(in: sortedEntries, after: index) {
                output.append(gapEntry(
                    newerPostID: entry.id,
                    olderPostID: nextPostID,
                    sortTimestamp: entry.sortTimestamp - 1,
                    relayCount: relayCount
                ))
            }
        }

        return output
    }

    private static func nearestPostID(in entries: [SortableTimelineEntry], before index: Int) -> String? {
        guard index > entries.startIndex else { return nil }
        for candidateIndex in stride(from: index - 1, through: entries.startIndex, by: -1) {
            if case .post = entries[candidateIndex].entry {
                return entries[candidateIndex].id
            }
        }
        return nil
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
        relayCount: Int
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
                state: .needsBackfill,
                backfilledPosts: []
            ))
        )
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
                    followedPubkeys: followedPubkeys,
                    avatarForItem: NostrTimelineAuthorProjection.avatar(for:),
                    relativeTimestamp: { NostrTimelineAuthorProjection.relativeTimestamp(from: $0) }
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
                            attribution: attribution,
                            relativeTimestamp: { NostrTimelineAuthorProjection.relativeTimestamp(from: $0) }
                        )
                    )
                }

                let targetItem = NostrHomeTimelineMaterializer.items(
                    noteEvents: [targetEvent],
                    metadataEvents: metadataEvents,
                    followedPubkeys: followedPubkeys,
                    nip05Resolutions: nip05Resolutions
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
