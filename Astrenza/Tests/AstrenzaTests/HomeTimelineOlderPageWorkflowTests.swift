import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline older page workflow")
@MainActor
struct HomeTimelineOlderPageWorkflowTests {
    @Test("A stale lifecycle performs no activity or loading work")
    func staleLifecycleStopsBeforeActivity() async {
        let fixture = OlderPageFixture()
        fixture.lifecycle.cancel()

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events.isEmpty)
        #expect(!fixture.activity.snapshot.isLoadingOlder)
    }

    @Test("An existing older load rejects duplicate work")
    func activeOlderLoadRejectsDuplicate() async throws {
        let fixture = OlderPageFixture()
        _ = try #require(fixture.activity.beginLoadingOlder())

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events.isEmpty)
        #expect(fixture.activity.snapshot.isLoadingOlder)
    }

    @Test("A runtime request applies loaded activity in order")
    func runtimeSuccessPreservesActivityOrder() async {
        let fixture = OlderPageFixture()

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == fixture.runtimeSuccessEvents)
        #expect(fixture.activity.snapshot == fixture.loadedIdleActivity)
    }

    @Test("An unavailable runtime request still restores loaded phase")
    func unavailableRuntimePreservesLoadedBehavior() async {
        let fixture = OlderPageFixture(runtimeOutcome: .unavailable)

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == fixture.runtimeSuccessEvents)
        #expect(fixture.activity.snapshot == fixture.loadedIdleActivity)
    }

    @Test("A failed runtime request records its diagnostic before loaded phase")
    func failedRuntimeRecordsDiagnostic() async {
        let diagnostic = HomeTimelineBackwardRequestDiagnostic(
            relayURL: "wss://failed.example",
            subscriptionID: "astrenza-home-older",
            message: "older enqueue failed: disconnected"
        )
        let fixture = OlderPageFixture(runtimeOutcome: .failed(diagnostic))

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.runtimeRequestEvent,
            .command(.recordDiagnostic(diagnostic)),
            fixture.loadedActivityEvent,
            fixture.endLoadedActivityEvent
        ])
    }

    @Test("A superseded runtime request suppresses phase and completion activity")
    func supersededRuntimeSuppressesLateActivity() async {
        let fixture = OlderPageFixture()
        fixture.probe.beforeRuntimeReturn = {
            fixture.lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.runtimeRequestEvent
        ])
        #expect(fixture.activity.snapshot.isLoadingOlder)
    }

    @Test("A cancelled runtime task ends activity without publishing loaded phase")
    func cancelledRuntimeEndsActivity() async {
        let fixture = OlderPageFixture()

        await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            await fixture.run(hasRelayRuntime: true)
        }.value

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.runtimeRequestEvent,
            fixture.endIdleActivityEvent
        ])
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }

    @Test("Remote older load uses the prepared database backfill input")
    func remoteLoadPreservesApplicationOrder() async {
        let fixture = OlderPageFixture()

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == fixture.remoteSuccessEvents)
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }

    @Test("A superseded remote load still delegates its outcome and skips completion activity")
    func supersededRemoteDelegatesOutcome() async {
        let fixture = OlderPageFixture()
        fixture.probe.beforeRemoteReturn = {
            fixture.lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == Array(
            fixture.remoteSuccessEvents.dropLast()
        ))
        #expect(fixture.activity.snapshot.isLoadingOlder)
    }

    @Test("Missing remote input closes the activity without loading")
    func missingRemoteInputEndsActivity() async {
        let fixture = OlderPageFixture(hasRemoteInput: false)

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.prepareRemoteInputEvent,
            fixture.endIdleActivityEvent
        ])
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }
}
