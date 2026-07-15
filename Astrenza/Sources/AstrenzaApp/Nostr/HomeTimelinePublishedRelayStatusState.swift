import AstrenzaCore

struct HomeTimelinePublishedRelayStatusState {
    private(set) var snapshot: HomeTimelineRelayStatusSnapshot
    private(set) var revision: Int

    init(
        runtimeStates: [String: NostrRelayConnectionState] = [:],
        connectedRelayCount: Int = 0,
        plannedRelayCount: Int = 1,
        revision: Int = 0
    ) {
        snapshot = HomeTimelineRelayStatusSnapshot(
            runtimeStates: runtimeStates,
            connectedRelayCount: connectedRelayCount,
            plannedRelayCount: plannedRelayCount
        )
        self.revision = revision
    }

    func applying(
        _ snapshot: HomeTimelineRelayStatusSnapshot,
        publishingStatusChange: Bool = false
    ) -> HomeTimelinePublishedRelayStatusState? {
        var next = self
        var didMutate = false

        if next.snapshot != snapshot {
            next.snapshot = snapshot
            didMutate = true
        }
        if publishingStatusChange {
            next.revision &+= 1
            didMutate = true
        }
        return didMutate ? next : nil
    }

    func publishingStatusChange() -> HomeTimelinePublishedRelayStatusState {
        var next = self
        next.revision &+= 1
        return next
    }
}
