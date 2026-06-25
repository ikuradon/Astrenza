import Foundation

enum TimelinePrefetchIntent: String, Equatable, Codable, Sendable {
    case projectionCache
    case mediaCacheMetadata
}

struct TimelinePrefetchRequest: Equatable, Sendable {
    var entryIDs: [TimelineEntryID]
    var intents: [TimelinePrefetchIntent]
    var allowsNetworkRequests: Bool
}

final class TimelinePrefetchCoordinator {
    private(set) var latestRequest: TimelinePrefetchRequest?
    private(set) var cancelledIDs: [TimelineEntryID] = []

    func preparePrefetch(
        for entryIDs: [TimelineEntryID],
        intents: [TimelinePrefetchIntent] = [.projectionCache, .mediaCacheMetadata]
    ) -> TimelinePrefetchRequest {
        let request = TimelinePrefetchRequest(
            entryIDs: Self.uniquePreservingOrder(entryIDs),
            intents: intents,
            allowsNetworkRequests: false
        )
        latestRequest = request
        return request
    }

    func cancelPrefetch(for entryIDs: [TimelineEntryID]) {
        cancelledIDs = Self.uniquePreservingOrder(entryIDs)
    }

    private static func uniquePreservingOrder(_ ids: [TimelineEntryID]) -> [TimelineEntryID] {
        var seen = Set<TimelineEntryID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
