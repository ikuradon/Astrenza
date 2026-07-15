import Testing
@testable import Astrenza

@Suite("Home timeline initial load workflow")
@MainActor
struct HomeTimelineInitialLoadWorkflowTests {
    @Test("A stale lifecycle performs no initial load work")
    func staleLifecycleStopsBeforeLoad() async {
        let fixture = InitialLoadFixture()
        fixture.lifecycle.cancel()

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events.isEmpty)
        #expect(fixture.activity.snapshot == fixture.idleActivity)
    }

    @Test("A non-runtime initial load maps every stage and fetched state in order")
    func nonRuntimeInitialLoadMapsStages() async {
        let fixture = InitialLoadFixture(
            stages: [
                .resolvingRelayList,
                .resolvingContactList,
                .loadingTimeline
            ],
            callsDidFetch: true
        )

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == fixture.nonRuntimeStageEvents)
        #expect(fixture.activity.snapshot == fixture.loadingActivity)
    }

    @Test("Superseded non-runtime stage callbacks cannot mutate activity")
    func supersededNonRuntimeStagesAreIgnored() async {
        let fixture = InitialLoadFixture(
            stages: [.resolvingRelayList, .resolvingContactList],
            callsDidFetch: true
        )
        let lifecycle = fixture.lifecycle
        fixture.probe.beforeStageCallbacks = {
            lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: false)

        #expect(fixture.probe.events == [
            fixture.loadInitialEvent,
            fixture.applyInitialOutcomeEvent
        ])
        #expect(fixture.activity.snapshot == fixture.idleActivity)
    }

    @Test("A fresh runtime bootstrap installs provisional relays before resolving")
    func freshRuntimeBootstrapStartsResolution() async {
        let fixture = InitialLoadFixture(hadCachedBootstrap: false)

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.installProvisionalEvent,
            fixture.resolvingRelaysEvent,
            fixture.loadRuntimeBootstrapEvent,
            fixture.applyFreshBootstrapOutcomeEvent
        ])
        #expect(fixture.activity.snapshot == fixture.resolvingRelaysActivity)
    }

    @Test("A cached runtime bootstrap queries relays after provisional install")
    func cachedRuntimeBootstrapConfiguresBeforeLoad() async {
        let fixture = InitialLoadFixture(
            hadCachedBootstrap: true,
            hasResolvedRelaysAfterProvisional: true
        )

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.installProvisionalEvent,
            .queryResolvedRelays,
            fixture.configureRuntimeEvent,
            fixture.loadRuntimeBootstrapEvent,
            fixture.applyCachedBootstrapOutcomeEvent
        ])
        #expect(fixture.activity.snapshot == fixture.idleActivity)
    }

    @Test("A cached bootstrap without relays returns to relay resolution")
    func cachedBootstrapWithoutRelaysResolvesAgain() async {
        let fixture = InitialLoadFixture(
            hadCachedBootstrap: true,
            hasResolvedRelaysAfterProvisional: false
        )

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.installProvisionalEvent,
            .queryResolvedRelays,
            fixture.resolvingRelaysEvent,
            fixture.loadRuntimeBootstrapEvent,
            fixture.applyCachedBootstrapOutcomeEvent
        ])
    }

    @Test("A superseded cached runtime stops before bootstrap fetch")
    func supersededRuntimeStopsAfterConfiguration() async {
        let fixture = InitialLoadFixture(
            hadCachedBootstrap: true,
            hasResolvedRelaysAfterProvisional: true
        )
        let lifecycle = fixture.lifecycle
        fixture.probe.beforeRuntimeReturn = {
            lifecycle.cancel()
        }

        await fixture.run(hasRelayRuntime: true)

        #expect(fixture.probe.events == [
            fixture.installProvisionalEvent,
            .queryResolvedRelays,
            fixture.configureRuntimeEvent
        ])
    }

    @Test("A cancelled cached runtime stops before bootstrap fetch")
    func cancelledRuntimeStopsAfterConfiguration() async {
        let fixture = InitialLoadFixture(
            hadCachedBootstrap: true,
            hasResolvedRelaysAfterProvisional: true
        )

        await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            await fixture.run(hasRelayRuntime: true)
        }.value

        #expect(fixture.probe.events == [
            fixture.installProvisionalEvent,
            .queryResolvedRelays,
            fixture.configureRuntimeEvent
        ])
    }
}
