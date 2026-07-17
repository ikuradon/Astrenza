import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline outbox drainer")
struct HomeTimelineOutboxDrainerTests {
    @Test("Duplicate relay acknowledgements count as accepted delivery")
    func duplicateAcknowledgement() {
        #expect(HomeTimelineOutboxDrainer.isDuplicateAcknowledgment(" Duplicate: already saved "))
        #expect(!HomeTimelineOutboxDrainer.isDuplicateAcknowledgment("blocked: denied"))
        #expect(!HomeTimelineOutboxDrainer.isDuplicateAcknowledgment(nil))
    }

    @Test("Permanent relay rejection prefixes stop retries")
    func terminalRejections() {
        for message in [
            "auth-required: challenge",
            "blocked: denied",
            "invalid: event",
            "payment-required: invoice",
            "pow: insufficient",
            "restricted: policy"
        ] {
            #expect(HomeTimelineOutboxDrainer.isTerminalRejection(message))
        }
        #expect(!HomeTimelineOutboxDrainer.isTerminalRejection("rate-limited: retry later"))
        #expect(!HomeTimelineOutboxDrainer.isTerminalRejection(nil))
    }

    @Test("A storage read failure schedules another drain")
    func storageReadFailureRetries() async {
        let drainer = HomeTimelineOutboxDrainer(
            eventStore: OutboxStoreStub(failsEventReads: true),
            publisher: OutboxPublisherStub(results: []),
            storageFailureRetrySeconds: 7
        )

        let result = await drainer.drain(accountID: "account", now: 100)

        #expect(result.nextRetryAt == 107)
        #expect(!result.didRecordRelayResults)
    }

    @Test("An acknowledgement persistence failure remains retryable")
    func acknowledgementPersistenceFailureRetries() async {
        let event = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: String(repeating: "2", count: 64),
            createdAt: 90,
            kind: 1,
            tags: [],
            content: "outbox",
            sig: String(repeating: "0", count: 128)
        )
        let relayURL = "wss://relay.example"
        let store = OutboxStoreStub(
            events: [NostrOutboxEventRecord(
                localID: "local",
                accountID: "account",
                eventID: event.id,
                event: event,
                status: NostrOutboxStatus.pending,
                createdAt: 90,
                nextRetryAt: nil,
                lastError: nil
            )],
            relays: [NostrOutboxRelayRecord(
                localID: "local",
                relayURL: relayURL,
                status: NostrOutboxStatus.pending,
                lastAttemptAt: nil,
                okMessage: nil
            )],
            failsResultWrites: true
        )
        let drainer = HomeTimelineOutboxDrainer(
            eventStore: store,
            publisher: OutboxPublisherStub(results: [
                NostrOutboxRelayPublishResult(
                    relayURL: relayURL,
                    accepted: true,
                    message: "saved"
                )
            ]),
            storageFailureRetrySeconds: 5
        )

        let result = await drainer.drain(accountID: "account", now: 100)

        #expect(result.nextRetryAt == 105)
        #expect(!result.didRecordRelayResults)
    }

    @Test("A pending event without relay destinations remains retryable")
    func missingRelayDestinationsRetry() async {
        let event = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: String(repeating: "2", count: 64),
            createdAt: 90,
            kind: 1,
            tags: [],
            content: "outbox",
            sig: String(repeating: "0", count: 128)
        )
        let store = OutboxStoreStub(events: [NostrOutboxEventRecord(
            localID: "local",
            accountID: "account",
            eventID: event.id,
            event: event,
            status: NostrOutboxStatus.pending,
            createdAt: 90,
            nextRetryAt: nil,
            lastError: nil
        )])
        let drainer = HomeTimelineOutboxDrainer(
            eventStore: store,
            publisher: OutboxPublisherStub(results: []),
            storageFailureRetrySeconds: 5
        )

        let result = await drainer.drain(accountID: "account", now: 100)

        #expect(result.nextRetryAt == 105)
        #expect(!result.didRecordRelayResults)
    }
}

private struct OutboxStoreStub: HomeTimelineOutboxStoring {
    var events: [NostrOutboxEventRecord] = []
    var relays: [NostrOutboxRelayRecord] = []
    var failsEventReads = false
    var failsResultWrites = false

    func outboxEvents(
        accountID _: String,
        limit _: Int
    ) throws -> [NostrOutboxEventRecord] {
        if failsEventReads {
            throw OutboxStoreStubError.failed
        }
        return events
    }

    func outboxRelays(localID _: String) throws -> [NostrOutboxRelayRecord] {
        relays
    }

    func recordOutboxRelayResult(
        localID _: String,
        relayURL _: String,
        accepted _: Bool,
        message _: String?,
        retryable _: Bool,
        attemptedAt _: Int
    ) throws {
        if failsResultWrites {
            throw OutboxStoreStubError.failed
        }
    }
}

private struct OutboxPublisherStub: HomeTimelineOutboxPublishing {
    let results: [NostrOutboxRelayPublishResult]

    func publish(
        event _: NostrEvent,
        relayURLs _: [String]
    ) async -> [NostrOutboxRelayPublishResult] {
        results
    }
}

private enum OutboxStoreStubError: Error {
    case failed
}
