import Foundation
import NostrProtocol
import NostrRelay

/// relay/filterごとにEOSEまで到達したcursorだけを保持し、再接続REQを安全に狭めます。
/// EOSE前の部分受信は確定しないため、途中切断でも未受信eventを飛ばしません。
struct NostrForwardReconnectTracker: Sendable {
    private struct Key: Hashable, Sendable {
        let relayURL: String
        let subscriptionID: String
    }

    private struct State: Sendable {
        var committedNewestCreatedAtByFilterIndex: [Int: Int] = [:]
        var pendingNewestCreatedAtByFilterIndex: [Int: Int] = [:]
        var reachedEOSE = false
    }

    private var states: [Key: State] = [:]

    mutating func record(
        event: NostrEvent,
        relayURL: String,
        packet: NostrREQPacket
    ) {
        let key = Key(relayURL: relayURL, subscriptionID: packet.subscriptionID)
        var state = states[key] ?? State()
        for index in packet.filters.indices
        where NostrRelayFilterMatcher.matches(event: event, filter: packet.filters[index]) {
            if state.reachedEOSE {
                state.committedNewestCreatedAtByFilterIndex[index] = max(
                    state.committedNewestCreatedAtByFilterIndex[index] ?? 0,
                    event.createdAt
                )
            } else {
                state.pendingNewestCreatedAtByFilterIndex[index] = max(
                    state.pendingNewestCreatedAtByFilterIndex[index] ?? 0,
                    event.createdAt
                )
            }
        }
        states[key] = state
    }

    mutating func reachedEOSE(relayURL: String, subscriptionID: String) {
        let key = Key(relayURL: relayURL, subscriptionID: subscriptionID)
        var state = states[key] ?? State()
        for (index, newestCreatedAt) in state.pendingNewestCreatedAtByFilterIndex {
            state.committedNewestCreatedAtByFilterIndex[index] = max(
                state.committedNewestCreatedAtByFilterIndex[index] ?? 0,
                newestCreatedAt
            )
        }
        state.pendingNewestCreatedAtByFilterIndex.removeAll(keepingCapacity: true)
        state.reachedEOSE = true
        states[key] = state
    }

    mutating func prepareReconnectPackets(
        relayURL: String,
        packets: [NostrREQPacket],
        overlapSeconds: Int
    ) -> [String: NostrREQPacket] {
        var replacements: [String: NostrREQPacket] = [:]
        for packet in packets {
            let key = Key(relayURL: relayURL, subscriptionID: packet.subscriptionID)
            var state = states[key] ?? State()
            let filters = packet.filters.enumerated().map { index, filter in
                guard let newestCreatedAt =
                        state.committedNewestCreatedAtByFilterIndex[index]
                else { return filter }
                var filter = filter
                let reconnectSince = max(0, newestCreatedAt - max(0, overlapSeconds))
                filter["since"] = .int(max(filter["since"]?.intValue ?? 0, reconnectSince))
                filter.removeValue(forKey: "limit")
                return filter
            }
            replacements[packet.subscriptionID] = packet.replacing(filters: filters)
            state.pendingNewestCreatedAtByFilterIndex.removeAll(keepingCapacity: true)
            state.reachedEOSE = false
            states[key] = state
        }
        return replacements
    }

    mutating func reset(subscriptionIDs: Set<String>) {
        guard !subscriptionIDs.isEmpty else { return }
        states = states.filter { !subscriptionIDs.contains($0.key.subscriptionID) }
    }

    mutating func removeRelay(_ relayURL: String) {
        states = states.filter { $0.key.relayURL != relayURL }
    }

    mutating func removeAll() {
        states.removeAll(keepingCapacity: false)
    }
}
