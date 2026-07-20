import AstrenzaCore

struct HomeTimelineProfileProjection {
    let profile: UserProfile
    let posts: [TimelinePost]
}

@MainActor
final class HomeTimelineProfileProjectionCache {
    struct Key: Equatable {
        let accountID: String?
        let pubkey: String
        let isCurrentUser: Bool
        let postsLimit: Int
        let homeContentRevision: Int
        let listContentRevision: Int
        let profileDataRevision: Int
        let resolvedRelayCount: Int
        let syncPolicy: NostrSyncPolicy
    }

    private struct Record {
        let key: Key
        let projection: HomeTimelineProfileProjection
    }

    private let capacity: Int
    private var records: [Record] = []

    init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    func projection(
        for key: Key,
        materialize: () -> HomeTimelineProfileProjection
    ) -> HomeTimelineProfileProjection {
        if let index = records.firstIndex(where: { $0.key == key }) {
            let record = records.remove(at: index)
            records.append(record)
            return record.projection
        }

        let projection = materialize()
        records.append(Record(key: key, projection: projection))
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
        return projection
    }
}
