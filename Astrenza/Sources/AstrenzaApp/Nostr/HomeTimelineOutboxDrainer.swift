import AstrenzaCore
import Foundation

struct HomeTimelineOutboxDrainResult: Sendable {
    let nextRetryAt: Int?
    let didRecordRelayResults: Bool
}

actor HomeTimelineOutboxDrainer: HomeTimelineOutboxDraining {
    private let eventStore: NostrEventStore?
    private let publisher: NostrOutboxRelayPublisher

    init(eventStore: NostrEventStore?, publisher: NostrOutboxRelayPublisher) {
        self.eventStore = eventStore
        self.publisher = publisher
    }

    func drain(accountID: String, now: Int = Int(Date().timeIntervalSince1970)) async
        -> HomeTimelineOutboxDrainResult
    {
        guard let eventStore else {
            return HomeTimelineOutboxDrainResult(
                nextRetryAt: nil,
                didRecordRelayResults: false
            )
        }
        let candidates = ((try? eventStore.outboxEvents(accountID: accountID, limit: 500)) ?? [])
            .filter { record in
                let isRetryReady = record.nextRetryAt.map { $0 <= now } ?? true
                return !Self.isTerminal(record.status) && isRetryReady
            }
        var didRecordRelayResults = false

        for record in candidates {
            guard !Task.isCancelled else {
                return HomeTimelineOutboxDrainResult(
                    nextRetryAt: nil,
                    didRecordRelayResults: didRecordRelayResults
                )
            }
            let relayRecords = (try? eventStore.outboxRelays(localID: record.localID)) ?? []
            let relayURLs = relayRecords
                .filter { !Self.isTerminal($0.status) }
                .map(\.relayURL)
            guard !relayURLs.isEmpty else { continue }

            let results = await publisher.publish(event: record.event, relayURLs: relayURLs)
            guard !Task.isCancelled else {
                return HomeTimelineOutboxDrainResult(
                    nextRetryAt: nil,
                    didRecordRelayResults: didRecordRelayResults
                )
            }
            for result in results {
                let accepted = result.accepted || Self.isDuplicateAcknowledgment(result.message)
                try? eventStore.recordOutboxRelayResult(
                    localID: record.localID,
                    relayURL: result.relayURL,
                    accepted: accepted,
                    message: result.message,
                    retryable: accepted || !Self.isTerminalRejection(result.message)
                )
                didRecordRelayResults = true
            }
        }

        let nextRetryAt = ((try? eventStore.outboxEvents(accountID: accountID, limit: 500)) ?? [])
            .filter { !Self.isTerminal($0.status) }
            .compactMap(\.nextRetryAt)
            .min()
        return HomeTimelineOutboxDrainResult(
            nextRetryAt: nextRetryAt,
            didRecordRelayResults: didRecordRelayResults
        )
    }

    static func isDuplicateAcknowledgment(_ message: String?) -> Bool {
        message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("duplicate:") == true
    }

    static func isTerminalRejection(_ message: String?) -> Bool {
        guard let prefix = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init)
        else { return false }
        return [
            "auth-required",
            "blocked",
            "invalid",
            "payment-required",
            "pow",
            "restricted"
        ].contains(prefix)
    }

    private static func isTerminal(_ status: String) -> Bool {
        status == NostrOutboxStatus.published || status == NostrOutboxStatus.rejected
    }
}
