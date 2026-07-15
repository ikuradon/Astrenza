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

@Suite("Home timeline pending event buffer")
struct HomeTimelinePendingEventBufferTests {
    @Test("Duplicate events share one debounced count publication")
    @MainActor
    func duplicateEventsCoalesceCountPublication() async throws {
        let delay = MaterializationDelayStub()
        let probe = PendingEventCountProbe()
        let buffer = HomeTimelinePendingEventBuffer(delay: { _ in
            await delay.suspend()
        })
        let publish: HomeTimelinePendingEventCountHandler = { publication in
            probe.counts.append(publication.count)
        }

        let insertedFirst = buffer.insert(
            eventID: "event-a",
            onCountPublication: publish
        )
        let insertedDuplicate = buffer.insert(
            eventID: "event-a",
            onCountPublication: publish
        )
        let insertedSecond = buffer.insert(
            eventID: "event-b",
            onCountPublication: publish
        )

        #expect(insertedFirst)
        #expect(!insertedDuplicate)
        #expect(insertedSecond)
        #expect(buffer.hasEvents)
        #expect(buffer.hasScheduledCountPublication)

        try #require(await waitUntil { await delay.requestCount() == 1 })
        await delay.resumeAll()
        try #require(await waitUntil { probe.counts == [2] })

        #expect(buffer.publishedCount == 2)
        #expect(!buffer.hasScheduledCountPublication)
    }

    @Test("Clear invalidates a stale publication before the buffer is reused")
    @MainActor
    func clearInvalidatesStalePublication() async throws {
        let delay = MaterializationDelayStub()
        let probe = PendingEventCountProbe()
        let buffer = HomeTimelinePendingEventBuffer(delay: { _ in
            await delay.suspend()
        })
        let publish: HomeTimelinePendingEventCountHandler = { publication in
            probe.counts.append(publication.count)
        }

        #expect(buffer.insert(
            eventID: "event-a",
            onCountPublication: publish
        ))
        try #require(await waitUntil { await delay.requestCount() == 1 })
        await delay.resumeAll()
        try #require(await waitUntil { probe.counts == [1] })

        #expect(buffer.insert(
            eventID: "event-b",
            onCountPublication: publish
        ))
        try #require(await waitUntil { await delay.requestCount() == 2 })
        #expect(buffer.removeAll(onCountPublication: publish))
        #expect(probe.counts == [1, 0])
        #expect(buffer.isEmpty)
        #expect(!buffer.hasScheduledCountPublication)

        #expect(buffer.insert(
            eventID: "event-c",
            onCountPublication: publish
        ))
        try #require(await waitUntil { await delay.requestCount() == 3 })
        await delay.resumeAll()
        try #require(await waitUntil { probe.counts == [1, 0, 1] })

        #expect(buffer.publishedCount == 1)
        #expect(buffer.hasEvents)
        #expect(!buffer.hasScheduledCountPublication)
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class MaterializationProbe {
    var permissions: [Bool] = []
}

@MainActor
private final class PendingEventCountProbe {
    var counts: [Int] = []
}

private actor MaterializationDelayStub {
    private var requests = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        requests += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func requestCount() -> Int {
        requests
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
