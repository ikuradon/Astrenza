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

enum HomeTimelineCachedStateRestoreOutcome: Equatable, Sendable {
    case restored(NostrHomeTimelineState)
    case missing
    case failed(String)
    case cancelled
}

actor HomeTimelinePersistenceWorker {
    private let eventStore: NostrEventStore

    init(eventStore: NostrEventStore) {
        self.eventStore = eventStore
    }

    func restoredState(
        accountID: String
    ) -> HomeTimelineCachedStateRestoreOutcome {
        do {
            if let state = try eventStore.homeFeedState(accountID: accountID) {
                return .restored(state)
            }
            // V4以前の開発用DBだけをGeneric Feedへ移行するcompatibility pathです。
            if let legacy = try eventStore.legacyHomeTimelineStateForMigration(
                accountID: accountID
            ) {
                return .restored(legacy)
            }
            return .missing
        } catch {
            return .failed("Database restore failed: \(error.localizedDescription)")
        }
    }

    /// Remote bootstrapがローカルheadより古いreplaceable eventで完了する競合を、
    /// 永続化actor上で解決し、MainActorにはmemory stateの適用だけを残します。
    func hydratingReplaceableConfiguration(
        in incoming: NostrHomeTimelineState,
        accountID: String
    ) -> NostrHomeTimelineState {
        let storedRelayListEvent = try? eventStore.latestReplaceableEvent(
            pubkey: accountID,
            kind: 10_002
        )
        let storedContactListEvent = try? eventStore.latestReplaceableEvent(
            pubkey: accountID,
            kind: 3
        )
        let relayListEvent = freshestReplaceableEvent(
            incoming.relayListEvent,
            storedRelayListEvent
        )
        let contactListEvent = freshestReplaceableEvent(
            incoming.contactListEvent,
            storedContactListEvent
        )
        let followedPubkeys: [String]
        if contactListEvent?.id != incoming.contactListEvent?.id {
            followedPubkeys = NostrContactList.pubkeys(from: contactListEvent)
        } else {
            followedPubkeys = incoming.followedPubkeys
        }
        let storedAuthorRelayListEvents = (try? eventStore.latestReplaceableEvents(
            pubkeys: Set(followedPubkeys),
            kind: 10_002
        )) ?? []
        let authorRelayListEvents = freshestRelayListEventsByAuthor(
            incoming.authorRelayListEvents + storedAuthorRelayListEvents,
            authors: Set(followedPubkeys)
        )
        let persistedReadRelays = NostrRelayList.parse(from: relayListEvent).readRelays

        return NostrHomeTimelineState(
            relays: persistedReadRelays.isEmpty ? incoming.relays : persistedReadRelays,
            followedPubkeys: followedPubkeys,
            noteEvents: incoming.noteEvents,
            metadataEvents: incoming.metadataEvents,
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            authorRelayListEvents: authorRelayListEvents,
            nip05Resolutions: incoming.nip05Resolutions,
            hasMoreOlder: incoming.hasMoreOlder,
            relaySyncEvents: incoming.relaySyncEvents
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

    private func freshestReplaceableEvent(
        _ lhs: NostrEvent?,
        _ rhs: NostrEvent?
    ) -> NostrEvent? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt ? lhs : rhs
        }
        return lhs.id <= rhs.id ? lhs : rhs
    }

    private func freshestRelayListEventsByAuthor(
        _ events: [NostrEvent],
        authors: Set<String>
    ) -> [NostrEvent] {
        let normalizedAuthors = Set(authors.map { $0.lowercased() })
        var latestByAuthor: [String: NostrEvent] = [:]
        for event in events where event.kind == 10_002 {
            let author = event.pubkey.lowercased()
            guard normalizedAuthors.contains(author) else { continue }
            latestByAuthor[author] = freshestReplaceableEvent(
                latestByAuthor[author],
                event
            )
        }
        return latestByAuthor.values.sorted { $0.pubkey < $1.pubkey }
    }
}
