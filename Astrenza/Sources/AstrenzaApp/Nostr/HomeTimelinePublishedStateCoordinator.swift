import AstrenzaCore
import Combine

@MainActor
final class HomeTimelinePublishedStateCoordinator: ObservableObject {
    @Published private(set) var accountContext:
        HomeTimelinePublishedAccountContextState
    @Published private(set) var presentation =
        HomeTimelinePublishedPresentationState()
    @Published private(set) var activity = HomeTimelinePublishedActivityState()
    @Published private(set) var content = HomeTimelinePublishedContentState()
    @Published private(set) var relayStatus =
        HomeTimelinePublishedRelayStatusState()
    @Published private(set) var listProjection =
        HomeTimelinePublishedListProjectionState()
    @Published private(set) var pendingEvents =
        HomeTimelinePublishedPendingEventState()

    init(syncPolicy: NostrSyncPolicy) {
        accountContext = HomeTimelinePublishedAccountContextState(
            syncPolicy: syncPolicy
        )
    }

    func applyContentSnapshot(_ snapshot: HomeTimelineContentSnapshot) {
        guard let next = content.applying(snapshot) else { return }
        content = next
    }

    func applyActivityTransition(
        _ transition: HomeTimelineActivityTransition
    ) {
        guard let next = activity.applying(transition) else { return }
        activity = next
    }

    func applyPresentationTransition(
        _ transition: HomeTimelinePresentationTransition
    ) {
        guard let next = presentation.applying(transition) else { return }
        presentation = next
    }

    func applyRelayStatusSnapshot(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool = false
    ) {
        guard let next = relayStatus.applying(
            snapshot,
            publishingStatusChange: publishingStatusChange
        ) else { return }
        relayStatus = next
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
        relayStatus = relayStatus.publishingStatusChange()
    }

    func applyAccountContextTransition(
        _ transition: HomeTimelineAccountContextTransition
    ) {
        guard let next = accountContext.applying(transition) else { return }
        accountContext = next
    }

    func applyPendingEventCountPublication(
        _ publication: HomeTimelinePendingEventCountPublication
    ) {
        guard let next = pendingEvents.applying(publication) else { return }
        pendingEvents = next
    }

    func applyListProjectionInvalidation(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) {
        guard let next = listProjection.applying(invalidation) else { return }
        listProjection = next
    }
}
