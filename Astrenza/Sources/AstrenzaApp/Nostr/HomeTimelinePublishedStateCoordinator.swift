import AstrenzaCore
import Observation

@MainActor
@Observable
final class HomeTimelinePublishedStateCoordinator {
    private(set) var account: NostrAccount?
    private(set) var syncPolicy: NostrSyncPolicy
    private(set) var entries: [TimelineFeedEntry] = []
    private(set) var filterStatus = TimelineFilterStatus()
    private(set) var materializedUnreadCount = 0
    private(set) var visibleUnreadBadgeCount = 0
    private(set) var resolvedContentRevision = 0
    private(set) var realtimeFollowSourceRevision: Int?
    private(set) var phase = NostrHomeTimelinePhase.idle
    private(set) var isRefreshing = false
    private(set) var isLoadingOlder = false
    private(set) var isRealtime = false
    private(set) var resolvedRelays: [String] = []
    private(set) var followedPubkeys: [String] = []
    private(set) var hasMoreOlder = true
    private(set) var relayStatusSnapshot = HomeTimelineRelayStatusSnapshot(
        runtimeStates: [:],
        connectedRelayCount: 0,
        plannedRelayCount: 1
    )
    private(set) var relayStatusRevision = 0
    private(set) var listProjectionRevision = 0
    private(set) var pendingEventCount = 0

    init(syncPolicy: NostrSyncPolicy) {
        self.syncPolicy = syncPolicy
    }

    var accountContext: HomeTimelinePublishedAccountContextState {
        HomeTimelinePublishedAccountContextState(
            account: account,
            syncPolicy: syncPolicy
        )
    }

    var presentation: HomeTimelinePublishedPresentationState {
        HomeTimelinePublishedPresentationState(
            entries: entries,
            filterStatus: filterStatus,
            materializedUnreadCount: materializedUnreadCount,
            visibleUnreadBadgeCount: visibleUnreadBadgeCount,
            resolvedContentRevision: resolvedContentRevision,
            realtimeFollowSourceRevision: realtimeFollowSourceRevision
        )
    }

    var activity: HomeTimelinePublishedActivityState {
        HomeTimelinePublishedActivityState(
            phase: phase,
            isRefreshing: isRefreshing,
            isLoadingOlder: isLoadingOlder,
            isRealtime: isRealtime
        )
    }

    var content: HomeTimelinePublishedContentState {
        HomeTimelinePublishedContentState(
            resolvedRelays: resolvedRelays,
            followedPubkeys: followedPubkeys,
            hasMoreOlder: hasMoreOlder
        )
    }

    var relayStatus: HomeTimelinePublishedRelayStatusState {
        HomeTimelinePublishedRelayStatusState(
            runtimeStates: relayStatusSnapshot.runtimeStates,
            connectedRelayCount: relayStatusSnapshot.connectedRelayCount,
            plannedRelayCount: relayStatusSnapshot.plannedRelayCount,
            revision: relayStatusRevision
        )
    }

    var listProjection: HomeTimelinePublishedListProjectionState {
        HomeTimelinePublishedListProjectionState(
            revision: listProjectionRevision
        )
    }

    var pendingEvents: HomeTimelinePublishedPendingEventState {
        HomeTimelinePublishedPendingEventState(count: pendingEventCount)
    }
}

extension HomeTimelinePublishedStateCoordinator {
    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        guard let next = content.applying(snapshot) else { return }
        if resolvedRelays != next.resolvedRelays {
            resolvedRelays = next.resolvedRelays
        }
        if followedPubkeys != next.followedPubkeys {
            followedPubkeys = next.followedPubkeys
        }
        if hasMoreOlder != next.hasMoreOlder {
            hasMoreOlder = next.hasMoreOlder
        }
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        guard let next = activity.applying(transition) else { return }
        let changes = transition.changes
        if changes.contains(.phase) {
            phase = next.phase
        }
        if changes.contains(.refreshing) {
            isRefreshing = next.isRefreshing
        }
        if changes.contains(.loadingOlder) {
            isLoadingOlder = next.isLoadingOlder
        }
        if changes.contains(.realtime) {
            isRealtime = next.isRealtime
        }
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        guard let next = presentation.applying(transition) else { return }
        let changes = transition.changes
        if changes.contains(.entries) {
            entries = next.entries
        }
        if changes.contains(.unreadCounts) {
            if materializedUnreadCount != next.materializedUnreadCount {
                materializedUnreadCount = next.materializedUnreadCount
            }
            if visibleUnreadBadgeCount != next.visibleUnreadBadgeCount {
                visibleUnreadBadgeCount = next.visibleUnreadBadgeCount
            }
        }
        if changes.contains(.filterStatus) {
            filterStatus = next.filterStatus
        }
        if changes.contains(.resolvedContentRevision) {
            resolvedContentRevision = next.resolvedContentRevision
        }
        if changes.contains(.realtimeFollowSourceRevision) {
            realtimeFollowSourceRevision = next.realtimeFollowSourceRevision
        }
    }

    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool = false
    ) {
        guard let next = relayStatus.applying(
            snapshot,
            publishingStatusChange: publishingStatusChange
        ) else { return }
        if relayStatusSnapshot != next.snapshot {
            relayStatusSnapshot = next.snapshot
        }
        if relayStatusRevision != next.revision {
            relayStatusRevision = next.revision
        }
    }

    @discardableResult
    func applyRelayStatusTransition(
        _ transition: HomeTimelineRelayStatusTransition?
    ) -> String? {
        guard let transition else { return nil }
        applyRelayStatusSnapshot(
            transition.snapshot,
            publishingStatusChange: transition.publishesStatusChange
        )
        return transition.invalidatedRealtimeRelayURL
    }

    func publishRelayStatusChange() {
        relayStatusRevision &+= 1
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        guard let next = accountContext.applying(transition) else { return }
        if account != next.account {
            account = next.account
        }
        if syncPolicy != next.syncPolicy {
            syncPolicy = next.syncPolicy
        }
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        guard let next = pendingEvents.applying(publication) else { return }
        pendingEventCount = next.count
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        guard let next = listProjection.applying(invalidation) else { return }
        listProjectionRevision = next.revision
    }
}
