import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline refresh workflow")
@MainActor
struct HomeTimelineRefreshWorkflowTests {
    @Test("A stale lifecycle performs no refresh work")
    func staleLifecycleStopsBeforeRefresh() async {
        let fixture = RefreshFixture()
        fixture.lifecycle.cancel()

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events.isEmpty)
        #expect(!fixture.activity.snapshot.isRefreshing)
    }

    @Test("An empty timeline restarts account loading without refresh activity")
    func emptyTimelineRestartsAccount() async {
        let fixture = RefreshFixture()

        await fixture.run(hasTimelineEvents: false, hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            .command(.restartAccount(fixture.account))
        ])
        #expect(!fixture.activity.snapshot.isRefreshing)
    }

    @Test("An existing refresh rejects duplicate work")
    func activeRefreshRejectsDuplicate() async throws {
        let fixture = RefreshFixture()
        _ = try #require(fixture.activity.beginRefresh())

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events.isEmpty)
        #expect(fixture.activity.snapshot.isRefreshing)
    }

    @Test("A runtime refresh reconfigures runtime and restores loaded activity")
    func runtimeRefreshPreservesActivityOrder() async {
        let fixture = RefreshFixture()

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == fixture.runtimeSuccessEvents)
        #expect(fixture.activity.snapshot == fixture.loadedIdleActivity)
    }

    @Test("A superseded runtime refresh suppresses phase and completion activity")
    func supersededRuntimeSuppressesLateActivity() async {
        let fixture = RefreshFixture()
        let lifecycle = fixture.lifecycle
        fixture.probe.beforeRuntimeReturn = {
            lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.configureRuntimeEvent
        ])
        #expect(fixture.activity.snapshot.isRefreshing)
    }

    @Test("A cancelled runtime refresh ends activity without publishing loaded phase")
    func cancelledRuntimeEndsActivity() async {
        let fixture = RefreshFixture()

        await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            await fixture.run(hasRelayRuntime: true)
        }.value

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.configureRuntimeEvent,
            fixture.endIdleActivityEvent
        ])
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }

    @Test("A remote refresh uses the prepared current timeline state")
    func remoteRefreshPreservesApplicationOrder() async {
        let fixture = RefreshFixture()

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == fixture.remoteSuccessEvents)
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }

    @Test("A superseded remote refresh still delegates its outcome")
    func supersededRemoteDelegatesOutcome() async {
        let fixture = RefreshFixture()
        let lifecycle = fixture.lifecycle
        fixture.probe.beforeRemoteReturn = {
            lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == Array(
            fixture.remoteSuccessEvents.dropLast()
        ))
        #expect(fixture.activity.snapshot.isRefreshing)
    }

    @Test("Missing remote input closes refresh activity without loading")
    func missingRemoteInputEndsActivity() async {
        let fixture = RefreshFixture(hasRemoteInput: false)

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == [
            fixture.beginActivityEvent,
            fixture.prepareRemoteInputEvent,
            fixture.endIdleActivityEvent
        ])
        #expect(fixture.activity.snapshot == fixture.initialActivity)
    }
}
