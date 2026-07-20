import AstrenzaCore
import Foundation

actor NostrProfilePageResolver {
    private struct RelayResult: Sendable {
        let relayURL: String
        let events: [NostrEvent]
    }

    private let eventStore: NostrEventStore?
    private let relayClient: any NostrRelayFetching
    private let refreshIntervalSeconds: Int
    private let now: @Sendable () -> Int
    private var lastAttemptAtByPubkey: [String: Int] = [:]

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

    func resolve(
        pubkey: String,
        relayURLs: [String]
    ) async -> Bool {
        let normalizedPubkey = pubkey.lowercased()
        let attemptAt = now()
        if let lastAttemptAt = lastAttemptAtByPubkey[normalizedPubkey],
           attemptAt - lastAttemptAt < refreshIntervalSeconds {
            return false
        }
        lastAttemptAtByPubkey[normalizedPubkey] = attemptAt

        let relays = NostrRelayURL.normalizedStrings(relayURLs)
        guard !relays.isEmpty else { return false }
        let request = NostrRelayRequest(
            subscriptionID: "astrenza-profile-\(UUID().uuidString.prefix(8))",
            filters: [
                [
                    "authors": .strings([normalizedPubkey]),
                    "kinds": .ints([0, 3, 10_002]),
                    "limit": .int(3)
                ],
                [
                    "kinds": .ints([3]),
                    "#p": .strings([normalizedPubkey]),
                    "limit": .int(500)
                ]
            ]
        )
        let relayClient = relayClient
        let results = await withTaskGroup(of: RelayResult.self) { group in
            for relayURL in relays.prefix(6) {
                group.addTask {
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

        var eventsByID: [String: NostrEvent] = [:]
        var sources: [NostrEventSourceRecord] = []
        for result in results {
            for event in result.events where Self.isRelevant(
                event,
                profilePubkey: normalizedPubkey
            ) {
                eventsByID[event.id] = event
                sources.append(NostrEventSourceRecord(
                    eventID: event.id,
                    relayURL: result.relayURL,
                    firstSeenAt: attemptAt,
                    lastSeenAt: attemptAt
                ))
            }
        }
        guard !eventsByID.isEmpty, let eventStore else { return false }
        do {
            try eventStore.ingest(
                events: Array(eventsByID.values),
                eventSources: sources,
                feedMemberships: [],
                receivedAt: attemptAt
            )
            return true
        } catch {
            return false
        }
    }

    private static func isRelevant(
        _ event: NostrEvent,
        profilePubkey: String
    ) -> Bool {
        if event.pubkey == profilePubkey && [0, 3, 10_002].contains(event.kind) {
            return true
        }
        return event.kind == 3 && event.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == profilePubkey
        }
    }
}
