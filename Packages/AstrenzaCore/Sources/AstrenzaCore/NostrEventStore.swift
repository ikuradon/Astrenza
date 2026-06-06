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
