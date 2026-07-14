@MainActor
final class HomeTimelineListProjectionCache {
    struct Key: Equatable, Sendable {
        let accountID: String
        let limit: Int
        let homeContentRevision: Int
    }

    private struct Record {
        let key: Key
        let revision: Int
        let entries: [TimelineFeedEntry]
    }

    private var record: Record?

    private(set) var revision = 0

    func entries(
        for key: Key,
        materialize: () -> [TimelineFeedEntry]
    ) -> [TimelineFeedEntry] {
        if let record,
           record.key == key,
           record.revision == revision {
            return record.entries
        }

        let entries = materialize()
        record = Record(
            key: key,
            revision: revision,
            entries: entries
        )
        return entries
    }

    @discardableResult
    func invalidate() -> Int {
        record = nil
        revision &+= 1
        return revision
    }
}
