import AstrenzaCore

@MainActor
protocol HomeStoreStatusPublishing: AnyObject {
    var content: HomeTimelinePublishedContentState { get }
    var activity: HomeTimelinePublishedActivityState { get }
    var relayStatus: HomeTimelinePublishedRelayStatusState { get }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    )
    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool
    )
    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> String?
    func publishRelayStatusChange()
}

extension HomeTimelinePublishedStateCoordinator:
    HomeStoreStatusPublishing {}

@MainActor
protocol HomeStoreActivityInteracting: AnyObject {
    func perform(
        _ intent: HomeTimelineActivityIntent
    ) -> HomeTimelineActivityTransition
    func status(
        context: HomeTimelineActivityContext
    ) -> NostrTimelineActivityStatus?
}

extension HomeTimelineActivityInteractionWorkflow:
    HomeStoreActivityInteracting {}

@MainActor
protocol HomeStoreSyncStatusSourcing: AnyObject {
    var backwardRequestState: HomeTimelineBackwardRequestState { get }
    var initialSyncState: HomeTimelineInitialSyncState { get }

    func relayStatusSnapshot(
        resolvedRelays: [String]
    ) -> HomeTimelineRelayStatusSnapshot
}

extension HomeTimelineSyncInteractionWorkflow:
    HomeStoreSyncStatusSourcing {}

@MainActor
protocol HomeStoreDependencyWorkSourcing: AnyObject {
    var dependencyWorkState: HomeTimelineDependencyWorkState { get }
}

extension HomeTimelineDataInteractionWorkflow:
    HomeStoreDependencyWorkSourcing {}

@MainActor
final class HomeStoreStatusCoordinator {
    private let publisher: any HomeStoreStatusPublishing
    private let activity: any HomeStoreActivityInteracting
    private let sync: any HomeStoreSyncStatusSourcing
    private let dependencies: any HomeStoreDependencyWorkSourcing

    init(
        publisher: any HomeStoreStatusPublishing,
        activity: any HomeStoreActivityInteracting,
        sync: any HomeStoreSyncStatusSourcing,
        dependencies: any HomeStoreDependencyWorkSourcing
    ) {
        self.publisher = publisher
        self.activity = activity
        self.sync = sync
        self.dependencies = dependencies
    }

    static func live(
        components: HomeTimelineStoreComponents
    ) -> HomeStoreStatusCoordinator {
        HomeStoreStatusCoordinator(
            publisher: components.publishedStateCoordinator,
            activity: components.activityInteractionWorkflow,
            sync: components.syncInteractionWorkflow,
            dependencies: components.dataInteractionWorkflow
        )
    }

    var activitySnapshot: HomeTimelineActivitySnapshot {
        let activity = publisher.activity
        return HomeTimelineActivitySnapshot(
            phase: activity.phase,
            isRefreshing: activity.isRefreshing,
            isLoadingOlder: activity.isLoadingOlder,
            isRealtime: activity.isRealtime
        )
    }

    var relayStatusSnapshot: HomeTimelineRelayStatusSnapshot {
        publisher.relayStatus.snapshot
    }

    var relayStatusRevision: Int {
        publisher.relayStatus.revision
    }

    var relayRuntimeStates: [String: NostrRelayConnectionState] {
        relayStatusSnapshot.runtimeStates
    }

    var phase: NostrHomeTimelinePhase {
        activitySnapshot.phase
    }

    var isRefreshing: Bool {
        activitySnapshot.isRefreshing
    }

    var isLoadingOlder: Bool {
        activitySnapshot.isLoadingOlder
    }

    var isRealtime: Bool {
        activitySnapshot.isRealtime
    }

    var initialSyncState: HomeTimelineInitialSyncState {
        // EOSE/CLOSED/timeout diagnostics advance this observable revision.
        _ = relayStatusRevision
        return sync.initialSyncState
    }

    var relayStatusCounts: (connected: Int, planned: Int) {
        let snapshot = relayStatusSnapshot
        return (
            connected: snapshot.connectedRelayCount,
            planned: snapshot.plannedRelayCount
        )
    }

    var activityStatus: NostrTimelineActivityStatus? {
        // Diagnostic-only changes also advance this revision and must
        // invalidate presentation even when the relay counts stay unchanged.
        _ = relayStatusRevision
        let backward = sync.backwardRequestState
        let relay = relayStatusSnapshot
        return activity.status(
            context: HomeTimelineActivityContext(
                connectedRelayCount: relay.connectedRelayCount,
                plannedRelayCount: relay.plannedRelayCount,
                initialSyncState: sync.initialSyncState,
                hasOlderPageRequest: backward.hasOlderPageRequest,
                hasGapWork: backward.hasGapWork,
                hasBackwardRequests: backward.hasRequests,
                hasPendingDependencyWork:
                    dependencies.dependencyWorkState.hasPendingWork
            )
        )
    }

    var isRelayProcessing: Bool {
        activityStatus != nil
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        publisher.applyActivityTransition(transition)
    }

    func applyActivityIntent(_ intent: HomeTimelineActivityIntent) {
        applyActivityTransition(activity.perform(intent))
    }

    func refreshRelayStatusCounts() {
        applyRelayStatusSnapshot(
            sync.relayStatusSnapshot(
                resolvedRelays: publisher.content.resolvedRelays
            )
        )
    }

    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot
    ) {
        publisher.applyRelayStatusSnapshot(
            snapshot,
            publishingStatusChange: false
        )
    }

    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> String? {
        publisher.applyRelayStatusTransition(transition)
    }

    func publishRelayStatusChange() {
        publisher.publishRelayStatusChange()
    }
}
