import Foundation
import NostrProtocol

public struct NostrOutboxRelayRouting: Sendable {
    public init() {}

    public func relayURLsByAuthor(
        authors: [String],
        relayListEvents: [NostrEvent],
        contactItems: [NostrContactListItem] = [],
        observedRelayURLsByAuthor: [String: [String]] = [:],
        fallbackRelayURLs: [String]
    ) -> [String: [String]] {
        let latestRelayListByAuthor = latestRelayListEvents(
            relayListEvents
        )
        let hintsByAuthor = Dictionary(
            contactItems.map { ($0.pubkey.lowercased(), $0.relayHints) },
            uniquingKeysWith: { current, replacement in
                deduplicated(current + replacement)
            }
        )
        let fallback = deduplicated(fallbackRelayURLs)

        return Dictionary(uniqueKeysWithValues: authors.map { author in
            let key = author.lowercased()
            let observedRelays = observedRelayURLsByAuthor[key] ?? []
            let writeRelays = NostrRelayList.parse(
                from: latestRelayListByAuthor[key]
            ).writeRelays
            let hints = hintsByAuthor[key] ?? []
            let relayURLs = deduplicated(
                observedRelays + writeRelays + hints + fallback
            )
            return (key, relayURLs)
        })
    }

    public func authorsByRelay(
        relayURLsByAuthor: [String: [String]]
    ) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for author in relayURLsByAuthor.keys.sorted() {
            for relayURL in relayURLsByAuthor[author] ?? [] {
                result[relayURL, default: []].append(author)
            }
        }
        return result
    }

    private func latestRelayListEvents(
        _ events: [NostrEvent]
    ) -> [String: NostrEvent] {
        var result: [String: NostrEvent] = [:]
        for event in events where event.kind == 10_002 {
            let key = event.pubkey.lowercased()
            guard let current = result[key] else {
                result[key] = event
                continue
            }
            if event.createdAt > current.createdAt ||
                (event.createdAt == current.createdAt && event.id < current.id) {
                result[key] = event
            }
        }
        return result
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
