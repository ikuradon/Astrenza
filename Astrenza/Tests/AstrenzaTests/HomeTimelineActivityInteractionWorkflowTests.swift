import Testing
@testable import Astrenza

@Suite("Home timeline activity interaction workflow")
@MainActor
struct HomeTimelineActivityInteractionTests {
    @Test("Store-facing activity state is projected from one snapshot")
    func projectsStoreFacingState() {
        let manager = ActivityManagerSpy(
            snapshot: HomeTimelineActivitySnapshot(
                phase: .loadingHome,
                isRefreshing: true,
                isLoadingOlder: false,
                isRealtime: true
            ),
            canBeginLoadingOlder: false
        )
        let workflow = HomeTimelineActivityInteractionWorkflow(
            activity: manager
        )

        #expect(workflow.state == HomeTimelineActivityInteractionState(
            phase: .loadingHome,
            isRealtime: true,
            canBeginLoadingOlder: false
        ))
        #expect(manager.events == [.snapshot, .canBeginLoadingOlder])
    }

    @Test("Phase and realtime intents preserve coordinator transitions")
    func routesMutationIntents() {
        let manager = ActivityManagerSpy()
        let workflow = HomeTimelineActivityInteractionWorkflow(
            activity: manager
        )

        let phase = workflow.perform(.setPhase(.loaded))
        let realtime = workflow.perform(.setRealtime(true))

        #expect(phase == manager.phaseTransition)
        #expect(realtime == manager.realtimeTransition)
        #expect(manager.events == [
            .setPhase(.loaded),
            .setRealtime(true)
        ])
    }

    @Test("Activity status preserves every workload input")
    func routesActivityStatusContext() {
        let manager = ActivityManagerSpy()
        let workflow = HomeTimelineActivityInteractionWorkflow(
            activity: manager
        )
        let context = HomeTimelineActivityContext(
            connectedRelayCount: 2,
            plannedRelayCount: 4,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 4,
            initialSyncExpectedRelayCount: 4,
            hasOlderPageRequest: true,
            hasGapWork: true,
            backwardRequestCount: 2,
            hasPendingDependencyWork: true,
            pendingDependencyRequestCount: 3
        )

        let status = workflow.status(context: context)

        #expect(status == manager.statusResult)
        #expect(manager.events == [.activityStatus(context)])
    }
}

private enum ActivityManagerEvent: Equatable {
    case snapshot
    case canBeginLoadingOlder
    case setPhase(NostrHomeTimelinePhase)
    case setRealtime(Bool)
    case activityStatus(HomeTimelineActivityContext)
}

@MainActor
private final class ActivityManagerSpy: HomeTimelineActivityManaging {
    private let snapshotResult: HomeTimelineActivitySnapshot
    private let canBeginLoadingOlderResult: Bool
    private(set) var events: [ActivityManagerEvent] = []

    let phaseTransition = HomeTimelineActivityTransition(
        snapshot: HomeTimelineActivitySnapshot(
            phase: .loaded,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        ),
        changes: .phase
    )
    let realtimeTransition = HomeTimelineActivityTransition(
        snapshot: HomeTimelineActivitySnapshot(
            phase: .loaded,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: true
        ),
        changes: .realtime
    )
    let statusResult = NostrTimelineActivityStatus(
        title: "Activity",
        detail: "Detail",
        compactLabel: "Active"
    )

    init(
        snapshot: HomeTimelineActivitySnapshot = HomeTimelineActivitySnapshot(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        ),
        canBeginLoadingOlder: Bool = true
    ) {
        snapshotResult = snapshot
        canBeginLoadingOlderResult = canBeginLoadingOlder
    }

    var snapshot: HomeTimelineActivitySnapshot {
        events.append(.snapshot)
        return snapshotResult
    }

    var canBeginLoadingOlder: Bool {
        events.append(.canBeginLoadingOlder)
        return canBeginLoadingOlderResult
    }

    func setPhase(
        _ phase: NostrHomeTimelinePhase
    ) -> HomeTimelineActivityTransition {
        events.append(.setPhase(phase))
        return phaseTransition
    }

    func setRealtime(
        _ isRealtime: Bool
    ) -> HomeTimelineActivityTransition {
        events.append(.setRealtime(isRealtime))
        return realtimeTransition
    }

    func activityStatus(
        context: HomeTimelineActivityContext
    ) -> NostrTimelineActivityStatus? {
        events.append(.activityStatus(context))
        return statusResult
    }
}
