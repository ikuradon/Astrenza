import Foundation
import GRDB
import NostrProtocol
import NostrStoreAPI

public struct NostrStoredEventTag: Codable, Equatable, Sendable {
    public let eventID: String
    public let position: Int
    public let name: String
    public let value: String?
    public let relayHint: String?
    public let marker: String?
    public let raw: [String]

    public init(eventID: String, position: Int, name: String, value: String?, relayHint: String?, marker: String?, raw: [String]) {
        self.eventID = eventID
        self.position = position
        self.name = name
        self.value = value
        self.relayHint = relayHint
        self.marker = marker
        self.raw = raw
    }
}

public struct NostrProfileSearchResult: Equatable, Sendable {
    public let pubkey: String
    public let displayName: String?
    public let nip05: String?
    public let pictureURL: URL?
    public let updatedAt: Int

    public init(pubkey: String, displayName: String?, nip05: String?, pictureURL: URL?, updatedAt: Int) {
        self.pubkey = pubkey
        self.displayName = displayName
        self.nip05 = nip05
        self.pictureURL = pictureURL
        self.updatedAt = updatedAt
    }
}

public struct NostrTimelineEntryRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let timelineKey: String
    public let eventID: String
    public let sortTimestamp: Int
    public let source: String
    public let insertedAt: Int
    public let gapBefore: Bool
    public let gapAfter: Bool

    public init(
        accountID: String,
        timelineKey: String,
        eventID: String,
        sortTimestamp: Int,
        source: String = "relay",
        insertedAt: Int,
        gapBefore: Bool = false,
        gapAfter: Bool = false
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.eventID = eventID
        self.sortTimestamp = sortTimestamp
        self.source = source
        self.insertedAt = insertedAt
        self.gapBefore = gapBefore
        self.gapAfter = gapAfter
    }
}

public struct NostrDeletedTimelineEntryRecord: Codable, Equatable, Sendable {
    public let targetEventID: String
    public let deletionEventID: String?
    public let deletedAt: Int
    public let sortTimestamp: Int

    public init(targetEventID: String, deletionEventID: String?, deletedAt: Int, sortTimestamp: Int) {
        self.targetEventID = targetEventID
        self.deletionEventID = deletionEventID
        self.deletedAt = deletedAt
        self.sortTimestamp = sortTimestamp
    }
}

public struct NostrSyncCursorRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let timelineKey: String
    public let relayURL: String
    public let newestCreatedAt: Int?
    public let oldestCreatedAt: Int?
    public let lastEOSEAt: Int?
    public let lastNegentropyAt: Int?

    public init(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        newestCreatedAt: Int?,
        oldestCreatedAt: Int?,
        lastEOSEAt: Int?,
        lastNegentropyAt: Int?
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.relayURL = relayURL
        self.newestCreatedAt = newestCreatedAt
        self.oldestCreatedAt = oldestCreatedAt
        self.lastEOSEAt = lastEOSEAt
        self.lastNegentropyAt = lastNegentropyAt
    }
}

public struct NostrRelayProfileRecord: Codable, Equatable, Sendable {
    public let relayURL: String
    public let information: NostrRelayInformationDocument?
    public let healthScore: Double
    public let lastEOSEAt: Int?
    public let lastConnectedAt: Int?
    public let authRequired: Bool
    public let paymentRequired: Bool

    public init(
        relayURL: String,
        information: NostrRelayInformationDocument?,
        healthScore: Double,
        lastEOSEAt: Int?,
        lastConnectedAt: Int?,
        authRequired: Bool,
        paymentRequired: Bool
    ) {
        self.relayURL = relayURL
        self.information = information
        self.healthScore = healthScore
        self.lastEOSEAt = lastEOSEAt
        self.lastConnectedAt = lastConnectedAt
        self.authRequired = authRequired
        self.paymentRequired = paymentRequired
    }
}

public struct NostrRelayPreferenceRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let relayURL: String
    public let isEnabled: Bool
    public let readEnabled: Bool
    public let writeEnabled: Bool
    public let updatedAt: Int

    public init(
        accountID: String,
        relayURL: String,
        isEnabled: Bool,
        readEnabled: Bool,
        writeEnabled: Bool,
        updatedAt: Int
    ) {
        self.accountID = accountID
        self.relayURL = relayURL
        self.isEnabled = isEnabled
        self.readEnabled = readEnabled
        self.writeEnabled = writeEnabled
        self.updatedAt = updatedAt
    }
}

public struct NostrLocalBookmarkRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let eventID: String
    public let createdAt: Int

    public init(accountID: String, eventID: String, createdAt: Int) {
        self.accountID = accountID
        self.eventID = eventID
        self.createdAt = createdAt
    }
}

private struct RelaySyncBucket: Hashable {
    let accountID: String
    let timelineKey: String
    let relayURL: String
}

private struct RelaySyncTimelineBucket: Hashable {
    let accountID: String
    let timelineKey: String
}

private struct NostrDeletionAddress: Hashable {
    let kind: Int
    let pubkey: String
    let dTag: String
}

public struct NostrRelaySyncSummaryRecord: Codable, Equatable, Sendable {
    public let relayURL: String
    public let lastEventKind: NostrRelaySyncEventKind?
    public let lastEventAt: Int?
    public let lastConnectedAt: Int?
    public let lastEOSEAt: Int?
    public let lastTimeoutAt: Int?
    public let lastErrorAt: Int?
    public let closedCount: Int
    public let reconnectCount: Int
    public let timeoutCount: Int
    public let partialFailureCount: Int
    public let authRequiredCount: Int
    public let paymentRequiredCount: Int
    public let rejectedCount: Int
    public let suspendedCount: Int
    public let lastPartialFailureReason: String?
    public let totalEventCount: Int
    public let averageEOSELatencyMilliseconds: Int?

    public init(
        relayURL: String,
        lastEventKind: NostrRelaySyncEventKind?,
        lastEventAt: Int?,
        lastConnectedAt: Int?,
        lastEOSEAt: Int?,
        lastTimeoutAt: Int?,
        lastErrorAt: Int?,
        closedCount: Int,
        reconnectCount: Int,
        timeoutCount: Int,
        partialFailureCount: Int,
        authRequiredCount: Int,
        paymentRequiredCount: Int,
        rejectedCount: Int = 0,
        suspendedCount: Int = 0,
        lastPartialFailureReason: String?,
        totalEventCount: Int,
        averageEOSELatencyMilliseconds: Int?
    ) {
        self.relayURL = relayURL
        self.lastEventKind = lastEventKind
        self.lastEventAt = lastEventAt
        self.lastConnectedAt = lastConnectedAt
        self.lastEOSEAt = lastEOSEAt
        self.lastTimeoutAt = lastTimeoutAt
        self.lastErrorAt = lastErrorAt
        self.closedCount = closedCount
        self.reconnectCount = reconnectCount
        self.timeoutCount = timeoutCount
        self.partialFailureCount = partialFailureCount
        self.authRequiredCount = authRequiredCount
        self.paymentRequiredCount = paymentRequiredCount
        self.rejectedCount = rejectedCount
        self.suspendedCount = suspendedCount
        self.lastPartialFailureReason = lastPartialFailureReason
        self.totalEventCount = totalEventCount
        self.averageEOSELatencyMilliseconds = averageEOSELatencyMilliseconds
    }

    public func isRecentlyReachable(
        now: Int = Int(Date().timeIntervalSince1970),
        freshnessWindowSeconds: Int = 180
    ) -> Bool {
        guard let lastEventAt,
              now - lastEventAt <= freshnessWindowSeconds
        else {
            return false
        }

        switch lastEventKind {
        case .eose, .connected, .authRequired, .paymentRequired:
            return true
        default:
            return false
        }
    }
}

public struct NostrEventSourceRecord: Codable, Equatable, Sendable {
    public let eventID: String
    public let relayURL: String
    public let firstSeenAt: Int
    public let lastSeenAt: Int

    public init(eventID: String, relayURL: String, firstSeenAt: Int, lastSeenAt: Int) {
        self.eventID = eventID
        self.relayURL = relayURL
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

public final class NostrEventStore: Sendable {
    private let database: any DatabaseWriter
    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { JSONDecoder() }

    private static func visibleEventPredicate(alias: String? = nil) -> String {
        let prefix = alias.map { "\($0)." } ?? ""
        return "\(prefix)deleted_at IS NULL AND (\(prefix)expires_at IS NULL OR \(prefix)expires_at > ?)"
    }

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        database = try DatabasePool(path: path, configuration: configuration)
        try migrate()
    }

    public init(database: any DatabaseWriter) throws {
        self.database = database
        try migrate()
    }

    public static func inMemory() throws -> NostrEventStore {
        try NostrEventStore(database: DatabaseQueue())
    }

    public static func applicationSupport(appDirectory: String, fileName: String = "nostr.sqlite") throws -> NostrEventStore {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent(appDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try NostrEventStore(path: directoryURL.appendingPathComponent(fileName).path)
    }

    public func save(events: [NostrEvent], receivedAt: Int = Int(Date().timeIntervalSince1970)) throws {
        guard !events.isEmpty else { return }

        try database.write { db in
            try persist(events: events, receivedAt: receivedAt, db: db)
        }
    }

    public func ingest(
        events: [NostrEvent],
        eventSources: [NostrEventSourceRecord],
        feedMemberships: [NostrFeedMembershipRecord],
        feedMembershipSources: [NostrFeedMembershipSourceRecord] = [],
        timelineEntries: [NostrTimelineEntryRecord] = [],
        receivedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        guard !events.isEmpty || !eventSources.isEmpty || !feedMemberships.isEmpty ||
            !feedMembershipSources.isEmpty || !timelineEntries.isEmpty
        else {
            return
        }

        try database.write { db in
            try persist(events: events, receivedAt: receivedAt, db: db)
            try upsertEventSources(eventSources, db: db)
            try upsertFeedMemberships(feedMemberships, db: db)
            try upsertFeedMembershipSources(feedMembershipSources, db: db)
            try upsertTimelineEntries(timelineEntries, db: db)
        }
    }

    public func ingestProfileResolutions(
        events: [NostrEvent],
        eventSources: [NostrEventSourceRecord],
        fetchRecords: [NostrProfileFetchRecord],
        receivedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        guard !events.isEmpty || !eventSources.isEmpty || !fetchRecords.isEmpty else { return }
        try database.write { db in
            try persist(events: events, receivedAt: receivedAt, db: db)
            try upsertEventSources(eventSources, db: db)
            try persistProfileFetchRecords(fetchRecords, db: db)
        }
    }

    /// V4以前の`timeline_entries`を使うmigration/test fixture向けの保存APIです。
    /// productionのHome Feed保存には`saveHomeFeedState`を使用してください。
    public func saveHomeTimelineState(
        _ state: NostrHomeTimelineState,
        accountID: String,
        timelineKey: String = "home",
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        let events = state.noteEvents + state.metadataEvents +
            state.authorRelayListEvents +
            [state.relayListEvent, state.contactListEvent].compactMap { $0 }
        try save(events: events, receivedAt: savedAt)
        try saveTimelineEntries(state.noteEvents.map { event in
            NostrTimelineEntryRecord(
                accountID: accountID,
                timelineKey: timelineKey,
                eventID: event.id,
                sortTimestamp: event.createdAt,
                source: "home",
                insertedAt: savedAt
            )
        })

        try saveRelaySyncEvents(state.relaySyncEvents)

        try saveTimelineStateMetadata(state, accountID: accountID, timelineKey: timelineKey, savedAt: savedAt)
    }

    /// Home Feedのcanonical event、projection、復元metadataを1 transactionで保存します。
    /// legacy `timeline_entries` は更新しません。
    public func saveHomeFeedState(
        _ state: NostrHomeTimelineState,
        accountID: String,
        definition: NostrFeedDefinitionRecord,
        memberships: [NostrFeedMembershipRecord],
        membershipSources: [NostrFeedMembershipSourceRecord] = [],
        readState: NostrFeedReadStateRecord? = nil,
        timelineKey: String = "home",
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        guard definition.accountID == accountID,
              definition.kind == timelineKey,
              memberships.allSatisfy({ membership in
                  membership.feedID == definition.feedID &&
                      (membership.feedRevision == nil || membership.feedRevision == definition.revision)
              }),
              membershipSources.allSatisfy({ source in
                  source.feedID == definition.feedID &&
                      (source.feedRevision == nil || source.feedRevision == definition.revision)
              }),
              readState?.feedID == nil || readState?.feedID == definition.feedID
        else {
            if memberships.contains(where: { membership in
                membership.feedID == definition.feedID &&
                    membership.feedRevision != nil &&
                    membership.feedRevision != definition.revision
            }) || membershipSources.contains(where: { source in
                source.feedID == definition.feedID &&
                    source.feedRevision != nil &&
                    source.feedRevision != definition.revision
            }) {
                throw NostrFeedProjectionError.mismatchedRevision
            }
            throw NostrFeedProjectionError.mismatchedFeedID
        }

        let membershipEventIDs = Set(memberships.map(\.eventID))
        guard membershipSources.allSatisfy({ membershipEventIDs.contains($0.eventID) }) else {
            throw NostrFeedProjectionError.sourceWithoutMembership
        }

        let events = state.noteEvents + state.metadataEvents +
            state.authorRelayListEvents +
            [state.relayListEvent, state.contactListEvent].compactMap { $0 }
        try database.write { db in
            try validateFeedDefinitionWrite(definition, db: db)
            try persist(events: events, receivedAt: savedAt, db: db)
            try upsertFeedDefinition(definition, db: db)
            try upsertFeedMemberships(
                memberships,
                revisionOverride: definition.revision,
                db: db
            )
            try upsertFeedMembershipSources(
                membershipSources,
                revisionOverride: definition.revision,
                db: db
            )
            try db.execute(
                sql: "DELETE FROM feed_memberships WHERE feed_id = ? AND feed_revision <> ?",
                arguments: [definition.feedID, definition.revision]
            )
            try saveRelaySyncEvents(state.relaySyncEvents, db: db)
            try updateSyncCursors(from: state.relaySyncEvents, db: db)
            try saveTimelineStateMetadata(
                state,
                accountID: accountID,
                timelineKey: timelineKey,
                savedAt: savedAt,
                db: db
            )
            if let readState {
                try saveFeedReadState(readState, db: db)
            }
        }
    }

    /// Generic Feedだけをsource-of-truthとしてHomeの復元snapshotを返します。
    /// membershipが0件でもdefinitionがあれば、relay/follow/read metadataの復元を継続できます。
    public func homeFeedState(
        accountID: String,
        timelineKey: String = "home",
        limit: Int = 250,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrHomeTimelineState? {
        try database.read { db in
            guard let genericFeedID = try String.fetchOne(
                db,
                sql: """
                SELECT feed_id
                FROM feed_definitions
                WHERE account_id = ? AND feed_kind = ?
                ORDER BY updated_at DESC, feed_id ASC
                LIMIT 1
                """,
                arguments: [accountID, timelineKey]
            ), let definition = try feedDefinition(feedID: genericFeedID, db: db)
            else { return nil }

            let memberships = try feedMemberships(
                feedID: genericFeedID,
                revision: definition.revision,
                limit: limit,
                excludingExpiredAt: now,
                db: db
            )
            let notes = try feedWindow(
                definition: definition,
                revision: definition.revision,
                memberships: memberships,
                now: now,
                db: db
            ).events
            return try homeTimelineState(
                accountID: accountID,
                timelineKey: timelineKey,
                notes: notes,
                now: now,
                db: db
            )
        }
    }

    /// V4以前の開発用DBに残る`timeline_entries`をGeneric Feedへ移す時だけ使用します。
    /// 通常のrestore pathでは呼び出さないでください。
    public func legacyHomeTimelineStateForMigration(
        accountID: String,
        timelineKey: String = "home",
        limit: Int = 250,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrHomeTimelineState? {
        try database.read { db in
            let notes = try timelineEvents(
                accountID: accountID,
                timelineKey: timelineKey,
                limit: limit,
                now: now,
                db: db
            )
            guard !notes.isEmpty else { return nil }
            return try homeTimelineState(
                accountID: accountID,
                timelineKey: timelineKey,
                notes: notes,
                now: now,
                db: db
            )
        }
    }

    public func event(id: String) throws -> NostrEvent? {
        try database.read { db in
            try fetchEvent(id: id, db: db)
        }
    }

    public func events(ids: [String], now: Int = Int(Date().timeIntervalSince1970)) throws -> [NostrEvent] {
        guard !ids.isEmpty else { return [] }

        return try database.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            var arguments: StatementArguments = [now]
            for id in ids {
                arguments += [id]
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE \(Self.visibleEventPredicate()) AND event_id IN (\(placeholders))
                """,
                arguments: arguments
            )
            let eventsByID = Dictionary(uniqueKeysWithValues: try rows.map { row in
                let event = try decodeEvent(row)
                return (event.id, event)
            })
            return ids.compactMap { eventsByID[$0] }
        }
    }

    public func events(kind: Int, limit: Int, now: Int = Int(Date().timeIntervalSince1970)) throws -> [NostrEvent] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind = ? AND \(Self.visibleEventPredicate())
                ORDER BY created_at DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [kind, now, limit]
            )
            return try rows.map(decodeEvent)
        }
    }

    /// 指定したtagを持つeventを、汎用Feed projectionの初期構築に使える順序で返します。
    ///
    /// NIP-01のtag filterは完全一致ですが、既存clientが大文字を含む`t` tagを保存する場合も
    /// 同じhashtag timelineへ復元できるよう、local DBではASCII case-insensitiveに照合します。
    public func events(
        kinds: [Int],
        tagName: String,
        tagValue: String,
        until: Int? = nil,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        guard !kinds.isEmpty,
              !tagName.isEmpty,
              !tagValue.isEmpty,
              limit > 0
        else { return [] }

        return try database.read { db in
            let kindPlaceholders = kinds.map { _ in "?" }.joined(separator: ", ")
            var arguments = StatementArguments()
            for kind in kinds {
                arguments += [kind]
            }
            arguments += [now, tagName, tagValue]
            let untilClause: String
            if let until {
                untilClause = " AND events.created_at <= ?"
                arguments += [until]
            } else {
                untilClause = ""
            }
            arguments += [limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind IN (\(kindPlaceholders))
                    AND \(Self.visibleEventPredicate())
                    AND EXISTS (
                        SELECT 1
                        FROM event_tags tag
                        WHERE tag.event_id = events.event_id
                            AND tag.tag_name = ?
                            AND tag.tag_value = ? COLLATE NOCASE
                    )\(untilClause)
                ORDER BY created_at DESC, event_id ASC
                LIMIT ?
                """,
                arguments: arguments
            )
            return try rows.map(decodeEvent)
        }
    }

    public func events(
        kind: Int,
        authors: [String],
        until: Int,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        guard !authors.isEmpty else { return [] }

        return try database.read { db in
            var arguments: StatementArguments = [kind, until, now]
            let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
            for author in authors {
                arguments += [author]
            }
            arguments += [limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind = ? AND created_at <= ? AND \(Self.visibleEventPredicate())
                    AND pubkey IN (\(placeholders))
                ORDER BY created_at DESC, event_id ASC
                LIMIT ?
                """,
                arguments: arguments
            )
            return try rows.map(decodeEvent)
        }
    }

    public func events(
        kind: Int,
        authors: [String],
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        guard !authors.isEmpty else { return [] }

        return try database.read { db in
            var arguments: StatementArguments = [kind, now]
            let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
            for author in authors {
                arguments += [author]
            }
            arguments += [limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind = ? AND \(Self.visibleEventPredicate())
                    AND pubkey IN (\(placeholders))
                ORDER BY created_at DESC, event_id ASC
                LIMIT ?
                """,
                arguments: arguments
            )
            return try rows.map(decodeEvent)
        }
    }

    public func eventCount(
        kind: Int,
        authors: [String],
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> Int {
        guard !authors.isEmpty else { return 0 }

        return try database.read { database in
            var arguments: StatementArguments = [kind, now]
            let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
            for author in authors {
                arguments += [author]
            }

            return try Int.fetchOne(
                database,
                sql: """
                SELECT COUNT(*)
                FROM events
                WHERE kind = ? AND \(Self.visibleEventPredicate())
                    AND pubkey IN (\(placeholders))
                """,
                arguments: arguments
            ) ?? 0
        }
    }

    public func eventsReferencing(
        eventID: String,
        kind: Int,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT e.event_id, e.pubkey, e.created_at, e.kind, e.tags_json, e.content, e.sig
                FROM event_tags tag
                JOIN events e ON e.event_id = tag.event_id
                WHERE tag.tag_name = 'e'
                    AND tag.tag_value = ?
                    AND e.kind = ?
                    AND \(Self.visibleEventPredicate(alias: "e"))
                ORDER BY e.created_at ASC, e.event_id ASC
                LIMIT ?
                """,
                arguments: [eventID, kind, now, limit]
            )
            return try rows.map(decodeEvent)
        }
    }

    public func tags(eventID: String) throws -> [NostrStoredEventTag] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pos, tag_name, tag_value, relay_hint, marker, raw_json
                FROM event_tags
                WHERE event_id = ?
                ORDER BY pos ASC
                """,
                arguments: [eventID]
            )
            return try rows.map(decodeTag)
        }
    }

    public func listSummaries(accountID: String) throws -> [NostrListSummary] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT list_id, account_id, kind, pubkey, d_tag, event_id, title, visibility,
                       private_content, created_at, updated_at
                FROM lists
                WHERE account_id = ?
                ORDER BY updated_at DESC, kind ASC, title ASC
                """,
                arguments: [accountID]
            )
            return rows.map(decodeListSummary)
        }
    }

    public func listItems(listID: String) throws -> [NostrListItemRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT list_id, item_key, item_type, value, relay_hint, visibility, position
                FROM list_items
                WHERE list_id = ?
                ORDER BY position ASC
                """,
                arguments: [listID]
            )
            return rows.map(decodeListItem)
        }
    }

    public func mediaAssets(eventID: String) throws -> [NostrMediaAssetRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT asset_id, event_id, url, mime_type, blurhash, width, height,
                       alt, sha256, status, local_path, created_at
                FROM media_assets
                WHERE event_id = ?
                ORDER BY created_at ASC, asset_id ASC
                """,
                arguments: [eventID]
            )
            return rows.map(decodeMediaAsset)
        }
    }

    public func mediaAssets(eventIDs: [String]) throws -> [String: [NostrMediaAssetRecord]] {
        let uniqueEventIDs = Array(Set(eventIDs)).sorted()
        guard !uniqueEventIDs.isEmpty else { return [:] }

        return try database.read { db in
            let placeholders = Array(repeating: "?", count: uniqueEventIDs.count).joined(separator: ", ")
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT asset_id, event_id, url, mime_type, blurhash, width, height,
                       alt, sha256, status, local_path, created_at
                FROM media_assets
                WHERE event_id IN (\(placeholders))
                ORDER BY event_id ASC, created_at ASC, asset_id ASC
                """,
                arguments: StatementArguments(uniqueEventIDs)
            )
            var assetsByEventID = Dictionary(
                uniqueKeysWithValues: uniqueEventIDs.map { ($0, [NostrMediaAssetRecord]()) }
            )
            for row in rows {
                let asset = decodeMediaAsset(row)
                assetsByEventID[asset.eventID, default: []].append(asset)
            }
            return assetsByEventID
        }
    }

    public func linkPreviews(urls: [URL]) throws -> [String: NostrLinkPreviewRecord] {
        let normalizedURLs = urls.map(NostrLinkParser.normalizedURLString)
        guard !normalizedURLs.isEmpty else { return [:] }

        return try database.read { db in
            let placeholders = Array(repeating: "?", count: normalizedURLs.count).joined(separator: ", ")
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT url, normalized_url, status, title, summary, site_name,
                       image_url, fetched_at, expires_at, error
                FROM link_previews
                WHERE normalized_url IN (\(placeholders))
                """,
                arguments: StatementArguments(normalizedURLs)
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let preview = decodeLinkPreview(row)
                return (preview.normalizedURL, preview)
            })
        }
    }

    public func unresolvedLinkPreviews(limit: Int = 20, now: Int = Int(Date().timeIntervalSince1970)) throws -> [NostrLinkPreviewRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT url, normalized_url, status, title, summary, site_name,
                       image_url, fetched_at, expires_at, error
                FROM link_previews
                WHERE status = 'unresolved'
                   OR (status = 'failed' AND (expires_at IS NULL OR expires_at <= ?))
                ORDER BY fetched_at IS NOT NULL ASC, fetched_at ASC, normalized_url ASC
                LIMIT ?
                """,
                arguments: [now, max(0, limit)]
            )
            return rows.map(decodeLinkPreview)
        }
    }

    public func saveLinkPreview(_ preview: NostrLinkPreviewRecord) throws {
        try database.write { db in
            try upsertLinkPreview(preview, db: db)
        }
    }

    @discardableResult
    public func enqueueOutboxEvent(
        _ event: NostrEvent,
        accountID: String,
        relayURLs: [String],
        localID: String = UUID().uuidString,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrOutboxEventRecord {
        let eventData = try encoder.encode(event)
        let relays = NostrPublishDestinationResolver.relayDestinations(
            accountWriteRelays: relayURLs,
            taggedUserReadRelays: [],
            fallbackRelays: []
        )

        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO outbox_events (
                    local_id, account_id, event_id, event_json, status,
                    created_at, next_retry_at, last_error
                ) VALUES (?, ?, ?, ?, ?, ?, NULL, NULL)
                ON CONFLICT(local_id) DO UPDATE SET
                    account_id = excluded.account_id,
                    event_id = excluded.event_id,
                    event_json = excluded.event_json,
                    status = excluded.status,
                    created_at = excluded.created_at,
                    next_retry_at = excluded.next_retry_at,
                    last_error = excluded.last_error
                """,
                arguments: [
                    localID,
                    accountID,
                    event.id,
                    eventData,
                    NostrOutboxStatus.pending,
                    createdAt
                ]
            )

            try db.execute(sql: "DELETE FROM outbox_relays WHERE local_id = ?", arguments: [localID])
            for relayURL in relays {
                try db.execute(
                    sql: """
                    INSERT INTO outbox_relays (
                        local_id, relay_url, status, last_attempt_at, ok_message
                    ) VALUES (?, ?, ?, NULL, NULL)
                    """,
                    arguments: [localID, relayURL, NostrOutboxStatus.pending]
                )
            }
        }

        return NostrOutboxEventRecord(
            localID: localID,
            accountID: accountID,
            eventID: event.id,
            event: event,
            status: NostrOutboxStatus.pending,
            createdAt: createdAt,
            nextRetryAt: nil,
            lastError: nil
        )
    }

    public func outboxEvents(accountID: String, limit: Int = 100) throws -> [NostrOutboxEventRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT local_id, account_id, event_id, event_json, status,
                       created_at, next_retry_at, last_error
                FROM outbox_events
                WHERE account_id = ?
                ORDER BY created_at DESC, local_id ASC
                LIMIT ?
                """,
                arguments: [accountID, limit]
            )
            return try rows.map(decodeOutboxEvent)
        }
    }

    public func outboxRelays(localID: String) throws -> [NostrOutboxRelayRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT local_id, relay_url, status, last_attempt_at, ok_message, attempt_count
                FROM outbox_relays
                WHERE local_id = ?
                ORDER BY relay_url ASC
                """,
                arguments: [localID]
            )
            return rows.map(decodeOutboxRelay)
        }
    }

    public func recordOutboxRelayResult(
        localID: String,
        relayURL: String,
        accepted: Bool,
        message: String?,
        retryable: Bool = true,
        attemptedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            let status = accepted
                ? NostrOutboxStatus.published
                : (retryable ? NostrOutboxStatus.failed : NostrOutboxStatus.rejected)
            try db.execute(
                sql: """
                UPDATE outbox_relays
                SET status = ?, last_attempt_at = ?, ok_message = ?, attempt_count = attempt_count + 1
                WHERE local_id = ? AND relay_url = ?
                """,
                arguments: [status, attemptedAt, message, localID, relayURL]
            )

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT status, last_attempt_at, ok_message, attempt_count
                FROM outbox_relays
                WHERE local_id = ?
                ORDER BY relay_url ASC
                """,
                arguments: [localID]
            )
            let statuses = rows.map { String($0["status"]) }
            let aggregate = aggregateOutboxStatus(relayStatuses: statuses)
            let errorRows = rows.filter { row in
                let status = String(row["status"])
                return status == NostrOutboxStatus.failed || status == NostrOutboxStatus.rejected
            }
            let lastError = errorRows.compactMap { row -> String? in row["ok_message"] }.last
            let nextRetryAt = rows
                .filter { row in String(row["status"]) == NostrOutboxStatus.failed }
                .compactMap { row -> Int? in
                    guard let lastAttemptAt: Int = row["last_attempt_at"] else { return nil }
                    let attemptCount: Int = row["attempt_count"]
                    return lastAttemptAt + Self.outboxRetryDelaySeconds(attemptCount: attemptCount)
                }
                .min()

            try db.execute(
                sql: """
                UPDATE outbox_events
                SET status = ?, next_retry_at = ?, last_error = ?
                WHERE local_id = ?
                """,
                arguments: [aggregate, nextRetryAt, lastError, localID]
            )
        }
    }

    public func latestReplaceableEvent(
        pubkey: String,
        kind: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrEvent? {
        try database.read { db in
            try latestReplaceableEvent(pubkey: pubkey, kind: kind, now: now, db: db)
        }
    }

    public func latestReplaceableEvents(
        pubkeys: Set<String>,
        kind: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        try database.read { db in
            try latestReplaceableEvents(pubkeys: pubkeys, kind: kind, now: now, db: db)
        }
    }

    public func followerCount(
        of pubkey: String,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> Int {
        try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(DISTINCT head.pubkey)
                FROM replaceable_heads head
                JOIN events event ON event.event_id = head.event_id
                JOIN event_tags tag ON tag.event_id = head.event_id
                WHERE head.kind = 3
                    AND \(Self.visibleEventPredicate(alias: "event"))
                    AND tag.tag_name = 'p'
                    AND tag.tag_value = ?
                """,
                arguments: [now, pubkey.lowercased()]
            ) ?? 0
        }
    }

    public func followerPubkeys(
        of pubkey: String,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [String] {
        guard limit > 0 else { return [] }
        return try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT head.pubkey
                FROM replaceable_heads head
                JOIN events event ON event.event_id = head.event_id
                JOIN event_tags tag ON tag.event_id = head.event_id
                WHERE head.kind = 3
                    AND \(Self.visibleEventPredicate(alias: "event"))
                    AND tag.tag_name = 'p'
                    AND tag.tag_value = ?
                ORDER BY head.created_at DESC, head.pubkey ASC
                LIMIT ?
                """,
                arguments: [now, pubkey.lowercased(), limit]
            )
        }
    }

    public func latestReplaceableEventReceivedAtByPubkey(
        pubkeys: Set<String>,
        kind: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [String: Int] {
        guard !pubkeys.isEmpty else { return [:] }

        return try database.read { db in
            var arguments: StatementArguments = [kind, now]
            let placeholders = pubkeys.map { _ in "?" }.joined(separator: ", ")
            for pubkey in pubkeys {
                arguments += [pubkey]
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT h.pubkey, e.received_at
                FROM replaceable_heads h
                JOIN events e ON e.event_id = h.event_id
                WHERE h.kind = ?
                    AND \(Self.visibleEventPredicate(alias: "e"))
                    AND h.pubkey IN (\(placeholders))
                """,
                arguments: arguments
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let pubkey: String = row["pubkey"]
                let receivedAt: Int = row["received_at"]
                return (pubkey, receivedAt)
            })
        }
    }

    public func saveProfileFetchRecords(_ records: [NostrProfileFetchRecord]) throws {
        guard !records.isEmpty else { return }
        try database.write { db in
            try persistProfileFetchRecords(records, db: db)
        }
    }

    private func persistProfileFetchRecords(
        _ records: [NostrProfileFetchRecord],
        db: Database
    ) throws {
        for record in records {
            try db.execute(
                sql: """
                INSERT INTO profile_fetch_state (
                    pubkey, last_outcome, last_attempt_at, last_success_at,
                    next_retry_at, last_error, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(pubkey) DO UPDATE SET
                    last_outcome = excluded.last_outcome,
                    last_attempt_at = excluded.last_attempt_at,
                    last_success_at = excluded.last_success_at,
                    next_retry_at = excluded.next_retry_at,
                    last_error = excluded.last_error,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    record.pubkey,
                    record.outcome.rawValue,
                    record.lastAttemptAt,
                    record.lastSuccessAt,
                    record.nextRetryAt,
                    record.lastError,
                    record.updatedAt
                ]
            )
        }
    }

    public func profileFetchRecords(pubkeys: Set<String>) throws -> [NostrProfileFetchRecord] {
        guard !pubkeys.isEmpty else { return [] }
        return try database.read { db in
            var arguments = StatementArguments()
            let placeholders = pubkeys.map { _ in "?" }.joined(separator: ", ")
            for pubkey in pubkeys {
                arguments += [pubkey]
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT pubkey, last_outcome, last_attempt_at, last_success_at,
                    next_retry_at, last_error, updated_at
                FROM profile_fetch_state
                WHERE pubkey IN (\(placeholders))
                """,
                arguments: arguments
            )
            return rows.compactMap { row in
                let rawOutcome: String = row["last_outcome"]
                guard let outcome = NostrProfileFetchOutcome(rawValue: rawOutcome) else { return nil }
                return NostrProfileFetchRecord(
                    pubkey: row["pubkey"],
                    outcome: outcome,
                    lastAttemptAt: row["last_attempt_at"],
                    lastSuccessAt: row["last_success_at"],
                    nextRetryAt: row["next_retry_at"],
                    lastError: row["last_error"],
                    updatedAt: row["updated_at"]
                )
            }
        }
    }

    public func profileSearchCandidates(
        query: String,
        limit: Int = 20,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrProfileSearchResult] {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT e.event_id, e.pubkey, e.created_at, e.kind, e.tags_json, e.content, e.sig
                FROM replaceable_heads h
                JOIN events e ON e.event_id = h.event_id
                WHERE h.kind = 0
                    AND \(Self.visibleEventPredicate(alias: "e"))
                ORDER BY e.created_at DESC, e.pubkey ASC
                LIMIT 1000
                """,
                arguments: [now]
            )

            var results: [NostrProfileSearchResult] = []
            results.reserveCapacity(min(rows.count, boundedLimit))

            for row in rows {
                let event = try decodeEvent(row)
                guard let metadata = Self.profileMetadata(from: event) else { continue }
                let result = NostrProfileSearchResult(
                    pubkey: event.pubkey,
                    displayName: metadata.bestName,
                    nip05: metadata.nip05?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    pictureURL: metadata.pictureURL,
                    updatedAt: event.createdAt
                )
                guard normalizedQuery.isEmpty || result.matches(normalizedQuery) else { continue }
                results.append(result)
                if results.count == boundedLimit {
                    break
                }
            }

            return results
        }
    }

    public func latestAddressableEvent(
        kind: Int,
        pubkey: String,
        dTag: String,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrEvent? {
        try database.read { db in
            guard let eventID = try String.fetchOne(
                db,
                sql: """
                SELECT h.event_id
                FROM addressable_heads h
                JOIN events e ON e.event_id = h.event_id
                WHERE h.kind = ? AND h.pubkey = ? AND h.d_tag = ?
                    AND \(Self.visibleEventPredicate(alias: "e"))
                """,
                arguments: [kind, pubkey, dTag, now]
            ) else { return nil }
            return try fetchEvent(id: eventID, db: db)
        }
    }

    public func eventCount() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
        }
    }

    public func recordEventSources(eventIDs: [String], relayURL: String, seenAt: Int = Int(Date().timeIntervalSince1970)) throws {
        guard !eventIDs.isEmpty else { return }

        try database.write { db in
            try upsertEventSources(eventIDs.map { eventID in
                NostrEventSourceRecord(
                    eventID: eventID,
                    relayURL: relayURL,
                    firstSeenAt: seenAt,
                    lastSeenAt: seenAt
                )
            }, db: db)
        }
    }

    public func eventSources(eventID: String) throws -> [NostrEventSourceRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, relay_url, first_seen_at, last_seen_at
                FROM event_sources
                WHERE event_id = ?
                ORDER BY relay_url ASC
                """,
                arguments: [eventID]
            )
            return rows.map(decodeEventSource)
        }
    }

    public func observedRelayURLsByAuthor(
        authors: Set<String>,
        limitPerAuthor: Int = 4
    ) throws -> [String: [String]] {
        guard !authors.isEmpty, limitPerAuthor > 0 else { return [:] }
        let normalizedAuthors = Set(authors.map { $0.lowercased() })
        let sortedAuthors = normalizedAuthors.sorted()
        let placeholders = Array(
            repeating: "?",
            count: sortedAuthors.count
        ).joined(separator: ", ")
        var arguments = StatementArguments()
        for author in sortedAuthors {
            arguments += [author]
        }

        return try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT e.pubkey, s.relay_url, MAX(s.last_seen_at) AS last_seen_at
                FROM event_sources s
                JOIN events e ON e.event_id = s.event_id
                WHERE e.pubkey IN (\(placeholders))
                GROUP BY e.pubkey, s.relay_url
                ORDER BY e.pubkey ASC, last_seen_at DESC, s.relay_url ASC
                """,
                arguments: arguments
            )
            var result: [String: [String]] = [:]
            for row in rows {
                let author: String = row["pubkey"]
                guard result[author, default: []].count < limitPerAuthor else {
                    continue
                }
                result[author, default: []].append(row["relay_url"])
            }
            return result
        }
    }

    public func saveTimelineEntries(_ entries: [NostrTimelineEntryRecord]) throws {
        guard !entries.isEmpty else { return }

        try database.write { db in
            try upsertTimelineEntries(entries, db: db)
        }
    }

    public func timelineEvents(
        accountID: String,
        timelineKey: String,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        try database.read { db in
            try timelineEvents(accountID: accountID, timelineKey: timelineKey, limit: limit, now: now, db: db)
        }
    }

    public func timelineEntries(accountID: String, timelineKey: String, limit: Int) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ?
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [accountID, timelineKey, limit]
            )
            return rows.map(decodeTimelineEntry)
        }
    }

    public func timelineEntries(
        accountID: String,
        timelineKey: String,
        newerThan sortTimestamp: Int,
        limit: Int
    ) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ? AND sort_ts > ?
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [accountID, timelineKey, sortTimestamp, limit]
            )
            return rows.map(decodeTimelineEntry)
        }
    }

    public func timelineEntries(
        accountID: String,
        timelineKey: String,
        newerThan cursor: NostrTimelineEntryCursor,
        limit: Int
    ) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ?
                    AND (sort_ts > ? OR (sort_ts = ? AND event_id < ?))
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [
                    accountID,
                    timelineKey,
                    cursor.sortTimestamp,
                    cursor.sortTimestamp,
                    cursor.eventID,
                    max(0, limit)
                ]
            )
            return rows.map(decodeTimelineEntry)
        }
    }

    public func timelineEntries(
        accountID: String,
        timelineKey: String,
        olderThan sortTimestamp: Int,
        limit: Int
    ) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ? AND sort_ts < ?
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [accountID, timelineKey, sortTimestamp, limit]
            )
            return rows.map(decodeTimelineEntry)
        }
    }

    public func timelineEntries(
        accountID: String,
        timelineKey: String,
        olderThan cursor: NostrTimelineEntryCursor,
        limit: Int
    ) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ?
                    AND (sort_ts < ? OR (sort_ts = ? AND event_id > ?))
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [
                    accountID,
                    timelineKey,
                    cursor.sortTimestamp,
                    cursor.sortTimestamp,
                    cursor.eventID,
                    max(0, limit)
                ]
            )
            return rows.map(decodeTimelineEntry)
        }
    }

    public func timelineEntries(
        accountID: String,
        timelineKey: String,
        aroundEventID eventID: String,
        leadingLimit: Int,
        trailingLimit: Int
    ) throws -> [NostrTimelineEntryRecord] {
        try database.read { db in
            guard let anchorRow = try Row.fetchOne(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ? AND event_id = ?
                """,
                arguments: [accountID, timelineKey, eventID]
            ) else {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                    FROM timeline_entries
                    WHERE account_id = ? AND timeline_key = ?
                    ORDER BY sort_ts DESC, event_id ASC
                    LIMIT ?
                    """,
                    arguments: [accountID, timelineKey, max(0, leadingLimit + trailingLimit + 1)]
                )
                return rows.map(decodeTimelineEntry)
            }

            let anchor = decodeTimelineEntry(anchorRow)
            let newerRows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ?
                    AND (sort_ts > ? OR (sort_ts = ? AND event_id < ?))
                ORDER BY sort_ts ASC, event_id DESC
                LIMIT ?
                """,
                arguments: [
                    accountID,
                    timelineKey,
                    anchor.sortTimestamp,
                    anchor.sortTimestamp,
                    anchor.eventID,
                    max(0, leadingLimit)
                ]
            )
            let olderRows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after
                FROM timeline_entries
                WHERE account_id = ? AND timeline_key = ?
                    AND (sort_ts < ? OR (sort_ts = ? AND event_id > ?))
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [
                    accountID,
                    timelineKey,
                    anchor.sortTimestamp,
                    anchor.sortTimestamp,
                    anchor.eventID,
                    max(0, trailingLimit)
                ]
            )

            return newerRows.reversed().map(decodeTimelineEntry) + [anchor] + olderRows.map(decodeTimelineEntry)
        }
    }

    public func markTimelineGap(
        accountID: String,
        timelineKey: String,
        newerEventID: String,
        olderEventID: String
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE timeline_entries
                SET gap_after = 1
                WHERE account_id = ? AND timeline_key = ? AND event_id = ?
                """,
                arguments: [accountID, timelineKey, newerEventID]
            )
            try db.execute(
                sql: """
                UPDATE timeline_entries
                SET gap_before = 1
                WHERE account_id = ? AND timeline_key = ? AND event_id = ?
                """,
                arguments: [accountID, timelineKey, olderEventID]
            )
        }
    }

    public func markTimelineGapResolved(
        accountID: String,
        timelineKey: String,
        newerEventID: String,
        olderEventID: String
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE timeline_entries
                SET gap_after = 0
                WHERE account_id = ? AND timeline_key = ? AND event_id = ?
                """,
                arguments: [accountID, timelineKey, newerEventID]
            )
            try db.execute(
                sql: """
                UPDATE timeline_entries
                SET gap_before = 0
                WHERE account_id = ? AND timeline_key = ? AND event_id = ?
                """,
                arguments: [accountID, timelineKey, olderEventID]
            )
        }
    }

    public func deletedTimelineEntries(
        accountID: String,
        timelineKey: String,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrDeletedTimelineEntryRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT te.event_id AS target_event_id,
                    tombstone.deletion_event_id,
                    e.deleted_at,
                    te.sort_ts
                FROM timeline_entries te
                JOIN events e ON e.event_id = te.event_id
                LEFT JOIN deletion_tombstones tombstone
                    ON tombstone.target_event_id = te.event_id
                    AND tombstone.author_pubkey = e.pubkey
                WHERE te.account_id = ? AND te.timeline_key = ?
                    AND e.deleted_at IS NOT NULL
                    AND (e.expires_at IS NULL OR e.expires_at > ?)
                ORDER BY te.sort_ts DESC, te.event_id ASC
                LIMIT ?
                """,
                arguments: [accountID, timelineKey, now, limit]
            )
            return rows.map(decodeDeletedTimelineEntry)
        }
    }

    public func saveFeedDefinition(_ definition: NostrFeedDefinitionRecord) throws {
        try database.write { db in
            try validateFeedDefinitionWrite(definition, db: db)
            try upsertFeedDefinition(definition, db: db)
        }
    }

    /// 新revisionのprojectionを構築し、definitionのactive revision切替までを1 transactionで行います。
    public func replaceFeedProjection(
        _ definition: NostrFeedDefinitionRecord,
        memberships: [NostrFeedMembershipRecord],
        sources: [NostrFeedMembershipSourceRecord] = [],
        gaps: [NostrFeedGapRecord] = []
    ) throws {
        guard memberships.allSatisfy({ membership in
            membership.feedID == definition.feedID &&
                (membership.feedRevision == nil || membership.feedRevision == definition.revision)
        }), sources.allSatisfy({ source in
            source.feedID == definition.feedID &&
                (source.feedRevision == nil || source.feedRevision == definition.revision)
        }), gaps.allSatisfy({ gap in
            gap.feedID == definition.feedID && gap.feedRevision == definition.revision
        }) else {
            if memberships.contains(where: { $0.feedID != definition.feedID }) ||
                sources.contains(where: { $0.feedID != definition.feedID }) ||
                gaps.contains(where: { $0.feedID != definition.feedID }) {
                throw NostrFeedProjectionError.mismatchedFeedID
            }
            throw NostrFeedProjectionError.mismatchedRevision
        }

        let membershipEventIDs = Set(memberships.map(\.eventID))
        guard sources.allSatisfy({ membershipEventIDs.contains($0.eventID) }) else {
            throw NostrFeedProjectionError.sourceWithoutMembership
        }
        guard gaps.allSatisfy({ gap in
            membershipEventIDs.contains(gap.newerEventID) && membershipEventIDs.contains(gap.olderEventID)
        }) else {
            throw NostrFeedProjectionError.gapWithoutBoundaryMembership
        }

        try database.write { db in
            try validateFeedDefinitionWrite(definition, db: db)
            // FKを満たすため先にupsertしますが、transaction commitまでは旧definitionが読まれます。
            try upsertFeedDefinition(definition, db: db)
            try db.execute(
                sql: "DELETE FROM feed_memberships WHERE feed_id = ? AND feed_revision = ?",
                arguments: [definition.feedID, definition.revision]
            )
            try upsertFeedMemberships(memberships, revisionOverride: definition.revision, db: db)
            try upsertFeedMembershipSources(sources, revisionOverride: definition.revision, db: db)
            try upsertFeedGaps(gaps, db: db)
            try db.execute(
                sql: "DELETE FROM feed_memberships WHERE feed_id = ? AND feed_revision <> ?",
                arguments: [definition.feedID, definition.revision]
            )
        }
    }

    public func feedDefinition(feedID: String) throws -> NostrFeedDefinitionRecord? {
        try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT feed_id, account_id, feed_kind, spec_json, spec_hash,
                    sort_policy, revision, created_at, updated_at
                FROM feed_definitions
                WHERE feed_id = ?
                """,
                arguments: [feedID]
            ).map(decodeFeedDefinition)
        }
    }

    public func feedDefinitions(accountID: String) throws -> [NostrFeedDefinitionRecord] {
        try database.read { db in
            return try Row.fetchAll(
                db,
                sql: """
                SELECT feed_id, account_id, feed_kind, spec_json, spec_hash,
                    sort_policy, revision, created_at, updated_at
                FROM feed_definitions
                WHERE account_id = ?
                ORDER BY updated_at DESC, feed_id ASC
                """,
                arguments: [accountID]
            ).map(decodeFeedDefinition)
        }
    }

    public func deleteFeedDefinition(feedID: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM feed_definitions WHERE feed_id = ?", arguments: [feedID])
        }
    }

    public func saveFeedMemberships(_ memberships: [NostrFeedMembershipRecord]) throws {
        guard !memberships.isEmpty else { return }

        try database.write { db in
            try upsertFeedMemberships(memberships, db: db)
        }
    }

    public func feedMemberships(
        feedID: String,
        revision: Int? = nil,
        limit: Int
    ) throws -> [NostrFeedMembershipRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT feed_id, feed_revision, event_id, subject_event_id, sort_ts, reason, inserted_at
                FROM feed_memberships
                WHERE feed_id = ? AND feed_revision = ?
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [feedID, revision, max(0, limit)]
            ).map(decodeFeedMembership)
        }
    }

    public func feedMemberships(
        feedID: String,
        revision: Int? = nil,
        newerThan cursor: NostrTimelineEntryCursor,
        limit: Int
    ) throws -> [NostrFeedMembershipRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT feed_id, feed_revision, event_id, subject_event_id, sort_ts, reason, inserted_at
                FROM feed_memberships
                WHERE feed_id = ? AND feed_revision = ?
                    AND (sort_ts > ? OR (sort_ts = ? AND event_id < ?))
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [
                    feedID,
                    revision,
                    cursor.sortTimestamp,
                    cursor.sortTimestamp,
                    cursor.eventID,
                    max(0, limit)
                ]
            ).map(decodeFeedMembership)
        }
    }

    public func feedMemberships(
        feedID: String,
        revision: Int? = nil,
        olderThan cursor: NostrTimelineEntryCursor,
        limit: Int
    ) throws -> [NostrFeedMembershipRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT feed_id, feed_revision, event_id, subject_event_id, sort_ts, reason, inserted_at
                FROM feed_memberships
                WHERE feed_id = ? AND feed_revision = ?
                    AND (sort_ts < ? OR (sort_ts = ? AND event_id > ?))
                ORDER BY sort_ts DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [
                    feedID,
                    revision,
                    cursor.sortTimestamp,
                    cursor.sortTimestamp,
                    cursor.eventID,
                    max(0, limit)
                ]
            ).map(decodeFeedMembership)
        }
    }

    public func feedMemberships(
        feedID: String,
        revision: Int? = nil,
        aroundEventID eventID: String,
        leadingLimit: Int,
        trailingLimit: Int
    ) throws -> [NostrFeedMembershipRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try feedMemberships(
                feedID: feedID,
                revision: revision,
                aroundEventID: eventID,
                leadingLimit: leadingLimit,
                trailingLimit: trailingLimit,
                db: db
            )
        }
    }

    public func saveFeedMembershipSources(_ sources: [NostrFeedMembershipSourceRecord]) throws {
        guard !sources.isEmpty else { return }
        try database.write { db in
            try upsertFeedMembershipSources(sources, db: db)
        }
    }

    public func feedMembershipSources(
        feedID: String,
        revision: Int? = nil,
        eventID: String? = nil
    ) throws -> [NostrFeedMembershipSourceRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            let eventClause = eventID == nil ? "" : " AND event_id = ?"
            var arguments: StatementArguments = [feedID, revision]
            if let eventID { arguments += [eventID] }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT feed_id, feed_revision, event_id, source_type, source_id, inserted_at
                FROM feed_membership_sources
                WHERE feed_id = ? AND feed_revision = ?\(eventClause)
                ORDER BY event_id ASC, source_type ASC, source_id ASC
                """,
                arguments: arguments
            ).map(decodeFeedMembershipSource)
        }
    }

    public func markFeedGap(
        feedID: String,
        revision: Int? = nil,
        newerEventID: String,
        olderEventID: String,
        state: NostrFeedGapState = .unresolved,
        sourceRequestID: String? = nil,
        at updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                throw NostrFeedProjectionError.missingFeedDefinition
            }
            try upsertFeedGaps([
                NostrFeedGapRecord(
                    feedID: feedID,
                    feedRevision: revision,
                    newerEventID: newerEventID,
                    olderEventID: olderEventID,
                    state: state,
                    sourceRequestID: sourceRequestID,
                    createdAt: updatedAt,
                    updatedAt: updatedAt,
                    resolvedAt: state == .resolved ? updatedAt : nil
                )
            ], db: db)
        }
    }

    public func resolveFeedGap(
        feedID: String,
        revision: Int? = nil,
        newerEventID: String,
        olderEventID: String,
        sourceRequestID: String? = nil,
        at resolvedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                throw NostrFeedProjectionError.missingFeedDefinition
            }
            try db.execute(
                sql: """
                UPDATE feed_gaps
                SET gap_state = ?,
                    source_request_id = CASE
                        WHEN gap_state <> ? OR ? >= updated_at
                            THEN COALESCE(?, source_request_id)
                        ELSE source_request_id
                    END,
                    updated_at = MAX(updated_at, ?),
                    resolved_at = CASE
                        WHEN resolved_at IS NULL OR resolved_at < ? THEN ?
                        ELSE resolved_at
                    END
                WHERE feed_id = ? AND feed_revision = ?
                    AND newer_event_id = ? AND older_event_id = ?
                """,
                arguments: [
                    NostrFeedGapState.resolved.rawValue,
                    NostrFeedGapState.resolved.rawValue,
                    resolvedAt,
                    sourceRequestID,
                    resolvedAt,
                    resolvedAt,
                    resolvedAt,
                    feedID,
                    revision,
                    newerEventID,
                    olderEventID
                ]
            )
        }
    }

    public func feedGaps(
        feedID: String,
        revision: Int? = nil,
        includeResolved: Bool = false
    ) throws -> [NostrFeedGapRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try feedGaps(
                feedID: feedID,
                revision: revision,
                includeResolved: includeResolved,
                db: db
            )
        }
    }

    public func deletedFeedItems(
        feedID: String,
        revision: Int? = nil,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrDeletedFeedItemRecord] {
        try database.read { db in
            guard let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db) else {
                return []
            }
            return try deletedFeedItems(
                feedID: feedID,
                revision: revision,
                limit: limit,
                now: now,
                db: db
            )
        }
    }

    public func feedWindow(
        feedID: String,
        revision: Int? = nil,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFeedWindow? {
        try database.read { db in
            guard let definition = try feedDefinition(feedID: feedID, db: db),
                  let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db)
            else { return nil }
            let memberships = try feedMemberships(
                feedID: feedID,
                revision: revision,
                limit: limit,
                excludingExpiredAt: now,
                db: db
            )
            return try feedWindow(
                definition: definition,
                revision: revision,
                memberships: memberships,
                now: now,
                db: db
            )
        }
    }

    public func feedWindow(
        feedID: String,
        revision: Int? = nil,
        newerThan cursor: NostrTimelineEntryCursor,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFeedWindow? {
        try database.read { db in
            guard let definition = try feedDefinition(feedID: feedID, db: db),
                  let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db)
            else { return nil }
            let memberships = try feedMemberships(
                feedID: feedID,
                revision: revision,
                newerThan: cursor,
                limit: limit,
                excludingExpiredAt: now,
                db: db
            )
            return try feedWindow(
                definition: definition,
                revision: revision,
                memberships: memberships,
                now: now,
                db: db
            )
        }
    }

    public func feedWindow(
        feedID: String,
        revision: Int? = nil,
        olderThan cursor: NostrTimelineEntryCursor,
        limit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFeedWindow? {
        try database.read { db in
            guard let definition = try feedDefinition(feedID: feedID, db: db),
                  let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db)
            else { return nil }
            let memberships = try feedMemberships(
                feedID: feedID,
                revision: revision,
                olderThan: cursor,
                limit: limit,
                excludingExpiredAt: now,
                db: db
            )
            return try feedWindow(
                definition: definition,
                revision: revision,
                memberships: memberships,
                now: now,
                db: db
            )
        }
    }

    public func feedWindow(
        feedID: String,
        revision: Int? = nil,
        aroundEventID eventID: String,
        leadingLimit: Int,
        trailingLimit: Int,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrFeedWindow? {
        try database.read { db in
            guard let definition = try feedDefinition(feedID: feedID, db: db),
                  let revision = try resolvedFeedRevision(feedID: feedID, revision: revision, db: db)
            else { return nil }
            let memberships = try feedMemberships(
                feedID: feedID,
                revision: revision,
                aroundEventID: eventID,
                leadingLimit: leadingLimit,
                trailingLimit: trailingLimit,
                excludingExpiredAt: now,
                db: db
            )
            return try feedWindow(
                definition: definition,
                revision: revision,
                memberships: memberships,
                now: now,
                db: db
            )
        }
    }

    public func beginFeedSyncRequest(
        _ request: NostrFeedSyncRequestRecord,
        filters: [NostrFeedSyncFilterRecord]
    ) throws {
        guard !filters.isEmpty, filters.allSatisfy({ $0.requestID == request.requestID }) else { return }

        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO feed_sync_requests (
                    request_id, feed_id, feed_revision, feed_spec_hash,
                    relay_url, subscription_id, protocol_kind, direction, purpose,
                    requested_at, installed_at, eose_at, ended_at, end_reason, end_message,
                    event_count, observed_oldest_ts, observed_oldest_event_id,
                    observed_newest_ts, observed_newest_event_id,
                    verification_outcome, difference_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(request_id) DO NOTHING
                """,
                arguments: feedSyncRequestArguments(request)
            )
            for filter in filters {
                try db.execute(
                    sql: """
                    INSERT INTO feed_sync_request_filters (
                        request_id, filter_index, filter_json, filter_hash, scope_hash,
                        requested_since, requested_until, request_limit, hit_limit
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(request_id, filter_index) DO NOTHING
                    """,
                    arguments: [
                        filter.requestID,
                        filter.filterIndex,
                        filter.filterJSON,
                        filter.filterHash,
                        filter.scopeHash,
                        filter.requestedSince,
                        filter.requestedUntil,
                        filter.requestedLimit,
                        filter.hitLimit
                    ]
                )
            }
        }
    }

    public func markFeedSyncRequestInstalled(requestID: String, at installedAt: Int) throws {
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE feed_sync_requests
                SET installed_at = COALESCE(installed_at, ?)
                WHERE request_id = ?
                """,
                arguments: [installedAt, requestID]
            )
        }
    }

    /// EOSEとrequest/filter更新、確定coverage、checkpointを同じtransactionで保存します。
    public func recordFeedSyncEOSE(
        requestID: String,
        at eoseAt: Int,
        eventCount: Int,
        observedOldestPosition: NostrTimelineEntryCursor?,
        observedNewestPosition: NostrTimelineEntryCursor?
    ) throws {
        try database.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM feed_sync_requests WHERE request_id = ?",
                arguments: [requestID]
            ), let request = decodeFeedSyncRequest(row) else { return }
            guard request.endReason == nil || request.endReason == .eose else { return }

            let filters = try Row.fetchAll(
                db,
                sql: """
                SELECT request_id, filter_index, filter_json, filter_hash, scope_hash,
                    requested_since, requested_until, request_limit, hit_limit
                FROM feed_sync_request_filters
                WHERE request_id = ?
                ORDER BY filter_index ASC
                """,
                arguments: [requestID]
            ).map(decodeFeedSyncFilter)
            let safeEventCount = max(0, eventCount)
            let endedAt: Int? = request.direction == .forward ? request.endedAt : eoseAt
            let endReason: String? = request.direction == .forward
                ? request.endReason?.rawValue
                : NostrFeedSyncEndReason.eose.rawValue

            try db.execute(
                sql: """
                UPDATE feed_sync_requests
                SET eose_at = COALESCE(eose_at, ?),
                    ended_at = COALESCE(ended_at, ?),
                    end_reason = COALESCE(end_reason, ?),
                    event_count = ?,
                    observed_oldest_ts = ?, observed_oldest_event_id = ?,
                    observed_newest_ts = ?, observed_newest_event_id = ?
                WHERE request_id = ?
                """,
                arguments: [
                    eoseAt,
                    endedAt,
                    endReason,
                    safeEventCount,
                    observedOldestPosition?.sortTimestamp,
                    observedOldestPosition?.eventID,
                    observedNewestPosition?.sortTimestamp,
                    observedNewestPosition?.eventID,
                    requestID
                ]
            )

            for filter in filters {
                let hitLimit = filter.requestedLimit.map { safeEventCount >= $0 } ?? false
                try db.execute(
                    sql: """
                    UPDATE feed_sync_request_filters
                    SET hit_limit = ?
                    WHERE request_id = ? AND filter_index = ?
                    """,
                    arguments: [hitLimit, requestID, filter.filterIndex]
                )

                if !hitLimit {
                    try insertFeedCoverageSegment(
                        NostrFeedCoverageSegmentRecord(
                            segmentID: "\(requestID):\(filter.filterIndex):eose",
                            feedID: request.feedID,
                            feedRevision: request.feedRevision,
                            feedSpecificationHash: request.feedSpecificationHash,
                            relayURL: request.relayURL,
                            scopeHash: filter.scopeHash,
                            lowerTimestamp: filter.requestedSince,
                            upperTimestamp: filter.requestedUntil,
                            snapshotAt: eoseAt,
                            confidence: .relayEOSE,
                            sourceRequestID: requestID,
                            createdAt: eoseAt
                        ),
                        db: db
                    )
                }

                try upsertFeedSyncCheckpoint(
                    feedID: request.feedID,
                    feedRevision: request.feedRevision,
                    relayURL: request.relayURL,
                    scopeHash: filter.scopeHash,
                    newestPosition: observedNewestPosition,
                    oldestPosition: observedOldestPosition,
                    lastEOSEAt: eoseAt,
                    lastVerifiedAt: nil,
                    updatedAt: eoseAt,
                    db: db
                )
            }
        }
    }

    public func endFeedSyncRequest(
        requestID: String,
        reason: NostrFeedSyncEndReason,
        message: String? = nil,
        at endedAt: Int,
        eventCount: Int,
        observedOldestPosition: NostrTimelineEntryCursor?,
        observedNewestPosition: NostrTimelineEntryCursor?
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE feed_sync_requests
                SET ended_at = COALESCE(ended_at, ?),
                    end_reason = COALESCE(end_reason, ?),
                    end_message = COALESCE(end_message, ?),
                    event_count = MAX(event_count, ?),
                    observed_oldest_ts = COALESCE(observed_oldest_ts, ?),
                    observed_oldest_event_id = COALESCE(observed_oldest_event_id, ?),
                    observed_newest_ts = COALESCE(observed_newest_ts, ?),
                    observed_newest_event_id = COALESCE(observed_newest_event_id, ?)
                WHERE request_id = ?
                """,
                arguments: [
                    endedAt,
                    reason.rawValue,
                    message,
                    max(0, eventCount),
                    observedOldestPosition?.sortTimestamp,
                    observedOldestPosition?.eventID,
                    observedNewestPosition?.sortTimestamp,
                    observedNewestPosition?.eventID,
                    requestID
                ]
            )
        }
    }

    /// NIP-77で差分0件になったRelayだけにverified segmentを作成します。
    public func completeFeedSyncVerification(
        requestID: String,
        outcome: NostrFeedVerificationOutcome,
        differenceCount: Int?,
        at completedAt: Int
    ) throws {
        try database.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM feed_sync_requests WHERE request_id = ?",
                arguments: [requestID]
            ), let request = decodeFeedSyncRequest(row) else { return }
            guard request.endedAt == nil, request.endReason == nil else { return }
            let filters = try Row.fetchAll(
                db,
                sql: """
                SELECT request_id, filter_index, filter_json, filter_hash, scope_hash,
                    requested_since, requested_until, request_limit, hit_limit
                FROM feed_sync_request_filters
                WHERE request_id = ?
                ORDER BY filter_index ASC
                """,
                arguments: [requestID]
            ).map(decodeFeedSyncFilter)

            try db.execute(
                sql: """
                UPDATE feed_sync_requests
                SET ended_at = COALESCE(ended_at, ?),
                    end_reason = COALESCE(end_reason, ?),
                    verification_outcome = ?, difference_count = ?
                WHERE request_id = ?
                """,
                arguments: [
                    completedAt,
                    NostrFeedSyncEndReason.completed.rawValue,
                    outcome.rawValue,
                    differenceCount,
                    requestID
                ]
            )

            guard outcome == .noRemoteMissing else { return }
            for filter in filters {
                try insertFeedCoverageSegment(
                    NostrFeedCoverageSegmentRecord(
                        segmentID: "\(requestID):\(filter.filterIndex):nip77",
                        feedID: request.feedID,
                        feedRevision: request.feedRevision,
                        feedSpecificationHash: request.feedSpecificationHash,
                        relayURL: request.relayURL,
                        scopeHash: filter.scopeHash,
                        lowerTimestamp: filter.requestedSince,
                        upperTimestamp: filter.requestedUntil,
                        snapshotAt: completedAt,
                        confidence: .nip77Verified,
                        sourceRequestID: requestID,
                        createdAt: completedAt
                    ),
                    db: db
                )
                try upsertFeedSyncCheckpoint(
                    feedID: request.feedID,
                    feedRevision: request.feedRevision,
                    relayURL: request.relayURL,
                    scopeHash: filter.scopeHash,
                    newestPosition: nil,
                    oldestPosition: nil,
                    lastEOSEAt: nil,
                    lastVerifiedAt: completedAt,
                    updatedAt: completedAt,
                    db: db
                )
            }
        }
    }

    public func feedSyncRequests(feedID: String, revision: Int? = nil) throws -> [NostrFeedSyncRequestRecord] {
        try database.read { db in
            let revisionClause = revision == nil ? "" : " AND feed_revision = ?"
            var arguments: StatementArguments = [feedID]
            if let revision { arguments += [revision] }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM feed_sync_requests
                WHERE feed_id = ?\(revisionClause)
                ORDER BY requested_at ASC, request_id ASC
                """,
                arguments: arguments
            ).compactMap(decodeFeedSyncRequest)
        }
    }

    public func feedSyncFilters(requestID: String) throws -> [NostrFeedSyncFilterRecord] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT request_id, filter_index, filter_json, filter_hash, scope_hash,
                    requested_since, requested_until, request_limit, hit_limit
                FROM feed_sync_request_filters
                WHERE request_id = ?
                ORDER BY filter_index ASC
                """,
                arguments: [requestID]
            ).map(decodeFeedSyncFilter)
        }
    }

    public func feedCoverageSegments(feedID: String, revision: Int? = nil) throws -> [NostrFeedCoverageSegmentRecord] {
        try database.read { db in
            let revisionClause = revision == nil ? "" : " AND feed_revision = ?"
            var arguments: StatementArguments = [feedID]
            if let revision { arguments += [revision] }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM feed_coverage_segments
                WHERE feed_id = ?\(revisionClause)
                ORDER BY snapshot_at ASC, segment_id ASC
                """,
                arguments: arguments
            ).compactMap(decodeFeedCoverageSegment)
        }
    }

    public func feedSyncCheckpoints(feedID: String, revision: Int? = nil) throws -> [NostrFeedSyncCheckpointRecord] {
        try database.read { db in
            let revisionClause = revision == nil ? "" : " AND feed_revision = ?"
            var arguments: StatementArguments = [feedID]
            if let revision { arguments += [revision] }
            return try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM feed_sync_checkpoints
                WHERE feed_id = ?\(revisionClause)
                ORDER BY relay_url ASC, scope_hash ASC
                """,
                arguments: arguments
            ).compactMap(decodeFeedSyncCheckpoint)
        }
    }

    public func saveFeedReadState(_ state: NostrFeedReadStateRecord) throws {
        try database.write { db in
            try saveFeedReadState(state, db: db)
        }
    }

    public func saveFeedReadBoundary(
        feedID: String,
        readBoundary: NostrTimelineEntryCursor?,
        updatedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO feed_read_state (
                    feed_id, read_sort_ts, read_event_id, updated_at
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(feed_id) DO UPDATE SET
                    read_sort_ts = excluded.read_sort_ts,
                    read_event_id = excluded.read_event_id,
                    updated_at = excluded.updated_at
                WHERE excluded.updated_at >= feed_read_state.updated_at
                """,
                arguments: [
                    feedID,
                    readBoundary?.sortTimestamp,
                    readBoundary?.eventID,
                    updatedAt
                ]
            )
        }
    }

    public func feedReadState(feedID: String) throws -> NostrFeedReadStateRecord? {
        try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT feed_id, read_sort_ts, read_event_id, updated_at
                FROM feed_read_state
                WHERE feed_id = ?
                """,
                arguments: [feedID]
            ).map(decodeFeedReadState)
        }
    }

    public func saveSyncCursor(_ cursor: NostrSyncCursorRecord) throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO sync_cursors (
                    account_id, timeline_key, relay_url, newest_created_at,
                    oldest_created_at, last_eose_at, last_negentropy_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, timeline_key, relay_url) DO UPDATE SET
                    newest_created_at = excluded.newest_created_at,
                    oldest_created_at = excluded.oldest_created_at,
                    last_eose_at = excluded.last_eose_at,
                    last_negentropy_at = excluded.last_negentropy_at
                """,
                arguments: [
                    cursor.accountID,
                    cursor.timelineKey,
                    cursor.relayURL,
                    cursor.newestCreatedAt,
                    cursor.oldestCreatedAt,
                    cursor.lastEOSEAt,
                    cursor.lastNegentropyAt
                ]
            )
        }
    }

    public func syncCursor(accountID: String, timelineKey: String, relayURL: String) throws -> NostrSyncCursorRecord? {
        try database.read { db in
            try syncCursor(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, db: db)
        }
    }

    public func saveRelayProfile(_ relay: NostrRelayProfileRecord) throws {
        let informationData = try relay.information.map(encoder.encode)
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO relay_profiles (
                    relay_url, information_json, health_score, last_eose_at,
                    last_connected_at, auth_required, payment_required
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(relay_url) DO UPDATE SET
                    information_json = excluded.information_json,
                    health_score = excluded.health_score,
                    last_eose_at = excluded.last_eose_at,
                    last_connected_at = excluded.last_connected_at,
                    auth_required = excluded.auth_required,
                    payment_required = excluded.payment_required
                """,
                arguments: [
                    relay.relayURL,
                    informationData,
                    relay.healthScore,
                    relay.lastEOSEAt,
                    relay.lastConnectedAt,
                    relay.authRequired,
                    relay.paymentRequired
                ]
            )
        }
    }

    public func relayProfile(relayURL: String) throws -> NostrRelayProfileRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT relay_url, information_json, health_score, last_eose_at,
                    last_connected_at, auth_required, payment_required
                FROM relay_profiles
                WHERE relay_url = ?
                """,
                arguments: [relayURL]
            ) else {
                return nil
            }
            return try decodeRelayProfile(row)
        }
    }

    public func saveRelayPreference(_ preference: NostrRelayPreferenceRecord) throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO relay_preferences (
                    account_id, relay_url, is_enabled, read_enabled, write_enabled, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, relay_url) DO UPDATE SET
                    is_enabled = excluded.is_enabled,
                    read_enabled = excluded.read_enabled,
                    write_enabled = excluded.write_enabled,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    preference.accountID,
                    preference.relayURL,
                    preference.isEnabled,
                    preference.readEnabled,
                    preference.writeEnabled,
                    preference.updatedAt
                ]
            )
        }
    }

    public func relayPreferences(accountID: String) throws -> [NostrRelayPreferenceRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, relay_url, is_enabled, read_enabled, write_enabled, updated_at
                FROM relay_preferences
                WHERE account_id = ?
                ORDER BY relay_url ASC
                """,
                arguments: [accountID]
            )
            return rows.map(decodeRelayPreference)
        }
    }

    public func saveDraft(_ draft: NostrDraftRecord) throws {
        let contextData = try encoder.encode(draft.context)
        let tagsData = try encoder.encode(draft.tags)
        let mediaData = try encoder.encode(draft.media)
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO drafts (
                    account_id, draft_id, context_json, text, content_warning,
                    tags_json, media_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, draft_id) DO UPDATE SET
                    context_json = excluded.context_json,
                    text = excluded.text,
                    content_warning = excluded.content_warning,
                    tags_json = excluded.tags_json,
                    media_json = excluded.media_json,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    draft.accountID,
                    draft.draftID,
                    contextData,
                    draft.text,
                    draft.contentWarning,
                    tagsData,
                    mediaData,
                    draft.updatedAt
                ]
            )
        }
    }

    public func drafts(accountID: String) throws -> [NostrDraftRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, draft_id, context_json, text,
                    content_warning, tags_json, media_json, updated_at
                FROM drafts
                WHERE account_id = ?
                ORDER BY updated_at DESC, draft_id DESC
                """,
                arguments: [accountID]
            )
            return try rows.map(decodeDraft)
        }
    }

    public func deleteDraft(accountID: String, draftID: String) throws {
        try deleteDrafts(accountID: accountID, draftIDs: [draftID])
    }

    public func deleteDrafts(accountID: String, draftIDs: [String]) throws {
        guard !draftIDs.isEmpty else { return }
        try database.write { db in
            for draftID in draftIDs {
                try db.execute(
                    sql: """
                    DELETE FROM drafts
                    WHERE account_id = ? AND draft_id = ?
                    """,
                    arguments: [accountID, draftID]
                )
            }
        }
    }

    public func saveFilterRule(_ rule: NostrFilterRuleRecord) throws {
        try database.write { db in
            let scopesData = try encoder.encode(rule.scopes.map(\.rawValue).sorted())
            try db.execute(
                sql: """
                INSERT INTO filter_rules (
                    rule_id, account_id, rule_kind, value, expires_at, is_enabled, presentation, scopes_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(rule_id) DO UPDATE SET
                    account_id = excluded.account_id,
                    rule_kind = excluded.rule_kind,
                    value = excluded.value,
                    expires_at = excluded.expires_at,
                    is_enabled = excluded.is_enabled,
                    presentation = excluded.presentation,
                    scopes_json = excluded.scopes_json,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    rule.ruleID,
                    rule.accountID,
                    rule.kind.rawValue,
                    rule.value,
                    rule.expiresAt,
                    rule.isEnabled,
                    rule.presentation.rawValue,
                    scopesData,
                    rule.createdAt,
                    rule.updatedAt
                ]
            )
        }
    }

    public func filterRules(accountID: String) throws -> [NostrFilterRuleRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT rule_id, account_id, rule_kind, value, expires_at, is_enabled, presentation, scopes_json, created_at, updated_at
                FROM filter_rules
                WHERE account_id = ?
                ORDER BY updated_at DESC, rule_id DESC
                """,
                arguments: [accountID]
            )
            return rows.compactMap(decodeFilterRule)
        }
    }

    public func filterRuleMatchingCount(
        accountID: String,
        rule: NostrFilterRuleRecord,
        timeline: NostrFilterTimelineScope,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> Int {
        try filterRuleMatchingEvents(accountID: accountID, rule: rule, timeline: timeline, limit: 10_000, now: now).count
    }

    public func filterRuleMatchingEvents(
        accountID: String,
        rule: NostrFilterRuleRecord,
        timeline: NostrFilterTimelineScope,
        limit: Int = 100,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [NostrEvent] {
        guard rule.accountID == accountID else { return [] }
        let events = try events(kind: 1, limit: 10_000, now: now)
        let ruleSet = NostrFilterRuleSet(rules: [rule])
        let matches = events.filter { ruleSet.matchingRule(for: $0, timeline: timeline, now: now) != nil }
        return Array(matches.prefix(max(0, limit)))
    }

    public func deleteFilterRule(accountID: String, ruleID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                DELETE FROM filter_rules
                WHERE account_id = ? AND rule_id = ?
                """,
                arguments: [accountID, ruleID]
            )
        }
    }

    public func saveLocalBookmark(_ bookmark: NostrLocalBookmarkRecord) throws {
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO local_bookmarks (account_id, event_id, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(account_id, event_id) DO UPDATE SET
                    created_at = excluded.created_at
                """,
                arguments: [bookmark.accountID, bookmark.eventID, bookmark.createdAt]
            )
        }
    }

    public func localBookmarks(accountID: String) throws -> [NostrLocalBookmarkRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT account_id, event_id, created_at
                FROM local_bookmarks
                WHERE account_id = ?
                ORDER BY created_at DESC, event_id DESC
                """,
                arguments: [accountID]
            )
            return rows.map(decodeLocalBookmark)
        }
    }

    public func deleteLocalBookmark(accountID: String, eventID: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                DELETE FROM local_bookmarks
                WHERE account_id = ? AND event_id = ?
                """,
                arguments: [accountID, eventID]
            )
        }
    }

    public func saveRelaySyncEvents(_ events: [NostrRelaySyncEventRecord]) throws {
        guard !events.isEmpty else { return }

        try database.write { db in
            try saveRelaySyncEvents(events, db: db)
            try updateSyncCursors(from: events, db: db)
        }
    }

    public func relaySyncEvents(
        accountID: String,
        timelineKey: String,
        relayURL: String? = nil,
        limit: Int = 50
    ) throws -> [NostrRelaySyncEventRecord] {
        try database.read { db in
            var sql = """
            SELECT account_id, timeline_key, relay_url, event_kind, occurred_at,
                subscription_id, event_count, newest_created_at, oldest_created_at,
                latency_ms, message
            FROM relay_sync_events
            WHERE account_id = ? AND timeline_key = ?
            """
            var arguments: StatementArguments = [accountID, timelineKey]
            if let relayURL {
                sql += " AND relay_url = ?"
                arguments += [relayURL]
            }
            sql += " ORDER BY occurred_at DESC, id DESC LIMIT ?"
            arguments += [limit]

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap(decodeRelaySyncEvent)
        }
    }

    public func relaySyncSummaries(accountID: String, timelineKey: String) throws -> [NostrRelaySyncSummaryRecord] {
        try database.read { db in
            let relayURLs = try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT relay_url
                FROM relay_sync_events
                WHERE account_id = ? AND timeline_key = ?
                ORDER BY relay_url ASC
                """,
                arguments: [accountID, timelineKey]
            )

            return try relayURLs.map { relayURL in
                let lastEvent = try Row.fetchOne(
                    db,
                    sql: """
                    SELECT account_id, timeline_key, relay_url, event_kind, occurred_at,
                        subscription_id, event_count, newest_created_at, oldest_created_at,
                        latency_ms, message
                    FROM relay_sync_events
                    WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                    ORDER BY occurred_at DESC, id DESC
                    LIMIT 1
                    """,
                    arguments: [accountID, timelineKey, relayURL]
                ).flatMap(decodeRelaySyncEvent)

                let lastConnectedAt = try relaySyncLastEventAt(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .connected, db: db)
                let lastEOSEAt = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT MAX(occurred_at)
                    FROM relay_sync_events
                    WHERE account_id = ? AND timeline_key = ? AND relay_url = ? AND event_kind = ?
                    """,
                    arguments: [accountID, timelineKey, relayURL, NostrRelaySyncEventKind.eose.rawValue]
                )
                let lastTimeoutAt = try relaySyncLastEventAt(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .timeout, db: db)
                let lastErrorAt = try relaySyncLastErrorAt(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, db: db)
                let closedCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .closed, db: db)
                let reconnectCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .reconnect, db: db)
                let timeoutCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .timeout, db: db)
                let partialFailureCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .partialFailure, db: db)
                let authRequiredCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .authRequired, db: db)
                let paymentRequiredCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .paymentRequired, db: db)
                let rejectedCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .rejected, db: db)
                let suspendedCount = try relaySyncEventCount(accountID: accountID, timelineKey: timelineKey, relayURL: relayURL, kind: .suspended, db: db)
                let lastPartialFailureReason = try String.fetchOne(
                    db,
                    sql: """
                    SELECT message
                    FROM relay_sync_events
                    WHERE account_id = ? AND timeline_key = ? AND relay_url = ? AND event_kind = ?
                    ORDER BY occurred_at DESC, id DESC
                    LIMIT 1
                    """,
                    arguments: [accountID, timelineKey, relayURL, NostrRelaySyncEventKind.partialFailure.rawValue]
                )
                let totalEventCount = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(SUM(event_count), 0)
                    FROM relay_sync_events
                    WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                    """,
                    arguments: [accountID, timelineKey, relayURL]
                ) ?? 0
                let averageEOSELatency = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT CAST(AVG(latency_ms) AS INTEGER)
                    FROM relay_sync_events
                    WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                        AND event_kind = ? AND latency_ms IS NOT NULL
                    """,
                    arguments: [accountID, timelineKey, relayURL, NostrRelaySyncEventKind.eose.rawValue]
                )

                return NostrRelaySyncSummaryRecord(
                    relayURL: relayURL,
                    lastEventKind: lastEvent?.kind,
                    lastEventAt: lastEvent?.occurredAt,
                    lastConnectedAt: lastConnectedAt,
                    lastEOSEAt: lastEOSEAt,
                    lastTimeoutAt: lastTimeoutAt,
                    lastErrorAt: lastErrorAt,
                    closedCount: closedCount,
                    reconnectCount: reconnectCount,
                    timeoutCount: timeoutCount,
                    partialFailureCount: partialFailureCount,
                    authRequiredCount: authRequiredCount,
                    paymentRequiredCount: paymentRequiredCount,
                    rejectedCount: rejectedCount,
                    suspendedCount: suspendedCount,
                    lastPartialFailureReason: lastPartialFailureReason,
                    totalEventCount: totalEventCount,
                    averageEOSELatencyMilliseconds: averageEOSELatency
                )
            }
        }
    }

    public func recordRelayTraffic(_ deltas: [NostrRelayTrafficDelta]) throws {
        guard !deltas.isEmpty else { return }

        try database.write { db in
            for delta in deltas {
                let hourStart = Self.hourStart(for: delta.occurredAt)
                try db.execute(
                    sql: """
                    INSERT INTO relay_traffic_hourly_counters (
                        account_id, relay_url, hour_start, network_type, sync_mode,
                        received_bytes, sent_bytes, received_messages, sent_messages, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(account_id, relay_url, hour_start, network_type, sync_mode) DO UPDATE SET
                        received_bytes = received_bytes + excluded.received_bytes,
                        sent_bytes = sent_bytes + excluded.sent_bytes,
                        received_messages = received_messages + excluded.received_messages,
                        sent_messages = sent_messages + excluded.sent_messages,
                        updated_at = excluded.updated_at
                    """,
                    arguments: [
                        delta.accountID,
                        delta.relayURL,
                        hourStart,
                        delta.networkType.rawValue,
                        delta.syncMode.rawValue,
                        delta.receivedBytes,
                        delta.sentBytes,
                        delta.receivedMessages,
                        delta.sentMessages,
                        delta.occurredAt
                    ]
                )
            }
        }
    }

    public func relayTrafficTotals(
        accountID: String,
        start: Int,
        end: Int
    ) throws -> NostrRelayTrafficTotals {
        try database.read { db in
            try relayTrafficTotals(accountID: accountID, relayURL: nil, start: start, end: end, db: db)
        }
    }

    public func relayTrafficTotalsByRelay(
        accountID: String,
        start: Int,
        end: Int
    ) throws -> [String: NostrRelayTrafficTotals] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT relay_url,
                    COALESCE(SUM(received_bytes), 0) AS received_bytes,
                    COALESCE(SUM(sent_bytes), 0) AS sent_bytes,
                    COALESCE(SUM(received_messages), 0) AS received_messages,
                    COALESCE(SUM(sent_messages), 0) AS sent_messages
                FROM relay_traffic_hourly_counters
                WHERE account_id = ? AND hour_start >= ? AND hour_start < ?
                GROUP BY relay_url
                ORDER BY relay_url ASC
                """,
                arguments: [accountID, start, end]
            )
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (
                    row["relay_url"],
                    NostrRelayTrafficTotals(
                        receivedBytes: row["received_bytes"],
                        sentBytes: row["sent_bytes"],
                        receivedMessages: row["received_messages"],
                        sentMessages: row["sent_messages"]
                    )
                )
            })
        }
    }

    private static func hourStart(for timestamp: Int) -> Int {
        timestamp - timestamp % 3_600
    }

    private func relayTrafficTotals(
        accountID: String,
        relayURL: String?,
        start: Int,
        end: Int,
        db: Database
    ) throws -> NostrRelayTrafficTotals {
        var sql = """
        SELECT COALESCE(SUM(received_bytes), 0) AS received_bytes,
            COALESCE(SUM(sent_bytes), 0) AS sent_bytes,
            COALESCE(SUM(received_messages), 0) AS received_messages,
            COALESCE(SUM(sent_messages), 0) AS sent_messages
        FROM relay_traffic_hourly_counters
        WHERE account_id = ? AND hour_start >= ? AND hour_start < ?
        """
        var arguments: StatementArguments = [accountID, start, end]
        if let relayURL {
            sql += " AND relay_url = ?"
            arguments += [relayURL]
        }
        guard let row = try Row.fetchOne(db, sql: sql, arguments: arguments) else {
            return .zero
        }
        return NostrRelayTrafficTotals(
            receivedBytes: row["received_bytes"],
            sentBytes: row["sent_bytes"],
            receivedMessages: row["received_messages"],
            sentMessages: row["sent_messages"]
        )
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createNostrEventStore") { db in
            try db.create(table: "events", ifNotExists: true) { table in
                table.column("event_id", .text).primaryKey()
                table.column("pubkey", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.column("kind", .integer).notNull()
                table.column("content", .text).notNull()
                table.column("tags_json", .blob).notNull()
                table.column("sig", .text).notNull()
                table.column("received_at", .integer).notNull()
                table.column("deleted_at", .integer)
                table.column("expires_at", .integer)
                table.column("raw_json", .blob).notNull()
            }

            try db.create(index: "events_kind_created_at", on: "events", columns: ["kind", "created_at"])
            try db.create(index: "events_pubkey_created_at", on: "events", columns: ["pubkey", "created_at"])
            try db.create(index: "events_deleted_at", on: "events", columns: ["deleted_at"])
            try db.create(index: "events_expires_at", on: "events", columns: ["expires_at"])

            try db.create(table: "event_tags", ifNotExists: true) { table in
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("pos", .integer).notNull()
                table.column("tag_name", .text).notNull()
                table.column("tag_value", .text)
                table.column("relay_hint", .text)
                table.column("marker", .text)
                table.column("raw_json", .blob).notNull()
                table.primaryKey(["event_id", "pos"])
            }

            try db.create(index: "event_tags_name_value", on: "event_tags", columns: ["tag_name", "tag_value"])
            try db.create(index: "event_tags_name_event", on: "event_tags", columns: ["tag_name", "event_id"])

            try db.create(table: "replaceable_heads", ifNotExists: true) { table in
                table.column("pubkey", .text).notNull()
                table.column("kind", .integer).notNull()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["pubkey", "kind"])
            }

            try db.create(index: "replaceable_heads_updated_at", on: "replaceable_heads", columns: ["updated_at"])

            try db.create(table: "timeline_entries", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("sort_ts", .integer).notNull()
                table.column("source", .text).notNull()
                table.column("inserted_at", .integer).notNull()
                table.column("gap_before", .boolean).notNull().defaults(to: false)
                table.column("gap_after", .boolean).notNull().defaults(to: false)
                table.uniqueKey(["account_id", "timeline_key", "event_id"])
            }

            try db.create(index: "timeline_entries_account_timeline_sort", on: "timeline_entries", columns: ["account_id", "timeline_key", "sort_ts"])
            try db.create(index: "timeline_entries_account_timeline_event", on: "timeline_entries", columns: ["account_id", "timeline_key", "event_id"])

            try db.create(table: "sync_cursors", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("newest_created_at", .integer)
                table.column("oldest_created_at", .integer)
                table.column("last_eose_at", .integer)
                table.column("last_negentropy_at", .integer)
                table.primaryKey(["account_id", "timeline_key", "relay_url"])
            }

            try db.create(index: "sync_cursors_timeline", on: "sync_cursors", columns: ["account_id", "timeline_key"])

            try db.create(table: "relay_profiles", ifNotExists: true) { table in
                table.column("relay_url", .text).primaryKey()
                table.column("information_json", .blob)
                table.column("health_score", .double).notNull().defaults(to: 0)
                table.column("last_eose_at", .integer)
                table.column("last_connected_at", .integer)
                table.column("auth_required", .boolean).notNull().defaults(to: false)
                table.column("payment_required", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "relay_profiles_health", on: "relay_profiles", columns: ["health_score"])
            try db.create(index: "relay_profiles_last_eose", on: "relay_profiles", columns: ["last_eose_at"])

            try db.create(table: "relay_sync_events", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("event_kind", .text).notNull()
                table.column("occurred_at", .integer).notNull()
                table.column("subscription_id", .text)
                table.column("event_count", .integer).notNull().defaults(to: 0)
                table.column("newest_created_at", .integer)
                table.column("oldest_created_at", .integer)
                table.column("latency_ms", .integer)
                table.column("message", .text)
            }

            try db.create(index: "relay_sync_events_timeline", on: "relay_sync_events", columns: ["account_id", "timeline_key", "occurred_at"])
            try db.create(index: "relay_sync_events_relay", on: "relay_sync_events", columns: ["relay_url", "occurred_at"])

            try db.create(table: "event_sources", ifNotExists: true) { table in
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("relay_url", .text).notNull()
                table.column("first_seen_at", .integer).notNull()
                table.column("last_seen_at", .integer).notNull()
                table.primaryKey(["event_id", "relay_url"])
            }

            try db.create(index: "event_sources_relay", on: "event_sources", columns: ["relay_url"])

            try db.create(table: "deletion_tombstones", ifNotExists: true) { table in
                table.column("target_event_id", .text).primaryKey()
                table.column("deletion_event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.column("author_pubkey", .text).notNull()
            }

            try db.create(table: "timeline_state", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relays_json", .blob).notNull()
                table.column("followed_pubkeys_json", .blob).notNull()
                table.column("nip05_resolutions_json", .blob).notNull()
                table.column("has_more_older", .boolean).notNull().defaults(to: true)
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["account_id", "timeline_key"])
            }
        }

        migrator.registerMigration("expandNostrEventStoreSchema") { db in
            try db.create(table: "timeline_entries", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("sort_ts", .integer).notNull()
                table.column("source", .text).notNull()
                table.column("inserted_at", .integer).notNull()
                table.column("gap_before", .boolean).notNull().defaults(to: false)
                table.column("gap_after", .boolean).notNull().defaults(to: false)
                table.uniqueKey(["account_id", "timeline_key", "event_id"])
            }

            try db.create(index: "timeline_entries_account_timeline_sort", on: "timeline_entries", columns: ["account_id", "timeline_key", "sort_ts"], ifNotExists: true)
            try db.create(index: "timeline_entries_account_timeline_event", on: "timeline_entries", columns: ["account_id", "timeline_key", "event_id"], ifNotExists: true)

            try db.create(table: "sync_cursors", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("newest_created_at", .integer)
                table.column("oldest_created_at", .integer)
                table.column("last_eose_at", .integer)
                table.column("last_negentropy_at", .integer)
                table.primaryKey(["account_id", "timeline_key", "relay_url"])
            }

            try db.create(index: "sync_cursors_timeline", on: "sync_cursors", columns: ["account_id", "timeline_key"], ifNotExists: true)

            try db.create(table: "relay_profiles", ifNotExists: true) { table in
                table.column("relay_url", .text).primaryKey()
                table.column("information_json", .blob)
                table.column("health_score", .double).notNull().defaults(to: 0)
                table.column("last_eose_at", .integer)
                table.column("last_connected_at", .integer)
                table.column("auth_required", .boolean).notNull().defaults(to: false)
                table.column("payment_required", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "relay_profiles_health", on: "relay_profiles", columns: ["health_score"], ifNotExists: true)
            try db.create(index: "relay_profiles_last_eose", on: "relay_profiles", columns: ["last_eose_at"], ifNotExists: true)

            try db.create(table: "event_sources", ifNotExists: true) { table in
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("relay_url", .text).notNull()
                table.column("first_seen_at", .integer).notNull()
                table.column("last_seen_at", .integer).notNull()
                table.primaryKey(["event_id", "relay_url"])
            }

            try db.create(index: "event_sources_relay", on: "event_sources", columns: ["relay_url"], ifNotExists: true)

            try db.create(table: "deletion_tombstones", ifNotExists: true) { table in
                table.column("target_event_id", .text).primaryKey()
                table.column("deletion_event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.column("author_pubkey", .text).notNull()
            }

            try db.create(table: "timeline_state", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relays_json", .blob).notNull()
                table.column("followed_pubkeys_json", .blob).notNull()
                table.column("nip05_resolutions_json", .blob).notNull()
                table.column("has_more_older", .boolean).notNull().defaults(to: true)
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["account_id", "timeline_key"])
            }
        }

        migrator.registerMigration("addRelaySyncEvents") { db in
            try db.create(table: "relay_sync_events", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_id", .text).notNull()
                table.column("timeline_key", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("event_kind", .text).notNull()
                table.column("occurred_at", .integer).notNull()
                table.column("subscription_id", .text)
                table.column("event_count", .integer).notNull().defaults(to: 0)
                table.column("newest_created_at", .integer)
                table.column("oldest_created_at", .integer)
                table.column("latency_ms", .integer)
                table.column("message", .text)
            }

            try db.create(index: "relay_sync_events_timeline", on: "relay_sync_events", columns: ["account_id", "timeline_key", "occurred_at"], ifNotExists: true)
            try db.create(index: "relay_sync_events_relay", on: "relay_sync_events", columns: ["relay_url", "occurred_at"], ifNotExists: true)
        }

        migrator.registerMigration("addRelayPreferences") { db in
            try db.create(table: "relay_preferences", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("is_enabled", .boolean).notNull().defaults(to: true)
                table.column("read_enabled", .boolean).notNull().defaults(to: true)
                table.column("write_enabled", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["account_id", "relay_url"])
            }

            try db.create(index: "relay_preferences_account", on: "relay_preferences", columns: ["account_id", "updated_at"], ifNotExists: true)
        }

        migrator.registerMigration("addComposeDrafts") { db in
            try db.create(table: "drafts", ifNotExists: true) { table in
                table.column("draft_id", .text).primaryKey()
                table.column("account_id", .text).notNull()
                table.column("kind", .integer).notNull()
                table.column("parent_event_id", .text)
                table.column("text", .text).notNull()
                table.column("content_warning", .text)
                table.column("media_json", .blob).notNull()
                table.column("updated_at", .integer).notNull()
            }

            try db.create(index: "drafts_account_updated", on: "drafts", columns: ["account_id", "updated_at"], ifNotExists: true)
        }

        migrator.registerMigration("replaceComposeDraftsV2") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS drafts")
            try db.create(table: "drafts") { table in
                table.column("account_id", .text).notNull()
                table.column("draft_id", .text).notNull()
                table.column("context_json", .blob).notNull()
                table.column("text", .text).notNull()
                table.column("content_warning", .text)
                table.column("tags_json", .blob).notNull()
                table.column("media_json", .blob).notNull()
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["account_id", "draft_id"])
            }
            try db.create(
                index: "drafts_account_updated",
                on: "drafts",
                columns: ["account_id", "updated_at"]
            )
        }

        migrator.registerMigration("addLocalFiltersAndBookmarks") { db in
            try db.create(table: "filter_rules", ifNotExists: true) { table in
                table.column("rule_id", .text).primaryKey()
                table.column("account_id", .text).notNull()
                table.column("rule_kind", .text).notNull()
                table.column("value", .text).notNull()
                table.column("expires_at", .integer)
                table.column("is_enabled", .boolean).notNull().defaults(to: true)
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
            }
            try db.create(index: "filter_rules_account", on: "filter_rules", columns: ["account_id", "updated_at"], ifNotExists: true)

            try db.create(table: "local_bookmarks", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("event_id", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.primaryKey(["account_id", "event_id"])
            }
            try db.create(index: "local_bookmarks_account", on: "local_bookmarks", columns: ["account_id", "created_at"], ifNotExists: true)
        }

        migrator.registerMigration("addFilterRulePresentationAndScopes") { db in
            try db.alter(table: "filter_rules") { table in
                table.add(column: "presentation", .text).notNull().defaults(to: NostrFilterRulePresentation.maskWithWarning.rawValue)
                table.add(column: "scopes_json", .blob)
            }
        }

        migrator.registerMigration("addNostrLists") { db in
            try db.create(table: "addressable_heads", ifNotExists: true) { table in
                table.column("kind", .integer).notNull()
                table.column("pubkey", .text).notNull()
                table.column("d_tag", .text).notNull()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["kind", "pubkey", "d_tag"])
            }
            try db.create(index: "addressable_heads_updated_at", on: "addressable_heads", columns: ["updated_at"], ifNotExists: true)

            try db.create(table: "lists", ifNotExists: true) { table in
                table.column("list_id", .text).primaryKey()
                table.column("account_id", .text).notNull()
                table.column("kind", .integer).notNull()
                table.column("pubkey", .text).notNull()
                table.column("d_tag", .text).notNull()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("title", .text)
                table.column("visibility", .text).notNull()
                table.column("private_content", .text)
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
            }
            try db.create(index: "lists_account_updated", on: "lists", columns: ["account_id", "updated_at"], ifNotExists: true)
            try db.create(index: "lists_kind", on: "lists", columns: ["kind"], ifNotExists: true)

            try db.create(table: "list_items", ifNotExists: true) { table in
                table.column("list_id", .text).notNull().references("lists", column: "list_id", onDelete: .cascade)
                table.column("item_key", .text).notNull()
                table.column("item_type", .text).notNull()
                table.column("value", .text).notNull()
                table.column("relay_hint", .text)
                table.column("visibility", .text).notNull()
                table.column("position", .integer).notNull()
                table.primaryKey(["list_id", "item_key", "position"])
            }
            try db.create(index: "list_items_list_position", on: "list_items", columns: ["list_id", "position"], ifNotExists: true)
            try db.create(index: "list_items_type_value", on: "list_items", columns: ["item_type", "value"], ifNotExists: true)
        }

        migrator.registerMigration("addMediaAssets") { db in
            try db.create(table: "media_assets", ifNotExists: true) { table in
                table.column("asset_id", .text).primaryKey()
                table.column("event_id", .text).notNull().references("events", column: "event_id", onDelete: .cascade)
                table.column("url", .text).notNull()
                table.column("mime_type", .text)
                table.column("blurhash", .text)
                table.column("width", .integer)
                table.column("height", .integer)
                table.column("alt", .text)
                table.column("sha256", .text)
                table.column("status", .text).notNull()
                table.column("local_path", .text)
                table.column("created_at", .integer).notNull()
            }
            try db.create(index: "media_assets_event", on: "media_assets", columns: ["event_id"], ifNotExists: true)
            try db.create(index: "media_assets_url", on: "media_assets", columns: ["url"], ifNotExists: true)
            try db.create(index: "media_assets_status", on: "media_assets", columns: ["status"], ifNotExists: true)
        }

        migrator.registerMigration("addLinkPreviews") { db in
            try db.create(table: "link_previews", ifNotExists: true) { table in
                table.column("url", .text).notNull()
                table.column("normalized_url", .text).primaryKey()
                table.column("status", .text).notNull()
                table.column("title", .text)
                table.column("summary", .text)
                table.column("site_name", .text)
                table.column("image_url", .text)
                table.column("fetched_at", .integer)
                table.column("expires_at", .integer)
                table.column("error", .text)
            }
            try db.create(index: "link_previews_status", on: "link_previews", columns: ["status"], ifNotExists: true)
            try db.create(index: "link_previews_expires", on: "link_previews", columns: ["expires_at"], ifNotExists: true)
        }

        migrator.registerMigration("addOutbox") { db in
            try db.create(table: "outbox_events", ifNotExists: true) { table in
                table.column("local_id", .text).primaryKey()
                table.column("account_id", .text).notNull()
                table.column("event_id", .text)
                table.column("event_json", .blob).notNull()
                table.column("status", .text).notNull()
                table.column("created_at", .integer).notNull()
                table.column("next_retry_at", .integer)
                table.column("last_error", .text)
            }
            try db.create(index: "outbox_events_account_status", on: "outbox_events", columns: ["account_id", "status", "created_at"], ifNotExists: true)

            try db.create(table: "outbox_relays", ifNotExists: true) { table in
                table.column("local_id", .text).notNull().references("outbox_events", column: "local_id", onDelete: .cascade)
                table.column("relay_url", .text).notNull()
                table.column("status", .text).notNull()
                table.column("last_attempt_at", .integer)
                table.column("ok_message", .text)
                table.primaryKey(["local_id", "relay_url"])
            }
            try db.create(index: "outbox_relays_status", on: "outbox_relays", columns: ["status"], ifNotExists: true)
        }

        migrator.registerMigration("addRelayTrafficHourlyCounters") { db in
            try db.create(table: "relay_traffic_hourly_counters", ifNotExists: true) { table in
                table.column("account_id", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("hour_start", .integer).notNull()
                table.column("network_type", .text).notNull()
                table.column("sync_mode", .text).notNull()
                table.column("received_bytes", .integer).notNull().defaults(to: 0)
                table.column("sent_bytes", .integer).notNull().defaults(to: 0)
                table.column("received_messages", .integer).notNull().defaults(to: 0)
                table.column("sent_messages", .integer).notNull().defaults(to: 0)
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["account_id", "relay_url", "hour_start", "network_type", "sync_mode"])
            }
            try db.create(
                index: "relay_traffic_hourly_account_hour",
                on: "relay_traffic_hourly_counters",
                columns: ["account_id", "hour_start"],
                ifNotExists: true
            )
            try db.create(
                index: "relay_traffic_hourly_relay",
                on: "relay_traffic_hourly_counters",
                columns: ["relay_url", "hour_start"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("upgradeDeletionTombstonesAndAddAddresses") { db in
            try db.execute(sql: "ALTER TABLE deletion_tombstones RENAME TO deletion_tombstones_legacy")
            try db.create(table: "deletion_tombstones") { table in
                table.column("target_event_id", .text).notNull()
                table.column("deletion_event_id", .text)
                    .notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.column("author_pubkey", .text).notNull()
                table.primaryKey(["target_event_id", "author_pubkey"])
            }
            try db.execute(
                sql: """
                INSERT INTO deletion_tombstones (
                    target_event_id, deletion_event_id, deleted_at, author_pubkey
                )
                SELECT target_event_id, deletion_event_id, deleted_at, author_pubkey
                FROM deletion_tombstones_legacy
                """
            )
            try db.drop(table: "deletion_tombstones_legacy")

            try db.create(table: "address_deletion_tombstones") { table in
                table.column("kind", .integer).notNull()
                table.column("pubkey", .text).notNull()
                table.column("d_tag", .text).notNull()
                table.column("deletion_event_id", .text)
                    .notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("deleted_at", .integer).notNull()
                table.primaryKey(["kind", "pubkey", "d_tag"])
            }
            try db.create(
                index: "address_deletion_tombstones_author",
                on: "address_deletion_tombstones",
                columns: ["pubkey", "deleted_at"]
            )
        }

        migrator.registerMigration("addGenericFeedProjectionV2") { db in
            try db.execute(
                sql: """
                CREATE INDEX timeline_entries_account_timeline_keyset
                ON timeline_entries(account_id, timeline_key, sort_ts DESC, event_id ASC)
                """
            )

            try db.create(table: "feed_definitions") { table in
                table.column("feed_id", .text).primaryKey()
                table.column("account_id", .text).notNull()
                table.column("feed_kind", .text).notNull()
                table.column("spec_json", .blob).notNull()
                table.column("spec_hash", .text).notNull()
                table.column("sort_policy", .text).notNull()
                table.column("revision", .integer).notNull()
                table.column("created_at", .integer).notNull()
                table.column("updated_at", .integer).notNull()
            }
            try db.create(
                index: "feed_definitions_account_kind",
                on: "feed_definitions",
                columns: ["account_id", "feed_kind", "updated_at"]
            )

            try db.create(table: "feed_memberships") { table in
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("event_id", .text)
                    .notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("subject_event_id", .text)
                table.column("sort_ts", .integer).notNull()
                table.column("reason", .text).notNull()
                table.column("inserted_at", .integer).notNull()
                table.primaryKey(["feed_id", "event_id"])
            }
            try db.execute(
                sql: """
                CREATE INDEX feed_memberships_feed_sort
                ON feed_memberships(feed_id, sort_ts DESC, event_id ASC)
                """
            )

            try db.create(table: "feed_coverage") { table in
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("relay_url", .text).notNull()
                table.column("filter_revision", .text).notNull()
                table.column("lower_sort_ts", .integer)
                table.column("lower_event_id", .text)
                table.column("upper_sort_ts", .integer)
                table.column("upper_event_id", .text)
                table.column("coverage_state", .text).notNull()
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["feed_id", "relay_url", "filter_revision"])
                table.check(sql: "(lower_sort_ts IS NULL) = (lower_event_id IS NULL)")
                table.check(sql: "(upper_sort_ts IS NULL) = (upper_event_id IS NULL)")
            }
            try db.create(
                index: "feed_coverage_feed_state",
                on: "feed_coverage",
                columns: ["feed_id", "coverage_state", "updated_at"]
            )

            try db.create(table: "feed_read_state") { table in
                table.column("feed_id", .text)
                    .primaryKey()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("anchor_event_id", .text)
                table.column("anchor_offset", .double).notNull().defaults(to: 0)
                table.column("read_sort_ts", .integer)
                table.column("read_event_id", .text)
                table.column("updated_at", .integer).notNull()
                table.check(sql: "(read_sort_ts IS NULL) = (read_event_id IS NULL)")
            }
        }

        migrator.registerMigration("addOutboxRelayAttemptCount") { db in
            try db.alter(table: "outbox_relays") { table in
                table.add(column: "attempt_count", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("replaceGenericFeedCoverageV3") { db in
            try db.drop(table: "feed_coverage")

            try db.create(table: "feed_sync_requests") { table in
                table.column("request_id", .text).primaryKey()
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("feed_revision", .integer).notNull()
                table.column("feed_spec_hash", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("subscription_id", .text).notNull()
                table.column("protocol_kind", .text).notNull()
                table.column("direction", .text).notNull()
                table.column("purpose", .text).notNull()
                table.column("requested_at", .integer).notNull()
                table.column("installed_at", .integer)
                table.column("eose_at", .integer)
                table.column("ended_at", .integer)
                table.column("end_reason", .text)
                table.column("end_message", .text)
                table.column("event_count", .integer).notNull().defaults(to: 0)
                table.column("observed_oldest_ts", .integer)
                table.column("observed_oldest_event_id", .text)
                table.column("observed_newest_ts", .integer)
                table.column("observed_newest_event_id", .text)
                table.column("verification_outcome", .text)
                table.column("difference_count", .integer)
                table.check(sql: "(observed_oldest_ts IS NULL) = (observed_oldest_event_id IS NULL)")
                table.check(sql: "(observed_newest_ts IS NULL) = (observed_newest_event_id IS NULL)")
            }
            try db.create(
                index: "feed_sync_requests_feed_revision",
                on: "feed_sync_requests",
                columns: ["feed_id", "feed_revision", "requested_at"]
            )
            try db.create(
                index: "feed_sync_requests_relay_subscription",
                on: "feed_sync_requests",
                columns: ["relay_url", "subscription_id", "requested_at"]
            )

            try db.create(table: "feed_sync_request_filters") { table in
                table.column("request_id", .text)
                    .notNull()
                    .references("feed_sync_requests", column: "request_id", onDelete: .cascade)
                table.column("filter_index", .integer).notNull()
                table.column("filter_json", .blob).notNull()
                table.column("filter_hash", .text).notNull()
                table.column("scope_hash", .text).notNull()
                table.column("requested_since", .integer)
                table.column("requested_until", .integer)
                table.column("request_limit", .integer)
                table.column("hit_limit", .boolean).notNull().defaults(to: false)
                table.primaryKey(["request_id", "filter_index"])
            }
            try db.create(
                index: "feed_sync_request_filters_scope",
                on: "feed_sync_request_filters",
                columns: ["scope_hash", "requested_since", "requested_until"]
            )

            try db.create(table: "feed_coverage_segments") { table in
                table.column("segment_id", .text).primaryKey()
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("feed_revision", .integer).notNull()
                table.column("feed_spec_hash", .text).notNull()
                table.column("relay_url", .text).notNull()
                table.column("scope_hash", .text).notNull()
                table.column("lower_ts", .integer)
                table.column("upper_ts", .integer)
                table.column("snapshot_at", .integer).notNull()
                table.column("confidence", .text).notNull()
                table.column("source_request_id", .text)
                    .notNull()
                    .references("feed_sync_requests", column: "request_id", onDelete: .cascade)
                table.column("created_at", .integer).notNull()
            }
            try db.create(
                index: "feed_coverage_segments_assessment",
                on: "feed_coverage_segments",
                columns: ["feed_id", "feed_revision", "relay_url", "scope_hash", "snapshot_at"]
            )

            try db.create(table: "feed_sync_checkpoints") { table in
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("feed_revision", .integer).notNull()
                table.column("relay_url", .text).notNull()
                table.column("scope_hash", .text).notNull()
                table.column("newest_ts", .integer)
                table.column("newest_event_id", .text)
                table.column("oldest_ts", .integer)
                table.column("oldest_event_id", .text)
                table.column("last_eose_at", .integer)
                table.column("last_verified_at", .integer)
                table.column("updated_at", .integer).notNull()
                table.primaryKey(["feed_id", "feed_revision", "relay_url", "scope_hash"])
                table.check(sql: "(newest_ts IS NULL) = (newest_event_id IS NULL)")
                table.check(sql: "(oldest_ts IS NULL) = (oldest_event_id IS NULL)")
            }
        }

        migrator.registerMigration("replaceGenericFeedProjectionV4") { db in
            // projectionをresetするため、旧revisionに対するcoverage/checkpointも破棄します。
            try db.execute(sql: "DELETE FROM feed_sync_checkpoints")
            try db.execute(sql: "DELETE FROM feed_sync_requests")
            try db.drop(table: "feed_read_state")
            try db.drop(table: "feed_memberships")

            try db.create(table: "feed_memberships") { table in
                table.column("feed_id", .text)
                    .notNull()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("feed_revision", .integer).notNull()
                table.column("event_id", .text)
                    .notNull()
                    .references("events", column: "event_id", onDelete: .cascade)
                table.column("subject_event_id", .text)
                table.column("sort_ts", .integer).notNull()
                table.column("reason", .text).notNull()
                table.column("inserted_at", .integer).notNull()
                table.primaryKey(["feed_id", "feed_revision", "event_id"])
            }
            try db.execute(
                sql: """
                CREATE INDEX feed_memberships_feed_revision_sort
                ON feed_memberships(feed_id, feed_revision, sort_ts DESC, event_id ASC)
                """
            )

            try db.execute(
                sql: """
                CREATE TABLE feed_membership_sources (
                    feed_id TEXT NOT NULL,
                    feed_revision INTEGER NOT NULL,
                    event_id TEXT NOT NULL,
                    source_type TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    inserted_at INTEGER NOT NULL,
                    PRIMARY KEY (feed_id, feed_revision, event_id, source_type, source_id),
                    FOREIGN KEY (feed_id, feed_revision, event_id)
                        REFERENCES feed_memberships(feed_id, feed_revision, event_id)
                        ON DELETE CASCADE
                )
                """
            )
            try db.create(
                index: "feed_membership_sources_source",
                on: "feed_membership_sources",
                columns: ["feed_id", "feed_revision", "source_type", "source_id"]
            )

            try db.execute(
                sql: """
                CREATE TABLE feed_gaps (
                    feed_id TEXT NOT NULL,
                    feed_revision INTEGER NOT NULL,
                    newer_event_id TEXT NOT NULL,
                    older_event_id TEXT NOT NULL,
                    gap_state TEXT NOT NULL,
                    source_request_id TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    resolved_at INTEGER,
                    PRIMARY KEY (feed_id, feed_revision, newer_event_id, older_event_id),
                    FOREIGN KEY (feed_id, feed_revision, newer_event_id)
                        REFERENCES feed_memberships(feed_id, feed_revision, event_id)
                        ON DELETE CASCADE,
                    FOREIGN KEY (feed_id, feed_revision, older_event_id)
                        REFERENCES feed_memberships(feed_id, feed_revision, event_id)
                        ON DELETE CASCADE,
                    FOREIGN KEY (source_request_id)
                        REFERENCES feed_sync_requests(request_id)
                        ON DELETE SET NULL,
                    CHECK (newer_event_id <> older_event_id)
                )
                """
            )
            try db.create(
                index: "feed_gaps_feed_revision_state",
                on: "feed_gaps",
                columns: ["feed_id", "feed_revision", "gap_state", "updated_at"]
            )

            try db.create(table: "feed_read_state") { table in
                table.column("feed_id", .text)
                    .primaryKey()
                    .references("feed_definitions", column: "feed_id", onDelete: .cascade)
                table.column("viewport_anchor_event_id", .text)
                table.column("viewport_anchor_offset", .double).notNull().defaults(to: 0)
                table.column("read_sort_ts", .integer)
                table.column("read_event_id", .text)
                table.column("updated_at", .integer).notNull()
                table.check(sql: "(read_sort_ts IS NULL) = (read_event_id IS NULL)")
            }
        }

        migrator.registerMigration("addPersistenceHotPathIndexesV5") { db in
            try db.execute(
                sql: """
                CREATE INDEX IF NOT EXISTS events_kind_pubkey_created_event
                ON events(kind, pubkey, created_at DESC, event_id ASC)
                """
            )
            try db.execute(
                sql: """
                CREATE INDEX IF NOT EXISTS relay_sync_events_timeline_relay_occurred_id
                ON relay_sync_events(
                    account_id, timeline_key, relay_url, occurred_at DESC, id DESC
                )
                """
            )
        }

        migrator.registerMigration("rebuildDeletionDerivedStateV6") { db in
            let deletionRows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind = 5
                ORDER BY created_at ASC, event_id ASC
                """
            )
            for row in deletionRows {
                try self.applyDeletionRequest(try self.decodeEvent(row), db: db)
            }
        }

        migrator.registerMigration("addFeedReadStateHalfTimestampsV7") { db in
            try db.alter(table: "feed_read_state") { table in
                table.add(column: "viewport_updated_at", .integer).notNull().defaults(to: 0)
                table.add(column: "read_updated_at", .integer).notNull().defaults(to: 0)
            }
            try db.execute(
                sql: """
                UPDATE feed_read_state
                SET viewport_updated_at = updated_at,
                    read_updated_at = updated_at
                """
            )
        }

        migrator.registerMigration("addProfileDirectoryStateV8") { db in
            try db.create(table: "profile_fetch_state") { table in
                table.column("pubkey", .text).primaryKey()
                table.column("last_outcome", .text).notNull()
                table.column("last_attempt_at", .integer).notNull()
                table.column("last_success_at", .integer)
                table.column("next_retry_at", .integer)
                table.column("last_error", .text)
                table.column("updated_at", .integer).notNull()
            }
            try db.create(
                index: "profile_fetch_state_retry",
                on: "profile_fetch_state",
                columns: ["next_retry_at", "updated_at"]
            )
        }

        migrator.registerMigration("reduceFeedReadStateToBoundaryV9") { db in
            try db.rename(
                table: "feed_read_state",
                to: "feed_read_state_before_v9"
            )
            try db.create(table: "feed_read_state") { table in
                table.column("feed_id", .text)
                    .primaryKey()
                    .references(
                        "feed_definitions",
                        column: "feed_id",
                        onDelete: .cascade
                    )
                table.column("read_sort_ts", .integer)
                table.column("read_event_id", .text)
                table.column("updated_at", .integer).notNull()
                table.check(
                    sql: "(read_sort_ts IS NULL) = (read_event_id IS NULL)"
                )
            }
            try db.execute(
                sql: """
                INSERT INTO feed_read_state (
                    feed_id, read_sort_ts, read_event_id, updated_at
                )
                SELECT feed_id, read_sort_ts, read_event_id, read_updated_at
                FROM feed_read_state_before_v9
                WHERE read_updated_at > 0
                """
            )
            try db.drop(table: "feed_read_state_before_v9")
        }

        migrator.registerMigration("addCaseInsensitiveTagLookupV10") { db in
            try db.execute(
                sql: """
                CREATE INDEX IF NOT EXISTS event_tags_name_value_nocase
                ON event_tags(tag_name, tag_value COLLATE NOCASE)
                """
            )
        }

        try migrator.migrate(database)
    }

    private func persist(events: [NostrEvent], receivedAt: Int, db: Database) throws {
        var insertedEvents: [NostrEvent] = []
        insertedEvents.reserveCapacity(events.count)

        for event in events {
            guard try insertIfNeeded(event: event, receivedAt: receivedAt, db: db) else {
                continue
            }
            insertedEvents.append(event)
            try replaceTags(for: event, db: db)
            try replaceMediaAssets(for: event, receivedAt: receivedAt, db: db)
            try upsertLinkPreviewRequests(for: event, db: db)
            try upsertReplaceableHeadIfNeeded(for: event, db: db)
            try upsertAddressableHeadIfNeeded(for: event, db: db)
            try upsertListIfNeeded(for: event, accountID: event.pubkey, db: db)
        }
        for event in insertedEvents where event.kind == 5 {
            try applyDeletionRequest(event, db: db)
        }
    }

    private func upsertEventSources(_ sources: [NostrEventSourceRecord], db: Database) throws {
        for source in sources {
            try db.execute(
                sql: """
                INSERT INTO event_sources (event_id, relay_url, first_seen_at, last_seen_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(event_id, relay_url) DO UPDATE SET
                    first_seen_at = MIN(event_sources.first_seen_at, excluded.first_seen_at),
                    last_seen_at = MAX(event_sources.last_seen_at, excluded.last_seen_at)
                """,
                arguments: [
                    source.eventID,
                    source.relayURL,
                    source.firstSeenAt,
                    source.lastSeenAt
                ]
            )
        }
    }

    private func validateFeedDefinitionWrite(
        _ definition: NostrFeedDefinitionRecord,
        db: Database
    ) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT account_id, feed_kind, spec_json, spec_hash, sort_policy, revision
            FROM feed_definitions
            WHERE feed_id = ?
            """,
            arguments: [definition.feedID]
        ) else {
            return
        }

        let currentRevision: Int = row["revision"]
        let currentAccountID: String = row["account_id"]
        let currentKind: String = row["feed_kind"]
        let currentSpecificationJSON: Data = row["spec_json"]
        let currentSpecificationHash: String = row["spec_hash"]
        let currentSortPolicy: String = row["sort_policy"]
        guard definition.revision >= currentRevision else {
            throw NostrFeedProjectionError.mismatchedRevision
        }
        guard definition.accountID == currentAccountID,
              definition.kind == currentKind
        else {
            throw NostrFeedProjectionError.mismatchedFeedID
        }
        guard definition.revision != currentRevision ||
            (
                definition.specificationJSON == currentSpecificationJSON &&
                    definition.specificationHash == currentSpecificationHash &&
                    definition.sortPolicy == currentSortPolicy
            )
        else {
            throw NostrFeedProjectionError.mismatchedRevision
        }
    }

    private func upsertFeedDefinition(_ definition: NostrFeedDefinitionRecord, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO feed_definitions (
                feed_id, account_id, feed_kind, spec_json, spec_hash,
                sort_policy, revision, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(feed_id) DO UPDATE SET
                spec_json = CASE
                    WHEN excluded.revision > feed_definitions.revision
                    THEN excluded.spec_json
                    ELSE feed_definitions.spec_json
                END,
                spec_hash = CASE
                    WHEN excluded.revision > feed_definitions.revision
                    THEN excluded.spec_hash
                    ELSE feed_definitions.spec_hash
                END,
                sort_policy = CASE
                    WHEN excluded.revision > feed_definitions.revision
                    THEN excluded.sort_policy
                    ELSE feed_definitions.sort_policy
                END,
                revision = MAX(feed_definitions.revision, excluded.revision),
                updated_at = MAX(feed_definitions.updated_at, excluded.updated_at)
            WHERE excluded.account_id = feed_definitions.account_id
                AND excluded.feed_kind = feed_definitions.feed_kind
                AND (
                    excluded.revision > feed_definitions.revision
                    OR (
                        excluded.revision = feed_definitions.revision
                        AND excluded.spec_json = feed_definitions.spec_json
                        AND excluded.spec_hash = feed_definitions.spec_hash
                        AND excluded.sort_policy = feed_definitions.sort_policy
                    )
                )
            """,
            arguments: [
                definition.feedID,
                definition.accountID,
                definition.kind,
                definition.specificationJSON,
                definition.specificationHash,
                definition.sortPolicy,
                definition.revision,
                definition.createdAt,
                definition.updatedAt
            ]
        )
    }

    private func resolvedFeedRevision(
        feedID: String,
        revision: Int?,
        db: Database
    ) throws -> Int? {
        guard let activeRevision = try Int.fetchOne(
            db,
            sql: "SELECT revision FROM feed_definitions WHERE feed_id = ?",
            arguments: [feedID]
        ) else { return nil }
        return revision ?? activeRevision
    }

    private func upsertFeedMemberships(
        _ memberships: [NostrFeedMembershipRecord],
        revisionOverride: Int? = nil,
        db: Database
    ) throws {
        var activeRevisionByFeedID: [String: Int] = [:]
        for membership in memberships {
            let revision: Int
            if let revisionOverride {
                guard membership.feedRevision == nil || membership.feedRevision == revisionOverride else {
                    throw NostrFeedProjectionError.mismatchedRevision
                }
                revision = revisionOverride
            } else if let membershipRevision = membership.feedRevision {
                guard try resolvedFeedRevision(feedID: membership.feedID, revision: membershipRevision, db: db) != nil else {
                    throw NostrFeedProjectionError.missingFeedDefinition
                }
                revision = membershipRevision
            } else if let cachedRevision = activeRevisionByFeedID[membership.feedID] {
                revision = cachedRevision
            } else {
                guard let activeRevision = try resolvedFeedRevision(
                    feedID: membership.feedID,
                    revision: nil,
                    db: db
                ) else {
                    throw NostrFeedProjectionError.missingFeedDefinition
                }
                activeRevisionByFeedID[membership.feedID] = activeRevision
                revision = activeRevision
            }
            try db.execute(
                sql: """
                INSERT INTO feed_memberships (
                    feed_id, feed_revision, event_id, subject_event_id, sort_ts, reason, inserted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(feed_id, feed_revision, event_id) DO UPDATE SET
                    subject_event_id = excluded.subject_event_id,
                    sort_ts = excluded.sort_ts,
                    reason = excluded.reason,
                    inserted_at = excluded.inserted_at
                """,
                arguments: [
                    membership.feedID,
                    revision,
                    membership.eventID,
                    membership.subjectEventID,
                    membership.sortTimestamp,
                    membership.reason,
                    membership.insertedAt
                ]
            )
        }
    }

    private func upsertFeedMembershipSources(
        _ sources: [NostrFeedMembershipSourceRecord],
        revisionOverride: Int? = nil,
        db: Database
    ) throws {
        var activeRevisionByFeedID: [String: Int] = [:]
        for source in sources {
            let revision: Int
            if let revisionOverride {
                guard source.feedRevision == nil || source.feedRevision == revisionOverride else {
                    throw NostrFeedProjectionError.mismatchedRevision
                }
                revision = revisionOverride
            } else if let sourceRevision = source.feedRevision {
                guard try resolvedFeedRevision(feedID: source.feedID, revision: sourceRevision, db: db) != nil else {
                    throw NostrFeedProjectionError.missingFeedDefinition
                }
                revision = sourceRevision
            } else if let cachedRevision = activeRevisionByFeedID[source.feedID] {
                revision = cachedRevision
            } else {
                guard let activeRevision = try resolvedFeedRevision(
                    feedID: source.feedID,
                    revision: nil,
                    db: db
                ) else {
                    throw NostrFeedProjectionError.missingFeedDefinition
                }
                activeRevisionByFeedID[source.feedID] = activeRevision
                revision = activeRevision
            }
            try db.execute(
                sql: """
                INSERT INTO feed_membership_sources (
                    feed_id, feed_revision, event_id, source_type, source_id, inserted_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(feed_id, feed_revision, event_id, source_type, source_id) DO UPDATE SET
                    inserted_at = MAX(feed_membership_sources.inserted_at, excluded.inserted_at)
                """,
                arguments: [
                    source.feedID,
                    revision,
                    source.eventID,
                    source.sourceType,
                    source.sourceID,
                    source.insertedAt
                ]
            )
        }
    }

    private func upsertFeedGaps(_ gaps: [NostrFeedGapRecord], db: Database) throws {
        for gap in gaps {
            try db.execute(
                sql: """
                INSERT INTO feed_gaps (
                    feed_id, feed_revision, newer_event_id, older_event_id,
                    gap_state, source_request_id, created_at, updated_at, resolved_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(feed_id, feed_revision, newer_event_id, older_event_id) DO UPDATE SET
                    gap_state = CASE
                        WHEN feed_gaps.gap_state = 'resolved' OR excluded.gap_state = 'resolved'
                            THEN 'resolved'
                        ELSE excluded.gap_state
                    END,
                    source_request_id = CASE
                        WHEN excluded.gap_state = 'resolved' AND feed_gaps.gap_state <> 'resolved'
                            THEN COALESCE(excluded.source_request_id, feed_gaps.source_request_id)
                        WHEN excluded.updated_at >= feed_gaps.updated_at
                            THEN COALESCE(excluded.source_request_id, feed_gaps.source_request_id)
                        ELSE feed_gaps.source_request_id
                    END,
                    created_at = MIN(feed_gaps.created_at, excluded.created_at),
                    updated_at = MAX(feed_gaps.updated_at, excluded.updated_at),
                    resolved_at = CASE
                        WHEN feed_gaps.resolved_at IS NULL THEN excluded.resolved_at
                        WHEN excluded.resolved_at IS NULL THEN feed_gaps.resolved_at
                        ELSE MAX(feed_gaps.resolved_at, excluded.resolved_at)
                    END
                WHERE NOT (
                        feed_gaps.gap_state = 'resolved'
                        AND excluded.gap_state <> 'resolved'
                    )
                    AND (
                        excluded.gap_state = 'resolved'
                        OR excluded.updated_at > feed_gaps.updated_at
                        OR (
                            excluded.updated_at = feed_gaps.updated_at
                            AND (
                                feed_gaps.gap_state <> 'resolved'
                                OR excluded.gap_state = 'resolved'
                            )
                        )
                    )
                """,
                arguments: [
                    gap.feedID,
                    gap.feedRevision,
                    gap.newerEventID,
                    gap.olderEventID,
                    gap.state.rawValue,
                    gap.sourceRequestID,
                    gap.createdAt,
                    gap.updatedAt,
                    gap.resolvedAt
                ]
            )
        }
    }

    private func feedDefinition(feedID: String, db: Database) throws -> NostrFeedDefinitionRecord? {
        try Row.fetchOne(
            db,
            sql: """
            SELECT feed_id, account_id, feed_kind, spec_json, spec_hash,
                sort_policy, revision, created_at, updated_at
            FROM feed_definitions
            WHERE feed_id = ?
            """,
            arguments: [feedID]
        ).map(decodeFeedDefinition)
    }

    private func feedMemberships(
        feedID: String,
        revision: Int,
        limit: Int,
        excludingExpiredAt now: Int? = nil,
        db: Database
    ) throws -> [NostrFeedMembershipRecord] {
        let eventJoin = now == nil
            ? ""
            : " JOIN events event ON event.event_id = membership.event_id"
        let expirationClause = now == nil
            ? ""
            : " AND (event.expires_at IS NULL OR event.expires_at > ?)"
        var arguments: StatementArguments = [feedID, revision]
        if let now { arguments += [now] }
        arguments += [max(0, limit)]
        return try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?\(expirationClause)
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            LIMIT ?
            """,
            arguments: arguments
        ).map(decodeFeedMembership)
    }

    private func feedMemberships(
        feedID: String,
        revision: Int,
        newerThan cursor: NostrTimelineEntryCursor,
        limit: Int,
        excludingExpiredAt now: Int? = nil,
        db: Database
    ) throws -> [NostrFeedMembershipRecord] {
        let eventJoin = now == nil
            ? ""
            : " JOIN events event ON event.event_id = membership.event_id"
        let expirationClause = now == nil
            ? ""
            : " AND (event.expires_at IS NULL OR event.expires_at > ?)"
        var arguments: StatementArguments = [feedID, revision]
        if let now { arguments += [now] }
        arguments += [
            cursor.sortTimestamp,
            cursor.sortTimestamp,
            cursor.eventID,
            max(0, limit)
        ]
        return try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?\(expirationClause)
                AND (membership.sort_ts > ? OR (membership.sort_ts = ? AND membership.event_id < ?))
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            LIMIT ?
            """,
            arguments: arguments
        ).map(decodeFeedMembership)
    }

    private func feedMemberships(
        feedID: String,
        revision: Int,
        olderThan cursor: NostrTimelineEntryCursor,
        limit: Int,
        excludingExpiredAt now: Int? = nil,
        db: Database
    ) throws -> [NostrFeedMembershipRecord] {
        let eventJoin = now == nil
            ? ""
            : " JOIN events event ON event.event_id = membership.event_id"
        let expirationClause = now == nil
            ? ""
            : " AND (event.expires_at IS NULL OR event.expires_at > ?)"
        var arguments: StatementArguments = [feedID, revision]
        if let now { arguments += [now] }
        arguments += [
            cursor.sortTimestamp,
            cursor.sortTimestamp,
            cursor.eventID,
            max(0, limit)
        ]
        return try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?\(expirationClause)
                AND (membership.sort_ts < ? OR (membership.sort_ts = ? AND membership.event_id > ?))
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            LIMIT ?
            """,
            arguments: arguments
        ).map(decodeFeedMembership)
    }

    private func feedMemberships(
        feedID: String,
        revision: Int,
        aroundEventID eventID: String,
        leadingLimit: Int,
        trailingLimit: Int,
        excludingExpiredAt now: Int? = nil,
        db: Database
    ) throws -> [NostrFeedMembershipRecord] {
        let eventJoin = now == nil
            ? ""
            : " JOIN events event ON event.event_id = membership.event_id"
        let expirationClause = now == nil
            ? ""
            : " AND (event.expires_at IS NULL OR event.expires_at > ?)"
        var anchorArguments: StatementArguments = [feedID, revision, eventID]
        if let now { anchorArguments += [now] }
        guard let anchorRow = try Row.fetchOne(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?
                AND membership.event_id = ?\(expirationClause)
            """,
            arguments: anchorArguments
        ) else {
            return try feedMemberships(
                feedID: feedID,
                revision: revision,
                limit: max(0, leadingLimit + trailingLimit + 1),
                excludingExpiredAt: now,
                db: db
            )
        }

        let anchor = decodeFeedMembership(anchorRow)
        var newerArguments: StatementArguments = [feedID, revision]
        if let now { newerArguments += [now] }
        newerArguments += [
            anchor.sortTimestamp,
            anchor.sortTimestamp,
            anchor.eventID,
            max(0, leadingLimit)
        ]
        let newerRows = try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?\(expirationClause)
                AND (membership.sort_ts > ? OR (membership.sort_ts = ? AND membership.event_id < ?))
            ORDER BY membership.sort_ts ASC, membership.event_id DESC
            LIMIT ?
            """,
            arguments: newerArguments
        )
        var olderArguments: StatementArguments = [feedID, revision]
        if let now { olderArguments += [now] }
        olderArguments += [
            anchor.sortTimestamp,
            anchor.sortTimestamp,
            anchor.eventID,
            max(0, trailingLimit)
        ]
        let olderRows = try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision, membership.event_id,
                membership.subject_event_id, membership.sort_ts, membership.reason, membership.inserted_at
            FROM feed_memberships membership\(eventJoin)
            WHERE membership.feed_id = ? AND membership.feed_revision = ?\(expirationClause)
                AND (membership.sort_ts < ? OR (membership.sort_ts = ? AND membership.event_id > ?))
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            LIMIT ?
            """,
            arguments: olderArguments
        )
        return newerRows.reversed().map(decodeFeedMembership) +
            [anchor] +
            olderRows.map(decodeFeedMembership)
    }

    private func feedGaps(
        feedID: String,
        revision: Int,
        includeResolved: Bool,
        db: Database
    ) throws -> [NostrFeedGapRecord] {
        let stateClause = includeResolved ? "" : " AND gap_state <> ?"
        var arguments: StatementArguments = [feedID, revision]
        if !includeResolved { arguments += [NostrFeedGapState.resolved.rawValue] }
        return try Row.fetchAll(
            db,
            sql: """
            SELECT feed_id, feed_revision, newer_event_id, older_event_id,
                gap_state, source_request_id, created_at, updated_at, resolved_at
            FROM feed_gaps
            WHERE feed_id = ? AND feed_revision = ?\(stateClause)
            ORDER BY updated_at DESC, newer_event_id ASC, older_event_id ASC
            """,
            arguments: arguments
        ).compactMap(decodeFeedGap)
    }

    private func deletedFeedItems(
        feedID: String,
        revision: Int,
        limit: Int,
        now: Int,
        db: Database
    ) throws -> [NostrDeletedFeedItemRecord] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision,
                membership.event_id AS target_event_id,
                tombstone.deletion_event_id,
                event.deleted_at,
                membership.sort_ts
            FROM feed_memberships membership
            JOIN events event ON event.event_id = membership.event_id
            LEFT JOIN deletion_tombstones tombstone
                ON tombstone.target_event_id = membership.event_id
                AND tombstone.author_pubkey = event.pubkey
            WHERE membership.feed_id = ? AND membership.feed_revision = ?
                AND event.deleted_at IS NOT NULL
                AND (event.expires_at IS NULL OR event.expires_at > ?)
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            LIMIT ?
            """,
            arguments: [feedID, revision, now, max(0, limit)]
        ).map(decodeDeletedFeedItem)
    }

    private func deletedFeedItems(
        feedID: String,
        revision: Int,
        eventIDs: [String],
        now: Int,
        db: Database
    ) throws -> [NostrDeletedFeedItemRecord] {
        guard !eventIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: eventIDs.count).joined(separator: ", ")
        var arguments: StatementArguments = [feedID, revision, now]
        for eventID in eventIDs { arguments += [eventID] }
        return try Row.fetchAll(
            db,
            sql: """
            SELECT membership.feed_id, membership.feed_revision,
                membership.event_id AS target_event_id,
                tombstone.deletion_event_id,
                event.deleted_at,
                membership.sort_ts
            FROM feed_memberships membership
            JOIN events event ON event.event_id = membership.event_id
            LEFT JOIN deletion_tombstones tombstone
                ON tombstone.target_event_id = membership.event_id
                AND tombstone.author_pubkey = event.pubkey
            WHERE membership.feed_id = ? AND membership.feed_revision = ?
                AND event.deleted_at IS NOT NULL
                AND (event.expires_at IS NULL OR event.expires_at > ?)
                AND membership.event_id IN (\(placeholders))
            ORDER BY membership.sort_ts DESC, membership.event_id ASC
            """,
            arguments: arguments
        ).map(decodeDeletedFeedItem)
    }

    private func feedWindow(
        definition: NostrFeedDefinitionRecord,
        revision: Int,
        memberships: [NostrFeedMembershipRecord],
        now: Int,
        db: Database
    ) throws -> NostrFeedWindow {
        let eventIDs = memberships.map(\.eventID)
        let visibleEvents = try visibleEvents(ids: eventIDs, now: now, db: db)
        let eventsByID = Dictionary(uniqueKeysWithValues: visibleEvents.map { ($0.id, $0) })
        let orderedEvents = eventIDs.compactMap { eventsByID[$0] }
        let deletedItems = try deletedFeedItems(
            feedID: definition.feedID,
            revision: revision,
            eventIDs: eventIDs,
            now: now,
            db: db
        )
        let membershipEventIDs = Set(eventIDs)
        let gaps = try feedGaps(
            feedID: definition.feedID,
            revision: revision,
            includeResolved: false,
            db: db
        ).filter { gap in
            membershipEventIDs.contains(gap.newerEventID) && membershipEventIDs.contains(gap.olderEventID)
        }
        return NostrFeedWindow(
            definition: definition,
            memberships: memberships,
            events: orderedEvents,
            deletedItems: deletedItems,
            gaps: gaps
        )
    }

    private func visibleEvents(ids: [String], now: Int, db: Database) throws -> [NostrEvent] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        var arguments: StatementArguments = [now]
        for id in ids { arguments += [id] }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
            FROM events
            WHERE \(Self.visibleEventPredicate(alias: "events"))
                AND event_id IN (\(placeholders))
            """,
            arguments: arguments
        )
        return try rows.map(decodeEvent)
    }

    private func feedSyncRequestArguments(_ request: NostrFeedSyncRequestRecord) -> StatementArguments {
        [
            request.requestID,
            request.feedID,
            request.feedRevision,
            request.feedSpecificationHash,
            request.relayURL,
            request.subscriptionID,
            request.syncProtocol.rawValue,
            request.direction.rawValue,
            request.purpose.rawValue,
            request.requestedAt,
            request.installedAt,
            request.eoseAt,
            request.endedAt,
            request.endReason?.rawValue,
            request.endMessage,
            request.eventCount,
            request.observedOldestPosition?.sortTimestamp,
            request.observedOldestPosition?.eventID,
            request.observedNewestPosition?.sortTimestamp,
            request.observedNewestPosition?.eventID,
            request.verificationOutcome?.rawValue,
            request.differenceCount
        ]
    }

    private func insertFeedCoverageSegment(
        _ segment: NostrFeedCoverageSegmentRecord,
        db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO feed_coverage_segments (
                segment_id, feed_id, feed_revision, feed_spec_hash,
                relay_url, scope_hash, lower_ts, upper_ts, snapshot_at,
                confidence, source_request_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(segment_id) DO NOTHING
            """,
            arguments: [
                segment.segmentID,
                segment.feedID,
                segment.feedRevision,
                segment.feedSpecificationHash,
                segment.relayURL,
                segment.scopeHash,
                segment.lowerTimestamp,
                segment.upperTimestamp,
                segment.snapshotAt,
                segment.confidence.rawValue,
                segment.sourceRequestID,
                segment.createdAt
            ]
        )
    }

    private func upsertFeedSyncCheckpoint(
        feedID: String,
        feedRevision: Int,
        relayURL: String,
        scopeHash: String,
        newestPosition: NostrTimelineEntryCursor?,
        oldestPosition: NostrTimelineEntryCursor?,
        lastEOSEAt: Int?,
        lastVerifiedAt: Int?,
        updatedAt: Int,
        db: Database
    ) throws {
        let existing = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM feed_sync_checkpoints
            WHERE feed_id = ? AND feed_revision = ? AND relay_url = ? AND scope_hash = ?
            """,
            arguments: [feedID, feedRevision, relayURL, scopeHash]
        ).flatMap(decodeFeedSyncCheckpoint)
        let mergedNewest = [existing?.newestPosition, newestPosition]
            .compactMap { $0 }
            .max(by: Self.isOlderTimelineCursor)
        let mergedOldest = [existing?.oldestPosition, oldestPosition]
            .compactMap { $0 }
            .min(by: Self.isOlderTimelineCursor)

        try db.execute(
            sql: """
            INSERT INTO feed_sync_checkpoints (
                feed_id, feed_revision, relay_url, scope_hash,
                newest_ts, newest_event_id, oldest_ts, oldest_event_id,
                last_eose_at, last_verified_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(feed_id, feed_revision, relay_url, scope_hash) DO UPDATE SET
                newest_ts = excluded.newest_ts,
                newest_event_id = excluded.newest_event_id,
                oldest_ts = excluded.oldest_ts,
                oldest_event_id = excluded.oldest_event_id,
                last_eose_at = COALESCE(excluded.last_eose_at, feed_sync_checkpoints.last_eose_at),
                last_verified_at = COALESCE(excluded.last_verified_at, feed_sync_checkpoints.last_verified_at),
                updated_at = MAX(feed_sync_checkpoints.updated_at, excluded.updated_at)
            """,
            arguments: [
                feedID,
                feedRevision,
                relayURL,
                scopeHash,
                mergedNewest?.sortTimestamp,
                mergedNewest?.eventID,
                mergedOldest?.sortTimestamp,
                mergedOldest?.eventID,
                lastEOSEAt,
                lastVerifiedAt,
                updatedAt
            ]
        )
    }

    private static func isOlderTimelineCursor(
        _ lhs: NostrTimelineEntryCursor,
        _ rhs: NostrTimelineEntryCursor
    ) -> Bool {
        if lhs.sortTimestamp == rhs.sortTimestamp {
            return lhs.eventID > rhs.eventID
        }
        return lhs.sortTimestamp < rhs.sortTimestamp
    }

    private func upsertTimelineEntries(_ entries: [NostrTimelineEntryRecord], db: Database) throws {
        for entry in entries {
            try db.execute(
                sql: """
                INSERT INTO timeline_entries (
                    account_id, timeline_key, event_id, sort_ts, source,
                    inserted_at, gap_before, gap_after
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, timeline_key, event_id) DO UPDATE SET
                    sort_ts = excluded.sort_ts,
                    source = excluded.source,
                    inserted_at = excluded.inserted_at,
                    gap_before = CASE
                        WHEN timeline_entries.gap_before OR excluded.gap_before THEN 1
                        ELSE 0
                    END,
                    gap_after = CASE
                        WHEN timeline_entries.gap_after OR excluded.gap_after THEN 1
                        ELSE 0
                    END
                """,
                arguments: [
                    entry.accountID,
                    entry.timelineKey,
                    entry.eventID,
                    entry.sortTimestamp,
                    entry.source,
                    entry.insertedAt,
                    entry.gapBefore,
                    entry.gapAfter
                ]
            )
        }
    }

    private func insertIfNeeded(event: NostrEvent, receivedAt: Int, db: Database) throws -> Bool {
        // event_idはcanonical payloadをcommitするため、既存eventは受信時刻だけを進めます。
        try db.execute(
            sql: """
            UPDATE events
            SET received_at = MAX(received_at, ?)
            WHERE event_id = ?
            """,
            arguments: [receivedAt, event.id]
        )
        guard db.changesCount == 0 else { return false }

        let tagsData = try encoder.encode(event.tags)
        let rawData = try encoder.encode(event)
        let expiresAt = expirationTimestamp(from: event)

        try db.execute(
            sql: """
            INSERT INTO events (
                event_id, pubkey, created_at, kind, content, tags_json, sig,
                received_at, deleted_at, expires_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
            """,
            arguments: [
                event.id,
                event.pubkey,
                event.createdAt,
                event.kind,
                event.content,
                tagsData,
                event.sig,
                receivedAt,
                expiresAt,
                rawData
            ]
        )
        try applyPendingDeletionRequests(to: event, db: db)
        return true
    }

    private func replaceTags(for event: NostrEvent, db: Database) throws {
        try db.execute(sql: "DELETE FROM event_tags WHERE event_id = ?", arguments: [event.id])

        for (position, tag) in event.tags.enumerated() {
            guard let name = tag.first else { continue }
            let rawData = try encoder.encode(tag)
            try db.execute(
                sql: """
                INSERT INTO event_tags (
                    event_id, pos, tag_name, tag_value, relay_hint, marker, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id,
                    position,
                    name,
                    tag.dropFirst().first,
                    relayHint(from: tag),
                    marker(from: tag),
                    rawData
                ]
            )
        }
    }

    private func replaceMediaAssets(for event: NostrEvent, receivedAt: Int, db: Database) throws {
        try db.execute(sql: "DELETE FROM media_assets WHERE event_id = ?", arguments: [event.id])

        for asset in NostrMediaParser.mediaAssets(from: event, createdAt: receivedAt) {
            try db.execute(
                sql: """
                INSERT INTO media_assets (
                    asset_id, event_id, url, mime_type, blurhash, width, height,
                    alt, sha256, status, local_path, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    asset.assetID,
                    asset.eventID,
                    asset.url,
                    asset.mimeType,
                    asset.blurhash,
                    asset.width,
                    asset.height,
                    asset.alt,
                    asset.sha256,
                    asset.status,
                    asset.localPath,
                    asset.createdAt
                ]
            )
        }
    }

    private func upsertLinkPreviewRequests(for event: NostrEvent, db: Database) throws {
        for url in NostrContentAttachmentClassifier.linkPreviewURLs(from: event) {
            let preview = NostrLinkPreviewRecord(
                url: url.absoluteString,
                normalizedURL: NostrLinkParser.normalizedURLString(url),
                status: "unresolved",
                title: nil,
                summary: nil,
                siteName: nil,
                imageURL: nil,
                fetchedAt: nil,
                expiresAt: nil,
                error: nil
            )
            try db.execute(
                sql: """
                INSERT INTO link_previews (
                    url, normalized_url, status, title, summary, site_name,
                    image_url, fetched_at, expires_at, error
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(normalized_url) DO NOTHING
                """,
                arguments: [
                    preview.url,
                    preview.normalizedURL,
                    preview.status,
                    preview.title,
                    preview.summary,
                    preview.siteName,
                    preview.imageURL,
                    preview.fetchedAt,
                    preview.expiresAt,
                    preview.error
                ]
            )
        }
    }

    private func upsertLinkPreview(_ preview: NostrLinkPreviewRecord, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO link_previews (
                url, normalized_url, status, title, summary, site_name,
                image_url, fetched_at, expires_at, error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(normalized_url) DO UPDATE SET
                url = excluded.url,
                status = excluded.status,
                title = excluded.title,
                summary = excluded.summary,
                site_name = excluded.site_name,
                image_url = excluded.image_url,
                fetched_at = excluded.fetched_at,
                expires_at = excluded.expires_at,
                error = excluded.error
            """,
            arguments: [
                preview.url,
                preview.normalizedURL,
                preview.status,
                preview.title,
                preview.summary,
                preview.siteName,
                preview.imageURL,
                preview.fetchedAt,
                preview.expiresAt,
                preview.error
            ]
        )
    }

    private func upsertReplaceableHeadIfNeeded(for event: NostrEvent, db: Database) throws {
        guard isReplaceable(kind: event.kind) else { return }

        try db.execute(
            sql: """
            INSERT INTO replaceable_heads (pubkey, kind, event_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(pubkey, kind) DO UPDATE SET
                event_id = excluded.event_id,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at
            WHERE excluded.created_at > replaceable_heads.created_at
                OR (excluded.created_at = replaceable_heads.created_at AND excluded.event_id < replaceable_heads.event_id)
            """,
            arguments: [
                event.pubkey,
                event.kind,
                event.id,
                event.createdAt,
                Int(Date().timeIntervalSince1970)
            ]
        )
    }

    private func upsertAddressableHeadIfNeeded(for event: NostrEvent, db: Database) throws {
        guard isAddressable(kind: event.kind) else { return }
        let dTag = NostrListParser.dTag(from: event)

        try db.execute(
            sql: """
            INSERT INTO addressable_heads (kind, pubkey, d_tag, event_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(kind, pubkey, d_tag) DO UPDATE SET
                event_id = excluded.event_id,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at
            WHERE excluded.created_at > addressable_heads.created_at
                OR (excluded.created_at = addressable_heads.created_at AND excluded.event_id < addressable_heads.event_id)
            """,
            arguments: [
                event.kind,
                event.pubkey,
                dTag,
                event.id,
                event.createdAt,
                Int(Date().timeIntervalSince1970)
            ]
        )
    }

    private func upsertListIfNeeded(for event: NostrEvent, accountID: String, db: Database) throws {
        let updatedAt = Int(Date().timeIntervalSince1970)
        guard let parsed = NostrListParser.parse(event: event, accountID: accountID, updatedAt: updatedAt),
              try shouldReplaceList(summary: parsed.summary, db: db)
        else { return }

        try db.execute(
            sql: """
            INSERT INTO lists (
                list_id, account_id, kind, pubkey, d_tag, event_id, title, visibility,
                private_content, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(list_id) DO UPDATE SET
                account_id = excluded.account_id,
                kind = excluded.kind,
                pubkey = excluded.pubkey,
                d_tag = excluded.d_tag,
                event_id = excluded.event_id,
                title = excluded.title,
                visibility = excluded.visibility,
                private_content = excluded.private_content,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at
            """,
            arguments: [
                parsed.summary.listID,
                parsed.summary.accountID,
                parsed.summary.kind,
                parsed.summary.pubkey,
                parsed.summary.dTag,
                parsed.summary.eventID,
                parsed.summary.title,
                parsed.summary.visibility,
                parsed.summary.privateContent,
                parsed.summary.createdAt,
                parsed.summary.updatedAt
            ]
        )
        try db.execute(sql: "DELETE FROM list_items WHERE list_id = ?", arguments: [parsed.summary.listID])
        for item in parsed.items {
            try db.execute(
                sql: """
                INSERT INTO list_items (
                    list_id, item_key, item_type, value, relay_hint, visibility, position
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.listID,
                    item.itemKey,
                    item.itemType,
                    item.value,
                    item.relayHint,
                    item.visibility,
                    item.position
                ]
            )
        }
    }

    private func shouldReplaceList(summary: NostrListSummary, db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT event_id, created_at FROM lists WHERE list_id = ?",
            arguments: [summary.listID]
        ) else { return true }

        let currentEventID: String = row["event_id"]
        let currentCreatedAt: Int = row["created_at"]
        return summary.createdAt > currentCreatedAt
            || (summary.createdAt == currentCreatedAt && summary.eventID < currentEventID)
    }

    private func applyDeletionRequest(_ deletionEvent: NostrEvent, db: Database) throws {
        let targetIDs = Set(deletionEvent.tags.compactMap { tag -> String? in
            guard tag.first == "e", tag.count > 1 else { return nil }
            return tag[1]
        })

        for targetID in targetIDs {
            let target = try fetchEvent(id: targetID, db: db)
            guard target?.kind != 5,
                  target == nil || target?.pubkey == deletionEvent.pubkey
            else {
                continue
            }

            try db.execute(
                sql: """
                INSERT INTO deletion_tombstones (
                    target_event_id, deletion_event_id, deleted_at, author_pubkey
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(target_event_id, author_pubkey) DO UPDATE SET
                    deletion_event_id = excluded.deletion_event_id,
                    deleted_at = excluded.deleted_at
                WHERE excluded.deleted_at > deletion_tombstones.deleted_at
                    OR (
                        excluded.deleted_at = deletion_tombstones.deleted_at
                        AND excluded.deletion_event_id < deletion_tombstones.deletion_event_id
                    )
                """,
                arguments: [
                    targetID,
                    deletionEvent.id,
                    deletionEvent.createdAt,
                    deletionEvent.pubkey
                ]
            )

            guard target != nil else { continue }
            try markEventDeleted(
                eventID: targetID,
                deletedAt: deletionEvent.createdAt,
                db: db
            )
        }

        let addresses = Set(deletionEvent.tags.compactMap { tag -> NostrDeletionAddress? in
            guard tag.first == "a", tag.count > 1 else { return nil }
            return deletionAddress(from: tag[1])
        })

        for address in addresses where address.pubkey == deletionEvent.pubkey && isAddressable(kind: address.kind) {
            try db.execute(
                sql: """
                INSERT INTO address_deletion_tombstones (
                    kind, pubkey, d_tag, deletion_event_id, deleted_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(kind, pubkey, d_tag) DO UPDATE SET
                    deletion_event_id = excluded.deletion_event_id,
                    deleted_at = excluded.deleted_at
                WHERE excluded.deleted_at > address_deletion_tombstones.deleted_at
                    OR (
                        excluded.deleted_at = address_deletion_tombstones.deleted_at
                        AND excluded.deletion_event_id < address_deletion_tombstones.deletion_event_id
                    )
                """,
                arguments: [
                    address.kind,
                    address.pubkey,
                    address.dTag,
                    deletionEvent.id,
                    deletionEvent.createdAt
                ]
            )

            try db.execute(
                sql: """
                UPDATE events
                SET deleted_at = CASE
                    WHEN deleted_at IS NULL OR deleted_at < ? THEN ?
                    ELSE deleted_at
                END
                WHERE kind = ? AND pubkey = ? AND created_at <= ? AND kind != 5
                    AND COALESCE((
                        SELECT tag_value
                        FROM event_tags
                        WHERE event_tags.event_id = events.event_id AND tag_name = 'd'
                        ORDER BY pos ASC
                        LIMIT 1
                    ), '') = ?
                """,
                arguments: [
                    deletionEvent.createdAt,
                    deletionEvent.createdAt,
                    address.kind,
                    address.pubkey,
                    deletionEvent.createdAt,
                    address.dTag
                ]
            )
        }
    }

    private func applyPendingDeletionRequests(to event: NostrEvent, db: Database) throws {
        guard event.kind != 5 else { return }

        if let deletedAt = try Int.fetchOne(
            db,
            sql: """
            SELECT deleted_at
            FROM deletion_tombstones
            WHERE target_event_id = ? AND author_pubkey = ?
            """,
            arguments: [event.id, event.pubkey]
        ) {
            try markEventDeleted(eventID: event.id, deletedAt: deletedAt, db: db)
        }

        guard isAddressable(kind: event.kind) else { return }
        let dTag = NostrListParser.dTag(from: event)
        if let deletedAt = try Int.fetchOne(
            db,
            sql: """
            SELECT deleted_at
            FROM address_deletion_tombstones
            WHERE kind = ? AND pubkey = ? AND d_tag = ? AND deleted_at >= ?
            """,
            arguments: [event.kind, event.pubkey, dTag, event.createdAt]
        ) {
            try markEventDeleted(eventID: event.id, deletedAt: deletedAt, db: db)
        }
    }

    private func markEventDeleted(eventID: String, deletedAt: Int, db: Database) throws {
        try db.execute(
            sql: """
            UPDATE events
            SET deleted_at = CASE
                WHEN deleted_at IS NULL OR deleted_at < ? THEN ?
                ELSE deleted_at
            END
            WHERE event_id = ? AND kind != 5
            """,
            arguments: [deletedAt, deletedAt, eventID]
        )
    }

    private func deletionAddress(from rawValue: String) -> NostrDeletionAddress? {
        let parts = rawValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let kind = Int(parts[0]),
              !parts[1].isEmpty
        else {
            return nil
        }
        return NostrDeletionAddress(
            kind: kind,
            pubkey: String(parts[1]),
            dTag: String(parts[2])
        )
    }

    /// Home timelineの復元metadataだけを保存し、eventやfeed projectionは更新しません。
    public func saveTimelineStateMetadata(
        _ state: NostrHomeTimelineState,
        accountID: String,
        timelineKey: String = "home",
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            try saveTimelineStateMetadata(
                state,
                accountID: accountID,
                timelineKey: timelineKey,
                savedAt: savedAt,
                db: db
            )
        }
    }

    private func saveRelaySyncEvents(
        _ events: [NostrRelaySyncEventRecord],
        db: Database
    ) throws {
        guard !events.isEmpty else { return }
        for event in events {
            try db.execute(
                sql: """
                INSERT INTO relay_sync_events (
                    account_id, timeline_key, relay_url, event_kind, occurred_at,
                    subscription_id, event_count, newest_created_at, oldest_created_at,
                    latency_ms, message
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.accountID,
                    event.timelineKey,
                    event.relayURL,
                    event.kind.rawValue,
                    event.occurredAt,
                    event.subscriptionID,
                    event.eventCount,
                    event.newestCreatedAt,
                    event.oldestCreatedAt,
                    event.latencyMilliseconds,
                    event.message
                ]
            )
        }
        try pruneRelaySyncEvents(for: events, keeping: 200, db: db)
        try pruneRelaySyncTimelineEvents(for: events, keeping: 2_000, db: db)
    }

    private func saveTimelineStateMetadata(
        _ state: NostrHomeTimelineState,
        accountID: String,
        timelineKey: String,
        savedAt: Int,
        db: Database
    ) throws {
        let relaysData = try encoder.encode(state.relays)
        let followedData = try encoder.encode(state.followedPubkeys)
        let nip05Data = try encoder.encode(state.nip05Resolutions)

        try db.execute(
            sql: """
            INSERT INTO timeline_state (
                account_id, timeline_key, relays_json, followed_pubkeys_json,
                nip05_resolutions_json, has_more_older, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, timeline_key) DO UPDATE SET
                relays_json = excluded.relays_json,
                followed_pubkeys_json = excluded.followed_pubkeys_json,
                nip05_resolutions_json = excluded.nip05_resolutions_json,
                has_more_older = excluded.has_more_older,
                updated_at = excluded.updated_at
            WHERE excluded.updated_at >= timeline_state.updated_at
            """,
            arguments: [
                accountID,
                timelineKey,
                relaysData,
                followedData,
                nip05Data,
                state.hasMoreOlder,
                savedAt
            ]
        )
    }

    private func saveFeedReadState(
        _ state: NostrFeedReadStateRecord,
        db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO feed_read_state (
                feed_id, read_sort_ts, read_event_id, updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(feed_id) DO UPDATE SET
                read_sort_ts = excluded.read_sort_ts,
                read_event_id = excluded.read_event_id,
                updated_at = excluded.updated_at
            WHERE excluded.updated_at >= feed_read_state.updated_at
            """,
            arguments: [
                state.feedID,
                state.readBoundary?.sortTimestamp,
                state.readBoundary?.eventID,
                state.updatedAt
            ]
        )
    }

    private func updateSyncCursors(
        from events: [NostrRelaySyncEventRecord],
        db: Database
    ) throws {
        let cursorEvents = events.filter { event in
            event.kind == .eose || event.kind == .negentropy
        }
        guard !cursorEvents.isEmpty else { return }

        for event in cursorEvents {
            let current = try syncCursor(
                accountID: event.accountID,
                timelineKey: event.timelineKey,
                relayURL: event.relayURL,
                db: db
            )
            let newestCreatedAt = [current?.newestCreatedAt, event.newestCreatedAt].compactMap { $0 }.max()
            let oldestCreatedAt = [current?.oldestCreatedAt, event.oldestCreatedAt].compactMap { $0 }.min()
            let lastEOSEAt = event.kind == .eose ? event.occurredAt : current?.lastEOSEAt
            let lastNegentropyAt = event.kind == .negentropy ? event.occurredAt : current?.lastNegentropyAt

            try db.execute(
                sql: """
                INSERT INTO sync_cursors (
                    account_id, timeline_key, relay_url, newest_created_at,
                    oldest_created_at, last_eose_at, last_negentropy_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, timeline_key, relay_url) DO UPDATE SET
                    newest_created_at = excluded.newest_created_at,
                    oldest_created_at = excluded.oldest_created_at,
                    last_eose_at = excluded.last_eose_at,
                    last_negentropy_at = excluded.last_negentropy_at
                """,
                arguments: [
                    event.accountID,
                    event.timelineKey,
                    event.relayURL,
                    newestCreatedAt,
                    oldestCreatedAt,
                    lastEOSEAt,
                    lastNegentropyAt
                ]
            )
        }
    }

    private struct TimelineStateMetadata {
        let relays: [String]
        let followedPubkeys: [String]
        let nip05Resolutions: [String: NostrNIP05Resolution]
        let hasMoreOlder: Bool
    }

    private func timelineStateMetadata(accountID: String, timelineKey: String, db: Database) throws -> TimelineStateMetadata? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT relays_json, followed_pubkeys_json, nip05_resolutions_json, has_more_older
            FROM timeline_state
            WHERE account_id = ? AND timeline_key = ?
            """,
            arguments: [accountID, timelineKey]
        ) else {
            return nil
        }

        let relaysData: Data = row["relays_json"]
        let followedData: Data = row["followed_pubkeys_json"]
        let nip05Data: Data = row["nip05_resolutions_json"]

        return TimelineStateMetadata(
            relays: try decoder.decode([String].self, from: relaysData),
            followedPubkeys: try decoder.decode([String].self, from: followedData),
            nip05Resolutions: try decoder.decode([String: NostrNIP05Resolution].self, from: nip05Data),
            hasMoreOlder: row["has_more_older"]
        )
    }

    private func homeTimelineState(
        accountID: String,
        timelineKey: String,
        notes: [NostrEvent],
        now: Int,
        db: Database
    ) throws -> NostrHomeTimelineState {
        let stateMetadata = try timelineStateMetadata(
            accountID: accountID,
            timelineKey: timelineKey,
            db: db
        )
        let relayListEvent = try latestReplaceableEvent(
            pubkey: accountID,
            kind: 10002,
            now: now,
            db: db
        )
        let contactListEvent = try latestReplaceableEvent(
            pubkey: accountID,
            kind: 3,
            now: now,
            db: db
        )
        let followedPubkeys = contactListEvent.map(NostrContactList.pubkeys(from:))
            ?? stateMetadata?.followedPubkeys
            ?? []
        let metadataPubkeys = Set(notes.map(\.pubkey)).union(followedPubkeys)
        let metadataEvents = try latestReplaceableEvents(
            pubkeys: metadataPubkeys,
            kind: 0,
            now: now,
            db: db
        )
        let authorRelayListEvents = try latestReplaceableEvents(
            pubkeys: Set(followedPubkeys),
            kind: 10_002,
            now: now,
            db: db
        )
        let relayList = NostrRelayList.parse(from: relayListEvent)
        let relays = relayList.readRelays.isEmpty
            ? (stateMetadata?.relays ?? syncRelayURLs(
                accountID: accountID,
                timelineKey: timelineKey,
                db: db
            ))
            : relayList.readRelays

        return NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: followedPubkeys,
            noteEvents: notes,
            metadataEvents: metadataEvents,
            relayListEvent: relayListEvent,
            contactListEvent: contactListEvent,
            authorRelayListEvents: authorRelayListEvents,
            nip05Resolutions: stateMetadata?.nip05Resolutions ?? [:],
            hasMoreOlder: stateMetadata?.hasMoreOlder ?? true,
            relaySyncEvents: Array(try relaySyncEvents(
                accountID: accountID,
                timelineKey: timelineKey,
                limit: 300,
                db: db
            ).reversed())
        )
    }

    private func relaySyncEvents(
        accountID: String,
        timelineKey: String,
        limit: Int,
        db: Database
    ) throws -> [NostrRelaySyncEventRecord] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT account_id, timeline_key, relay_url, event_kind, occurred_at,
                subscription_id, event_count, newest_created_at, oldest_created_at,
                latency_ms, message
            FROM relay_sync_events
            WHERE account_id = ? AND timeline_key = ?
            ORDER BY occurred_at DESC, id DESC
            LIMIT ?
            """,
            arguments: [accountID, timelineKey, max(0, limit)]
        )
        return rows.compactMap(decodeRelaySyncEvent)
    }

    private func timelineEvents(
        accountID: String,
        timelineKey: String,
        limit: Int,
        now: Int,
        db: Database
    ) throws -> [NostrEvent] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT e.event_id, e.pubkey, e.created_at, e.kind, e.tags_json, e.content, e.sig
            FROM timeline_entries te
            JOIN events e ON e.event_id = te.event_id
            WHERE te.account_id = ? AND te.timeline_key = ? AND \(Self.visibleEventPredicate(alias: "e"))
            ORDER BY te.sort_ts DESC, te.event_id ASC
            LIMIT ?
            """,
            arguments: [accountID, timelineKey, now, limit]
        )
        return try rows.map(decodeEvent)
    }

    private func latestReplaceableEvents(pubkeys: Set<String>, kind: Int, now: Int, db: Database) throws -> [NostrEvent] {
        guard !pubkeys.isEmpty else { return [] }
        let sortedPubkeys = pubkeys.sorted()
        let placeholders = Array(repeating: "?", count: sortedPubkeys.count).joined(separator: ", ")
        var arguments: StatementArguments = [kind, now]
        for pubkey in sortedPubkeys {
            arguments += [pubkey]
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT e.event_id, e.pubkey, e.created_at, e.kind, e.tags_json, e.content, e.sig
            FROM replaceable_heads h
            JOIN events e ON e.event_id = h.event_id
            WHERE h.kind = ? AND \(Self.visibleEventPredicate(alias: "e"))
                AND h.pubkey IN (\(placeholders))
            ORDER BY e.created_at DESC, e.event_id ASC
            """,
            arguments: arguments
        )
        return try rows.map(decodeEvent)
    }

    private func latestReplaceableEvent(pubkey: String, kind: Int, now: Int, db: Database) throws -> NostrEvent? {
        guard let eventID = try String.fetchOne(
            db,
            sql: """
            SELECT h.event_id
            FROM replaceable_heads h
            JOIN events e ON e.event_id = h.event_id
            WHERE h.pubkey = ? AND h.kind = ?
                AND \(Self.visibleEventPredicate(alias: "e"))
            """,
            arguments: [pubkey, kind, now]
        ) else {
            return nil
        }
        return try fetchEvent(id: eventID, db: db)
    }

    private func syncRelayURLs(accountID: String, timelineKey: String, db: Database) -> [String] {
        (try? String.fetchAll(
            db,
            sql: """
            SELECT relay_url
            FROM sync_cursors
            WHERE account_id = ? AND timeline_key = ?
            ORDER BY relay_url ASC
            """,
            arguments: [accountID, timelineKey]
        )) ?? []
    }

    private func syncCursor(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        db: Database
    ) throws -> NostrSyncCursorRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT account_id, timeline_key, relay_url, newest_created_at,
                oldest_created_at, last_eose_at, last_negentropy_at
            FROM sync_cursors
            WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
            """,
            arguments: [accountID, timelineKey, relayURL]
        ) else {
            return nil
        }
        return decodeSyncCursor(row)
    }

    private func pruneRelaySyncEvents(
        for events: [NostrRelaySyncEventRecord],
        keeping limit: Int,
        db: Database
    ) throws {
        let buckets = Set(events.map { RelaySyncBucket(accountID: $0.accountID, timelineKey: $0.timelineKey, relayURL: $0.relayURL) })
        for bucket in buckets {
            try db.execute(
                sql: """
                DELETE FROM relay_sync_events
                WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                    AND id NOT IN (
                        SELECT id
                        FROM relay_sync_events
                        WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                        ORDER BY occurred_at DESC, id DESC
                        LIMIT ?
                    )
                """,
                arguments: [
                    bucket.accountID,
                    bucket.timelineKey,
                    bucket.relayURL,
                    bucket.accountID,
                    bucket.timelineKey,
                    bucket.relayURL,
                    limit
                ]
            )
        }
    }

    private func pruneRelaySyncTimelineEvents(
        for events: [NostrRelaySyncEventRecord],
        keeping limit: Int,
        db: Database
    ) throws {
        let buckets = Set(events.map {
            RelaySyncTimelineBucket(accountID: $0.accountID, timelineKey: $0.timelineKey)
        })
        for bucket in buckets {
            try db.execute(
                sql: """
                DELETE FROM relay_sync_events
                WHERE account_id = ? AND timeline_key = ?
                    AND id NOT IN (
                        SELECT id
                        FROM relay_sync_events
                        WHERE account_id = ? AND timeline_key = ?
                        ORDER BY occurred_at DESC, id DESC
                        LIMIT ?
                    )
                """,
                arguments: [
                    bucket.accountID,
                    bucket.timelineKey,
                    bucket.accountID,
                    bucket.timelineKey,
                    limit
                ]
            )
        }
    }

    private func relaySyncLastEventAt(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        db: Database
    ) throws -> Int? {
        try Int.fetchOne(
            db,
            sql: """
            SELECT MAX(occurred_at)
            FROM relay_sync_events
            WHERE account_id = ? AND timeline_key = ? AND relay_url = ? AND event_kind = ?
            """,
            arguments: [accountID, timelineKey, relayURL, kind.rawValue]
        )
    }

    private func relaySyncLastErrorAt(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        db: Database
    ) throws -> Int? {
        try Int.fetchOne(
            db,
            sql: """
            SELECT MAX(occurred_at)
            FROM relay_sync_events
            WHERE account_id = ? AND timeline_key = ? AND relay_url = ?
                AND event_kind IN (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                accountID,
                timelineKey,
                relayURL,
                NostrRelaySyncEventKind.closed.rawValue,
                NostrRelaySyncEventKind.timeout.rawValue,
                NostrRelaySyncEventKind.partialFailure.rawValue,
                NostrRelaySyncEventKind.authRequired.rawValue,
                NostrRelaySyncEventKind.paymentRequired.rawValue,
                NostrRelaySyncEventKind.rejected.rawValue,
                NostrRelaySyncEventKind.suspended.rawValue
            ]
        )
    }

    private func relaySyncEventCount(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        db: Database
    ) throws -> Int {
        try Int.fetchOne(
            db,
            sql: """
            SELECT COUNT(*)
            FROM relay_sync_events
            WHERE account_id = ? AND timeline_key = ? AND relay_url = ? AND event_kind = ?
            """,
            arguments: [accountID, timelineKey, relayURL, kind.rawValue]
        ) ?? 0
    }

    private func fetchEvent(id: String, db: Database) throws -> NostrEvent? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
            FROM events
            WHERE event_id = ?
            """,
            arguments: [id]
        ) else {
            return nil
        }
        return try decodeEvent(row)
    }

    private func decodeEvent(_ row: Row) throws -> NostrEvent {
        let tagsData: Data = row["tags_json"]
        return NostrEvent(
            id: row["event_id"],
            pubkey: row["pubkey"],
            createdAt: row["created_at"],
            kind: row["kind"],
            tags: try decoder.decode([[String]].self, from: tagsData),
            content: row["content"],
            sig: row["sig"]
        )
    }

    private func decodeTag(_ row: Row) throws -> NostrStoredEventTag {
        let rawData: Data = row["raw_json"]
        return NostrStoredEventTag(
            eventID: row["event_id"],
            position: row["pos"],
            name: row["tag_name"],
            value: row["tag_value"],
            relayHint: row["relay_hint"],
            marker: row["marker"],
            raw: try decoder.decode([String].self, from: rawData)
        )
    }

    private func decodeListSummary(_ row: Row) -> NostrListSummary {
        NostrListSummary(
            listID: row["list_id"],
            accountID: row["account_id"],
            kind: row["kind"],
            pubkey: row["pubkey"],
            dTag: row["d_tag"],
            eventID: row["event_id"],
            title: row["title"],
            visibility: row["visibility"],
            privateContent: row["private_content"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func decodeListItem(_ row: Row) -> NostrListItemRecord {
        NostrListItemRecord(
            listID: row["list_id"],
            itemKey: row["item_key"],
            itemType: row["item_type"],
            value: row["value"],
            relayHint: row["relay_hint"],
            visibility: row["visibility"],
            position: row["position"]
        )
    }

    private func decodeMediaAsset(_ row: Row) -> NostrMediaAssetRecord {
        NostrMediaAssetRecord(
            assetID: row["asset_id"],
            eventID: row["event_id"],
            url: row["url"],
            mimeType: row["mime_type"],
            blurhash: row["blurhash"],
            width: row["width"],
            height: row["height"],
            alt: row["alt"],
            sha256: row["sha256"],
            status: row["status"],
            localPath: row["local_path"],
            createdAt: row["created_at"]
        )
    }

    private func decodeLinkPreview(_ row: Row) -> NostrLinkPreviewRecord {
        NostrLinkPreviewRecord(
            url: row["url"],
            normalizedURL: row["normalized_url"],
            status: row["status"],
            title: row["title"],
            summary: row["summary"],
            siteName: row["site_name"],
            imageURL: row["image_url"],
            fetchedAt: row["fetched_at"],
            expiresAt: row["expires_at"],
            error: row["error"]
        )
    }

    private func decodeOutboxEvent(_ row: Row) throws -> NostrOutboxEventRecord {
        let eventData: Data = row["event_json"]
        return NostrOutboxEventRecord(
            localID: row["local_id"],
            accountID: row["account_id"],
            eventID: row["event_id"],
            event: try decoder.decode(NostrEvent.self, from: eventData),
            status: row["status"],
            createdAt: row["created_at"],
            nextRetryAt: row["next_retry_at"],
            lastError: row["last_error"]
        )
    }

    private func decodeOutboxRelay(_ row: Row) -> NostrOutboxRelayRecord {
        NostrOutboxRelayRecord(
            localID: row["local_id"],
            relayURL: row["relay_url"],
            status: row["status"],
            lastAttemptAt: row["last_attempt_at"],
            okMessage: row["ok_message"],
            attemptCount: row["attempt_count"]
        )
    }

    private func aggregateOutboxStatus(relayStatuses: [String]) -> String {
        guard !relayStatuses.isEmpty else { return NostrOutboxStatus.failed }
        let publishedCount = relayStatuses.filter { $0 == NostrOutboxStatus.published }.count
        let failedCount = relayStatuses.filter { $0 == NostrOutboxStatus.failed }.count
        let rejectedCount = relayStatuses.filter { $0 == NostrOutboxStatus.rejected }.count
        let terminalCount = publishedCount + rejectedCount

        if terminalCount == relayStatuses.count {
            return publishedCount > 0 ? NostrOutboxStatus.published : NostrOutboxStatus.rejected
        }
        if failedCount + rejectedCount == relayStatuses.count {
            return NostrOutboxStatus.failed
        }
        if terminalCount > 0 && failedCount > 0 {
            return NostrOutboxStatus.partial
        }
        if relayStatuses.contains(NostrOutboxStatus.publishing) {
            return NostrOutboxStatus.publishing
        }
        return NostrOutboxStatus.pending
    }

    private static func outboxRetryDelaySeconds(attemptCount: Int) -> Int {
        let exponent = max(0, min(attemptCount - 1, 7))
        return min(3_600, 30 * (1 << exponent))
    }

    private func decodeTimelineEntry(_ row: Row) -> NostrTimelineEntryRecord {
        NostrTimelineEntryRecord(
            accountID: row["account_id"],
            timelineKey: row["timeline_key"],
            eventID: row["event_id"],
            sortTimestamp: row["sort_ts"],
            source: row["source"],
            insertedAt: row["inserted_at"],
            gapBefore: row["gap_before"],
            gapAfter: row["gap_after"]
        )
    }

    private func decodeFeedDefinition(_ row: Row) -> NostrFeedDefinitionRecord {
        NostrFeedDefinitionRecord(
            feedID: row["feed_id"],
            accountID: row["account_id"],
            kind: row["feed_kind"],
            specificationJSON: row["spec_json"],
            specificationHash: row["spec_hash"],
            sortPolicy: row["sort_policy"],
            revision: row["revision"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func decodeFeedMembership(_ row: Row) -> NostrFeedMembershipRecord {
        NostrFeedMembershipRecord(
            feedID: row["feed_id"],
            eventID: row["event_id"],
            subjectEventID: row["subject_event_id"],
            sortTimestamp: row["sort_ts"],
            reason: row["reason"],
            insertedAt: row["inserted_at"],
            feedRevision: row["feed_revision"]
        )
    }

    private func decodeFeedMembershipSource(_ row: Row) -> NostrFeedMembershipSourceRecord {
        NostrFeedMembershipSourceRecord(
            feedID: row["feed_id"],
            eventID: row["event_id"],
            sourceType: row["source_type"],
            sourceID: row["source_id"],
            insertedAt: row["inserted_at"],
            feedRevision: row["feed_revision"]
        )
    }

    private func decodeFeedGap(_ row: Row) -> NostrFeedGapRecord? {
        let rawState: String = row["gap_state"]
        guard let state = NostrFeedGapState(rawValue: rawState) else { return nil }
        return NostrFeedGapRecord(
            feedID: row["feed_id"],
            feedRevision: row["feed_revision"],
            newerEventID: row["newer_event_id"],
            olderEventID: row["older_event_id"],
            state: state,
            sourceRequestID: row["source_request_id"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            resolvedAt: row["resolved_at"]
        )
    }

    private func decodeDeletedFeedItem(_ row: Row) -> NostrDeletedFeedItemRecord {
        NostrDeletedFeedItemRecord(
            feedID: row["feed_id"],
            feedRevision: row["feed_revision"],
            targetEventID: row["target_event_id"],
            deletionEventID: row["deletion_event_id"],
            deletedAt: row["deleted_at"],
            sortTimestamp: row["sort_ts"]
        )
    }

    private func decodeFeedSyncRequest(_ row: Row) -> NostrFeedSyncRequestRecord? {
        let rawProtocol: String = row["protocol_kind"]
        let rawDirection: String = row["direction"]
        let rawPurpose: String = row["purpose"]
        guard let syncProtocol = NostrFeedSyncProtocol(rawValue: rawProtocol),
              let direction = NostrFeedSyncDirection(rawValue: rawDirection),
              let purpose = NostrFeedSyncPurpose(rawValue: rawPurpose)
        else { return nil }
        let rawEndReason: String? = row["end_reason"]
        let rawVerificationOutcome: String? = row["verification_outcome"]
        let oldestTimestamp: Int? = row["observed_oldest_ts"]
        let oldestEventID: String? = row["observed_oldest_event_id"]
        let newestTimestamp: Int? = row["observed_newest_ts"]
        let newestEventID: String? = row["observed_newest_event_id"]
        return NostrFeedSyncRequestRecord(
            requestID: row["request_id"],
            feedID: row["feed_id"],
            feedRevision: row["feed_revision"],
            feedSpecificationHash: row["feed_spec_hash"],
            relayURL: row["relay_url"],
            subscriptionID: row["subscription_id"],
            syncProtocol: syncProtocol,
            direction: direction,
            purpose: purpose,
            requestedAt: row["requested_at"],
            installedAt: row["installed_at"],
            eoseAt: row["eose_at"],
            endedAt: row["ended_at"],
            endReason: rawEndReason.flatMap(NostrFeedSyncEndReason.init(rawValue:)),
            endMessage: row["end_message"],
            eventCount: row["event_count"],
            observedOldestPosition: optionalTimelineCursor(
                sortTimestamp: oldestTimestamp,
                eventID: oldestEventID
            ),
            observedNewestPosition: optionalTimelineCursor(
                sortTimestamp: newestTimestamp,
                eventID: newestEventID
            ),
            verificationOutcome: rawVerificationOutcome.flatMap(NostrFeedVerificationOutcome.init(rawValue:)),
            differenceCount: row["difference_count"]
        )
    }

    private func decodeFeedSyncFilter(_ row: Row) -> NostrFeedSyncFilterRecord {
        NostrFeedSyncFilterRecord(
            requestID: row["request_id"],
            filterIndex: row["filter_index"],
            filterJSON: row["filter_json"],
            filterHash: row["filter_hash"],
            scopeHash: row["scope_hash"],
            requestedSince: row["requested_since"],
            requestedUntil: row["requested_until"],
            requestedLimit: row["request_limit"],
            hitLimit: row["hit_limit"]
        )
    }

    private func decodeFeedCoverageSegment(_ row: Row) -> NostrFeedCoverageSegmentRecord? {
        let rawConfidence: String = row["confidence"]
        guard let confidence = NostrFeedCoverageConfidence(rawValue: rawConfidence) else { return nil }
        return NostrFeedCoverageSegmentRecord(
            segmentID: row["segment_id"],
            feedID: row["feed_id"],
            feedRevision: row["feed_revision"],
            feedSpecificationHash: row["feed_spec_hash"],
            relayURL: row["relay_url"],
            scopeHash: row["scope_hash"],
            lowerTimestamp: row["lower_ts"],
            upperTimestamp: row["upper_ts"],
            snapshotAt: row["snapshot_at"],
            confidence: confidence,
            sourceRequestID: row["source_request_id"],
            createdAt: row["created_at"]
        )
    }

    private func decodeFeedSyncCheckpoint(_ row: Row) -> NostrFeedSyncCheckpointRecord? {
        let newestTimestamp: Int? = row["newest_ts"]
        let newestEventID: String? = row["newest_event_id"]
        let oldestTimestamp: Int? = row["oldest_ts"]
        let oldestEventID: String? = row["oldest_event_id"]
        return NostrFeedSyncCheckpointRecord(
            feedID: row["feed_id"],
            feedRevision: row["feed_revision"],
            relayURL: row["relay_url"],
            scopeHash: row["scope_hash"],
            newestPosition: optionalTimelineCursor(
                sortTimestamp: newestTimestamp,
                eventID: newestEventID
            ),
            oldestPosition: optionalTimelineCursor(
                sortTimestamp: oldestTimestamp,
                eventID: oldestEventID
            ),
            lastEOSEAt: row["last_eose_at"],
            lastVerifiedAt: row["last_verified_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func decodeFeedReadState(_ row: Row) -> NostrFeedReadStateRecord {
        let readSortTimestamp: Int? = row["read_sort_ts"]
        let readEventID: String? = row["read_event_id"]
        return NostrFeedReadStateRecord(
            feedID: row["feed_id"],
            readBoundary: optionalTimelineCursor(
                sortTimestamp: readSortTimestamp,
                eventID: readEventID
            ),
            updatedAt: row["updated_at"]
        )
    }

    private func optionalTimelineCursor(
        sortTimestamp: Int?,
        eventID: String?
    ) -> NostrTimelineEntryCursor? {
        guard let sortTimestamp, let eventID else { return nil }
        return NostrTimelineEntryCursor(sortTimestamp: sortTimestamp, eventID: eventID)
    }

    private func decodeDeletedTimelineEntry(_ row: Row) -> NostrDeletedTimelineEntryRecord {
        NostrDeletedTimelineEntryRecord(
            targetEventID: row["target_event_id"],
            deletionEventID: row["deletion_event_id"],
            deletedAt: row["deleted_at"],
            sortTimestamp: row["sort_ts"]
        )
    }

    private func decodeSyncCursor(_ row: Row) -> NostrSyncCursorRecord {
        NostrSyncCursorRecord(
            accountID: row["account_id"],
            timelineKey: row["timeline_key"],
            relayURL: row["relay_url"],
            newestCreatedAt: row["newest_created_at"],
            oldestCreatedAt: row["oldest_created_at"],
            lastEOSEAt: row["last_eose_at"],
            lastNegentropyAt: row["last_negentropy_at"]
        )
    }

    private func decodeRelayProfile(_ row: Row) throws -> NostrRelayProfileRecord {
        let informationData: Data? = row["information_json"]
        return NostrRelayProfileRecord(
            relayURL: row["relay_url"],
            information: try informationData.map { try decoder.decode(NostrRelayInformationDocument.self, from: $0) },
            healthScore: row["health_score"],
            lastEOSEAt: row["last_eose_at"],
            lastConnectedAt: row["last_connected_at"],
            authRequired: row["auth_required"],
            paymentRequired: row["payment_required"]
        )
    }

    private func decodeRelayPreference(_ row: Row) -> NostrRelayPreferenceRecord {
        NostrRelayPreferenceRecord(
            accountID: row["account_id"],
            relayURL: row["relay_url"],
            isEnabled: row["is_enabled"],
            readEnabled: row["read_enabled"],
            writeEnabled: row["write_enabled"],
            updatedAt: row["updated_at"]
        )
    }

    private func decodeDraft(_ row: Row) throws -> NostrDraftRecord {
        let contextData: Data = row["context_json"]
        let tagsData: Data = row["tags_json"]
        let mediaData: Data = row["media_json"]
        return NostrDraftRecord(
            draftID: row["draft_id"],
            accountID: row["account_id"],
            context: try decoder.decode(NostrDraftContext.self, from: contextData),
            text: row["text"],
            contentWarning: row["content_warning"],
            tags: try decoder.decode([[String]].self, from: tagsData),
            media: try decoder.decode([NostrDraftMediaReference].self, from: mediaData),
            updatedAt: row["updated_at"]
        )
    }

    private func decodeFilterRule(_ row: Row) -> NostrFilterRuleRecord? {
        guard let kind = NostrFilterRuleKind(rawValue: row["rule_kind"]) else { return nil }
        let presentation = NostrFilterRulePresentation(rawValue: row["presentation"] ?? "") ?? .maskWithWarning
        let scopes = decodeFilterRuleScopes(row["scopes_json"])
        return NostrFilterRuleRecord(
            ruleID: row["rule_id"],
            accountID: row["account_id"],
            kind: kind,
            value: row["value"],
            expiresAt: row["expires_at"],
            isEnabled: row["is_enabled"],
            presentation: presentation,
            scopes: scopes,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func decodeFilterRuleScopes(_ data: Data?) -> Set<NostrFilterTimelineScope> {
        guard let data,
              let rawValues = try? decoder.decode([String].self, from: data)
        else {
            return [.home, .lists, .publicTimelines]
        }
        let scopes = Set(rawValues.compactMap(NostrFilterTimelineScope.init(rawValue:)))
        return scopes.isEmpty ? [.home, .lists, .publicTimelines] : scopes
    }

    private func decodeLocalBookmark(_ row: Row) -> NostrLocalBookmarkRecord {
        NostrLocalBookmarkRecord(
            accountID: row["account_id"],
            eventID: row["event_id"],
            createdAt: row["created_at"]
        )
    }

    private func decodeRelaySyncEvent(_ row: Row) -> NostrRelaySyncEventRecord? {
        guard let kind = NostrRelaySyncEventKind(rawValue: row["event_kind"]) else {
            return nil
        }
        return NostrRelaySyncEventRecord(
            accountID: row["account_id"],
            timelineKey: row["timeline_key"],
            relayURL: row["relay_url"],
            kind: kind,
            occurredAt: row["occurred_at"],
            subscriptionID: row["subscription_id"],
            eventCount: row["event_count"],
            newestCreatedAt: row["newest_created_at"],
            oldestCreatedAt: row["oldest_created_at"],
            latencyMilliseconds: row["latency_ms"],
            message: row["message"]
        )
    }

    private func decodeEventSource(_ row: Row) -> NostrEventSourceRecord {
        NostrEventSourceRecord(
            eventID: row["event_id"],
            relayURL: row["relay_url"],
            firstSeenAt: row["first_seen_at"],
            lastSeenAt: row["last_seen_at"]
        )
    }

    private func isReplaceable(kind: Int) -> Bool {
        kind == 0 || kind == 3 || (10_000...19_999).contains(kind)
    }

    private func isAddressable(kind: Int) -> Bool {
        (30_000...39_999).contains(kind)
    }

    private func expirationTimestamp(from event: NostrEvent) -> Int? {
        event.tags.first { tag in
            tag.count >= 2 && tag[0] == "expiration"
        }.flatMap { Int($0[1]) }
    }

    private func relayHint(from tag: [String]) -> String? {
        switch tag.first {
        case "e", "p", "a":
            guard tag.count >= 3, tag[2].hasPrefix("wss://") || tag[2].hasPrefix("ws://") else { return nil }
            return tag[2]
        default:
            return nil
        }
    }

    private func marker(from tag: [String]) -> String? {
        switch tag.first {
        case "e":
            guard tag.count >= 4 else { return nil }
            return tag[3]
        default:
            return nil
        }
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }
}

private extension NostrProfileSearchResult {
    func matches(_ normalizedQuery: String) -> Bool {
        let haystacks = [
            displayName,
            nip05,
            pubkey,
            pubkey.abbreviatedMiddle
        ]
        return haystacks
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedQuery) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var abbreviatedMiddle: String {
        guard count > 18 else { return self }
        return "\(prefix(10))...\(suffix(8))"
    }
}
