import AstrenzaCore
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

    @Test("Published presentation reads stay behind the source")
    func routesPublishedPresentationReads() {
        let fixture = StorePresentationFixture()
        let post = MockTimelineData.posts[0]
        fixture.source.entries = [.post(post)]
        fixture.source.filterStatus = TimelineFilterStatus(
            activeRuleCount: 2
        )
        fixture.source.materializedUnreadCount = 7
        fixture.source.visibleUnreadBadgeCount = 5
        fixture.source.resolvedContentRevision = 11
        fixture.source.profileMetadataRevision = 13
        fixture.source.realtimeFollowSourceRevision = 17

        #expect(fixture.coordinator.entries.map(\.id) == [post.id])
        #expect(fixture.coordinator.filterStatus.activeRuleCount == 2)
        #expect(fixture.coordinator.materializedUnreadCount == 7)
        #expect(fixture.coordinator.visibleUnreadBadgeCount == 5)
        #expect(fixture.coordinator.resolvedContentRevision == 11)
        #expect(fixture.coordinator.profileMetadataRevision == 13)
        #expect(fixture.coordinator.realtimeFollowSourceRevision == 17)
        #expect(fixture.projection.requests.isEmpty)
        #expect(fixture.scheduler.commands.isEmpty)
    }

    @Test("Presentation resources stay behind the coordinator")
    func ownsPresentationResources() throws {
        let eventStore = try NostrEventStore.inMemory()
        let fixture = StorePresentationFixture(eventStore: eventStore)

        #expect(fixture.coordinator.presentationEventStore === eventStore)
        #expect(fixture.projection.requests.isEmpty)
        #expect(fixture.scheduler.commands.isEmpty)
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
