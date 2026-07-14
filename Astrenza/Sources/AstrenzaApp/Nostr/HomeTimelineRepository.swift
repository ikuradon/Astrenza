import Foundation
import AstrenzaCore

struct HomeTimelineMaterializedSnapshot {
    var entries: [TimelineFeedEntry]
    var filterStatus: TimelineFilterStatus
    var renderFingerprint: [Int]
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

    func profile(
        pubkey: String,
        isCurrentUser: Bool,
        context: HomeTimelineReadContext
    ) -> UserProfile {
        let metadata = try? eventStore?.latestReplaceableEvent(pubkey: pubkey, kind: 0)
        let posts = profilePosts(pubkey: pubkey, limit: 1_000, context: context)
        let author = materializedAuthor(
            pubkey: pubkey,
            metadataEvent: metadata,
            context: context
        )
        let avatar = posts.first?.avatar ?? avatar(for: pubkey, context: context)
        let relayCount = isCurrentUser
            ? context.resolvedRelayCount
            : max(1, context.resolvedRelayCount)

        return UserProfile(
            id: pubkey,
            author: author,
            avatar: avatar,
            banner: banner(for: pubkey),
            bio: metadata.flatMap(Self.profileMetadata).map { _ in
                "kind:0 profile metadata is cached."
            } ?? "kind:0 profile is not cached yet.",
            isCurrentUser: isCurrentUser,
            isFollowed: context.followedPubkeys.contains(pubkey) || isCurrentUser,
            followerCount: 0,
            followingCount: isCurrentUser ? context.followedPubkeys.count : 0,
            postCount: posts.count,
            relayCount: relayCount,
            latestFollowers: [],
            featuredHashtags: []
        )
    }

    func profilePosts(
        pubkey: String,
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        guard let events = try? eventStore?.events(
            kind: 1,
            authors: [pubkey],
            limit: limit
        ) else {
            return context.fallbackEntries.compactMap(\.post).filter {
                $0.author.pubkey == pubkey
            }
        }

        return materializedPosts(from: events, context: context)
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

    func listEntries(
        limit: Int,
        context: HomeTimelineReadContext
    ) -> [TimelineFeedEntry] {
        guard let accountID = context.accountID, let eventStore else { return [] }
        let listEvents = cachedListTimelineEvents(
            accountID: accountID,
            eventStore: eventStore,
            limit: limit
        )
        guard !listEvents.isEmpty else { return [] }

        let pubkeys = Set(listEvents.map(\.pubkey))
        let metadata = (try? eventStore.latestReplaceableEvents(
            pubkeys: pubkeys,
            kind: 0
        )) ?? context.metadataEvents.filter { pubkeys.contains($0.pubkey) }
        return NostrTimelineMaterializer.entries(
            noteEvents: listEvents,
            metadataEvents: metadata,
            nip05Resolutions: context.nip05Resolutions,
            profileResolutionStates: context.profileResolutionStates,
            followedPubkeys: context.followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID(for: listEvents),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: listEvents),
            filterRules: listFilterRuleSet(accountID: accountID),
            timeline: .lists
        )
    }

    private func materializedPosts(
        from events: some Sequence<NostrEvent>,
        context: HomeTimelineReadContext
    ) -> [TimelinePost] {
        let events = Array(events)
        let profilePubkeys = Set(events.flatMap { event in
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
            metadataEvents: storedMetadata + liveMetadata,
            nip05Resolutions: context.nip05Resolutions,
            profileResolutionStates: context.profileResolutionStates,
            followedPubkeys: context.followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID(for: events),
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL(for: events),
            filterRules: context.filterRules,
            policy: context.syncPolicy
        )
    }

    private func listFilterRuleSet(accountID: String) -> NostrFilterRuleSet? {
        guard let eventStore else { return nil }
        let rules = ((try? eventStore.filterRules(accountID: accountID)) ?? [])
            .filter { $0.applies(to: .lists) }
        guard !rules.isEmpty else { return nil }
        return NostrFilterRuleSet(rules: rules)
    }

    private func cachedListTimelineEvents(
        accountID: String,
        eventStore: NostrEventStore,
        limit: Int
    ) -> [NostrEvent] {
        guard let summaries = try? eventStore.listSummaries(accountID: accountID) else {
            return []
        }
        var eventsByID: [String: NostrEvent] = [:]
        var remaining = max(0, limit)
        guard remaining > 0 else { return [] }

        for summary in summaries where remaining > 0 {
            let items = (try? eventStore.listItems(listID: summary.listID)) ?? []
            switch summary.kind {
            case 30_000:
                let authors = items
                    .filter { $0.itemType == "pubkey" }
                    .map(\.value)
                let events = (try? eventStore.events(
                    kind: 1,
                    authors: authors,
                    limit: remaining
                )) ?? []
                for event in events where eventsByID[event.id] == nil {
                    eventsByID[event.id] = event
                    remaining -= 1
                    if remaining <= 0 { break }
                }
            case 10_003, 30_003:
                for item in items where item.itemType == "event" && remaining > 0 {
                    guard let event = try? eventStore.event(id: item.value),
                          event.kind == 1,
                          eventsByID[event.id] == nil
                    else { continue }
                    eventsByID[event.id] = event
                    remaining -= 1
                }
            default:
                break
            }
        }

        return eventsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func materializedAuthor(
        pubkey: String,
        metadataEvent: NostrEvent?,
        context: HomeTimelineReadContext
    ) -> TimelineAuthor {
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        guard metadataEvent != nil else {
            return .unresolved(
                pubkey: pubkey,
                state: context.profileResolutionStates[pubkey] ?? .unknown
            )
        }

        return .metadataResolved(
            displayName: metadata?.bestName,
            nip05: metadata?.nip05,
            nip05Status: NIP05Status(
                context.nip05Resolutions[pubkey]?.status ?? .unchecked
            ),
            pubkey: pubkey,
            isFollowed: context.followedPubkeys.contains(pubkey)
        )
    }

    private func avatar(
        for pubkey: String,
        context: HomeTimelineReadContext
    ) -> AvatarStyle {
        let item = NostrHomeTimelineItem(
            id: pubkey,
            pubkey: pubkey,
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            isFollowed: context.followedPubkeys.contains(pubkey),
            body: "",
            createdAt: Int(Date().timeIntervalSince1970),
            avatarPictureState: .metadataPending,
            avatarImageURL: nil,
            profileResolutionState: context.profileResolutionStates[pubkey] ?? .unknown
        )
        return NostrTimelineAuthorProjection.avatar(for: item)
    }

    private func banner(for pubkey: String) -> ProfileBannerStyle {
        let palette = NostrTimelineAuthorProjection.avatarPalette(for: pubkey)
        return ProfileBannerStyle(
            colors: [palette.secondary, palette.primary],
            symbolName: "sparkles"
        )
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
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
