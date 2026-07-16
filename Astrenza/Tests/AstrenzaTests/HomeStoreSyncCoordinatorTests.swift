import Testing
@testable import Astrenza

@Suite("Home Store sync coordinator")
@MainActor
struct HomeStoreSyncCoordinatorTests {
    @Test("contextを伴うsync操作は実行ごとに最新contextへ委譲する")
    func routesContextBoundOperations() {
        let fixture = StoreSyncCoordinatorFixture()
        let expectedKeys = Set([fixture.firstKey, fixture.secondKey])

        fixture.coordinator.prepareForwardSubscriptions(expectedKeys)
        fixture.coordinator.invalidateForwardSubscription(fixture.firstKey)
        fixture.coordinator.invalidateForwardSubscriptions(
            relayURL: fixture.secondKey.relayURL
        )

        #expect(fixture.interaction.calls == [
            .prepare(expectedKeys),
            .invalidate(fixture.firstKey),
            .invalidateRelay(fixture.secondKey.relayURL)
        ])
        #expect(fixture.contexts.contextIDs == [1, 2, 3])
        #expect(fixture.contexts.applications == [
            StoreSyncContextProviderSpy.Application(
                contextID: 1,
                action: .setRealtime(false)
            ),
            StoreSyncContextProviderSpy.Application(
                contextID: 2,
                action: .setRealtime(true)
            ),
            StoreSyncContextProviderSpy.Application(
                contextID: 3,
                action: .setRealtime(false)
            )
        ])
    }

    @Test("request registrationとmetricsはsync境界内に留める")
    func routesRegistrationAndMetrics() {
        let fixture = StoreSyncCoordinatorFixture()

        fixture.coordinator.setRealtimeForTesting(true)
        fixture.coordinator.registerOlderFeedRequest(
            packet: fixture.packet,
            definition: fixture.definition,
            anchorEventID: "anchor"
        )
        fixture.coordinator.registerForwardFeedRequest(
            packet: fixture.packet,
            definition: fixture.definition
        )
        fixture.coordinator.registerGapFeedRequest(
            packet: fixture.packet,
            definition: fixture.definition,
            newerEventID: "newer",
            olderEventID: "older",
            direction: .older
        )

        #expect(fixture.contexts.contextIDs == [1])
        #expect(fixture.contexts.applications == [
            StoreSyncContextProviderSpy.Application(
                contextID: 1,
                action: .setRealtime(true)
            )
        ])
        #expect(fixture.interaction.calls == [
            .registerOlder(
                groupID: fixture.packet.groupID,
                context: fixture.feedContext,
                anchorEventID: "anchor"
            ),
            .registerForward(
                fixture.feedContext,
                groupID: fixture.packet.groupID
            ),
            .registerGap(
                groupID: fixture.packet.groupID,
                context: fixture.feedContext,
                newerEventID: "newer",
                olderEventID: "older",
                direction: .older
            )
        ])
        #expect(fixture.coordinator.backwardRequestCount == 2)
        #expect(fixture.coordinator.activeRequestCount == 4)
        #expect(fixture.coordinator.activeContextCount == 3)
    }
}
