import AstrenzaCore
import Foundation

actor NostrComposeEmojiResolver {
    private struct RelayResult: Sendable {
        let relayURL: String
        let events: [NostrEvent]
    }

    private let eventStore: NostrEventStore?
    private let relayClient: any NostrRelayFetching
    private let refreshIntervalSeconds: Int
    private let now: @Sendable () -> Int
    private var lastAttemptAtByAccountID: [String: Int] = [:]

    init(
        eventStore: NostrEventStore?,
        relayClient: any NostrRelayFetching,
        refreshIntervalSeconds: Int = 60,
        now: @escaping @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970)
        }
    ) {
        self.eventStore = eventStore
        self.relayClient = relayClient
        self.refreshIntervalSeconds = max(0, refreshIntervalSeconds)
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

        let attemptAt = now()
        if let lastAttemptAt = lastAttemptAtByAccountID[normalizedAccountID],
           attemptAt - lastAttemptAt < refreshIntervalSeconds {
            return false
        }
        lastAttemptAtByAccountID[normalizedAccountID] = attemptAt

        let baseRelays = NostrRelayURL.normalizedStrings(relayURLs)
        var didPersist = false
        if !baseRelays.isEmpty {
            let request = NostrRelayRequest(
                subscriptionID: "astrenza-emoji-list-\(UUID().uuidString.prefix(8))",
                filters: [[
                    "authors": .strings([normalizedAccountID]),
                    "kinds": .ints([10_030]),
                    "limit": .int(1)
                ]]
            )
            let results = await fetch(
                relayURLs: Array(baseRelays.prefix(6)),
                request: request
            )
            let listEvents = results.flatMap(\.events).filter {
                $0.kind == 10_030 && $0.pubkey == normalizedAccountID
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
            pubkey: normalizedAccountID,
            kind: 10_030
        ) else { return didPersist }
        let references = NostrEmojiSetReference.references(in: emojiListEvent)
        guard !references.isEmpty else { return didPersist }

        let setFetchPlan = makeSetFetchPlan(
            references: references,
            baseRelays: baseRelays,
            eventStore: eventStore
        )
        let setResults = await fetchEmojiSets(
            plan: setFetchPlan,
            concurrencyLimit: 4
        )

        let expectedAddresses = Set(references.map(\.address))
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
