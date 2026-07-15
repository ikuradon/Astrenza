import AstrenzaCore

extension HomeTimelineRepository {
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
            linkPreviewsByNormalizedURL:
                linkPreviewsByNormalizedURL(for: listEvents),
            filterRules: listFilterRuleSet(accountID: accountID),
            timeline: .lists
        )
    }

    private func listFilterRuleSet(
        accountID: String
    ) -> NostrFilterRuleSet? {
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
        guard limit > 0,
              let summaries = try? eventStore.listSummaries(
                accountID: accountID
              )
        else { return [] }

        var eventsByID: [String: NostrEvent] = [:]
        for summary in summaries where eventsByID.count < limit {
            let remaining = limit - eventsByID.count
            let candidates = listTimelineCandidates(
                summary: summary,
                eventStore: eventStore,
                limit: remaining
            )
            for event in candidates
            where eventsByID[event.id] == nil && eventsByID.count < limit {
                eventsByID[event.id] = event
            }
        }
        return eventsByID.values.sorted(by: listEventOrdering)
    }

    private func listTimelineCandidates(
        summary: NostrListSummary,
        eventStore: NostrEventStore,
        limit: Int
    ) -> [NostrEvent] {
        let items = (try? eventStore.listItems(listID: summary.listID)) ?? []
        switch summary.kind {
        case 30_000:
            let authors = items
                .filter { $0.itemType == "pubkey" }
                .map(\.value)
            return (try? eventStore.events(
                kind: 1,
                authors: authors,
                limit: limit
            )) ?? []
        case 10_003, 30_003:
            return items.compactMap { item in
                guard item.itemType == "event",
                      let event = try? eventStore.event(id: item.value),
                      event.kind == 1
                else { return nil }
                return event
            }
        default:
            return []
        }
    }

    private func listEventOrdering(
        _ lhs: NostrEvent,
        _ rhs: NostrEvent
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id < rhs.id
        }
        return lhs.createdAt > rhs.createdAt
    }
}
