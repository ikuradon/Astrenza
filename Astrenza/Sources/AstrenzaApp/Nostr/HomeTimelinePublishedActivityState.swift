struct HomeTimelinePublishedActivityState {
    private(set) var phase: NostrHomeTimelinePhase
    private(set) var isRefreshing: Bool
    private(set) var isLoadingOlder: Bool
    private(set) var isRealtime: Bool

    init(
        phase: NostrHomeTimelinePhase = .idle,
        isRefreshing: Bool = false,
        isLoadingOlder: Bool = false,
        isRealtime: Bool = false
    ) {
        self.phase = phase
        self.isRefreshing = isRefreshing
        self.isLoadingOlder = isLoadingOlder
        self.isRealtime = isRealtime
    }

    func applying(
        _ transition: HomeTimelineActivityTransition
    ) -> HomeTimelinePublishedActivityState? {
        let changes = transition.changes
        let snapshot = transition.snapshot
        var next = self
        var didMutate = false

        if changes.contains(.phase) {
            next.phase = snapshot.phase
            didMutate = true
        }
        if changes.contains(.refreshing) {
            next.isRefreshing = snapshot.isRefreshing
            didMutate = true
        }
        if changes.contains(.loadingOlder) {
            next.isLoadingOlder = snapshot.isLoadingOlder
            didMutate = true
        }
        if changes.contains(.realtime) {
            next.isRealtime = snapshot.isRealtime
            didMutate = true
        }
        return didMutate ? next : nil
    }
}
