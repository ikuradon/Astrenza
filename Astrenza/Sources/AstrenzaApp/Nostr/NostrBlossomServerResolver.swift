import AstrenzaCore
import Foundation

actor NostrBlossomServerResolver {
    private let eventStore: NostrEventStore?
    private let relayClient: any NostrRelayFetching

    init(
        eventStore: NostrEventStore?,
        relayClient: any NostrRelayFetching
    ) {
        self.eventStore = eventStore
        self.relayClient = relayClient
    }

    func resolve(
        accountID: String,
        relayURLs: [String]
    ) async -> [URL] {
        if let cached = cachedServers(accountID: accountID), !cached.isEmpty {
            return cached
        }

        let request = NostrRelayRequest(
            subscriptionID: "astrenza-blossom-\(UUID().uuidString.prefix(8))",
            filters: [[
                "authors": .strings([accountID]),
                "kinds": .ints([10_063]),
                "limit": .int(1)
            ]]
        )
        let relayClient = relayClient
        let events = await withTaskGroup(of: (String, NostrEvent?).self) { group in
            for relayURL in Array(relayURLs.prefix(6)) {
                group.addTask {
                    let events = try? await relayClient.fetch(
                        relayURL: relayURL,
                        request: request
                    )
                    let event = events?
                        .filter { $0.kind == 10_063 && $0.pubkey == accountID }
                        .max(by: { $0.createdAt < $1.createdAt })
                    return (relayURL, event)
                }
            }
            var values: [(String, NostrEvent)] = []
            for await (relayURL, event) in group {
                if let event { values.append((relayURL, event)) }
            }
            return values
        }
        guard let freshest = events.max(by: {
            $0.1.createdAt < $1.1.createdAt
        })?.1 else { return [] }

        try? eventStore?.ingest(
            events: [freshest],
            eventSources: events.filter { $0.1.id == freshest.id }.map {
                NostrEventSourceRecord(
                    eventID: freshest.id,
                    relayURL: $0.0,
                    firstSeenAt: Int(Date().timeIntervalSince1970),
                    lastSeenAt: Int(Date().timeIntervalSince1970)
                )
            },
            feedMemberships: [],
            receivedAt: Int(Date().timeIntervalSince1970)
        )
        return Self.serverURLs(from: freshest)
    }

    private func cachedServers(accountID: String) -> [URL]? {
        guard let event = try? eventStore?.latestReplaceableEvent(
            pubkey: accountID,
            kind: 10_063
        ) else { return nil }
        return Self.serverURLs(from: event)
    }

    private static func serverURLs(from event: NostrEvent?) -> [URL] {
        guard let event else { return [] }
        var seen = Set<String>()
        return event.tags.compactMap { tag -> URL? in
            guard tag.count >= 2,
                  tag[0] == "server",
                  let url = URL(string: tag[1]),
                  url.scheme == "https" || url.scheme == "http",
                  seen.insert(url.absoluteString).inserted
            else { return nil }
            return url
        }
    }
}
