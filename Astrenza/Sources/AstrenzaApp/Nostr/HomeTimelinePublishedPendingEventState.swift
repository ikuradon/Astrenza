struct HomeTimelinePublishedPendingEventState {
    private(set) var count: Int

    init(count: Int = 0) {
        self.count = count
    }

    func applying(
        _ publication: HomeTimelinePendingEventCountPublication
    ) -> HomeTimelinePublishedPendingEventState? {
        guard count != publication.count else { return nil }
        var next = self
        next.count = publication.count
        return next
    }
}
