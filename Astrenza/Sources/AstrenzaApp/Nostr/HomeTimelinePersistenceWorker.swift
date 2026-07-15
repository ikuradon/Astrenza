import AstrenzaCore
import Foundation

enum HomeTimelinePersistenceProjection {
    static let retainedEventLimit = 480

    /// routine persistence用のsnapshotは、現在のmemory windowだけからboundedに生成します。
    static func boundedEvents(
        from noteEvents: [NostrEvent],
        allowedAuthors: Set<String>,
        limit: Int = retainedEventLimit
    ) -> [NostrEvent] {
        guard limit > 0 else { return [] }
        return Array(
            noteEvents
                .filter { event in
                    (event.kind == 1 || event.kind == 6) && allowedAuthors.contains(event.pubkey)
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id < rhs.id
                }
                .prefix(limit)
        )
    }
}

struct HomeTimelineFeedPersistenceSnapshot: Sendable {
    let state: NostrHomeTimelineState
    let accountID: String
    let definition: NostrFeedDefinitionRecord
    let memberships: [NostrFeedMembershipRecord]
    let membershipSources: [NostrFeedMembershipSourceRecord]
    let savedAt: Int
    let windowLimit: Int
}

actor HomeTimelinePersistenceWorker {
    private let eventStore: NostrEventStore

    init(eventStore: NostrEventStore) {
        self.eventStore = eventStore
    }

    func restoredState(accountID: String) -> NostrHomeTimelineState? {
        if let state = try? eventStore.homeFeedState(accountID: accountID) {
            return state
        }

        // V4以前の開発用DBだけをGeneric Feedへ移行するcompatibility pathです。
        return try? eventStore.legacyHomeTimelineStateForMigration(
            accountID: accountID
        )
    }

    func restoredReadState(feedID: String) throws -> NostrFeedReadStateRecord? {
        try eventStore.feedReadState(feedID: feedID)
    }

    func saveFeedSnapshot(
        _ snapshot: HomeTimelineFeedPersistenceSnapshot
    ) throws -> NostrFeedWindow? {
        try eventStore.saveHomeFeedState(
            snapshot.state,
            accountID: snapshot.accountID,
            definition: snapshot.definition,
            memberships: snapshot.memberships,
            membershipSources: snapshot.membershipSources,
            savedAt: snapshot.savedAt
        )
        return try eventStore.feedWindow(
            feedID: snapshot.definition.feedID,
            revision: snapshot.definition.revision,
            limit: snapshot.windowLimit,
            now: snapshot.savedAt
        )
    }

    func saveTimelineMetadata(
        _ state: NostrHomeTimelineState,
        accountID: String,
        savedAt: Int
    ) throws {
        try eventStore.saveTimelineStateMetadata(
            state,
            accountID: accountID,
            savedAt: savedAt
        )
    }

    func saveRelaySyncEvents(_ events: [NostrRelaySyncEventRecord]) throws {
        try eventStore.saveRelaySyncEvents(events)
    }

    func saveViewportState(
        feedID: String,
        anchorEventID: String?,
        anchorOffset: Double,
        updatedAt: Int
    ) throws {
        try eventStore.saveFeedViewportState(
            feedID: feedID,
            viewportAnchorEventID: anchorEventID,
            viewportAnchorOffset: anchorOffset,
            updatedAt: updatedAt
        )
    }

    func saveReadBoundary(
        feedID: String,
        boundary: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) throws {
        try eventStore.saveFeedReadBoundary(
            feedID: feedID,
            readBoundary: boundary,
            updatedAt: updatedAt
        )
    }
}
