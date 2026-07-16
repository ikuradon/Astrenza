import Foundation

enum NostrRelayDemand: Hashable, Sendable {
    case persistentDefault
    case backwardInstallation(UUID)
    case backwardSubscription(subscriptionID: String, generation: UInt64)
    case publish(eventID: String)
    case bootstrap(UUID)
}

struct NostrRelayDemandRegistry: Sendable {
    private var demandsByRelayURL: [NostrRelayURL: Set<NostrRelayDemand>] = [:]

    mutating func acquire(_ demand: NostrRelayDemand, for relayURLs: [NostrRelayURL]) {
        for relayURL in relayURLs {
            demandsByRelayURL[relayURL, default: []].insert(demand)
        }
    }

    mutating func release(_ demand: NostrRelayDemand, from relayURLs: [NostrRelayURL]) {
        for relayURL in relayURLs {
            demandsByRelayURL[relayURL]?.remove(demand)
            if demandsByRelayURL[relayURL]?.isEmpty == true {
                demandsByRelayURL[relayURL] = nil
            }
        }
    }

    func hasDemand(for relayURL: NostrRelayURL) -> Bool {
        demandsByRelayURL[relayURL]?.isEmpty == false
    }

    func contains(_ demand: NostrRelayDemand, for relayURL: NostrRelayURL) -> Bool {
        demandsByRelayURL[relayURL]?.contains(demand) == true
    }

    func demands(for relayURL: NostrRelayURL) -> Set<NostrRelayDemand> {
        demandsByRelayURL[relayURL] ?? []
    }

    mutating func removeAll() {
        demandsByRelayURL.removeAll(keepingCapacity: false)
    }
}
