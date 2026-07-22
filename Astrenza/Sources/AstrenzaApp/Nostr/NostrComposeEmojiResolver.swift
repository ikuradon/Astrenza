import AstrenzaCore
import Foundation

actor NostrComposeEmojiResolver {
    private struct ActiveResolution {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private struct RelayResult: Sendable {
        let relayURL: String
        let events: [NostrEvent]
    }

    private let eventStore: NostrEventStore?
    private let relayClient: any NostrRelayFetching
    private let refreshIntervalSeconds: Int
    private let cacheRefreshIntervalSeconds: Int
    private let now: @Sendable () -> Int
    private var lastAttemptAtByAccountID: [String: Int] = [:]
    private var activeResolutionByAccountID: [String: ActiveResolution] = [:]

    init(
        eventStore: NostrEventStore?,
        relayClient: any NostrRelayFetching,
        refreshIntervalSeconds: Int = 60,
        cacheRefreshIntervalSeconds: Int = 15 * 60,
        now: @escaping @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.eventStore = eventStore
        self.relayClient = relayClient
        self.refreshIntervalSeconds = max(0, refreshIntervalSeconds)
        self.cacheRefreshIntervalSeconds = max(0, cacheRefreshIntervalSeconds)
        self.now = now
    }

    @discardableResult
    func resolve(
        accountID: String,
        relayURLs: [String]
    ) async -> Bool {
        let normalizedAccountID = accountID.lowercased()
        guard NostrHex.isLowercaseHex(normalizedAccountID, byteCount: 32),
              let eventStore
        else { return false }

        if let activeResolution = activeResolutionByAccountID[normalizedAccountID] {
            return await activeResolution.task.value
        }

        let resolutionID = UUID()
        let task = Task { [self] in
            await resolveUncoalesced(
                accountID: normalizedAccountID,
                relayURLs: relayURLs,
                eventStore: eventStore
            )
        }
        activeResolutionByAccountID[normalizedAccountID] = ActiveResolution(
            id: resolutionID,
            task: task
        )
        let didPersist = await task.value
        if activeResolutionByAccountID[normalizedAccountID]?.id == resolutionID {
            activeResolutionByAccountID[normalizedAccountID] = nil
        }
        return didPersist
    }

    private func resolveUncoalesced(
        accountID: String,
        relayURLs: [String],
        eventStore: NostrEventStore
    ) async -> Bool {
        let attemptAt = now()
        let cachedListEvent = try? eventStore.latestReplaceableEvent(
            pubkey: accountID,
            kind: 10_030
        )
        let cachedReferences = NostrEmojiSetReference.references(in: cachedListEvent)
        let cachedReferencesNeedingRefresh = referencesNeedingRefresh(
            cachedReferences,
            eventStore: eventStore,
            now: attemptAt
        )
        let listNeedsRefresh = cachedListEvent.map {
            !isFresh(event: $0, eventStore: eventStore, now: attemptAt)
        } ?? true
        guard listNeedsRefresh || !cachedReferencesNeedingRefresh.isEmpty else {
            return false
        }

        if let lastAttemptAt = lastAttemptAtByAccountID[accountID],
           attemptAt - lastAttemptAt < refreshIntervalSeconds {
            return false
        }
        lastAttemptAtByAccountID[accountID] = attemptAt

        let baseRelays = NostrRelayURL.normalizedStrings(relayURLs)
        var didPersist = false
        if listNeedsRefresh, !baseRelays.isEmpty {
            let request = NostrRelayRequest(
                subscriptionID: "astrenza-emoji-list-\(UUID().uuidString.prefix(8))",
                filters: [[
                    "authors": .strings([accountID]),
                    "kinds": .ints([10_030]),
                    "limit": .int(1)
                ]]
            )
            let results = await fetch(
                relayURLs: Array(baseRelays.prefix(6)),
                request: request
            )
            let listEvents = results.flatMap(\.events).filter {
                $0.kind == 10_030 && $0.pubkey == accountID
            }
            if !listEvents.isEmpty {
                didPersist = persist(
                    events: listEvents,
                    results: results,
                    receivedAt: attemptAt,
                    eventStore: eventStore
                ) || didPersist
            }
        }

        guard let emojiListEvent = try? eventStore.latestReplaceableEvent(
            pubkey: accountID,
            kind: 10_030
        ) else { return didPersist }
        let references = NostrEmojiSetReference.references(in: emojiListEvent)
        let referencesToFetch = referencesNeedingRefresh(
            references,
            eventStore: eventStore,
            now: attemptAt
        )
        guard !referencesToFetch.isEmpty else { return didPersist }

        let setFetchPlan = makeSetFetchPlan(
            references: referencesToFetch,
            baseRelays: baseRelays,
            eventStore: eventStore
        )
        let setResults = await fetchEmojiSets(
            plan: setFetchPlan,
            concurrencyLimit: 4
        )

        let expectedAddresses = Set(referencesToFetch.map(\.address))
        let setEvents = setResults.flatMap(\.events).filter { event in
            guard event.kind == 30_030,
                  let dTag = event.tags.first(where: {
                    $0.count >= 2 && $0[0] == "d"
                  })?[1]
            else { return false }
            return expectedAddresses.contains(
                "30030:\(event.pubkey.lowercased()):\(dTag)"
            )
        }
        if !setEvents.isEmpty {
            didPersist = persist(
                events: setEvents,
                results: setResults,
                receivedAt: attemptAt,
                eventStore: eventStore
            ) || didPersist
        }
        return didPersist
    }

    private func referencesNeedingRefresh(
        _ references: [NostrEmojiSetReference],
        eventStore: NostrEventStore,
        now: Int
    ) -> [NostrEmojiSetReference] {
        references.filter { reference in
            guard let event = try? eventStore.latestAddressableEvent(
                kind: 30_030,
                pubkey: reference.pubkey,
                dTag: reference.dTag
            ) else { return true }
            return !isFresh(event: event, eventStore: eventStore, now: now)
        }
    }

    private func isFresh(
        event: NostrEvent,
        eventStore: NostrEventStore,
        now: Int
    ) -> Bool {
        guard cacheRefreshIntervalSeconds > 0 else { return false }
        let lastSeenAt = (try? eventStore.eventSources(eventID: event.id))?
            .map(\.lastSeenAt)
            .max()
        guard let lastSeenAt else { return false }
        return now - lastSeenAt < cacheRefreshIntervalSeconds
    }

    private func fetch(
        relayURLs: [String],
        request: NostrRelayRequest
    ) async -> [RelayResult] {
        await withTaskGroup(of: RelayResult.self) { group in
            for relayURL in relayURLs {
                group.addTask { [relayClient] in
                    RelayResult(
                        relayURL: relayURL,
                        events: (try? await relayClient.fetch(
                            relayURL: relayURL,
                            request: request
                        )) ?? []
                    )
                }
            }
            var results: [RelayResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func fetchEmojiSets(
        plan: [(String, [NostrEmojiSetReference])],
        concurrencyLimit: Int
    ) async -> [RelayResult] {
        let batchSize = max(1, concurrencyLimit)
        var results: [RelayResult] = []
        for batchStart in stride(from: 0, to: plan.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batchEnd = min(batchStart + batchSize, plan.count)
            let batch = Array(plan[batchStart..<batchEnd])
            let batchResults = await withTaskGroup(of: RelayResult.self) { group in
                for (relayURL, references) in batch {
                    group.addTask { [relayClient] in
                        let filters = references.map { reference in
                            [
                                "authors": AnySendableJSON.strings([reference.pubkey]),
                                "kinds": .ints([30_030]),
                                "#d": .strings([reference.dTag]),
                                "limit": .int(1)
                            ]
                        }
                        let request = NostrRelayRequest(
                            subscriptionID: "astrenza-emoji-set-\(UUID().uuidString.prefix(8))",
                            filters: filters
                        )
                        return RelayResult(
                            relayURL: relayURL,
                            events: (try? await relayClient.fetch(
                                relayURL: relayURL,
                                request: request
                            )) ?? []
                        )
                    }
                }
                var batchResults: [RelayResult] = []
                for await result in group {
                    batchResults.append(result)
                }
                return batchResults
            }
            results.append(contentsOf: batchResults)
        }
        return results
    }

    private func makeSetFetchPlan(
        references: [NostrEmojiSetReference],
        baseRelays: [String],
        eventStore: NostrEventStore
    ) -> [(String, [NostrEmojiSetReference])] {
        let authors = Set(references.map(\.pubkey))
        let observedRelays = (try? eventStore.observedRelayURLsByAuthor(
            authors: authors,
            limitPerAuthor: 2
        )) ?? [:]
        var relayOrder: [String] = []
        var referencesByRelay: [String: [NostrEmojiSetReference]] = [:]

        for reference in references {
            let relayList = NostrRelayList.parse(from:
                try? eventStore.latestReplaceableEvent(
                    pubkey: reference.pubkey,
                    kind: 10_002
                )
            )
            let routes = NostrRelayURL.normalizedStrings(
                [reference.relayHint].compactMap { $0 }
                    + Array(relayList.writeRelays.prefix(4))
                    + (observedRelays[reference.pubkey] ?? [])
                    + Array(baseRelays.prefix(2))
            )
            for relayURL in routes {
                if referencesByRelay[relayURL] == nil {
                    relayOrder.append(relayURL)
                }
                if referencesByRelay[relayURL]?.contains(reference) != true {
                    referencesByRelay[relayURL, default: []].append(reference)
                }
            }
        }
        return relayOrder.compactMap { relayURL in
            referencesByRelay[relayURL].map { (relayURL, $0) }
        }
    }

    private func persist(
        events: [NostrEvent],
        results: [RelayResult],
        receivedAt: Int,
        eventStore: NostrEventStore
    ) -> Bool {
        let eventIDs = Set(events.map(\.id))
        let uniqueEvents = Dictionary(
            events.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        ).map(\.value)
        let sources: [NostrEventSourceRecord] = results.flatMap { result in
            result.events.compactMap { event in
                guard eventIDs.contains(event.id) else { return nil }
                return NostrEventSourceRecord(
                    eventID: event.id,
                    relayURL: result.relayURL,
                    firstSeenAt: receivedAt,
                    lastSeenAt: receivedAt
                )
            }
        }
        do {
            try eventStore.ingest(
                events: uniqueEvents,
                eventSources: sources,
                feedMemberships: [],
                receivedAt: receivedAt
            )
            return true
        } catch {
            return false
        }
    }
}
