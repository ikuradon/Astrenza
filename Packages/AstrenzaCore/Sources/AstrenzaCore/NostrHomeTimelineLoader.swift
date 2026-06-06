import Foundation

public struct NostrHomeTimelineState: Equatable, Sendable {
    public let relays: [String]
    public let followedPubkeys: [String]
    public let noteEvents: [NostrEvent]
    public let metadataEvents: [NostrEvent]
    public let relayListEvent: NostrEvent?
    public let contactListEvent: NostrEvent?
    public let nip05Resolutions: [String: NostrNIP05Resolution]
    public let hasMoreOlder: Bool
    public let relaySyncEvents: [NostrRelaySyncEventRecord]

    public init(
        relays: [String],
        followedPubkeys: [String],
        noteEvents: [NostrEvent],
        metadataEvents: [NostrEvent],
        relayListEvent: NostrEvent? = nil,
        contactListEvent: NostrEvent? = nil,
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        hasMoreOlder: Bool = true,
        relaySyncEvents: [NostrRelaySyncEventRecord] = []
    ) {
        self.relays = relays
        self.followedPubkeys = followedPubkeys
        self.noteEvents = noteEvents
        self.metadataEvents = metadataEvents
        self.relayListEvent = relayListEvent
        self.contactListEvent = contactListEvent
        self.nip05Resolutions = nip05Resolutions
        self.hasMoreOlder = hasMoreOlder
        self.relaySyncEvents = relaySyncEvents
    }
}

public struct NostrHomeTimelineLoader: Sendable {
    public let relayClient: any NostrRelayFetching
    public let nip05Resolver: any NostrNIP05Resolving
    public let bootstrapRelays: [String]
    public let pageLimit: Int

    public init(
        relayClient: any NostrRelayFetching = NostrRelayClient(),
        nip05Resolver: any NostrNIP05Resolving = NostrNIP05Resolver(),
        bootstrapRelays: [String] = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.primal.net",
            "wss://relay.nostr.band",
            "wss://nostr.wine"
        ],
        pageLimit: Int = 100
    ) {
        self.relayClient = relayClient
        self.nip05Resolver = nip05Resolver
        self.bootstrapRelays = bootstrapRelays
        self.pageLimit = max(1, min(pageLimit, 250))
    }

    public func initialState(account: NostrAccount) async throws -> NostrHomeTimelineState {
        var relaySyncEvents: [NostrRelaySyncEventRecord] = []
        let relayListResult = try await latestEvent(
            relays: bootstrapRelays,
            request: NostrRelayRequest(
                subscriptionID: "astrenza-nip65",
                filters: [[
                    "authors": .strings([account.pubkey]),
                    "kinds": .ints([10002]),
                    "limit": .int(1)
                ]]
            ),
            accountID: account.pubkey
        )
        relaySyncEvents.append(contentsOf: relayListResult.syncEvents)
        let relayListEvent = relayListResult.event

        let relayList = NostrRelayList.parse(from: relayListEvent)
        let readRelays = relayList.readRelays.isEmpty ? bootstrapRelays : Array(relayList.readRelays.prefix(8))
        let contactRelays = Array((readRelays + bootstrapRelays).uniqued().prefix(10))

        let contactResult = try await latestEvent(
            relays: contactRelays,
            request: NostrRelayRequest(
                subscriptionID: "astrenza-kind3",
                filters: [[
                    "authors": .strings([account.pubkey]),
                    "kinds": .ints([3]),
                    "limit": .int(1)
                ]]
            ),
            accountID: account.pubkey
        )
        relaySyncEvents.append(contentsOf: contactResult.syncEvents)
        let contactEvent = contactResult.event
        let contacts = Array(NostrContactList.pubkeys(from: contactEvent).prefix(256))

        guard !contacts.isEmpty else {
            return NostrHomeTimelineState(
                relays: readRelays,
                followedPubkeys: [],
                noteEvents: [],
                metadataEvents: [],
                relayListEvent: relayListEvent,
                contactListEvent: contactEvent,
                nip05Resolutions: [:],
                hasMoreOlder: true,
                relaySyncEvents: relaySyncEvents
            )
        }

        let planner = NostrHomeFetchPlanner(authors: Array(contacts.prefix(128)), pageLimit: pageLimit)
        let homeResult = try await mergedEvents(
            relays: readRelays,
            request: planner.initialRequest(subscriptionID: "astrenza-home"),
            accountID: account.pubkey
        )
        relaySyncEvents.append(contentsOf: homeResult.syncEvents)
        let homeEvents = homeResult.events
        let metadataEvents = try await metadataEvents(
            for: homeEvents,
            existingMetadataEvents: [],
            relays: readRelays,
            accountID: account.pubkey,
            relaySyncEvents: &relaySyncEvents
        )
        let nip05Resolutions = await nip05Resolutions(
            metadataEvents: metadataEvents,
            existingResolutions: [:]
        )

        return NostrHomeTimelineState(
            relays: readRelays,
            followedPubkeys: contacts,
            noteEvents: sortedUnique(homeEvents),
            metadataEvents: sortedUnique(metadataEvents),
            relayListEvent: relayListEvent,
            contactListEvent: contactEvent,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: true,
            relaySyncEvents: relaySyncEvents
        )
    }

    public func refreshedState(account: NostrAccount, current: NostrHomeTimelineState) async throws -> NostrHomeTimelineState {
        guard !current.noteEvents.isEmpty else {
            return try await initialState(account: account)
        }

        let relays = current.relays.isEmpty ? bootstrapRelays : current.relays
        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : Array(current.followedPubkeys.prefix(128))
        let newestCreatedAt = current.noteEvents.map(\.createdAt).max() ?? 0
        let planner = NostrHomeFetchPlanner(authors: authors, pageLimit: pageLimit)
        var relaySyncEvents: [NostrRelaySyncEventRecord] = []
        let freshResult = try await mergedEvents(
            relays: relays,
            request: planner.newerRequest(subscriptionID: "astrenza-home-newer", after: newestCreatedAt),
            accountID: account.pubkey
        )
        relaySyncEvents.append(contentsOf: freshResult.syncEvents)
        let freshEvents = freshResult.events
        let noteEvents = sortedUnique(current.noteEvents + freshEvents)
        let freshMetadata = try await metadataEvents(
            for: freshEvents,
            existingMetadataEvents: current.metadataEvents,
            relays: relays,
            accountID: account.pubkey,
            relaySyncEvents: &relaySyncEvents
        )
        let metadataEvents = sortedUnique(current.metadataEvents + freshMetadata)
        let nip05Resolutions = await nip05Resolutions(
            metadataEvents: metadataEvents,
            existingResolutions: current.nip05Resolutions
        )

        return NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: current.followedPubkeys,
            noteEvents: noteEvents,
            metadataEvents: metadataEvents,
            relayListEvent: current.relayListEvent,
            contactListEvent: current.contactListEvent,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: current.hasMoreOlder,
            relaySyncEvents: relaySyncEvents
        )
    }

    public func olderState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]? = nil
    ) async throws -> NostrHomeTimelineState {
        let relays = current.relays.isEmpty ? bootstrapRelays : current.relays
        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : Array(current.followedPubkeys.prefix(128))
        guard let oldestCreatedAt = current.noteEvents.map(\.createdAt).min() else {
            return current
        }

        let planner = NostrHomeFetchPlanner(authors: authors, pageLimit: pageLimit)
        let until = max(0, oldestCreatedAt - 1)
        var relaySyncEvents: [NostrRelaySyncEventRecord] = []
        let olderResult = try await mergedEvents(
            relays: relays,
            request: planner.olderRequest(subscriptionID: "astrenza-home-older", before: oldestCreatedAt),
            accountID: account.pubkey
        )
        relaySyncEvents.append(contentsOf: olderResult.syncEvents)
        var olderEvents = olderResult.events
        if olderEvents.isEmpty {
            olderEvents = try await negentropyBackfillEvents(
                relays: relays,
                authors: authors,
                until: until,
                currentNoteEvents: localBackfillEvents ?? current.noteEvents,
                accountID: account.pubkey,
                relaySyncEvents: &relaySyncEvents
            )
        }
        guard !olderEvents.isEmpty else {
            return NostrHomeTimelineState(
                relays: relays,
                followedPubkeys: current.followedPubkeys,
                noteEvents: current.noteEvents,
                metadataEvents: current.metadataEvents,
                relayListEvent: current.relayListEvent,
                contactListEvent: current.contactListEvent,
                nip05Resolutions: current.nip05Resolutions,
                hasMoreOlder: false,
                relaySyncEvents: relaySyncEvents
            )
        }

        let olderMetadata = try await metadataEvents(
            for: olderEvents,
            existingMetadataEvents: current.metadataEvents,
            relays: relays,
            accountID: account.pubkey,
            relaySyncEvents: &relaySyncEvents
        )
        let metadataEvents = sortedUnique(current.metadataEvents + olderMetadata)
        let nip05Resolutions = await nip05Resolutions(
            metadataEvents: metadataEvents,
            existingResolutions: current.nip05Resolutions
        )
        return NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: current.followedPubkeys,
            noteEvents: sortedUnique(current.noteEvents + olderEvents),
            metadataEvents: metadataEvents,
            relayListEvent: current.relayListEvent,
            contactListEvent: current.contactListEvent,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: true,
            relaySyncEvents: relaySyncEvents
        )
    }

    private func nip05Resolutions(
        metadataEvents: [NostrEvent],
        existingResolutions: [String: NostrNIP05Resolution]
    ) async -> [String: NostrNIP05Resolution] {
        let metadataByPubkey = NostrHomeTimelineMaterializer.latestMetadataByPubkey(metadataEvents)
        let missing = metadataByPubkey.filter { pubkey, metadata in
            guard let identifier = metadata.nip05, !identifier.isEmpty else { return false }
            return existingResolutions[pubkey]?.identifier != identifier
        }
        guard !missing.isEmpty else { return existingResolutions }

        let resolver = nip05Resolver
        var resolutions = existingResolutions
        await withTaskGroup(of: (String, NostrNIP05Resolution).self) { group in
            for (pubkey, metadata) in missing {
                guard let identifier = metadata.nip05 else { continue }
                group.addTask {
                    let resolution = await resolver.resolve(identifier: identifier, expectedPubkey: pubkey)
                    return (pubkey, resolution)
                }
            }

            for await (pubkey, resolution) in group {
                resolutions[pubkey] = resolution
            }
        }
        return resolutions
    }

    private func metadataEvents(
        for noteEvents: [NostrEvent],
        existingMetadataEvents: [NostrEvent],
        relays: [String],
        accountID: String,
        relaySyncEvents: inout [NostrRelaySyncEventRecord]
    ) async throws -> [NostrEvent] {
        let missingAuthors = Array(Set(noteEvents.map(\.pubkey)).subtracting(Set(existingMetadataEvents.map(\.pubkey))))
        guard !missingAuthors.isEmpty else { return [] }
        let result = try await mergedEvents(
            relays: relays,
            request: NostrRelayRequest(
                subscriptionID: "astrenza-kind0",
                filters: [[
                    "authors": .strings(missingAuthors),
                    "kinds": .ints([0]),
                    "limit": .int(min(max(missingAuthors.count, 1), 250))
                ]]
            ),
            accountID: accountID
        )
        relaySyncEvents.append(contentsOf: result.syncEvents)
        return result.events
    }

    private func negentropyBackfillEvents(
        relays: [String],
        authors: [String],
        until: Int,
        currentNoteEvents: [NostrEvent],
        accountID: String,
        relaySyncEvents: inout [NostrRelaySyncEventRecord]
    ) async throws -> [NostrEvent] {
        let relayClient = relayClient
        let pageLimit = pageLimit
        let localWindowEvents = currentNoteEvents.filter { event in
            event.createdAt <= until && authors.contains(event.pubkey)
        }
        let filter = NostrRelayFilter(kinds: [1], authors: authors, until: until, limit: pageLimit)

        let missingIDs = try await withThrowingTaskGroup(of: [String].self) { group in
            for relay in relays.prefix(4) {
                group.addTask {
                    (try? await relayClient.fetchMissingEventIDs(
                        relayURL: relay,
                        filter: filter,
                        localEvents: localWindowEvents,
                        subscriptionID: "astrenza-neg-gap"
                    )) ?? []
                }
            }

            var ids = Set<String>()
            for try await relayIDs in group {
                ids.formUnion(relayIDs)
            }
            return Array(ids).sorted()
        }

        guard !missingIDs.isEmpty else { return [] }
        let result = try await mergedEvents(
            relays: relays,
            request: NostrRelayRequest(
                subscriptionID: "astrenza-gap-events",
                filters: [["ids": .strings(Array(missingIDs.prefix(250)))]]
            ),
            accountID: accountID
        )
        relaySyncEvents.append(contentsOf: result.syncEvents)
        return result.events
    }

    private func latestEvent(
        relays: [String],
        request: NostrRelayRequest,
        accountID: String
    ) async throws -> (event: NostrEvent?, syncEvents: [NostrRelaySyncEventRecord]) {
        let result = try await mergedEvents(relays: relays, request: request, accountID: accountID)
        let event = result.events.max { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
        return (event, result.syncEvents)
    }

    private func mergedEvents(
        relays: [String],
        request: NostrRelayRequest,
        accountID: String
    ) async throws -> (events: [NostrEvent], syncEvents: [NostrRelaySyncEventRecord]) {
        let relayClient = relayClient
        return try await withThrowingTaskGroup(of: (String, Result<[NostrEvent], Error>, Int, Int).self) { group in
            for relay in relays {
                group.addTask {
                    let started = Date()
                    do {
                        let events = try await relayClient.fetch(relayURL: relay, request: request)
                        let latency = Int(Date().timeIntervalSince(started) * 1_000)
                        return (relay, .success(events), Int(started.timeIntervalSince1970), latency)
                    } catch {
                        let latency = Int(Date().timeIntervalSince(started) * 1_000)
                        return (relay, .failure(error), Int(started.timeIntervalSince1970), latency)
                    }
                }
            }

            var eventsByID: [String: NostrEvent] = [:]
            var syncEvents: [NostrRelaySyncEventRecord] = []
            for try await (relay, result, startedAt, latency) in group {
                switch result {
                case .success(let relayEvents):
                    for event in relayEvents {
                        eventsByID[event.id] = event
                    }
                    syncEvents.append(NostrRelaySyncEventRecord(
                        accountID: accountID,
                        timelineKey: "home",
                        relayURL: relay,
                        kind: .eose,
                        occurredAt: startedAt + max(0, latency / 1_000),
                        subscriptionID: request.subscriptionID,
                        eventCount: relayEvents.count,
                        newestCreatedAt: relayEvents.map(\.createdAt).max(),
                        oldestCreatedAt: relayEvents.map(\.createdAt).min(),
                        latencyMilliseconds: latency,
                        message: "EOSE received"
                    ))
                case .failure(let error):
                    let kind: NostrRelaySyncEventKind
                    switch error as? NostrRelayClientError {
                    case .timeout:
                        kind = .timeout
                    default:
                        kind = .partialFailure
                    }
                    syncEvents.append(NostrRelaySyncEventRecord(
                        accountID: accountID,
                        timelineKey: "home",
                        relayURL: relay,
                        kind: kind,
                        occurredAt: startedAt + max(0, latency / 1_000),
                        subscriptionID: request.subscriptionID,
                        eventCount: 0,
                        latencyMilliseconds: latency,
                        message: String(describing: error)
                    ))
                }
            }

            return (sortedUnique(Array(eventsByID.values)), syncEvents)
        }
    }

    private func sortedUnique(_ events: [NostrEvent]) -> [NostrEvent] {
        var eventsByID: [String: NostrEvent] = [:]
        for event in events {
            eventsByID[event.id] = event
        }
        return eventsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
