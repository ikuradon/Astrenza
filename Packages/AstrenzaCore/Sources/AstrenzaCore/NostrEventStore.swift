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
                try upsertReplaceableHeadIfNeeded(for: event, db: db)
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

        try saveTimelineStateMetadata(state, accountID: accountID, timelineKey: timelineKey, savedAt: savedAt)
    }

    public func homeTimelineState(accountID: String, timelineKey: String = "home", limit: Int = 250) throws -> NostrHomeTimelineState? {
        try database.read { db in
            let notes = try timelineEvents(accountID: accountID, timelineKey: timelineKey, limit: limit, db: db)
            guard !notes.isEmpty else { return nil }

            let metadataEvents = try latestReplaceableEvents(
                pubkeys: Set(notes.map(\.pubkey)),
                kind: 0,
                db: db
            )

            let stateMetadata = try timelineStateMetadata(accountID: accountID, timelineKey: timelineKey, db: db)
            let relayListEvent = try latestReplaceableEvent(pubkey: accountID, kind: 10002, db: db)
            let contactListEvent = try latestReplaceableEvent(pubkey: accountID, kind: 3, db: db)
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

    public func events(kind: Int, limit: Int) throws -> [NostrEvent] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT event_id, pubkey, created_at, kind, tags_json, content, sig
                FROM events
                WHERE kind = ? AND deleted_at IS NULL
                ORDER BY created_at DESC, event_id ASC
                LIMIT ?
                """,
                arguments: [kind, limit]
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

    public func latestReplaceableEvent(pubkey: String, kind: Int) throws -> NostrEvent? {
        try database.read { db in
            guard let eventID = try String.fetchOne(
                db,
                sql: "SELECT event_id FROM replaceable_heads WHERE pubkey = ? AND kind = ?",
                arguments: [pubkey, kind]
            ) else {
                return nil
            }
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

    public func timelineEvents(accountID: String, timelineKey: String, limit: Int) throws -> [NostrEvent] {
        try database.read { db in
            try timelineEvents(accountID: accountID, timelineKey: timelineKey, limit: limit, db: db)
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

    private func timelineEvents(accountID: String, timelineKey: String, limit: Int, db: Database) throws -> [NostrEvent] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT e.event_id, e.pubkey, e.created_at, e.kind, e.tags_json, e.content, e.sig
            FROM timeline_entries te
            JOIN events e ON e.event_id = te.event_id
            WHERE te.account_id = ? AND te.timeline_key = ? AND e.deleted_at IS NULL
            ORDER BY te.sort_ts DESC, te.event_id ASC
            LIMIT ?
            """,
            arguments: [accountID, timelineKey, limit]
        )
        return try rows.map(decodeEvent)
    }

    private func latestReplaceableEvents(pubkeys: Set<String>, kind: Int, db: Database) throws -> [NostrEvent] {
        guard !pubkeys.isEmpty else { return [] }

        var events: [NostrEvent] = []
        for pubkey in pubkeys {
            guard let event = try latestReplaceableEvent(pubkey: pubkey, kind: kind, db: db) else {
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

    private func latestReplaceableEvent(pubkey: String, kind: Int, db: Database) throws -> NostrEvent? {
        guard let eventID = try String.fetchOne(
            db,
            sql: "SELECT event_id FROM replaceable_heads WHERE pubkey = ? AND kind = ?",
            arguments: [pubkey, kind]
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
}
