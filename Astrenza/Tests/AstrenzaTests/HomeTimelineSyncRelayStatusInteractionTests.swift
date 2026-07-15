import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline sync relay status interaction")
@MainActor
struct SyncRelayStatusInteractionTests {
    @Test("Relay history, snapshots, and diagnostics stay behind sync interaction")
    func routesRelayStatusStateAndRecording() {
        let fixture = SyncRelayStatusFixture()

        let events = fixture.workflow.relaySyncEvents
        let currentSnapshot = fixture.workflow.relayStatusSnapshot(
            resolvedRelays: [fixture.relayURL]
        )
        let transition = fixture.workflow.recordRelayStatus(fixture.record)

        #expect(events == [fixture.syncEvent])
        #expect(currentSnapshot == fixture.snapshot)
        #expect(transition == fixture.expectedTransition)
        #expect(fixture.relayStatus.interactions == [
            .readEvents,
            .snapshot(resolvedRelays: [fixture.relayURL]),
            .record(fixture.record)
        ])
    }
}
