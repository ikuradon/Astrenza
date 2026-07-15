struct HomeTimelinePublishedListProjectionState {
    private(set) var revision: Int

    init(revision: Int = 0) {
        self.revision = revision
    }

    func applying(
        _ invalidation: HomeTimelineListProjectionInvalidation
    ) -> HomeTimelinePublishedListProjectionState? {
        guard revision != invalidation.revision else { return nil }
        var next = self
        next.revision = invalidation.revision
        return next
    }
}
