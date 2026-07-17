import Testing
@testable import Astrenza

@MainActor
@Suite("Home timeline activity coordinator")
struct HomeTimelineActivityCoordinatorTests {
    @Test("Bootstrap phases preserve the user-visible activity copy")
    func bootstrapPhasesPreserveActivityCopy() {
        let coordinator = HomeTimelineActivityCoordinator()

        _ = coordinator.setPhase(.resolvingRelays)
        #expect(coordinator.activityStatus(context: .empty) == NostrTimelineActivityStatus(
            title: "Resolving relay list",
            detail: "Looking up kind:10002 on discovery relays",
            compactLabel: "kind:10002"
        ))

        _ = coordinator.setPhase(.resolvingContacts)
        #expect(coordinator.activityStatus(context: .empty) == NostrTimelineActivityStatus(
            title: "Resolving contacts",
            detail: "Looking up kind:3 before opening Home",
            compactLabel: "kind:3"
        ))

        _ = coordinator.setPhase(.loadingHome)
        let loadingContext = HomeTimelineActivityContext(
            connectedRelayCount: 2,
            plannedRelayCount: 5,
            initialSyncState: .awaitingRelayResponses,
            initialSyncCompletedRelayCount: 0,
            initialSyncExpectedRelayCount: 5,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 0,
            hasPendingDependencyWork: false,
            pendingDependencyRequestCount: 0
        )
        #expect(coordinator.activityStatus(context: loadingContext) == NostrTimelineActivityStatus(
            title: "Connecting Home relays",
            detail: "2 of 5 relays ready",
            compactLabel: "Home"
        ))
    }

    @Test("Operational activity keeps refresh, older, gap, and dependency priority")
    func operationalActivityPreservesPriority() throws {
        let coordinator = HomeTimelineActivityCoordinator()
        _ = coordinator.setPhase(.loaded)
        _ = try #require(coordinator.beginLoadingOlder())
        _ = try #require(coordinator.beginRefresh())
        let allWork = HomeTimelineActivityContext(
            connectedRelayCount: 1,
            plannedRelayCount: 1,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 1,
            hasOlderPageRequest: true,
            hasGapWork: true,
            backwardRequestCount: 1,
            hasPendingDependencyWork: true,
            pendingDependencyRequestCount: 1
        )

        #expect(coordinator.activityStatus(context: allWork) == NostrTimelineActivityStatus(
            title: "Updating Home timeline",
            detail: "Applying events already received from Home relays",
            compactLabel: "Updating"
        ))

        _ = coordinator.endRefresh()
        #expect(coordinator.activityStatus(context: allWork)?.compactLabel == "Older")

        _ = coordinator.endLoadingOlder()
        let gapWork = HomeTimelineActivityContext(
            connectedRelayCount: 1,
            plannedRelayCount: 1,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 1,
            hasOlderPageRequest: false,
            hasGapWork: true,
            backwardRequestCount: 1,
            hasPendingDependencyWork: true,
            pendingDependencyRequestCount: 1
        )
        #expect(coordinator.activityStatus(context: gapWork)?.compactLabel == "Gap")

        let dependencyWork = HomeTimelineActivityContext(
            connectedRelayCount: 1,
            plannedRelayCount: 1,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 1,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 1,
            hasPendingDependencyWork: true,
            pendingDependencyRequestCount: 2
        )
        #expect(coordinator.activityStatus(context: dependencyWork) == NostrTimelineActivityStatus(
            title: "Resolving referenced posts",
            detail: "Waiting for 2 referenced event requests",
            compactLabel: "Resolving"
        ))
    }

    @Test("Dependency and backward work report the actual pending phase")
    func dependencyAndBackwardWorkReportActualPhase() {
        let coordinator = HomeTimelineActivityCoordinator()
        _ = coordinator.setPhase(.loaded)

        let preparing = HomeTimelineActivityContext(
            connectedRelayCount: 1,
            plannedRelayCount: 1,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 1,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 0,
            hasPendingDependencyWork: true,
            pendingDependencyRequestCount: 0
        )
        #expect(coordinator.activityStatus(context: preparing)?.detail ==
            "Preparing referenced event requests")

        let awaitingRelay = HomeTimelineActivityContext(
            connectedRelayCount: 1,
            plannedRelayCount: 1,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 1,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 3,
            hasPendingDependencyWork: false,
            pendingDependencyRequestCount: 0
        )
        #expect(coordinator.activityStatus(context: awaitingRelay)?.detail ==
            "3 backward requests remain active")
    }

    @Test("Bootstrap phase takes priority over concurrent operational work")
    func bootstrapPhaseTakesPriority() throws {
        let coordinator = HomeTimelineActivityCoordinator()
        _ = try #require(coordinator.beginRefresh())
        _ = try #require(coordinator.beginLoadingOlder())
        _ = coordinator.setPhase(.resolvingContacts)

        #expect(coordinator.activityStatus(context: .allWork)?.compactLabel == "kind:3")
    }

    @Test("Duplicate starts and assignments do not publish duplicate changes")
    func duplicateMutationsDoNotPublishChanges() throws {
        let coordinator = HomeTimelineActivityCoordinator()

        let firstPhase = coordinator.setPhase(.loaded)
        let duplicatePhase = coordinator.setPhase(.loaded)
        let firstRefresh = try #require(coordinator.beginRefresh())

        #expect(firstPhase.changes == .phase)
        #expect(duplicatePhase.changes.isEmpty)
        #expect(firstRefresh.changes == .refreshing)
        #expect(coordinator.beginRefresh() == nil)
        #expect(coordinator.setRealtime(false).changes.isEmpty)
    }

    @Test("Reset clears all activity state in one transition")
    func resetClearsAllActivityState() throws {
        let coordinator = HomeTimelineActivityCoordinator()
        _ = coordinator.setPhase(.failed("failed"))
        _ = try #require(coordinator.beginRefresh())
        _ = try #require(coordinator.beginLoadingOlder())
        _ = coordinator.setRealtime(true)

        let reset = coordinator.reset()

        #expect(reset.snapshot == HomeTimelineActivitySnapshot(
            phase: .idle,
            isRefreshing: false,
            isLoadingOlder: false,
            isRealtime: false
        ))
        #expect(reset.changes == [.phase, .refreshing, .loadingOlder, .realtime])
        #expect(coordinator.activityStatus(context: .empty) == nil)
    }

    @Test("Realtime state remains independent from processing activity")
    func realtimeStateDoesNotCreateProcessingActivity() {
        let coordinator = HomeTimelineActivityCoordinator()
        _ = coordinator.setPhase(.loaded)

        let transition = coordinator.setRealtime(true)

        #expect(transition.changes == .realtime)
        #expect(transition.snapshot.isRealtime)
        #expect(coordinator.activityStatus(context: .empty) == nil)
    }

    @Test("Loaded Home reports initial EOSE wait without treating realtime reconnects as work")
    func initialSyncActivityEndsAtTerminalResult() {
        let coordinator = HomeTimelineActivityCoordinator()
        let awaiting = HomeTimelineActivityContext(
            connectedRelayCount: 2,
            plannedRelayCount: 3,
            initialSyncState: .awaitingRelayResponses,
            initialSyncCompletedRelayCount: 1,
            initialSyncExpectedRelayCount: 3,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 0,
            hasPendingDependencyWork: false,
            pendingDependencyRequestCount: 0
        )
        let synchronized = HomeTimelineActivityContext(
            connectedRelayCount: 2,
            plannedRelayCount: 3,
            initialSyncState: .synchronized,
            initialSyncCompletedRelayCount: 3,
            initialSyncExpectedRelayCount: 3,
            hasOlderPageRequest: false,
            hasGapWork: false,
            backwardRequestCount: 0,
            hasPendingDependencyWork: false,
            pendingDependencyRequestCount: 0
        )

        #expect(coordinator.activityStatus(context: awaiting) == nil)
        _ = coordinator.setPhase(.loaded)
        #expect(coordinator.activityStatus(context: awaiting) == NostrTimelineActivityStatus(
            title: "Synchronizing Home timeline",
            detail: "1 of 3 relays completed initial sync; 2 connected",
            compactLabel: "Syncing"
        ))
        #expect(coordinator.activityStatus(context: synchronized) == nil)
    }
}

private extension HomeTimelineActivityContext {
    static let empty = HomeTimelineActivityContext(
        connectedRelayCount: 0,
        plannedRelayCount: 1,
        initialSyncState: .synchronized,
        initialSyncCompletedRelayCount: 1,
        initialSyncExpectedRelayCount: 1,
        hasOlderPageRequest: false,
        hasGapWork: false,
        backwardRequestCount: 0,
        hasPendingDependencyWork: false,
        pendingDependencyRequestCount: 0
    )

    static let allWork = HomeTimelineActivityContext(
        connectedRelayCount: 1,
        plannedRelayCount: 2,
        initialSyncState: .synchronized,
        initialSyncCompletedRelayCount: 2,
        initialSyncExpectedRelayCount: 2,
        hasOlderPageRequest: true,
        hasGapWork: true,
        backwardRequestCount: 2,
        hasPendingDependencyWork: true,
        pendingDependencyRequestCount: 3
    )
}
