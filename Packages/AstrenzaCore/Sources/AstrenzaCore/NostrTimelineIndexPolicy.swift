import Foundation

public struct NostrTimelineIndexCandidate: Equatable, Sendable {
    public let eventID: String
    public let sortTimestamp: Int
    public let insertedAt: Int
    public let gapBefore: Bool
    public let gapAfter: Bool

    public init(
        eventID: String,
        sortTimestamp: Int,
        insertedAt: Int,
        gapBefore: Bool,
        gapAfter: Bool
    ) {
        self.eventID = eventID
        self.sortTimestamp = sortTimestamp
        self.insertedAt = insertedAt
        self.gapBefore = gapBefore
        self.gapAfter = gapAfter
    }
}

public struct NostrTimelineIndexPolicy: Equatable, Sendable {
    public let recentLimit: Int
    public let anchorRadius: Int
    public let retainedAgeSeconds: Int

    public init(recentLimit: Int, anchorRadius: Int, retainedAgeSeconds: Int) {
        self.recentLimit = max(0, recentLimit)
        self.anchorRadius = max(0, anchorRadius)
        self.retainedAgeSeconds = max(0, retainedAgeSeconds)
    }

    public func retainedEventIDs(
        from entries: [NostrTimelineIndexCandidate],
        anchorEventID: String?,
        now: Int
    ) -> Set<String> {
        let sorted = entries.sorted {
            if $0.sortTimestamp == $1.sortTimestamp {
                return $0.eventID < $1.eventID
            }
            return $0.sortTimestamp > $1.sortTimestamp
        }

        var retained = Set(sorted.prefix(recentLimit).map(\.eventID))

        for entry in sorted where entry.gapBefore || entry.gapAfter {
            retained.insert(entry.eventID)
        }

        for entry in sorted where now - entry.insertedAt <= retainedAgeSeconds {
            retained.insert(entry.eventID)
        }

        if let anchorEventID,
           let anchorIndex = sorted.firstIndex(where: { $0.eventID == anchorEventID }) {
            let lowerBound = max(0, anchorIndex - anchorRadius)
            let upperBound = min(sorted.count - 1, anchorIndex + anchorRadius)
            if lowerBound <= upperBound {
                for index in lowerBound...upperBound {
                    retained.insert(sorted[index].eventID)
                }
            }
        }

        return retained
    }
}
