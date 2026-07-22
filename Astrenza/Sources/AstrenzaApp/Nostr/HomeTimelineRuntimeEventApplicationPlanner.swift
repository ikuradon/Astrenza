import AstrenzaCore

struct HomeTimelineRuntimeEventApplicationPlan: Equatable, Sendable {
    struct Deletion: Equatable, Sendable {
        let event: NostrEvent
        let materialization: DeletionMaterialization
    }

    enum DeletionMaterialization: Equatable, Sendable {
        case scheduled(allowsRealtimeFollow: Bool)
        case immediate
    }

    enum ProjectionUpdate: Equatable, Sendable {
        case reloadNewestAndSchedule(allowsRealtimeFollow: Bool)
        case bufferPendingEvent(String)
    }

    enum MaterializationSchedule: Equatable, Sendable {
        case standard
        case deferredDependencies
    }

    var invalidatesListEntries = false
    var metadataEvent: NostrEvent?
    var backwardTimelineEventID: String?
    var sourceEventIDToFinish: String?
    var dependencyEvent: NostrEvent?
    var embeddedDependencyEvent: NostrEvent?
    var deletion: Deletion?
    var projectionUpdate: ProjectionUpdate?
    var materializationSchedule: MaterializationSchedule?
}

struct HomeTimelineRuntimeEventApplicationPlanner: Sendable {
    struct ForwardInput: Sendable {
        let event: NostrEvent
        let embeddedEvent: NostrEvent?
        let projectsIntoCurrentFeed: Bool
        let receivedWhileRealtime: Bool
        let hasRestoreProjectionAnchor: Bool
        let isTimelineAtNewestWindow: Bool
        let hasPendingEvents: Bool
    }

    struct BackwardInput: Sendable {
        let event: NostrEvent
        let embeddedEvent: NostrEvent?
        let projectsIntoCurrentFeed: Bool
        let isTimelineBackfill: Bool
    }

    func planForward(
        _ input: ForwardInput
    ) -> HomeTimelineRuntimeEventApplicationPlan {
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        guard input.event.kind == 1 || input.event.kind == 5 || input.event.kind == 6 else {
            return plan
        }

        plan.invalidatesListEntries = true
        guard input.projectsIntoCurrentFeed else { return plan }

        if input.event.kind == 5 {
            plan.deletion = HomeTimelineRuntimeEventApplicationPlan.Deletion(
                event: input.event,
                materialization: .scheduled(
                    allowsRealtimeFollow: input.receivedWhileRealtime
                )
            )
            return plan
        }

        plan.dependencyEvent = input.event
        plan.embeddedDependencyEvent = input.embeddedEvent
        if !input.receivedWhileRealtime {
            plan.projectionUpdate = .reloadNewestAndSchedule(
                allowsRealtimeFollow: false
            )
        } else if !input.hasRestoreProjectionAnchor,
           input.isTimelineAtNewestWindow,
           !input.hasPendingEvents {
            plan.projectionUpdate = .reloadNewestAndSchedule(
                allowsRealtimeFollow: true
            )
        } else {
            plan.projectionUpdate = .bufferPendingEvent(input.event.id)
        }
        return plan
    }

    func planBackward(
        _ input: BackwardInput
    ) -> HomeTimelineRuntimeEventApplicationPlan {
        var plan = HomeTimelineRuntimeEventApplicationPlan()
        if input.event.kind == 1 || input.event.kind == 5 || input.event.kind == 6 {
            plan.invalidatesListEntries = true
        }

        switch input.event.kind {
        case 0:
            plan.metadataEvent = input.event
            plan.materializationSchedule = .standard
        case 1, 6:
            if input.projectsIntoCurrentFeed {
                plan.backwardTimelineEventID = input.event.id
            }
            plan.sourceEventIDToFinish = input.event.id
            if !input.isTimelineBackfill || input.projectsIntoCurrentFeed {
                plan.dependencyEvent = input.event
                plan.embeddedDependencyEvent = input.embeddedEvent
            }
            if !input.isTimelineBackfill {
                plan.materializationSchedule = .deferredDependencies
            }
        case 5:
            if !input.isTimelineBackfill || input.projectsIntoCurrentFeed {
                plan.deletion = HomeTimelineRuntimeEventApplicationPlan.Deletion(
                    event: input.event,
                    materialization: .immediate
                )
            }
        default:
            break
        }
        return plan
    }
}
