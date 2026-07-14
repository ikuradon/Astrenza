import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime packet sync")
struct RuntimePacketSyncTests {
    @Test("Request start, installation, and end retain persisted provenance")
    @MainActor
    func routesRequestLifecycle() throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = RuntimePacketFixture(eventStore: eventStore)
        let request = try fixture.prepareForwardRequest(suffix: "lifecycle")
        let context = fixture.context()

        let started = fixture.coordinator.handle(
            .requestStarted(request.attempt),
            context: context
        )
        #expect(started.realtimeState == false)
        #expect(fixture.feedSyncCoordinator.activeRequestCount == 1)

        let installed = fixture.coordinator.handle(
            .requestInstalled(
                requestID: request.attempt.requestID,
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: request.packet.subscriptionID,
                installedAt: 11
            ),
            context: context
        )
        #expect(installed.wasHandled)

        let ended = fixture.coordinator.handle(
            .requestEnded(requestEnd(for: request)),
            context: context
        )
        #expect(ended.realtimeState == false)
        #expect(fixture.feedSyncCoordinator.activeRequestCount == 0)

        let record = try #require(
            try eventStore.feedSyncRequests(feedID: request.definition.feedID).first
        )
        #expect(record.requestID == request.attempt.requestID)
        #expect(record.installedAt == 11)
        #expect(record.endReason == .installFailed)
        #expect(record.endMessage == "install failed")
        #expect(record.endedAt == 12)
    }

    @Test("Request persistence failures become relay diagnostics")
    @MainActor
    func recordsRequestStartPersistenceFailure() throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = RuntimePacketFixture(eventStore: eventStore)
        let request = try fixture.prepareForwardRequest(
            suffix: "missing-definition",
            savesDefinition: false
        )

        let application = fixture.coordinator.handle(
            .requestStarted(request.attempt),
            context: fixture.context()
        )

        #expect(application.realtimeState == false)
        #expect(application.relayStatusTransition != nil)
        #expect(fixture.feedSyncCoordinator.activeRequestCount == 0)
        let diagnostic = try #require(fixture.relayStatusCoordinator.events.last)
        #expect(diagnostic.kind == .partialFailure)
        #expect(diagnostic.subscriptionID == request.packet.subscriptionID)
        #expect(diagnostic.message?.hasPrefix("feed sync request save failed:") == true)
    }

    @Test(
        "EOSE, CLOSED, and timeout apply feed state before recording diagnostics",
        arguments: RuntimeStreamCompletionCase.allCases
    )
    @MainActor
    func routesStreamCompletion(testCase: RuntimeStreamCompletionCase) throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = RuntimePacketFixture(eventStore: eventStore)
        let request = try fixture.prepareForwardRequest(suffix: testCase.testDescription)
        let context = fixture.context()
        _ = fixture.coordinator.handle(
            .requestStarted(request.attempt),
            context: context
        )
        fixture.feedSyncCoordinator.record(
            runtimePacketEvent(idSeed: "2", createdAt: 100),
            relayURL: runtimePacketTestRelayURL,
            subscriptionID: request.packet.subscriptionID
        )

        let application = fixture.coordinator.handle(
            testCase.packet(subscriptionID: request.packet.subscriptionID),
            context: context
        )

        #expect(application.wasHandled)
        #expect(application.realtimeState == testCase.isRealtime)
        #expect(application.relayStatusTransition != nil)
        #expect(application.action == nil)
        let diagnostic = try #require(fixture.relayStatusCoordinator.events.last)
        #expect(diagnostic.kind == testCase.diagnosticKind)
        #expect(diagnostic.eventCount == 1)
        #expect(diagnostic.newestCreatedAt == 100)
        #expect(diagnostic.oldestCreatedAt == 100)
        #expect(diagnostic.message == testCase.message)
    }

    private func requestEnd(
        for request: RuntimePacketPreparedRequest
    ) -> NostrRelayRequestAttemptEnd {
        NostrRelayRequestAttemptEnd(
            requestID: request.attempt.requestID,
            relayURL: runtimePacketTestRelayURL,
            subscriptionID: request.packet.subscriptionID,
            reason: .installFailed,
            message: "install failed",
            endedAt: 12
        )
    }
}
