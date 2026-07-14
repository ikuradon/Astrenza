import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline runtime event application planner")
struct HomeTimelineRuntimeEventApplicationPlannerTests {
    @Test("Projected forward notes resolve dependencies and reload the newest realtime window")
    func forwardNoteAtNewestWindow() {
        let note = event(kind: 6, idCharacter: "a")
        let embedded = event(kind: 1, idCharacter: "b")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planForward(
            .init(
                event: note,
                embeddedEvent: embedded,
                projectsIntoCurrentFeed: true,
                receivedWhileRealtime: true,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        expected.dependencyEvent = note
        expected.embeddedDependencyEvent = embedded
        expected.projectionUpdate = .reloadNewestAndSchedule(allowsRealtimeFollow: true)
        #expect(plan == expected)
    }

    @Test("Projected forward notes buffer for every detached viewport state")
    func forwardNoteWhileDetached() {
        let note = event(kind: 1, idCharacter: "c")
        let detachedStates = [
            (hasRestoreAnchor: true, isAtNewest: true, hasPending: false),
            (hasRestoreAnchor: false, isAtNewest: false, hasPending: false),
            (hasRestoreAnchor: false, isAtNewest: true, hasPending: true)
        ]

        for state in detachedStates {
            let plan = HomeTimelineRuntimeEventApplicationPlanner().planForward(.init(
                event: note,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: true,
                receivedWhileRealtime: true,
                hasRestoreProjectionAnchor: state.hasRestoreAnchor,
                isTimelineAtNewestWindow: state.isAtNewest,
                hasPendingEvents: state.hasPending
            ))

            var expected = HomeTimelineRuntimeEventApplicationPlan()
            expected.invalidatesListEntries = true
            expected.dependencyEvent = note
            expected.projectionUpdate = .bufferPendingEvent(note.id)
            #expect(plan == expected)
        }
    }

    @Test("Unprojected forward events only invalidate derived list entries")
    func unprojectedForwardEvent() {
        let note = event(kind: 1, idCharacter: "d")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planForward(
            .init(
                event: note,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: false,
                receivedWhileRealtime: false,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        #expect(plan == expected)
    }

    @Test("Projected forward deletions reload and schedule with realtime permission")
    func forwardDeletion() {
        let deletion = event(kind: 5, idCharacter: "e")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planForward(
            .init(
                event: deletion,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: true,
                receivedWhileRealtime: true,
                hasRestoreProjectionAnchor: false,
                isTimelineAtNewestWindow: true,
                hasPendingEvents: false
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        expected.deletion = .init(
            event: deletion,
            materialization: .scheduled(allowsRealtimeFollow: true)
        )
        #expect(plan == expected)
    }

    @Test("Backward metadata updates profile state before standard materialization")
    func backwardMetadata() {
        let metadata = event(kind: 0, idCharacter: "f")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planBackward(
            .init(
                event: metadata,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: false,
                isTimelineBackfill: false
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.metadataEvent = metadata
        expected.materializationSchedule = .standard
        #expect(plan == expected)
    }

    @Test("Projected timeline backfill records membership progress and dependencies")
    func projectedBackwardTimelineEvent() {
        let repost = event(kind: 6, idCharacter: "1")
        let embedded = event(kind: 1, idCharacter: "2")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planBackward(
            .init(
                event: repost,
                embeddedEvent: embedded,
                projectsIntoCurrentFeed: true,
                isTimelineBackfill: true
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        expected.backwardTimelineEventID = repost.id
        expected.sourceEventIDToFinish = repost.id
        expected.dependencyEvent = repost
        expected.embeddedDependencyEvent = embedded
        #expect(plan == expected)
    }

    @Test("Dependency fetch events use deferred materialization outside timeline backfill")
    func backwardDependencyEvent() {
        let source = event(kind: 1, idCharacter: "3")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planBackward(
            .init(
                event: source,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: false,
                isTimelineBackfill: false
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        expected.sourceEventIDToFinish = source.id
        expected.dependencyEvent = source
        expected.materializationSchedule = .deferredDependencies
        #expect(plan == expected)
    }

    @Test("Rejected timeline backfills finish source work without changing presentation")
    func rejectedBackwardTimelineEvent() {
        let source = event(kind: 1, idCharacter: "4")

        let plan = HomeTimelineRuntimeEventApplicationPlanner().planBackward(
            .init(
                event: source,
                embeddedEvent: nil,
                projectsIntoCurrentFeed: false,
                isTimelineBackfill: true
            )
        )

        var expected = HomeTimelineRuntimeEventApplicationPlan()
        expected.invalidatesListEntries = true
        expected.sourceEventIDToFinish = source.id
        #expect(plan == expected)
    }

    @Test("Only accepted timeline backfill deletions change the current projection")
    func backwardTimelineDeletion() {
        let deletion = event(kind: 5, idCharacter: "5")
        let planner = HomeTimelineRuntimeEventApplicationPlanner()

        let accepted = planner.planBackward(.init(
            event: deletion,
            embeddedEvent: nil,
            projectsIntoCurrentFeed: true,
            isTimelineBackfill: true
        ))
        let rejected = planner.planBackward(.init(
            event: deletion,
            embeddedEvent: nil,
            projectsIntoCurrentFeed: false,
            isTimelineBackfill: true
        ))
        let dependencyFetch = planner.planBackward(.init(
            event: deletion,
            embeddedEvent: nil,
            projectsIntoCurrentFeed: false,
            isTimelineBackfill: false
        ))

        var expectedAccepted = HomeTimelineRuntimeEventApplicationPlan()
        expectedAccepted.invalidatesListEntries = true
        expectedAccepted.deletion = .init(
            event: deletion,
            materialization: .immediate
        )
        var expectedRejected = HomeTimelineRuntimeEventApplicationPlan()
        expectedRejected.invalidatesListEntries = true
        var expectedDependencyFetch = HomeTimelineRuntimeEventApplicationPlan()
        expectedDependencyFetch.invalidatesListEntries = true
        expectedDependencyFetch.deletion = .init(
            event: deletion,
            materialization: .immediate
        )
        #expect(accepted == expectedAccepted)
        #expect(rejected == expectedRejected)
        #expect(dependencyFetch == expectedDependencyFetch)
    }

    private func event(kind: Int, idCharacter: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: idCharacter, count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: 100,
            kind: kind,
            tags: [],
            content: idCharacter,
            sig: String(repeating: "b", count: 128)
        )
    }
}
