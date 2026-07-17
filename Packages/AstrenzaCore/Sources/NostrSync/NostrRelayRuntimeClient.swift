import Foundation
import NostrProtocol
import NostrRelay

package protocol NostrRelayBootstrapScoping: Sendable {
    func beginBootstrapScope() async -> UUID
    func finishBootstrapScope(
        _ scopeID: UUID,
        retainUntilDefaultRelayHandoff: Bool
    ) async
}

/// NIP-01 fetchesを`NostrRelayRuntime`の共有sessionへ流すadapterです。
///
/// NIP-77はruntimeへ未統合のため、negentropy fetchだけはfallback clientへ委譲します。
public actor NostrRelayRuntimeClient: NostrRelayFetching, NostrRelayBootstrapScoping {
    private let runtime: NostrRelayRuntime
    private let fallback: any NostrRelayFetching
    private var relayURLsByBootstrapScopeID: [UUID: Set<String>] = [:]

    public init(
        runtime: NostrRelayRuntime,
        fallback: any NostrRelayFetching = NostrRelayClient()
    ) {
        self.runtime = runtime
        self.fallback = fallback
    }

    public func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        guard let identity = NostrRelayURL(relayURL) else {
            throw NostrRelayClientError.invalidRelayURL(relayURL)
        }

        let scopeIDs = Array(relayURLsByBootstrapScopeID.keys)
        for scopeID in scopeIDs {
            relayURLsByBootstrapScopeID[scopeID, default: []].insert(identity.rawValue)
        }
        for scopeID in scopeIDs {
            try await runtime.retainBootstrapRelay(identity.rawValue, scopeID: scopeID)
            if relayURLsByBootstrapScopeID[scopeID] == nil {
                await runtime.finishBootstrapScope(
                    scopeID,
                    retainUntilDefaultRelayHandoff: false
                )
            }
        }

        return try await runtime.fetch(
            relayURL: identity.rawValue,
            request: request
        )
    }

    public func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        try await fallback.fetchMissingEventIDs(
            relayURL: relayURL,
            filter: filter,
            localEvents: localEvents,
            subscriptionID: subscriptionID
        )
    }

    package func beginBootstrapScope() -> UUID {
        let scopeID = UUID()
        relayURLsByBootstrapScopeID[scopeID] = []
        return scopeID
    }

    package func finishBootstrapScope(
        _ scopeID: UUID,
        retainUntilDefaultRelayHandoff: Bool
    ) async {
        guard relayURLsByBootstrapScopeID.removeValue(forKey: scopeID) != nil else { return }
        await runtime.finishBootstrapScope(
            scopeID,
            retainUntilDefaultRelayHandoff: retainUntilDefaultRelayHandoff
        )
    }
}
