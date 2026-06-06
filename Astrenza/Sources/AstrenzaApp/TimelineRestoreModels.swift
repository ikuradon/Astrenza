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

struct TimelineLayoutCache: Codable, Equatable {
    var measuredHeights: [TimelinePost.ID: CGFloat] = [:]

    mutating func merge(measuredFrames: [TimelinePost.ID: CGRect]) {
        for (postID, frame) in measuredFrames where frame.height > 0 {
            measuredHeights[postID] = frame.height
        }
    }

    func height(for post: TimelinePost) -> CGFloat {
        measuredHeights[post.id] ?? TimelineLayoutEstimator.estimatedHeight(for: post)
    }
}

struct TimelineLayoutSnapshot {
    private let offsetsByPostID: [TimelinePost.ID: CGFloat]

    init(posts: [TimelinePost], layoutCache: TimelineLayoutCache, topContentPadding: CGFloat) {
        var nextOffsets: [TimelinePost.ID: CGFloat] = [:]
        nextOffsets.reserveCapacity(posts.count)

        var offset = topContentPadding
        for post in posts {
            nextOffsets[post.id] = offset
            offset += layoutCache.height(for: post)
        }

        offsetsByPostID = nextOffsets
    }

    init(entries: [TimelineFeedEntry], layoutCache: TimelineLayoutCache, topContentPadding: CGFloat) {
        var nextOffsets: [TimelinePost.ID: CGFloat] = [:]
        nextOffsets.reserveCapacity(entries.count)

        var offset = topContentPadding
        for entry in entries {
            switch entry {
            case .post(let post):
                nextOffsets[post.id] = offset
                offset += layoutCache.height(for: post)
            case .gap(let gap):
                offset += TimelineLayoutEstimator.estimatedHeight(for: gap)
            case .deleted:
                offset += TimelineLayoutEstimator.estimatedHeightForDeletedRow
            }
        }

        offsetsByPostID = nextOffsets
    }

    func offset(for postID: TimelinePost.ID) -> CGFloat? {
        offsetsByPostID[postID]
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
        if state.contentOffset > 0 {
            return state.contentOffset
        }

        guard let anchorTopY = snapshot.offset(for: state.anchorPostID) else { return nil }
        let restoredOffset = anchorTopY - anchorLineY + state.anchorOffset
        return max(restoredOffset, 0)
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
        case .gallery:
            return 218
        case .linkPreview:
            return 112
        case .unresolvedLink:
            return 72
        }
    }
}

final class TimelineRestoreStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func viewportState(accountID: String, timelineKey: String) -> TimelineViewportState? {
        decode(TimelineViewportState.self, key: TimelineViewportState.storageKey(accountID: accountID, timelineKey: timelineKey))
    }

    func saveViewportState(_ state: TimelineViewportState) {
        encode(state, key: TimelineViewportState.storageKey(accountID: state.accountID, timelineKey: state.timelineKey))
    }

    func layoutCache(accountID: String, timelineKey: String) -> TimelineLayoutCache {
        decode(TimelineLayoutCache.self, key: layoutCacheKey(accountID: accountID, timelineKey: timelineKey)) ?? TimelineLayoutCache()
    }

    func saveLayoutCache(_ cache: TimelineLayoutCache, accountID: String, timelineKey: String) {
        encode(cache, key: layoutCacheKey(accountID: accountID, timelineKey: timelineKey))
    }

    private func layoutCacheKey(accountID: String, timelineKey: String) -> String {
        "timeline.layout.\(accountID).\(timelineKey)"
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
