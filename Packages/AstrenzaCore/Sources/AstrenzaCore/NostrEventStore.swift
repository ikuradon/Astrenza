import Foundation
import GRDB

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

public enum NostrRelaySyncEventKind: String, Codable, Equatable, Sendable {
    case connected
    case eose
    case closed
    case reconnect
    case timeout
    case partialFailure
    case authRequired
    case paymentRequired
    case negentropy
}

public struct NostrRelaySyncEventRecord: Codable, Equatable, Sendable {
    public let accountID: String
    public let timelineKey: String
    public let relayURL: String
    public let kind: NostrRelaySyncEventKind
    public let occurredAt: Int
    public let subscriptionID: String?
    public let eventCount: Int
    public let newestCreatedAt: Int?
    public let oldestCreatedAt: Int?
    public let latencyMilliseconds: Int?
    public let message: String?

    public init(
        accountID: String,
        timelineKey: String,
        relayURL: String,
        kind: NostrRelaySyncEventKind,
        occurredAt: Int,
        subscriptionID: String? = nil,
        eventCount: Int = 0,
        newestCreatedAt: Int? = nil,
        oldestCreatedAt: Int? = nil,
        latencyMilliseconds: Int? = nil,
        message: String? = nil
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.relayURL = relayURL
        self.kind = kind
        self.occurredAt = occurredAt
        self.subscriptionID = subscriptionID
        self.eventCount = eventCount
        self.newestCreatedAt = newestCreatedAt
        self.oldestCreatedAt = oldestCreatedAt
        self.latencyMilliseconds = latencyMilliseconds
        self.message = message
    }
}

private struct RelaySyncBucket: Hashable {
    let accountID: String
    let timelineKey: String
    let relayURL: String
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
        self.lastPartialFailureReason = lastPartialFailureReason
        self.totalEventCount = totalEventCount
        self.averageEOSELatencyMilliseconds = averageEOSELatencyMilliseconds
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

public final class NostrEventStore {
    private let database: any DatabaseWriter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
            for event in events {
                try upsert(event: event, receivedAt: receivedAt, db: db)
                try replaceTags(for: event, db: db)
                try replaceMediaAssets(for: event, receivedAt: receivedAt, db: db)
                try upsertLinkPreviewRequests(for: event, db: db)
                try upsertReplaceableHeadIfNeeded(for: event, db: db)
                try upsertAddressableHeadIfNeeded(for: event, db: db)
                try upsertListIfNeeded(for: event, accountID: event.pubkey, db: db)
            }
            for event in events where event.kind == 5 {
                try applyDeletionRequest(event, db: db)
            }
        }
    }

    public func saveHomeTimelineState(
        _ state: NostrHomeTimelineState,
        accountID: String,
        timelineKey: String = "home",
        savedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        let events = state.noteEvents + state.metadataEvents + [state.relayListEvent, state.contactListEvent].compactMap { $0 }
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

        let newestCreatedAt = state.noteEvents.map(\.createdAt).max()
        let oldestCreatedAt = state.noteEvents.map(\.createdAt).min()
        for relayURL in state.relays {
            try saveSyncCursor(NostrSyncCursorRecord(
                accountID: accountID,
                timelineKey: timelineKey,
                relayURL: relayURL,
                newestCreatedAt: newestCreatedAt,
                oldestCreatedAt: oldestCreatedAt,
                lastEOSEAt: savedAt,
                lastNegentropyAt: nil
            ))
        }
        try saveRelaySyncEvents(state.relaySyncEvents)
        try updateSyncCursors(from: state.relaySyncEvents)

        try saveTimelineStateMetadata(state, accountID: accountID, timelineKey: timelineKey, savedAt: savedAt)
    }

    public func homeTimelineState(
        accountID: String,
        timelineKey: String = "home",
        limit: Int = 250,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrHomeTimelineState? {
        try database.read { db in
            let notes = try timelineEvents(accountID: accountID, timelineKey: timelineKey, limit: limit, now: now, db: db)
            guard !notes.isEmpty else { return nil }

            let metadataEvents = try latestReplaceableEvents(
                pubkeys: Set(notes.map(\.pubkey)),
                kind: 0,
                now: now,
                db: db
            )

            let stateMetadata = try timelineStateMetadata(accountID: accountID, timelineKey: timelineKey, db: db)
            let relayListEvent = try latestReplaceableEvent(pubkey: accountID, kind: 10002, now: now, db: db)
            let contactListEvent = try latestReplaceableEvent(pubkey: accountID, kind: 3, now: now, db: db)
            let relayList = NostrRelayList.parse(from: relayListEvent)
            let contactPubkeys = contactListEvent.map(NostrContactList.pubkeys(from:)) ?? []
            let relays = relayList.readRelays.isEmpty
                ? (stateMetadata?.relays ?? syncRelayURLs(accountID: accountID, timelineKey: timelineKey, db: db))
                : relayList.readRelays

            return NostrHomeTimelineState(
                relays: relays,
                followedPubkeys: contactPubkeys.isEmpty ? (stateMetadata?.followedPubkeys ?? []) : contactPubkeys,
                noteEvents: notes,
                metadataEvents: metadataEvents,
                relayListEvent: relayListEvent,
                contactListEvent: contactListEvent,
                nip05Resolutions: stateMetadata?.nip05Resolutions ?? [:],
                hasMoreOlder: stateMetadata?.hasMoreOlder ?? true
            )
        }
    }

    public func event(id: String) throws -> NostrEvent? {
        try database.read { db in
            try fetchEvent(id: id, db: db)
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
                SELECT local_id, relay_url, status, last_attempt_at, ok_message
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
        attemptedAt: Int = Int(Date().timeIntervalSince1970)
    ) throws {
        try database.write { db in
            let status = accepted ? NostrOutboxStatus.published : NostrOutboxStatus.failed
            try db.execute(
                sql: """
                UPDATE outbox_relays
                SET status = ?, last_attempt_at = ?, ok_message = ?
                WHERE local_id = ? AND relay_url = ?
                """,
                arguments: [status, attemptedAt, message, localID, relayURL]
            )

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT status, ok_message
                FROM outbox_relays
                WHERE local_id = ?
                """,
                arguments: [localID]
            )
            let statuses = rows.map { String($0["status"]) }
            let aggregate = aggregateOutboxStatus(relayStatuses: statuses)
            let lastError = rows
                .compactMap { row -> String? in
                    guard String(row["status"]) == NostrOutboxStatus.failed else { return nil }
                    return row["ok_message"]
                }
                .last

            try db.execute(
                sql: """
                UPDATE outbox_events
                SET status = ?, last_error = ?
                WHERE local_id = ?
                """,
                arguments: [aggregate, lastError, localID]
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
            for eventID in eventIDs {
                try db.execute(
                    sql: """
                    INSERT INTO event_sources (event_id, relay_url, first_seen_at, last_seen_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(event_id, relay_url) DO UPDATE SET
                        last_seen_at = excluded.last_seen_at
                    """,
                    arguments: [eventID, relayURL, seenAt, seenAt]
                )
            }
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

    public func saveTimelineEntries(_ entries: [NostrTimelineEntryRecord]) throws {
        guard !entries.isEmpty else { return }

        try database.write { db in
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
                        gap_before = excluded.gap_before,
                        gap_after = excluded.gap_after
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
                LEFT JOIN deletion_tombstones tombstone ON tombstone.target_event_id = te.event_id
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
        let mediaData = try encoder.encode(draft.media)
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO drafts (
                    draft_id, account_id, kind, parent_event_id, text, content_warning, media_json, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(draft_id) DO UPDATE SET
                    account_id = excluded.account_id,
                    kind = excluded.kind,
                    parent_event_id = excluded.parent_event_id,
                    text = excluded.text,
                    content_warning = excluded.content_warning,
                    media_json = excluded.media_json,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    draft.draftID,
                    draft.accountID,
                    draft.kind,
                    draft.parentEventID,
                    draft.text,
                    draft.contentWarning,
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
                SELECT draft_id, account_id, kind, parent_event_id, text,
                    content_warning, media_json, updated_at
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
                    lastPartialFailureReason: lastPartialFailureReason,
                    totalEventCount: totalEventCount,
                    averageEOSELatencyMilliseconds: averageEOSELatency
                )
            }
        }
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

        try migrator.migrate(database)
    }

    private func upsert(event: NostrEvent, receivedAt: Int, db: Database) throws {
        let tagsData = try encoder.encode(event.tags)
        let rawData = try encoder.encode(event)
        let expiresAt = expirationTimestamp(from: event)

        try db.execute(
            sql: """
            INSERT INTO events (
                event_id, pubkey, created_at, kind, content, tags_json, sig,
                received_at, deleted_at, expires_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
            ON CONFLICT(event_id) DO UPDATE SET
                pubkey = excluded.pubkey,
                created_at = excluded.created_at,
                kind = excluded.kind,
                content = excluded.content,
                tags_json = excluded.tags_json,
                sig = excluded.sig,
                received_at = excluded.received_at,
                expires_at = excluded.expires_at,
                raw_json = excluded.raw_json
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
        for url in NostrLinkParser.webURLs(in: event.content) where !NostrMediaParser.isDirectMediaURL(url) {
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
        let targetIDs = deletionEvent.tags.compactMap { tag -> String? in
            guard tag.first == "e", tag.count > 1 else { return nil }
            return tag[1]
        }
        guard !targetIDs.isEmpty else { return }

        for targetID in Set(targetIDs) {
            guard let target = try fetchEvent(id: targetID, db: db), target.pubkey == deletionEvent.pubkey else {
                continue
            }

            try db.execute(
                sql: """
                INSERT INTO deletion_tombstones (
                    target_event_id, deletion_event_id, deleted_at, author_pubkey
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(target_event_id) DO UPDATE SET
                    deletion_event_id = excluded.deletion_event_id,
                    deleted_at = excluded.deleted_at,
                    author_pubkey = excluded.author_pubkey
                """,
                arguments: [
                    targetID,
                    deletionEvent.id,
                    deletionEvent.createdAt,
                    deletionEvent.pubkey
                ]
            )

            try db.execute(
                sql: """
                UPDATE events
                SET deleted_at = ?
                WHERE event_id = ?
                """,
                arguments: [deletionEvent.createdAt, targetID]
            )
        }
    }

    private func saveTimelineStateMetadata(
        _ state: NostrHomeTimelineState,
        accountID: String,
        timelineKey: String,
        savedAt: Int
    ) throws {
        let relaysData = try encoder.encode(state.relays)
        let followedData = try encoder.encode(state.followedPubkeys)
        let nip05Data = try encoder.encode(state.nip05Resolutions)

        try database.write { db in
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
    }

    private func updateSyncCursors(from events: [NostrRelaySyncEventRecord]) throws {
        let cursorEvents = events.filter { event in
            event.kind == .eose || event.kind == .negentropy
        }
        guard !cursorEvents.isEmpty else { return }

        try database.write { db in
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

        var events: [NostrEvent] = []
        for pubkey in pubkeys {
            guard let event = try latestReplaceableEvent(pubkey: pubkey, kind: kind, now: now, db: db) else {
                continue
            }
            events.append(event)
        }
        return events.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
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
                AND event_kind IN (?, ?, ?, ?, ?)
            """,
            arguments: [
                accountID,
                timelineKey,
                relayURL,
                NostrRelaySyncEventKind.closed.rawValue,
                NostrRelaySyncEventKind.timeout.rawValue,
                NostrRelaySyncEventKind.partialFailure.rawValue,
                NostrRelaySyncEventKind.authRequired.rawValue,
                NostrRelaySyncEventKind.paymentRequired.rawValue
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
            okMessage: row["ok_message"]
        )
    }

    private func aggregateOutboxStatus(relayStatuses: [String]) -> String {
        guard !relayStatuses.isEmpty else { return NostrOutboxStatus.failed }
        let publishedCount = relayStatuses.filter { $0 == NostrOutboxStatus.published }.count
        let failedCount = relayStatuses.filter { $0 == NostrOutboxStatus.failed }.count

        if publishedCount == relayStatuses.count {
            return NostrOutboxStatus.published
        }
        if failedCount == relayStatuses.count {
            return NostrOutboxStatus.failed
        }
        if publishedCount > 0 && failedCount > 0 {
            return NostrOutboxStatus.partial
        }
        if relayStatuses.contains(NostrOutboxStatus.publishing) {
            return NostrOutboxStatus.publishing
        }
        return NostrOutboxStatus.pending
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
        let mediaData: Data = row["media_json"]
        return NostrDraftRecord(
            draftID: row["draft_id"],
            accountID: row["account_id"],
            kind: row["kind"],
            parentEventID: row["parent_event_id"],
            text: row["text"],
            contentWarning: row["content_warning"],
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
