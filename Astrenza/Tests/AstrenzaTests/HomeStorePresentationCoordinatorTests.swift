import Testing
@testable import Astrenza

@Suite("Home Store presentation coordinator")
@MainActor
struct HomeStorePresentationCoordinatorTests {
    @Test("Each materialization uses fresh state and applies before completion")
    func materializationUsesFreshStateAndOrderedCompletion() throws {
        let fixture = StorePresentationFixture()
        fixture.coordinator.materializeEntries(
            allowsRealtimeFollow: false,
            onTransition: nil
        )
        fixture.source.snapshot = fixture.replacementSnapshot
        fixture.coordinator.materializeEntries(
            allowsRealtimeFollow: true
        ) { transition in
            fixture.events.append(.completion(
                transition.snapshot.resolvedContentRevision
            ))
        }

        let initial = try #require(fixture.projection.requests.first)
        let replacement = try #require(fixture.projection.requests.last)
        #expect(initial.account == fixture.account)
        #expect(!initial.allowsRealtimeFollow)
        #expect(
            initial.nip05Resolutions ==
                fixture.initialSnapshot.dependencies.nip05Resolutions
        )
        #expect(replacement.account == fixture.replacementAccount)
        #expect(replacement.allowsRealtimeFollow)
        #expect(
            replacement.profileResolutionStates ==
                fixture.replacementSnapshot.dependencies
                    .profileResolutionStates
        )
        #expect(replacement.policy == fixture.replacementSnapshot.policy)

        fixture.projection.completeLast(with: fixture.transition)

        #expect(fixture.events.values == [
            .applied(fixture.transition.snapshot.resolvedContentRevision),
            .completion(fixture.transition.snapshot.resolvedContentRevision)
        ])
    }

    @Test("Scheduling preserves delay and realtime-follow selection")
    func schedulingPreservesArguments() throws {
        let fixture = StorePresentationFixture()

        fixture.coordinator.scheduleMaterialization(
            delayNanoseconds: 120,
            allowsRealtimeFollow: nil
        )
        fixture.scheduler.runScheduledMaterialization(
            allowsRealtimeFollow: true
        )

        #expect(fixture.scheduler.schedules == [
            StorePresentationSchedule(
                delayNanoseconds: 120,
                allowsRealtimeFollow: nil
            )
        ])
        let request = try #require(fixture.projection.requests.last)
        #expect(request.allowsRealtimeFollow)
        #expect(request.account == fixture.account)
    }

    @Test("Presentation commands route through scheduler and source")
    func routesPresentationCommands() {
        let fixture = StorePresentationFixture()

        fixture.coordinator.requestNewestProjectionReload()
        fixture.coordinator.clearNewestProjectionReload()
        fixture.coordinator.restoreReadBoundary(postID: "restored")
        fixture.coordinator.applyPresentationTransition(fixture.transition)

        #expect(
            fixture.coordinator.currentReadBoundaryPostID == "boundary"
        )
        #expect(fixture.scheduler.commands == [
            .requestNewestProjectionReload,
            .clearNewestProjectionReload,
            .restoreReadBoundary("restored")
        ])
        #expect(fixture.source.appliedRevisions == [
            fixture.scheduler.restoredTransition.snapshot
                .resolvedContentRevision,
            fixture.transition.snapshot.resolvedContentRevision
        ])
    }

    @Test("Retained callbacks do not retain the coordinator")
    func retainedCallbacksDoNotRetainCoordinator() {
        let scheduled = RetainedStorePresentationFixture()
        var scheduledCoordinator: HomeStorePresentationCoordinator? =
            scheduled.makeCoordinator()
        scheduledCoordinator?.scheduleMaterialization(
            delayNanoseconds: nil,
            allowsRealtimeFollow: nil
        )
        weak let weakScheduledCoordinator = scheduledCoordinator

        scheduledCoordinator = nil

        #expect(weakScheduledCoordinator == nil)
        scheduled.scheduler.runScheduledMaterialization(
            allowsRealtimeFollow: true
        )
        #expect(scheduled.projection.requests.isEmpty)

        let projected = RetainedStorePresentationFixture()
        var projectedCoordinator: HomeStorePresentationCoordinator? =
            projected.makeCoordinator()
        projectedCoordinator?.materializeEntries(
            allowsRealtimeFollow: false,
            onTransition: nil
        )
        weak let weakProjectedCoordinator = projectedCoordinator

        projectedCoordinator = nil

        #expect(weakProjectedCoordinator == nil)
        projected.projection.completeLast(with: projected.transition)
        #expect(projected.source.appliedTransitions.isEmpty)
    }
}
