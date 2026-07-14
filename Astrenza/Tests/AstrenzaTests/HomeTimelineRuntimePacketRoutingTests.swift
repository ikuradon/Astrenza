import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime packet routing")
struct RuntimePacketRoutingTests {
    @Test("Inactive lifecycle packets are ignored")
    @MainActor
    func ignoresInactivePackets() {
        let fixture = RuntimePacketFixture()

        let application = fixture.coordinator.handle(
            .stateChanged(relayURL: runtimePacketTestRelayURL, state: .connected),
            context: fixture.context(isActive: false)
        )

        #expect(application == .ignored)
        #expect(fixture.relayStatusCoordinator.snapshot(
            resolvedRelays: [runtimePacketTestRelayURL]
        ).runtimeStates.isEmpty)
    }

    @Test(
        "Profile directory packets are isolated from the home timeline",
        arguments: RuntimeProfilePacketCase.allCases
    )
    @MainActor
    func ignoresProfileDirectoryPackets(testCase: RuntimeProfilePacketCase) {
        let fixture = RuntimePacketFixture()

        let application = fixture.coordinator.handle(
            testCase.packet(),
            context: fixture.context()
        )

        #expect(application == .ignored)
        #expect(fixture.feedSyncCoordinator.activeRequestCount == 0)
        #expect(fixture.relayStatusCoordinator.events.isEmpty)
    }

    @Test("Relay state and traffic route through relay status ownership")
    @MainActor
    func routesRelayStateAndTraffic() throws {
        let fixture = RuntimePacketFixture()
        let context = fixture.context()
        let connected = fixture.coordinator.handle(
            .stateChanged(relayURL: runtimePacketTestRelayURL, state: .connected),
            context: context
        )
        let connectedTransition = try #require(connected.relayStatusTransition)

        let traffic = NostrRelayTrafficDelta(
            accountID: runtimePacketTestAccountID,
            relayURL: runtimePacketTestRelayURL,
            occurredAt: 201,
            networkType: .wifi,
            syncMode: .ownRelayList,
            receivedBytes: 10,
            sentBytes: 5,
            receivedMessages: 1,
            sentMessages: 1
        )
        let trafficApplication = fixture.coordinator.handle(
            .traffic(traffic),
            context: context
        )

        #expect(connectedTransition.snapshot.runtimeStates == [
            runtimePacketTestRelayURL: .connected
        ])
        #expect(connectedTransition.snapshot.connectedRelayCount == 1)
        #expect(trafficApplication.wasHandled)
        #expect(fixture.diagnostics.pendingRelayTrafficDeltaCount == 1)
    }

    @Test("NOTICE and AUTH classification remains in relay status ownership")
    @MainActor
    func routesNoticeAndAuthentication() {
        let fixture = RuntimePacketFixture()
        let context = fixture.context()
        let notice = fixture.coordinator.handle(
            .notice(relayURL: runtimePacketTestRelayURL, message: "idle timeout"),
            context: context
        )
        let authentication = fixture.coordinator.handle(
            .auth(relayURL: runtimePacketTestRelayURL, challenge: "challenge"),
            context: context
        )
        let duplicate = fixture.coordinator.handle(
            .auth(relayURL: runtimePacketTestRelayURL, challenge: "challenge"),
            context: context
        )

        #expect(notice.relayStatusTransition != nil)
        #expect(authentication.relayStatusTransition != nil)
        #expect(duplicate.relayStatusTransition == nil)
        #expect(fixture.relayStatusCoordinator.events.map(\.kind) == [
            .timeout,
            .authRequired
        ])
    }

    @Test("EVENT and backward completion remain explicit Store actions")
    @MainActor
    func returnsDeferredStoreActions() {
        let fixture = RuntimePacketFixture()
        let subscriptionID = "astrenza-home-forward-action"
        let runtimeEvent = runtimePacketEvent(idSeed: "3", createdAt: 100)
        let completion = NostrBackwardREQCompletion(
            groupID: "older-action",
            relayURLs: [runtimePacketTestRelayURL],
            subscriptionIDs: [subscriptionID],
            eventCount: 1,
            eoseCount: 1,
            closedCount: 0,
            timeoutCount: 0
        )
        let eventApplication = fixture.coordinator.handle(
            .event(
                relayURL: runtimePacketTestRelayURL,
                subscriptionID: subscriptionID,
                event: runtimeEvent
            ),
            context: fixture.context()
        )
        let completionApplication = fixture.coordinator.handle(
            .backwardCompleted(completion),
            context: fixture.context()
        )

        #expect(eventApplication.action == .event(
            relayURL: runtimePacketTestRelayURL,
            subscriptionID: subscriptionID,
            event: runtimeEvent
        ))
        #expect(completionApplication.action == .backwardCompleted(completion))
        #expect(eventApplication.realtimeState == nil)
        #expect(completionApplication.relayStatusTransition == nil)
    }
}
