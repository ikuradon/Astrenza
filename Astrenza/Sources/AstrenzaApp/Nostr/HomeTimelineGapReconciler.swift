import AstrenzaCore
import Foundation

enum HomeTimelineGapReconciliationResult: Sendable {
    case verifiedComplete
    case recovered([NostrEvent])
    case indeterminate
}

struct HomeTimelineGapDiagnostic: Sendable {
    let relayURL: String
    let message: String
}

struct HomeTimelineGapReconciliationOutput: Sendable {
    let result: HomeTimelineGapReconciliationResult
    let diagnostics: [HomeTimelineGapDiagnostic]
}

actor HomeTimelineGapReconciler {
    private let eventStore: NostrEventStore?
    private let relayClient: any NostrRelayFetching

    init(eventStore: NostrEventStore?, relayClient: any NostrRelayFetching) {
        self.eventStore = eventStore
        self.relayClient = relayClient
    }

    func reconcile(
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        context: HomeFeedRuntimeContext,
        relays: [String],
        inMemoryEvents: [NostrEvent]
    ) async -> HomeTimelineGapReconciliationOutput {
        let authors = context.allowedAuthors.isEmpty
            ? [context.accountID]
            : context.allowedAuthors.sorted()
        guard !authors.isEmpty,
              olderEvent.createdAt < newerEvent.createdAt,
              !relays.isEmpty
        else {
            return output(.indeterminate)
        }

        let localEvents = localGapWindowEvents(
            authors: authors,
            newerEvent: newerEvent,
            olderEvent: olderEvent,
            inMemoryEvents: inMemoryEvents
        )
        let filter = NostrRelayFilter(
            kinds: [1, 6],
            authors: authors,
            since: olderEvent.createdAt + 1,
            until: newerEvent.createdAt - 1
        )
        let requestStart = beginVerificationRequests(
            relays: relays,
            filter: filter,
            requestedAt: Int(Date().timeIntervalSince1970),
            context: context
        )
        let probe = await probeMissingEventIDs(
            relays: relays,
            filter: filter,
            localEvents: localEvents,
            requestIDs: requestStart.requestIDs
        )
        persistVerificationResults(probe.results)
        guard probe.successCount > 0 else {
            return output(.indeterminate, diagnostics: requestStart.diagnostics)
        }
        guard !probe.ids.isEmpty else {
            let result: HomeTimelineGapReconciliationResult =
                probe.successCount == relays.count ? .verifiedComplete : .indeterminate
            return output(result, diagnostics: requestStart.diagnostics)
        }

        let events = await fetchMissingEvents(ids: probe.ids, relays: relays)
        let missingIDSet = Set(probe.ids)
        let recoveredEvents = Array(
            Dictionary(uniqueKeysWithValues: events.compactMap { event -> (String, NostrEvent)? in
                guard missingIDSet.contains(event.id),
                      [1, 6].contains(event.kind),
                      authors.contains(event.pubkey),
                      event.createdAt > olderEvent.createdAt,
                      event.createdAt < newerEvent.createdAt
                else { return nil }
                return (event.id, event)
            }).values
        ).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
        let result: HomeTimelineGapReconciliationResult = recoveredEvents.isEmpty
            ? .indeterminate
            : .recovered(recoveredEvents)
        return output(result, diagnostics: requestStart.diagnostics)
    }

    private func probeMissingEventIDs(
        relays: [String],
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        requestIDs: [String: String]
    ) async -> (ids: [String], successCount: Int, results: [GapRelayProbeResult]) {
        let relayClient = relayClient
        return await withTaskGroup(of: GapRelayProbeResult.self) { group in
            for relay in relays {
                let requestID = requestIDs[relay]
                group.addTask {
                    do {
                        return .success(
                            requestID: requestID,
                            missingEventIDs: try await relayClient.fetchMissingEventIDs(
                                relayURL: relay,
                                filter: filter,
                                localEvents: localEvents,
                                subscriptionID: "astrenza-neg-gap"
                            )
                        )
                    } catch {
                        return .failure(
                            requestID: requestID,
                            outcome: Self.verificationFailureOutcome(error)
                        )
                    }
                }
            }

            var ids = Set<String>()
            var successCount = 0
            var results: [GapRelayProbeResult] = []
            for await result in group {
                results.append(result)
                guard case .success(_, let relayIDs) = result else { continue }
                successCount += 1
                ids.formUnion(relayIDs)
            }
            return (Array(ids).sorted(), successCount, results)
        }
    }

    private func fetchMissingEvents(ids: [String], relays: [String]) async -> [NostrEvent] {
        let request = NostrRelayRequest(
            subscriptionID: "astrenza-gap-events",
            filters: [["ids": .strings(Array(ids.prefix(250)))]]
        )
        let relayClient = relayClient
        return await withTaskGroup(of: [NostrEvent].self) { group in
            for relay in relays {
                group.addTask {
                    (try? await relayClient.fetch(relayURL: relay, request: request)) ?? []
                }
            }

            var fetched: [NostrEvent] = []
            for await events in group {
                fetched.append(contentsOf: events)
            }
            return fetched
        }
    }

    private func beginVerificationRequests(
        relays: [String],
        filter: NostrRelayFilter,
        requestedAt: Int,
        context: HomeFeedRuntimeContext
    ) -> (requestIDs: [String: String], diagnostics: [HomeTimelineGapDiagnostic]) {
        guard let eventStore else { return ([:], []) }
        var filterObject: [String: AnySendableJSON] = [:]
        if let kinds = filter.kinds { filterObject["kinds"] = .ints(kinds) }
        if let authors = filter.authors { filterObject["authors"] = .strings(authors) }
        if let since = filter.since { filterObject["since"] = .int(since) }
        if let until = filter.until { filterObject["until"] = .int(until) }

        var requestIDs: [String: String] = [:]
        var diagnostics: [HomeTimelineGapDiagnostic] = []
        for relayURL in relays {
            let requestID = UUID().uuidString
            do {
                let syncFilter = try NostrFeedSyncFilterRecord(
                    requestID: requestID,
                    filterIndex: 0,
                    filter: filterObject
                )
                try eventStore.beginFeedSyncRequest(
                    NostrFeedSyncRequestRecord(
                        requestID: requestID,
                        feedID: context.feedID,
                        feedRevision: context.revision,
                        feedSpecificationHash: context.specificationHash,
                        relayURL: relayURL,
                        subscriptionID: "astrenza-neg-gap",
                        syncProtocol: .nip77,
                        direction: .verification,
                        purpose: .gap,
                        requestedAt: requestedAt
                    ),
                    filters: [syncFilter]
                )
                try eventStore.markFeedSyncRequestInstalled(requestID: requestID, at: requestedAt)
                requestIDs[relayURL] = requestID
            } catch {
                diagnostics.append(HomeTimelineGapDiagnostic(
                    relayURL: relayURL,
                    message: "gap verification save failed: \(error.localizedDescription)"
                ))
            }
        }
        return (requestIDs, diagnostics)
    }

    private func persistVerificationResults(_ results: [GapRelayProbeResult]) {
        let completedAt = Int(Date().timeIntervalSince1970)
        for result in results {
            switch result {
            case .success(let requestID, let missingEventIDs):
                guard let requestID else { continue }
                let outcome: NostrFeedVerificationOutcome = missingEventIDs.isEmpty
                    ? .noRemoteMissing
                    : .differencesFound
                try? eventStore?.completeFeedSyncVerification(
                    requestID: requestID,
                    outcome: outcome,
                    differenceCount: missingEventIDs.count,
                    at: completedAt
                )
            case .failure(let requestID, let outcome):
                guard let requestID else { continue }
                try? eventStore?.completeFeedSyncVerification(
                    requestID: requestID,
                    outcome: outcome,
                    differenceCount: nil,
                    at: completedAt
                )
            }
        }
    }

    private func localGapWindowEvents(
        authors: [String],
        newerEvent: NostrEvent,
        olderEvent: NostrEvent,
        inMemoryEvents: [NostrEvent]
    ) -> [NostrEvent] {
        let liveEvents = inMemoryEvents.filter { event in
            [1, 6].contains(event.kind) &&
                authors.contains(event.pubkey) &&
                event.createdAt > olderEvent.createdAt &&
                event.createdAt < newerEvent.createdAt
        }
        guard let eventStore else { return liveEvents }

        let storedKind1 = ((try? eventStore.events(
            kind: 1,
            authors: authors,
            until: newerEvent.createdAt - 1,
            limit: 500
        )) ?? []).filter { $0.createdAt > olderEvent.createdAt }
        let storedKind6 = ((try? eventStore.events(
            kind: 6,
            authors: authors,
            until: newerEvent.createdAt - 1,
            limit: 500
        )) ?? []).filter { $0.createdAt > olderEvent.createdAt }
        return Array(
            Dictionary(
                uniqueKeysWithValues: (liveEvents + storedKind1 + storedKind6).map { ($0.id, $0) }
            ).values
        )
    }

    private func output(
        _ result: HomeTimelineGapReconciliationResult,
        diagnostics: [HomeTimelineGapDiagnostic] = []
    ) -> HomeTimelineGapReconciliationOutput {
        HomeTimelineGapReconciliationOutput(result: result, diagnostics: diagnostics)
    }

    nonisolated private static func verificationFailureOutcome(
        _ error: any Error
    ) -> NostrFeedVerificationOutcome {
        guard let relayError = error as? NostrRelayClientError,
              case .negentropyRelayError(let reason) = relayError
        else {
            return .failed
        }
        let normalizedReason = reason.lowercased()
        return normalizedReason.contains("unsupported") ||
            normalizedReason.contains("not supported") ||
            normalizedReason.contains("unknown command")
            ? .unsupported
            : .failed
    }
}

private enum GapRelayProbeResult: Sendable {
    case success(requestID: String?, missingEventIDs: [String])
    case failure(requestID: String?, outcome: NostrFeedVerificationOutcome)
}
