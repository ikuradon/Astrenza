import Foundation
import NostrProtocol
import NostrRelay
import NostrStoreAPI
import NostrSync

public enum NostrHomeTimelineLoadStage: Equatable, Sendable {
    case resolvingRelayList
    case resolvingContactList
    case resolvingOutboxRelayLists
    case loadingTimeline
}

public struct NostrHomeTimelineDiscoveryPolicy: Equatable, Sendable {
    public let settlementNanoseconds: UInt64
    public let absoluteTimeoutNanoseconds: UInt64

    public init(
        settlementMilliseconds: Int = 150,
        absoluteTimeoutMilliseconds: Int = 5_000
    ) {
        settlementNanoseconds = Self.nanoseconds(
            milliseconds: settlementMilliseconds,
            minimum: 0
        )
        absoluteTimeoutNanoseconds = Self.nanoseconds(
            milliseconds: absoluteTimeoutMilliseconds,
            minimum: 1
        )
    }

    private static func nanoseconds(milliseconds: Int, minimum: Int) -> UInt64 {
        let maximum = Int(UInt64.max / 1_000_000)
        return UInt64(min(max(minimum, milliseconds), maximum)) * 1_000_000
    }
}

public struct NostrHomeTimelineLoader: Sendable {
    public static let defaultBootstrapRelays = [
        "wss://nos.lol",
        "wss://purplepag.es",
        "wss://directory.yabu.me",
        "wss://relay.damus.io"
    ]

    public let relayClient: any NostrRelayFetching
    public let nip05Resolver: any NostrNIP05Resolving
    public let bootstrapRelays: [String]
    public let pageLimit: Int
    public let discoveryPolicy: NostrHomeTimelineDiscoveryPolicy

    public init(
        relayClient: any NostrRelayFetching,
        nip05Resolver: any NostrNIP05Resolving = NostrNIP05Resolver(),
        bootstrapRelays: [String] = NostrHomeTimelineLoader.defaultBootstrapRelays,
        pageLimit: Int = 100,
        discoveryPolicy: NostrHomeTimelineDiscoveryPolicy = NostrHomeTimelineDiscoveryPolicy()
    ) {
        self.relayClient = relayClient
        self.nip05Resolver = nip05Resolver
        self.bootstrapRelays = bootstrapRelays
        self.pageLimit = max(1, min(pageLimit, 250))
        self.discoveryPolicy = discoveryPolicy
    }

    public func bootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy = .default(),
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)? = nil
    ) async throws -> NostrHomeTimelineState {
        try await withBootstrapScope {
            try await bootstrapStateWithoutScope(
                account: account,
                policy: policy,
                onStage: onStage
            )
        }
    }

    private func bootstrapStateWithoutScope(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        try await resolvedAccountBootstrapState(
            account: account,
            policy: policy,
            onStage: onStage
        )
    }

    public func initialState(
        account: NostrAccount,
        policy: NostrSyncPolicy = .default(),
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)? = nil
    ) async throws -> NostrHomeTimelineState {
        try await withBootstrapScope {
            try await initialStateWithoutScope(
                account: account,
                policy: policy,
                onStage: onStage
            )
        }
    }

    private func initialStateWithoutScope(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        let bootstrapState = try await resolvedAccountBootstrapState(
            account: account,
            policy: policy,
            onStage: onStage
        )
        var relaySyncEvents = bootstrapState.relaySyncEvents
        let readRelays = bootstrapState.relays
        let contacts = bootstrapState.followedPubkeys

        guard !contacts.isEmpty else {
            return bootstrapState
        }

        await onStage?(.loadingTimeline)
        let homeResult = try await timelineEvents(
            authors: contacts,
            authorRelayListEvents: bootstrapState.authorRelayListEvents,
            contactListEvent: bootstrapState.contactListEvent,
            fallbackRelays: readRelays,
            policy: policy,
            accountID: account.pubkey,
            subscriptionID: "astrenza-home"
        ) { planner, subscriptionID in
            planner.initialRequest(subscriptionID: subscriptionID)
        }
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
            relayListEvent: bootstrapState.relayListEvent,
            contactListEvent: bootstrapState.contactListEvent,
            authorRelayListEvents: bootstrapState.authorRelayListEvents,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: true,
            relaySyncEvents: relaySyncEvents
        )
    }

    private func resolvedAccountBootstrapState(
        account: NostrAccount,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?
    ) async throws -> NostrHomeTimelineState {
        let discoveryStartedAt = ProcessInfo.processInfo.systemUptime
        let discoveryRelays = (normalizedRelayURLs(account.discoveryRelays) + bootstrapRelays).uniqued()
        let relayListRequest = NostrRelayRequest(
            subscriptionID: "astrenza-nip65",
            filters: [[
                "authors": .strings([account.pubkey]),
                "kinds": .ints([10_002]),
                "limit": .int(1)
            ]]
        )
        let contactListRequest = NostrRelayRequest(
            subscriptionID: "astrenza-kind3",
            filters: [[
                "authors": .strings([account.pubkey]),
                "kinds": .ints([3]),
                "limit": .int(1)
            ]]
        )

        await onStage?(.resolvingRelayList)
        async let discoveryContactResult = settledLatestEvent(
            relays: discoveryRelays,
            request: contactListRequest,
            accountID: account.pubkey
        )
        let resolvedRelayList = try await settledLatestEvent(
            relays: discoveryRelays,
            request: relayListRequest,
            accountID: account.pubkey
        )
        await onStage?(.resolvingContactList)
        let resolvedDiscoveryContact = try await discoveryContactResult
        var relaySyncEvents = resolvedRelayList.syncEvents + resolvedDiscoveryContact.syncEvents
        let relayListEvent = resolvedRelayList.event
        let relayList = NostrRelayList.parse(from: relayListEvent)
        let readRelays = relayList.readRelays.isEmpty ? bootstrapRelays : relayList.readRelays
        let contactRelays = (readRelays + discoveryRelays).uniqued()

        var contactEvent = resolvedDiscoveryContact.event
        let additionalContactRelays = readRelays.filter { !discoveryRelays.contains($0) }
        let discoveryElapsedNanoseconds = UInt64(
            max(0, ProcessInfo.processInfo.systemUptime - discoveryStartedAt) * 1_000_000_000
        )
        if contactEvent == nil,
           !additionalContactRelays.isEmpty,
           discoveryElapsedNanoseconds < discoveryPolicy.absoluteTimeoutNanoseconds {
            let supplementalContactResult = try await settledLatestEvent(
                relays: additionalContactRelays,
                request: contactListRequest,
                accountID: account.pubkey,
                absoluteTimeoutNanoseconds: discoveryPolicy.absoluteTimeoutNanoseconds
                    - discoveryElapsedNanoseconds
            )
            relaySyncEvents.append(contentsOf: supplementalContactResult.syncEvents)
            contactEvent = supplementalContactResult.event
        }

        let contacts = NostrContactList.pubkeys(from: contactEvent)
        let authorRelayListEvents = try await authorRelayListEvents(
            authors: contacts,
            relays: contactRelays,
            accountID: account.pubkey,
            policy: policy,
            onStage: onStage,
            relaySyncEvents: &relaySyncEvents
        )

        return NostrHomeTimelineState(
            relays: readRelays,
            followedPubkeys: contacts,
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: relayListEvent,
            contactListEvent: contactEvent,
            authorRelayListEvents: authorRelayListEvents,
            nip05Resolutions: [:],
            hasMoreOlder: true,
            relaySyncEvents: relaySyncEvents
        )
    }

    public func refreshedState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        policy: NostrSyncPolicy = .default()
    ) async throws -> NostrHomeTimelineState {
        guard !current.noteEvents.isEmpty else {
            return try await initialState(account: account, policy: policy)
        }

        let relays = current.relays.isEmpty ? bootstrapRelays : current.relays
        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : current.followedPubkeys
        let newestCreatedAt = current.noteEvents.map(\.createdAt).max() ?? 0
        var relaySyncEvents: [NostrRelaySyncEventRecord] = []
        let refreshedRelayListEvents = try await authorRelayListEvents(
            authors: authors,
            relays: relays,
            accountID: account.pubkey,
            policy: policy,
            onStage: nil,
            relaySyncEvents: &relaySyncEvents
        )
        let authorRelayListEvents = latestRelayListEvents(
            current.authorRelayListEvents + refreshedRelayListEvents,
            authors: Set(authors.map { $0.lowercased() })
        )
        let freshResult = try await timelineEvents(
            authors: authors,
            authorRelayListEvents: authorRelayListEvents,
            contactListEvent: current.contactListEvent,
            fallbackRelays: relays,
            policy: policy,
            accountID: account.pubkey,
            subscriptionID: "astrenza-home-newer"
        ) { planner, subscriptionID in
            planner.newerRequest(
                subscriptionID: subscriptionID,
                after: newestCreatedAt
            )
        }
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
            authorRelayListEvents: authorRelayListEvents,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: current.hasMoreOlder,
            relaySyncEvents: relaySyncEvents
        )
    }

    public func olderState(
        account: NostrAccount,
        current: NostrHomeTimelineState,
        localBackfillEvents: [NostrEvent]? = nil,
        policy: NostrSyncPolicy = .default()
    ) async throws -> NostrHomeTimelineState {
        let relays = current.relays.isEmpty ? bootstrapRelays : current.relays
        let authors = current.followedPubkeys.isEmpty ? [account.pubkey] : current.followedPubkeys
        guard let oldestCreatedAt = current.noteEvents.map(\.createdAt).min() else {
            return current
        }

        let until = max(0, oldestCreatedAt - 1)
        var relaySyncEvents: [NostrRelaySyncEventRecord] = []
        let olderResult = try await timelineEvents(
            authors: authors,
            authorRelayListEvents: current.authorRelayListEvents,
            contactListEvent: current.contactListEvent,
            fallbackRelays: relays,
            policy: policy,
            accountID: account.pubkey,
            subscriptionID: "astrenza-home-older"
        ) { planner, subscriptionID in
            planner.olderRequest(
                subscriptionID: subscriptionID,
                before: oldestCreatedAt
            )
        }
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
                authorRelayListEvents: current.authorRelayListEvents,
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
            authorRelayListEvents: current.authorRelayListEvents,
            nip05Resolutions: nip05Resolutions,
            hasMoreOlder: true,
            relaySyncEvents: relaySyncEvents
        )
    }

    private func timelineEvents(
        authors: [String],
        authorRelayListEvents: [NostrEvent],
        contactListEvent: NostrEvent?,
        fallbackRelays: [String],
        policy: NostrSyncPolicy,
        accountID: String,
        subscriptionID: String,
        makeRequest: (NostrHomeFetchPlanner, String) -> NostrRelayRequest
    ) async throws -> (
        events: [NostrEvent],
        syncEvents: [NostrRelaySyncEventRecord]
    ) {
        guard policy.mode == .fullOutbox else {
            return try await mergedEvents(
                relays: fallbackRelays,
                request: makeRequest(
                    NostrHomeFetchPlanner(
                        authors: authors,
                        pageLimit: pageLimit
                    ),
                    subscriptionID
                ),
                accountID: accountID
            )
        }

        let routing = NostrOutboxRelayRouting()
        let relayURLsByAuthor = routing.relayURLsByAuthor(
            authors: authors,
            relayListEvents: authorRelayListEvents,
            contactItems: NostrContactList.items(from: contactListEvent),
            fallbackRelayURLs: fallbackRelays
        )
        let authorsByRelay = routing.authorsByRelay(
            relayURLsByAuthor: relayURLsByAuthor
        )
        let relayClient = relayClient
        return try await withThrowingTaskGroup(
            of: (
                String,
                NostrRelayRequest,
                Result<[NostrEvent], Error>,
                Int,
                Int
            ).self
        ) { group in
            for (index, relayURL) in authorsByRelay.keys.sorted().enumerated() {
                let relayAuthors = authorsByRelay[relayURL] ?? []
                let request = makeRequest(
                    NostrHomeFetchPlanner(
                        authors: relayAuthors,
                        pageLimit: pageLimit
                    ),
                    "\(subscriptionID)-outbox-\(index + 1)"
                )
                group.addTask {
                    let started = Date()
                    do {
                        let events = try await relayClient.fetch(
                            relayURL: relayURL,
                            request: request
                        )
                        return (
                            relayURL,
                            request,
                            .success(events),
                            Int(started.timeIntervalSince1970),
                            Int(Date().timeIntervalSince(started) * 1_000)
                        )
                    } catch {
                        return (
                            relayURL,
                            request,
                            .failure(error),
                            Int(started.timeIntervalSince1970),
                            Int(Date().timeIntervalSince(started) * 1_000)
                        )
                    }
                }
            }

            var eventsByID: [String: NostrEvent] = [:]
            var syncEvents: [NostrRelaySyncEventRecord] = []
            for try await (relay, request, result, startedAt, latency) in group {
                syncEvents.append(relaySyncEvent(
                    relay: relay,
                    result: result,
                    startedAt: startedAt,
                    latency: latency,
                    request: request,
                    accountID: accountID
                ))
                if case .success(let relayEvents) = result {
                    for event in relayEvents {
                        eventsByID[event.id] = event
                    }
                }
            }
            return (sortedUnique(Array(eventsByID.values)), syncEvents)
        }
    }

    private func authorRelayListEvents(
        authors: [String],
        relays: [String],
        accountID: String,
        policy: NostrSyncPolicy,
        onStage: (@Sendable (NostrHomeTimelineLoadStage) async -> Void)?,
        relaySyncEvents: inout [NostrRelaySyncEventRecord]
    ) async throws -> [NostrEvent] {
        guard policy.mode == .fullOutbox, !authors.isEmpty else { return [] }
        await onStage?(.resolvingOutboxRelayLists)
        let sortedAuthors = authors.sorted()
        let filters = stride(from: 0, to: sortedAuthors.count, by: 200)
            .map { offset in
                let chunk = Array(sortedAuthors[offset..<min(offset + 200, sortedAuthors.count)])
                return [
                    "authors": AnySendableJSON.strings(chunk),
                    "kinds": .ints([10_002]),
                    "limit": .int(chunk.count)
                ]
            }
        let result = try await mergedEvents(
            relays: relays,
            request: NostrRelayRequest(
                subscriptionID: "astrenza-outbox-relay-lists",
                filters: filters
            ),
            accountID: accountID
        )
        relaySyncEvents.append(contentsOf: result.syncEvents)
        return latestRelayListEvents(
            result.events,
            authors: Set(authors.map { $0.lowercased() })
        )
    }

    private func latestRelayListEvents(
        _ events: [NostrEvent],
        authors: Set<String>
    ) -> [NostrEvent] {
        var latestByAuthor: [String: NostrEvent] = [:]
        for event in events where event.kind == 10_002 {
            let author = event.pubkey.lowercased()
            guard authors.contains(author) else { continue }
            guard let current = latestByAuthor[author] else {
                latestByAuthor[author] = event
                continue
            }
            if event.createdAt > current.createdAt ||
                (event.createdAt == current.createdAt && event.id < current.id) {
                latestByAuthor[author] = event
            }
        }
        return latestByAuthor.values.sorted { lhs, rhs in
            lhs.pubkey < rhs.pubkey
        }
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

    private func settledLatestEvent(
        relays: [String],
        request: NostrRelayRequest,
        accountID: String,
        settlementNanoseconds: UInt64? = nil,
        absoluteTimeoutNanoseconds: UInt64? = nil
    ) async throws -> (event: NostrEvent?, syncEvents: [NostrRelaySyncEventRecord]) {
        let relays = relays.uniqued()
        guard !relays.isEmpty else { return (nil, []) }

        let relayClient = relayClient
        let settlementNanoseconds = settlementNanoseconds ?? discoveryPolicy.settlementNanoseconds
        let absoluteTimeoutNanoseconds = absoluteTimeoutNanoseconds
            ?? discoveryPolicy.absoluteTimeoutNanoseconds
        return try await withThrowingTaskGroup(of: SettledRelayFetchOutcome.self) { group in
            defer { group.cancelAll() }
            let deadlineStarted = Date()
            let deadlineStartedAt = Int(deadlineStarted.timeIntervalSince1970)
            var pendingRelays = Set(relays)
            for relay in relays {
                group.addTask {
                    let started = Date()
                    do {
                        let events = try await relayClient.fetch(relayURL: relay, request: request)
                        let latency = Int(Date().timeIntervalSince(started) * 1_000)
                        return .relay(
                            relay,
                            .success(events),
                            Int(started.timeIntervalSince1970),
                            latency
                        )
                    } catch {
                        let latency = Int(Date().timeIntervalSince(started) * 1_000)
                        return .relay(
                            relay,
                            .failure(error),
                            Int(started.timeIntervalSince1970),
                            latency
                        )
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: absoluteTimeoutNanoseconds)
                return .absoluteDeadline
            }

            var eventsByID: [String: NostrEvent] = [:]
            var syncEvents: [NostrRelaySyncEventRecord] = []
            var didScheduleSettlement = false
            fetchLoop: while let outcome = try await group.next() {
                try Task.checkCancellation()
                switch outcome {
                case .relay(let relay, let result, let startedAt, let latency):
                    pendingRelays.remove(relay)
                    let syncEvent = relaySyncEvent(
                        relay: relay,
                        result: result,
                        startedAt: startedAt,
                        latency: latency,
                        request: request,
                        accountID: accountID
                    )
                    syncEvents.append(syncEvent)

                    if case .success(let relayEvents) = result {
                        relayEvents.forEach { eventsByID[$0.id] = $0 }
                        if !relayEvents.isEmpty, !didScheduleSettlement {
                            didScheduleSettlement = true
                            group.addTask {
                                try await Task.sleep(nanoseconds: settlementNanoseconds)
                                return .settlementDeadline
                            }
                        }
                    }
                    if pendingRelays.isEmpty {
                        break fetchLoop
                    }
                case .settlementDeadline:
                    break fetchLoop
                case .absoluteDeadline:
                    let latency = Int(Date().timeIntervalSince(deadlineStarted) * 1_000)
                    for relay in pendingRelays.sorted() {
                        let timeout: Result<[NostrEvent], any Error> = .failure(
                            NostrRelayClientError.timeout
                        )
                        syncEvents.append(relaySyncEvent(
                            relay: relay,
                            result: timeout,
                            startedAt: deadlineStartedAt,
                            latency: max(0, latency),
                            request: request,
                            accountID: accountID
                        ))
                    }
                    break fetchLoop
                }
            }

            let event = eventsByID.values.max { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
            return (event, syncEvents)
        }
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
                syncEvents.append(relaySyncEvent(
                    relay: relay,
                    result: result,
                    startedAt: startedAt,
                    latency: latency,
                    request: request,
                    accountID: accountID
                ))

                switch result {
                case .success(let relayEvents):
                    for event in relayEvents {
                        eventsByID[event.id] = event
                    }
                case .failure:
                    break
                }
            }

            return (sortedUnique(Array(eventsByID.values)), syncEvents)
        }
    }

    private func relaySyncEvent(
        relay: String,
        result: Result<[NostrEvent], Error>,
        startedAt: Int,
        latency: Int,
        request: NostrRelayRequest,
        accountID: String
    ) -> NostrRelaySyncEventRecord {
        switch result {
        case .success(let relayEvents):
            return NostrRelaySyncEventRecord(
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
            )
        case .failure(let error):
            let kind: NostrRelaySyncEventKind
            let message: String
            switch error as? NostrRelayClientError {
            case .timeout:
                kind = .timeout
                message = "timeout"
            case .authRequired(let challenge):
                kind = .authRequired
                message = challenge
            case .paymentRequired(let reason):
                kind = .paymentRequired
                message = reason
            case .relayClosed(let reason):
                kind = .closed
                message = reason
            default:
                kind = .partialFailure
                message = String(describing: error)
            }
            return NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relay,
                kind: kind,
                occurredAt: startedAt + max(0, latency / 1_000),
                subscriptionID: request.subscriptionID,
                eventCount: 0,
                latencyMilliseconds: latency,
                message: message
            )
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

    private func withBootstrapScope<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        guard let scopedClient = relayClient as? any NostrRelayBootstrapScoping else {
            return try await operation()
        }

        let scopeID = await scopedClient.beginBootstrapScope()
        do {
            let result = try await operation()
            await scopedClient.finishBootstrapScope(
                scopeID,
                retainUntilDefaultRelayHandoff: true
            )
            return result
        } catch {
            await scopedClient.finishBootstrapScope(
                scopeID,
                retainUntilDefaultRelayHandoff: false
            )
            throw error
        }
    }

    private func normalizedRelayURLs(_ relays: [String]) -> [String] {
        NostrRelayURL.normalizedStrings(relays, mode: .userFacing)
    }
}

private enum SettledRelayFetchOutcome: Sendable {
    case relay(String, Result<[NostrEvent], any Error>, Int, Int)
    case settlementDeadline
    case absoluteDeadline
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
