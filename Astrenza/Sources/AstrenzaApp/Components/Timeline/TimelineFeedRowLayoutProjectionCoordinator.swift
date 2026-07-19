import CoreGraphics
import Foundation

@MainActor
final class TimelineFeedRowLayoutProjectionCoordinator {
    private(set) var layoutCache = TimelineLayoutCache()
    private var stagedMeasurements: [TimelineFeedEntry.ID: CGFloat] = [:]
    private var stagedInvalidations = Set<TimelineFeedEntry.ID>()
    private var hasPendingChanges = false
    private var isScrollActive = false
    private var isProjectionMutationSuspended = false
    private var projectionCommitTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var onLayoutCacheChanged: (TimelineLayoutCache) -> Void = { _ in }
    private var onProjectedHeightsChanged:
        ([TimelineFeedEntry.ID: CGFloat]) -> Void = { _ in }

    func configure(
        onLayoutCacheChanged: @escaping (TimelineLayoutCache) -> Void,
        onProjectedHeightsChanged:
            @escaping ([TimelineFeedEntry.ID: CGFloat]) -> Void = { _ in }
    ) {
        self.onLayoutCacheChanged = onLayoutCacheChanged
        self.onProjectedHeightsChanged = onProjectedHeightsChanged
    }

    func reset(layoutCache: TimelineLayoutCache) {
        projectionCommitTask?.cancel()
        projectionCommitTask = nil
        publishTask?.cancel()
        publishTask = nil
        stagedMeasurements = [:]
        stagedInvalidations = []
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
        stagedInvalidations.formUnion(changedPostIDs)
        for postID in changedPostIDs {
            stagedMeasurements.removeValue(forKey: postID)
        }
        let previousCount = layoutCache.measuredHeights.count
        layoutCache.prune(
            keeping: Set(newEntries.compactMap { $0.post?.id })
        )
        let retainedEntryIDs = Set(newEntries.map(\.id))
        stagedMeasurements = stagedMeasurements.filter {
            retainedEntryIDs.contains($0.key)
        }
        stagedInvalidations.formIntersection(retainedEntryIDs)
        if layoutCache.measuredHeights.count != previousCount {
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

    func stageMeasuredHeight(
        _ height: CGFloat,
        for entryID: TimelineFeedEntry.ID
    ) {
        guard height > 0 else { return }
        if let committedHeight = layoutCache.measuredHeights[entryID],
           abs(committedHeight - height) <= 0.5 {
            stagedMeasurements.removeValue(forKey: entryID)
            stagedInvalidations.remove(entryID)
            return
        }
        if let stagedHeight = stagedMeasurements[entryID],
           abs(stagedHeight - height) <= 0.5 {
            return
        }
        stagedMeasurements[entryID] = height
        scheduleProjectionCommitIfNeeded()
    }

    func setScrollActive(_ isActive: Bool) {
        guard isScrollActive != isActive else { return }
        isScrollActive = isActive
        if isActive {
            projectionCommitTask?.cancel()
            projectionCommitTask = nil
            publishTask?.cancel()
            publishTask = nil
        } else {
            scheduleProjectionCommitIfNeeded()
            schedulePublishIfNeeded()
        }
    }

    func setProjectionMutationSuspended(_ isSuspended: Bool) {
        guard isProjectionMutationSuspended != isSuspended else { return }
        isProjectionMutationSuspended = isSuspended
        if isSuspended {
            projectionCommitTask?.cancel()
            projectionCommitTask = nil
        } else {
            scheduleProjectionCommitIfNeeded()
        }
    }

    func flush() {
        projectionCommitTask?.cancel()
        projectionCommitTask = nil
        commitStagedMeasurements(notifyProjection: false)
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

    private func scheduleProjectionCommitIfNeeded() {
        projectionCommitTask?.cancel()
        projectionCommitTask = nil
        guard !stagedMeasurements.isEmpty,
              !isScrollActive,
              !isProjectionMutationSuspended
        else { return }

        projectionCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled,
                  let self,
                  !isScrollActive,
                  !isProjectionMutationSuspended
            else { return }
            projectionCommitTask = nil
            commitStagedMeasurements(notifyProjection: true)
        }
    }

    private func commitStagedMeasurements(notifyProjection: Bool) {
        guard !stagedMeasurements.isEmpty else { return }
        let staged = stagedMeasurements
        stagedMeasurements = [:]
        var committed: [TimelineFeedEntry.ID: CGFloat] = [:]
        committed.reserveCapacity(staged.count)
        for (entryID, height) in staged where
            layoutCache.recordMeasuredHeight(height, for: entryID) {
            committed[entryID] = height
        }
        stagedInvalidations.subtract(staged.keys)
        guard !committed.isEmpty else { return }
        if notifyProjection {
            onProjectedHeightsChanged(committed)
        }
        markChanged()
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
