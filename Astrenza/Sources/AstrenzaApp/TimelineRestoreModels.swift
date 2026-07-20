import CoreGraphics
import Foundation

struct TimelineViewportState: Codable, Equatable {
    let accountID: String
    let timelineKey: String
    var anchorPostID: TimelinePost.ID
    var anchorOffset: CGFloat
    var contentOffset: CGFloat
    var updatedAt: Date

    static func storageKey(accountID: String, timelineKey: String) -> String {
        "timeline.viewport.\(accountID).\(timelineKey)"
    }
}

struct TimelineViewportAnchor: Equatable {
    let postID: TimelinePost.ID
    let offset: CGFloat
}

enum TimelinePullRefreshAnchorPolicy {
    static func prependedAnchor(
        _ anchor: TimelineViewportAnchor,
        oldIDs: [TimelineFeedEntry.ID],
        newIDs: [TimelineFeedEntry.ID]
    ) -> TimelineViewportAnchor? {
        guard let oldAnchorIndex = oldIDs.firstIndex(of: anchor.postID),
              let newAnchorIndex = newIDs.firstIndex(of: anchor.postID),
              newAnchorIndex > oldAnchorIndex
        else { return nil }
        return anchor
    }
}

struct TimelineScrollCommand: Equatable, Identifiable {
    enum Target: Equatable {
        case top
        case viewport(TimelineViewportState)
    }

    let id = UUID()
    let target: Target

    static func == (lhs: TimelineScrollCommand, rhs: TimelineScrollCommand) -> Bool {
        lhs.id == rhs.id
    }
}

struct TimelineLayoutCache: Codable, Equatable {
    var measuredHeights: [TimelinePost.ID: CGFloat] = [:]

    mutating func merge(measuredFrames: [TimelinePost.ID: CGRect]) {
        for (postID, frame) in measuredFrames where frame.height > 0 {
            measuredHeights[postID] = frame.height
        }
    }

    @discardableResult
    mutating func recordMeasuredHeight(
        _ height: CGFloat,
        for postID: TimelinePost.ID,
        changeThreshold: CGFloat = 0.5
    ) -> Bool {
        guard height > 0 else { return false }
        if let previousHeight = measuredHeights[postID],
           abs(previousHeight - height) <= changeThreshold {
            return false
        }

        measuredHeights[postID] = height
        return true
    }

    mutating func prune(keeping postIDs: Set<TimelinePost.ID>) {
        measuredHeights = measuredHeights.filter { postIDs.contains($0.key) }
    }

    @discardableResult
    mutating func invalidate(postIDs: Set<TimelinePost.ID>) -> Bool {
        var didInvalidate = false
        for postID in postIDs where measuredHeights.removeValue(forKey: postID) != nil {
            didInvalidate = true
        }
        return didInvalidate
    }

    func height(for post: TimelinePost) -> CGFloat {
        measuredHeights[post.id] ?? TimelineLayoutEstimator.estimatedHeight(for: post)
    }
}

enum TimelineContentHeightAnchorPlanner {
    static func changedPostIDs(
        oldEntries: [TimelineFeedEntry],
        newEntries: [TimelineFeedEntry]
    ) -> Set<TimelinePost.ID> {
        guard oldEntries.count == newEntries.count else { return [] }
        var changedPostIDs = Set<TimelinePost.ID>()

        for index in oldEntries.indices {
            let oldEntry = oldEntries[index]
            let newEntry = newEntries[index]
            guard oldEntry.id == newEntry.id else { return [] }
            guard TimelineRenderFingerprint.entry(oldEntry) != TimelineRenderFingerprint.entry(newEntry)
            else { continue }

            if case .post(let oldPost) = oldEntry {
                changedPostIDs.insert(oldPost.id)
            }
            if case .post(let newPost) = newEntry {
                changedPostIDs.insert(newPost.id)
            }
        }

        return changedPostIDs
    }

    static func changedPostIDsAffectingAnchor(
        entries: [TimelineFeedEntry],
        changedPostIDs: Set<TimelinePost.ID>,
        anchorPostID: TimelinePost.ID
    ) -> Set<TimelinePost.ID> {
        var affectingPostIDs = Set<TimelinePost.ID>()

        for entry in entries {
            if let postID = entry.post?.id, changedPostIDs.contains(postID) {
                affectingPostIDs.insert(postID)
            }
            if entry.id == anchorPostID {
                return affectingPostIDs
            }
        }

        return []
    }

    static func changedCommonPostIDsAffectingAnchor(
        oldEntries: [TimelineFeedEntry],
        newEntries: [TimelineFeedEntry],
        anchorPostID: TimelinePost.ID
    ) -> Set<TimelinePost.ID> {
        var oldFingerprintsByPostID: [TimelinePost.ID: Int] = [:]
        var foundOldAnchor = false
        for entry in oldEntries {
            if case .post(let post) = entry {
                oldFingerprintsByPostID[post.id] = TimelineRenderFingerprint.entry(entry)
            }
            if entry.id == anchorPostID {
                foundOldAnchor = true
                break
            }
        }
        guard foundOldAnchor else { return [] }

        var changedPostIDs = Set<TimelinePost.ID>()
        for entry in newEntries {
            if case .post(let post) = entry,
               let oldFingerprint = oldFingerprintsByPostID[post.id],
               oldFingerprint != TimelineRenderFingerprint.entry(entry) {
                changedPostIDs.insert(post.id)
            }
            if entry.id == anchorPostID {
                return changedPostIDs
            }
        }

        return []
    }

    static func insertedPostIDsAffectingAnchor(
        oldEntries: [TimelineFeedEntry],
        newEntries: [TimelineFeedEntry],
        anchorPostID: TimelinePost.ID
    ) -> Set<TimelinePost.ID> {
        let oldPostIDs = Set(oldEntries.compactMap { $0.post?.id })
        var insertedPostIDs = Set<TimelinePost.ID>()

        for entry in newEntries {
            if let postID = entry.post?.id, !oldPostIDs.contains(postID) {
                insertedPostIDs.insert(postID)
            }
            if entry.id == anchorPostID {
                return insertedPostIDs
            }
        }

        return []
    }
}

struct TimelineLayoutSnapshot {
    private let offsets: [(postID: TimelinePost.ID, minY: CGFloat, maxY: CGFloat)]
    private let offsetIndexByPostID: [TimelinePost.ID: Int]
    private var heightDeltas: TimelineHeightDeltaIndex

    init(posts: [TimelinePost], layoutCache: TimelineLayoutCache, topContentPadding: CGFloat) {
        var nextOffsets: [(postID: TimelinePost.ID, minY: CGFloat, maxY: CGFloat)] = []
        var nextOffsetIndexByPostID: [TimelinePost.ID: Int] = [:]
        nextOffsets.reserveCapacity(posts.count)
        nextOffsetIndexByPostID.reserveCapacity(posts.count)

        var offset = topContentPadding
        for post in posts {
            let height = layoutCache.height(for: post)
            nextOffsetIndexByPostID[post.id] = nextOffsets.count
            nextOffsets.append((postID: post.id, minY: offset, maxY: offset + height))
            offset += height
        }

        offsets = nextOffsets
        offsetIndexByPostID = nextOffsetIndexByPostID
        heightDeltas = TimelineHeightDeltaIndex(count: nextOffsets.count)
    }

    init(entries: [TimelineFeedEntry], layoutCache: TimelineLayoutCache, topContentPadding: CGFloat) {
        var nextOffsets: [(postID: TimelinePost.ID, minY: CGFloat, maxY: CGFloat)] = []
        var nextOffsetIndexByPostID: [TimelinePost.ID: Int] = [:]
        nextOffsets.reserveCapacity(entries.count)
        nextOffsetIndexByPostID.reserveCapacity(entries.count)

        var offset = topContentPadding
        for entry in entries {
            switch entry {
            case .post(let post):
                let height = layoutCache.height(for: post)
                nextOffsetIndexByPostID[post.id] = nextOffsets.count
                nextOffsets.append((postID: post.id, minY: offset, maxY: offset + height))
                offset += height
            case .gap(let gap):
                offset += TimelineLayoutEstimator.estimatedHeight(for: gap)
            case .deleted:
                offset += TimelineLayoutEstimator.estimatedHeightForDeletedRow
            }
        }

        offsets = nextOffsets
        offsetIndexByPostID = nextOffsetIndexByPostID
        heightDeltas = TimelineHeightDeltaIndex(count: nextOffsets.count)
    }

    /// 同じentry集合のrow再計測はprefix差分だけを更新し、全snapshotを再構築しません。
    @discardableResult
    mutating func recordMeasuredHeight(
        _ height: CGFloat,
        for postID: TimelinePost.ID,
        changeThreshold: CGFloat = 0.5
    ) -> Bool {
        guard height > 0,
              let index = offsetIndexByPostID[postID]
        else { return false }

        let baseHeight = offsets[index].maxY - offsets[index].minY
        let currentHeight = baseHeight + heightDeltas.value(at: index)
        let delta = height - currentHeight
        guard abs(delta) > changeThreshold else { return false }

        heightDeltas.add(delta, at: index)
        return true
    }

    func anchor(at contentOffset: CGFloat, anchorLineY: CGFloat) -> TimelineViewportAnchor? {
        let targetY = contentOffset + anchorLineY
        var lowerBound = 0
        var upperBound = offsets.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if maxY(at: middle) <= targetY {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        if lowerBound < offsets.count {
            let candidate = offsets[lowerBound]
            let candidateMinY = minY(at: lowerBound)
            if candidateMinY <= targetY {
                return TimelineViewportAnchor(
                    postID: candidate.postID,
                    offset: max(0, targetY - candidateMinY)
                )
            }
            return TimelineViewportAnchor(postID: candidate.postID, offset: 0)
        }

        guard let last = offsets.last else { return nil }
        return TimelineViewportAnchor(
            postID: last.postID,
            offset: max(0, targetY - minY(at: offsets.count - 1))
        )
    }

    func offset(for postID: TimelinePost.ID) -> CGFloat? {
        guard let index = offsetIndexByPostID[postID] else { return nil }
        return minY(at: index)
    }

    private func minY(at index: Int) -> CGFloat {
        offsets[index].minY + heightDeltas.prefixSum(before: index)
    }

    private func maxY(at index: Int) -> CGFloat {
        offsets[index].maxY + heightDeltas.prefixSum(through: index)
    }
}

private struct TimelineHeightDeltaIndex {
    private var tree: [CGFloat]

    init(count: Int) {
        tree = Array(repeating: 0, count: count + 1)
    }

    mutating func add(_ delta: CGFloat, at index: Int) {
        var treeIndex = index + 1
        while treeIndex < tree.count {
            tree[treeIndex] += delta
            treeIndex += treeIndex & -treeIndex
        }
    }

    func value(at index: Int) -> CGFloat {
        prefixSum(through: index) - prefixSum(before: index)
    }

    func prefixSum(before index: Int) -> CGFloat {
        prefixSum(count: index)
    }

    func prefixSum(through index: Int) -> CGFloat {
        prefixSum(count: index + 1)
    }

    private func prefixSum(count: Int) -> CGFloat {
        var total: CGFloat = 0
        var treeIndex = min(max(count, 0), tree.count - 1)
        while treeIndex > 0 {
            total += tree[treeIndex]
            treeIndex -= treeIndex & -treeIndex
        }
        return total
    }
}

enum TimelineViewportResolver {
    static func restoredContentOffsetY(
        posts: [TimelinePost],
        state: TimelineViewportState,
        layoutCache: TimelineLayoutCache,
        topContentPadding: CGFloat,
        anchorLineY: CGFloat
    ) -> CGFloat? {
        let snapshot = TimelineLayoutSnapshot(posts: posts, layoutCache: layoutCache, topContentPadding: topContentPadding)
        return restoredContentOffsetY(snapshot: snapshot, state: state, anchorLineY: anchorLineY)
    }

    static func restoredContentOffsetY(
        entries: [TimelineFeedEntry],
        state: TimelineViewportState,
        layoutCache: TimelineLayoutCache,
        topContentPadding: CGFloat,
        anchorLineY: CGFloat
    ) -> CGFloat? {
        let snapshot = TimelineLayoutSnapshot(entries: entries, layoutCache: layoutCache, topContentPadding: topContentPadding)
        return restoredContentOffsetY(snapshot: snapshot, state: state, anchorLineY: anchorLineY)
    }

    static func restoredContentOffsetY(
        snapshot: TimelineLayoutSnapshot,
        state: TimelineViewportState,
        anchorLineY: CGFloat
    ) -> CGFloat? {
        if let anchorTopY = snapshot.offset(for: state.anchorPostID) {
            let restoredOffset = anchorTopY - anchorLineY + state.anchorOffset
            return max(restoredOffset, 0)
        }

        return state.contentOffset > 0 ? state.contentOffset : nil
    }

    static func contentOffsetPreservingAnchor(
        entries: [TimelineFeedEntry],
        anchor: TimelineViewportAnchor,
        layoutCache: TimelineLayoutCache,
        topContentPadding: CGFloat,
        anchorLineY: CGFloat
    ) -> CGFloat? {
        let snapshot = TimelineLayoutSnapshot(entries: entries, layoutCache: layoutCache, topContentPadding: topContentPadding)
        return contentOffsetPreservingAnchor(
            snapshot: snapshot,
            anchor: anchor,
            anchorLineY: anchorLineY
        )
    }

    static func contentOffsetPreservingAnchor(
        snapshot: TimelineLayoutSnapshot,
        anchor: TimelineViewportAnchor,
        anchorLineY: CGFloat
    ) -> CGFloat? {
        guard let anchorTopY = snapshot.offset(for: anchor.postID) else { return nil }
        return max(anchorTopY - anchorLineY + anchor.offset, 0)
    }
}

enum TimelineLayoutEstimator {
    static let estimatedHeightForDeletedRow: CGFloat = 44

    static func estimatedHeight(for gap: TimelineGap) -> CGFloat {
        74
    }

    static func estimatedReplacementDelta(for gap: TimelineGap, layoutCache: TimelineLayoutCache) -> CGFloat {
        let insertedHeight = gap.backfilledPosts.reduce(CGFloat.zero) { height, post in
            height + layoutCache.height(for: post)
        }

        return max(0, insertedHeight - estimatedHeight(for: gap))
    }

    static func estimatedHeight(for post: TimelinePost) -> CGFloat {
        var height: CGFloat = 92
        height += bodyHeight(for: post)

        if post.repostedBy != nil {
            height += 25
        }

        if post.replyContext != nil {
            height += 44
        }

        if post.quotedPost != nil {
            height += 126
        }

        if let media = post.media {
            height += mediaEstimatedHeight(media)
        }

        if post.contentWarning != nil {
            height = max(height, 236)
        }

        if post.bodyPresentation.collapseReason != nil || post.linkSummary != nil {
            height += 26
        }

        return height
    }

    private static func bodyHeight(for post: TimelinePost) -> CGFloat {
        let lineLimit = post.bodyPresentation.timelineLineLimit
        let estimatedLineCount = max(1, Int(ceil(Double(post.body.count) / 34.0)))
        let visibleLineCount = lineLimit.map { min($0, estimatedLineCount) } ?? estimatedLineCount
        return CGFloat(visibleLineCount) * 22
    }

    private static func mediaEstimatedHeight(_ media: TimelineMedia) -> CGFloat {
        switch media {
        case .gallery(let tiles):
            return galleryEstimatedHeight(tiles)
        case .linkPreview(let preview):
            return preview.imageURL == nil ? 226 : 252
        case .unresolvedLink:
            return 72
        }
    }

    private static func galleryEstimatedHeight(_ tiles: [MediaTile]) -> CGFloat {
        let estimatedWidth: CGFloat = 414
        switch tiles.count {
        case 1:
            return TimelineMediaLayoutMetrics.singleMediaSize(
                aspectRatio: tiles.first?.aspectRatio,
                availableWidth: estimatedWidth
            ).height
        default:
            return TimelineMediaLayoutMetrics.galleryGridSize(
                tileCount: tiles.count,
                availableWidth: estimatedWidth,
                spacing: AstrenzaSpacing.point2
            ).height
        }
    }
}

final class TimelineRestoreStore {
    private struct PendingViewportSave {
        let token: UUID
        let state: TimelineViewportState
    }

    private struct PendingLayoutCacheSave {
        let token: UUID
        let cache: TimelineLayoutCache
        let accountID: String
        let timelineKey: String
    }

    private let defaults: UserDefaults
    @MainActor private var pendingViewportSaves: [String: PendingViewportSave] = [:]
    @MainActor private var pendingViewportSaveTasks: [String: Task<Void, Never>] = [:]
    @MainActor private var pendingLayoutCacheSaves: [String: PendingLayoutCacheSave] = [:]
    @MainActor private var pendingLayoutCacheSaveTasks: [String: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func viewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        decode(TimelineViewportState.self, key: TimelineViewportState.storageKey(accountID: accountID, timelineKey: timelineKey))
    }

    @MainActor
    func latestViewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        let key = TimelineViewportState.storageKey(accountID: accountID, timelineKey: timelineKey)
        return pendingViewportSaves[key]?.state ?? viewportState(accountID: accountID, timelineKey: timelineKey)
    }

    func saveViewportState(_ state: TimelineViewportState) {
        encode(state, key: TimelineViewportState.storageKey(accountID: state.accountID, timelineKey: state.timelineKey))
    }

    @MainActor
    func scheduleViewportStateSave(_ state: TimelineViewportState, delay: TimeInterval = 0.75) {
        let key = TimelineViewportState.storageKey(accountID: state.accountID, timelineKey: state.timelineKey)
        let token = UUID()
        pendingViewportSaveTasks[key]?.cancel()
        pendingViewportSaves[key] = PendingViewportSave(token: token, state: state)
        pendingViewportSaveTasks[key] = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.commitViewportSave(key: key, token: token)
        }
    }

    func layoutCache(accountID: String, timelineKey: String) -> TimelineLayoutCache {
        decode(TimelineLayoutCache.self, key: layoutCacheKey(accountID: accountID, timelineKey: timelineKey)) ?? TimelineLayoutCache()
    }

    func saveLayoutCache(_ cache: TimelineLayoutCache, accountID: String, timelineKey: String) {
        encode(cache, key: layoutCacheKey(accountID: accountID, timelineKey: timelineKey))
    }

    @MainActor
    func scheduleLayoutCacheSave(
        _ cache: TimelineLayoutCache,
        accountID: String,
        timelineKey: String,
        delay: TimeInterval = 0.75
    ) {
        let key = layoutCacheKey(accountID: accountID, timelineKey: timelineKey)
        let token = UUID()
        pendingLayoutCacheSaveTasks[key]?.cancel()
        pendingLayoutCacheSaves[key] = PendingLayoutCacheSave(
            token: token,
            cache: cache,
            accountID: accountID,
            timelineKey: timelineKey
        )
        pendingLayoutCacheSaveTasks[key] = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.commitLayoutCacheSave(key: key, token: token)
        }
    }

    @MainActor
    func flushPendingSaves() {
        pendingViewportSaveTasks.values.forEach { $0.cancel() }
        pendingViewportSaveTasks.removeAll()
        let viewportSaves = Array(pendingViewportSaves.values)
        pendingViewportSaves.removeAll()
        viewportSaves.forEach { saveViewportState($0.state) }

        pendingLayoutCacheSaveTasks.values.forEach { $0.cancel() }
        pendingLayoutCacheSaveTasks.removeAll()
        let layoutCacheSaves = Array(pendingLayoutCacheSaves.values)
        pendingLayoutCacheSaves.removeAll()
        layoutCacheSaves.forEach {
            saveLayoutCache($0.cache, accountID: $0.accountID, timelineKey: $0.timelineKey)
        }
    }

    private func layoutCacheKey(accountID: String, timelineKey: String) -> String {
        "timeline.layout.\(accountID).\(timelineKey)"
    }

    @MainActor
    private func commitViewportSave(key: String, token: UUID) {
        guard let pendingSave = pendingViewportSaves[key], pendingSave.token == token else { return }
        pendingViewportSaves[key] = nil
        pendingViewportSaveTasks[key] = nil
        saveViewportState(pendingSave.state)
    }

    @MainActor
    private func commitLayoutCacheSave(key: String, token: UUID) {
        guard let pendingSave = pendingLayoutCacheSaves[key], pendingSave.token == token else { return }
        pendingLayoutCacheSaves[key] = nil
        pendingLayoutCacheSaveTasks[key] = nil
        saveLayoutCache(
            pendingSave.cache,
            accountID: pendingSave.accountID,
            timelineKey: pendingSave.timelineKey
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
