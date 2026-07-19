import CoreGraphics
import Foundation

@MainActor
final class TimelineFeedRowHeightCoordinator {
    private(set) var layoutCache = TimelineLayoutCache()
    private var hasPendingChanges = false
    private var isScrollActive = false
    private var publishTask: Task<Void, Never>?
    private var onLayoutCacheChanged: (TimelineLayoutCache) -> Void = { _ in }

    func configure(
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void
    ) {
        self.onLayoutCacheChanged = onLayoutCacheChanged
    }

    func reset(layoutCache: TimelineLayoutCache) {
        publishTask?.cancel()
        publishTask = nil
        hasPendingChanges = false
        self.layoutCache = layoutCache
    }

    func prepareForEntries(
        oldEntries: [TimelineFeedEntry],
        newEntries: [TimelineFeedEntry]
    ) {
        let changedPostIDs = TimelineContentHeightAnchorPlanner
            .changedPostIDs(
                oldEntries: oldEntries,
                newEntries: newEntries
            )
        let didInvalidate = layoutCache.invalidate(
            postIDs: changedPostIDs
        )
        let previousCount = layoutCache.measuredHeights.count
        layoutCache.prune(
            keeping: Set(newEntries.compactMap { $0.post?.id })
        )
        if didInvalidate || layoutCache.measuredHeights.count != previousCount {
            markChanged()
        }
    }

    func estimatedHeight(for entry: TimelineFeedEntry) -> CGFloat {
        switch entry {
        case .post(let post):
            layoutCache.height(for: post)
        case .gap(let gap):
            TimelineLayoutEstimator.estimatedHeight(for: gap)
        case .deleted:
            TimelineLayoutEstimator.estimatedHeightForDeletedRow
        }
    }

    func recordMeasuredHeight(
        _ height: CGFloat,
        for postID: TimelinePost.ID
    ) {
        guard layoutCache.recordMeasuredHeight(height, for: postID)
        else { return }
        markChanged()
    }

    func setScrollActive(_ isActive: Bool) {
        guard isScrollActive != isActive else { return }
        isScrollActive = isActive
        if isActive {
            publishTask?.cancel()
            publishTask = nil
        } else {
            schedulePublishIfNeeded()
        }
    }

    func flush() {
        publishTask?.cancel()
        publishTask = nil
        guard hasPendingChanges else { return }
        hasPendingChanges = false
        onLayoutCacheChanged(layoutCache)
    }

    private func markChanged() {
        hasPendingChanges = true
        schedulePublishIfNeeded()
    }

    private func schedulePublishIfNeeded() {
        publishTask?.cancel()
        publishTask = nil
        guard hasPendingChanges, !isScrollActive else { return }

        publishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let self,
                  hasPendingChanges,
                  !isScrollActive
            else { return }
            publishTask = nil
            hasPendingChanges = false
            onLayoutCacheChanged(layoutCache)
        }
    }
}
