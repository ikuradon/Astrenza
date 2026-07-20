import Foundation
import AstrenzaCore

struct HomeTimelineMaterializedSnapshot {
    var entries: [TimelineFeedEntry]
    var filterStatus: TimelineFilterStatus
    var renderFingerprint: [Int]
}

struct HomeTimelineRenderInput {
    let noteEvents: [NostrEvent]
    let feedWindow: NostrFeedWindow?
    let contextEvents: [NostrEvent]
    let metadataEvents: [NostrEvent]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
    let followedPubkeys: [String]
    let resolvedRelayCount: Int
    let filterRules: NostrFilterRuleSet?
    let filterStatus: TimelineFilterStatus
    let timeline: NostrFilterTimelineScope
    let policy: NostrSyncPolicy
}

struct HomeTimelineReadContext {
    let accountID: String?
    let fallbackEntries: [TimelineFeedEntry]
    let metadataEvents: [NostrEvent]
    let nip05Resolutions: [String: NostrNIP05Resolution]
    let profileResolutionStates: [String: NostrProfileResolutionState]
    let followedPubkeys: Set<String>
    let resolvedRelayCount: Int
    let filterRules: NostrFilterRuleSet?
    let syncPolicy: NostrSyncPolicy
}

struct HomeTimelineRepository: Sendable {
    let eventStore: NostrEventStore?

    func event(id: String) -> NostrEvent? {
        try? eventStore?.event(id: id)
    }

    func contextEvents(for visibleEvents: [NostrEvent]) -> [NostrEvent] {
        guard let eventStore else { return [] }
        let sourceEventIDs = Array(Set(visibleEvents.flatMap { event in
            NostrEventDependencies.extract(from: event).sourceEventIDs
        })).sorted()
        guard !sourceEventIDs.isEmpty else { return [] }

        let visibleEventIDs = Set(visibleEvents.map(\.id))
        return ((try? eventStore.events(ids: sourceEventIDs)) ?? []).filter {
            !visibleEventIDs.contains($0.id)
        }
    }

    func newestCreatedAtByRelay(
        accountID: String,
        timelineKey: String,
        relayURLs: [String]
    ) -> [String: Int]? {
        guard let eventStore else { return nil }

        var result: [String: Int] = [:]
        for relayURL in relayURLs {
            if let newestCreatedAt = try? eventStore.syncCursor(
                accountID: accountID,
                timelineKey: timelineKey,
                relayURL: relayURL
            )?.newestCreatedAt {
                result[relayURL] = newestCreatedAt
            }
        }
        return result
    }

    func observedRelayURLsByAuthor(
        _ authors: [String],
        limitPerAuthor: Int = 4
    ) -> [String: [String]] {
        guard let eventStore else { return [:] }
        return (try? eventStore.observedRelayURLsByAuthor(
            authors: Set(authors.map { $0.lowercased() }),
            limitPerAuthor: limitPerAuthor
        )) ?? [:]
    }

    func olderBackfillEvents(
        accountID: String,
        followedPubkeys: [String],
        currentEvents: [NostrEvent],
        limit: Int
    ) -> [NostrEvent]? {
        guard let eventStore,
              let until = currentEvents.map(\.createdAt).min().map({ max(0, $0 - 1) })
        else {
            return nil
        }

        let authors = followedPubkeys.isEmpty ? [accountID] : followedPubkeys
        guard let events = try? eventStore.events(
            kind: 1,
            authors: authors,
            until: until,
            limit: limit
        ), !events.isEmpty else {
            return nil
        }
        return events
    }

    func materialize(
        _ input: HomeTimelineRenderInput
    ) -> HomeTimelineMaterializedSnapshot {
        let projectedEvents = input.feedWindow?.events ?? input.noteEvents
        let materialReferenceEvents = projectedEvents + input.contextEvents
        let entries = NostrTimelineMaterializer.entries(
            noteEvents: projectedEvents,
            contextEvents: input.contextEvents,
            metadataEvents: input.metadataEvents,
            nip05Resolutions: input.nip05Resolutions,
            profileResolutionStates: input.profileResolutionStates,
            followedPubkeys: Set(input.followedPubkeys),
            mediaAssetsByEventID: mediaAssetsByEventID(for: materialReferenceEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: materialReferenceEvents),
            filterRules: input.filterRules,
            deletedEntries: input.feedWindow?.deletedItems ?? [],
            gaps: input.feedWindow?.gaps ?? [],
            relayCount: max(1, input.resolvedRelayCount),
            timeline: input.timeline,
            policy: input.policy
        )

        return HomeTimelineMaterializedSnapshot(
            entries: entries,
            filterStatus: input.filterStatus,
            renderFingerprint: entriesRenderFingerprint(for: entries)
        )
    }

    func post(
        eventID: String,
        context: HomeTimelineReadContext
    ) -> TimelinePost? {
        guard let eventStore,
              let event = try? eventStore.event(id: eventID),
              event.kind == 1
        else {
            return context.fallbackEntries.compactMap(\.post).first { $0.id == eventID }
        }

        return materializedPosts(from: [event], context: context).first
    }

    func replyAncestors(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        guard let eventStore else { return [] }

        var ancestors: [NostrEvent] = []
        var currentID = post.id
        var visited = Set([post.id])

        while ancestors.count < limit {
            guard let tags = try? eventStore.tags(eventID: currentID),
                  let parentID = NostrTimelineReplyProjection.replyParentID(from: tags),
                  !visited.contains(parentID),
                  let parentEvent = try? eventStore.event(id: parentID),
                  parentEvent.kind == 1
            else {
                break
            }

            ancestors.append(parentEvent)
            visited.insert(parentID)
            currentID = parentID
        }

        return materializedPosts(from: ancestors.reversed(), context: context)
    }

    func replies(
        for post: TimelinePost,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        guard let events = try? eventStore?.eventsReferencing(
            eventID: post.id,
            kind: 1,
            limit: limit
        ) else {
            return []
        }

        return materializedPosts(
            from: events.filter { event in
                NostrTimelineReplyProjection.replyParentID(from: event.tags) == post.id
            },
            context: context
        )
    }

    func isBookmarked(eventID: String, accountID: String?) -> Bool {
        guard let accountID, let eventStore else { return false }
        return ((try? eventStore.localBookmarks(accountID: accountID)) ?? [])
            .contains { $0.eventID == eventID }
    }

    func materializedPosts(
        from events: some Sequence<NostrEvent>,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        let events = Array(events)
        let dependencyEvents = contextEvents(for: events)
        let materialEvents = events + dependencyEvents
        let profilePubkeys = Set(materialEvents.flatMap { event in
            NostrEventDependencies.extract(from: event).profilePubkeys
        })
        let storedMetadata = (try? eventStore?.latestReplaceableEvents(
            pubkeys: profilePubkeys,
            kind: 0
        )) ?? []
        let liveMetadata = context.metadataEvents.filter {
            profilePubkeys.contains($0.pubkey)
        }

        return NostrTimelineMaterializer.posts(
            noteEvents: events,
            contextEvents: dependencyEvents,
            metadataEvents: storedMetadata + liveMetadata,
            nip05Resolutions: context.nip05Resolutions,
            profileResolutionStates: context.profileResolutionStates,
            followedPubkeys: context.followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID(for: materialEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: materialEvents),
            filterRules: context.filterRules,
            policy: context.syncPolicy
        )
    }

    func mediaAssetsByEventID(for events: [NostrEvent]) -> [String: [NostrMediaAssetRecord]] {
        guard let eventStore else { return [:] }
        return (try? eventStore.mediaAssets(eventIDs: events.map(\.id))) ?? [:]
    }

    func linkPreviewsByNormalizedURL(for events: [NostrEvent]) -> [String: NostrLinkPreviewRecord] {
        guard let eventStore else { return [:] }
        let urls = events.flatMap { NostrLinkParser.webURLs(in: $0.content) }
        return (try? eventStore.linkPreviews(urls: urls)) ?? [:]
    }

    func entriesRenderFingerprint(for entries: [TimelineFeedEntry]) -> [Int] {
        TimelineRenderFingerprint.entries(entries)
    }
}
