import Testing
@testable import Astrenza

@Suite("Home timeline materialization scheduler")
struct HomeTimelineMaterializationSchedulerTests {
    @Test("Coalesced updates preserve the most conservative realtime follow permission")
    @MainActor
    func coalescedRealtimePermission() async {
        let scheduler = HomeTimelineMaterializationScheduler(defaultDelayNanoseconds: 0)
        let probe = MaterializationProbe()
        let materialize: HomeTimelineMaterializationScheduler.MaterializeHandler = { permission in
            probe.permissions.append(permission)
        }

        scheduler.schedule(allowsRealtimeFollow: true, materialize: materialize)
        scheduler.schedule(allowsRealtimeFollow: false, materialize: materialize)
        scheduler.schedule(allowsRealtimeFollow: true, materialize: materialize)

        for _ in 0..<100 where probe.permissions.isEmpty {
            await Task.yield()
        }

        #expect(probe.permissions == [false])
    }

    @Test("Scrolling defers one coalesced materialization until interaction ends")
    @MainActor
    func scrollingDefersMaterialization() async {
        let scheduler = HomeTimelineMaterializationScheduler(defaultDelayNanoseconds: 0)
        let probe = MaterializationProbe()
        let materialize: HomeTimelineMaterializationScheduler.MaterializeHandler = { permission in
            probe.permissions.append(permission)
        }

        scheduler.setScrollActive(true, materialize: materialize)
        scheduler.schedule(allowsRealtimeFollow: true, materialize: materialize)
        await Task.yield()

        #expect(probe.permissions.isEmpty)
        #expect(scheduler.hasPendingMaterialization)

        scheduler.setScrollActive(false, materialize: materialize)
        for _ in 0..<100 where probe.permissions.isEmpty {
            await Task.yield()
        }

        #expect(probe.permissions == [true])
        #expect(!scheduler.hasPendingMaterialization)
    }

    @Test("Projection reload, fingerprint, and follow revision share one state boundary")
    @MainActor
    func stateBoundary() throws {
        let scheduler = HomeTimelineMaterializationScheduler()
        scheduler.requestNewestProjectionReload()

        let firstPass = try #require(scheduler.beginMaterialization(allowsRealtimeFollow: true))
        #expect(firstPass.shouldReloadNewestProjection)
        scheduler.clearNewestProjectionReload()

        let secondPass = try #require(scheduler.beginMaterialization(allowsRealtimeFollow: false))
        #expect(!secondPass.shouldReloadNewestProjection)
        #expect(scheduler.shouldPublish(renderFingerprint: [1, 2]))
        #expect(!scheduler.shouldPublish(renderFingerprint: [1, 2]))

        scheduler.didPublish(revision: 7, allowsRealtimeFollow: true)
        #expect(scheduler.realtimeFollowSourceRevision == 7)

        scheduler.reset()
        #expect(scheduler.realtimeFollowSourceRevision == nil)
        #expect(scheduler.shouldPublish(renderFingerprint: [1, 2]))
    }
}

@MainActor
private final class MaterializationProbe {
    var permissions: [Bool] = []
}
