import Foundation
import SQLite3
import Testing
@testable import AstrenzaCore

@Suite("TimelineRepositoryStore read-only")
struct TimelineRepositoryStoreReadOnlyTests {
    @Test("official v0.2 DDL fixture creates required TimelineRepository tables")
    func officialV02DDLFixtureCreatesRequiredTimelineRepositoryTables() throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()

        #expect(try fixture.columns(in: "feeds") == [
            "id",
            "account_id",
            "type",
            "title",
            "params_json",
            "include_replies",
            "include_reposts",
            "relay_set_hash",
            "created_at_ms",
            "updated_at_ms"
        ])
        #expect(try fixture.columns(in: "feed_items") == [
            "feed_id",
            "item_key",
            "source_event_id",
            "subject_event_id",
            "reason",
            "actor_pubkey",
            "sort_at",
            "tie_break_id",
            "hidden_reason",
            "collapsed",
            "pending_new",
            "inserted_at_ms",
            "updated_at_ms"
        ])
        #expect(try fixture.columns(in: "feed_read_state") == [
            "account_id",
            "feed_id",
            "marker_sort_at",
            "marker_event_id",
            "scroll_anchor_item_key",
            "scroll_anchor_event_id",
            "scroll_anchor_sort_at",
            "scroll_anchor_tie_break_id",
            "scroll_anchor_offset_px",
            "viewport_height_px",
            "viewport_width_px",
            "content_inset_top_px",
            "content_inset_bottom_px",
            "last_visible_top_id",
            "last_visible_bottom_id",
            "restore_fallback_reason",
            "client_state_json",
            "last_viewed_at_ms",
            "updated_at_ms"
        ])
    }

    @Test("visible query filters hidden pending rows orders deterministically and isolates feeds")
    func visibleQueryFiltersHiddenPendingRowsOrdersDeterministicallyAndIsolatesFeeds() async throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()
        try fixture.seedFeed(id: 20, paramsJSON: "{\"scope\":\"other\"}")
        try fixture.seedFeedItems([
            fixture.feedItem(
                itemKey: "note:newest",
                sourceEventID: eventID("a"),
                actorPubkey: pubkey("a"),
                sortAt: 30,
                tieBreakID: "z"
            ),
            fixture.feedItem(
                itemKey: "note:older-b",
                sourceEventID: eventID("b"),
                actorPubkey: pubkey("b"),
                sortAt: 10,
                tieBreakID: "b"
            ),
            fixture.feedItem(
                itemKey: "note:older-a",
                sourceEventID: eventID("c"),
                actorPubkey: pubkey("c"),
                sortAt: 10,
                tieBreakID: "a"
            ),
            fixture.feedItem(
                itemKey: "note:hidden",
                sourceEventID: eventID("d"),
                actorPubkey: pubkey("d"),
                sortAt: 50,
                tieBreakID: "h",
                hiddenReason: "muted"
            ),
            fixture.feedItem(
                itemKey: "note:pending",
                sourceEventID: eventID("e"),
                actorPubkey: pubkey("e"),
                sortAt: 40,
                tieBreakID: "p",
                pendingNew: true
            ),
            fixture.feedItem(
                itemKey: "note:collapsed",
                sourceEventID: eventID("f"),
                actorPubkey: pubkey("f"),
                sortAt: 20,
                tieBreakID: "c",
                collapsed: true
            )
        ])
        try fixture.seedFeedItems([
            fixture.feedItem(
                feedID: 20,
                itemKey: "note:other-feed",
                sourceEventID: eventID("9"),
                actorPubkey: pubkey("9"),
                sortAt: 90,
                tieBreakID: "x"
            )
        ], feedID: 20)

        let store = try GRDBTimelineRepositoryStore(databasePath: fixture.path)
        let defaultWindow = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 10)
        )
        let explicitPendingWindow = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .explicitUserPendingNew(itemKeys: ["note:pending"], maxVisibleCount: 10)
        )

        #expect(defaultWindow.rows.map(\.itemKey) == [
            "note:newest",
            "note:collapsed",
            "note:older-a",
            "note:older-b"
        ])
        #expect(defaultWindow.rows.first { $0.itemKey == "note:collapsed" }?.collapsed == true)
        #expect(defaultWindow.diagnostics.excludedHiddenCount == 1)
        #expect(defaultWindow.diagnostics.excludedPendingNewCount == 1)
        #expect(defaultWindow.diagnostics.pendingNewIncludedCount == 0)
        #expect(defaultWindow.rows.allSatisfy { $0.feedID == 10 })

        #expect(explicitPendingWindow.rows.map(\.itemKey) == [
            "note:pending",
            "note:newest",
            "note:collapsed",
            "note:older-a",
            "note:older-b"
        ])
        #expect(explicitPendingWindow.diagnostics.pendingNewIncludedCount == 1)
        #expect(explicitPendingWindow.rows.first?.pendingNew == true)
    }

    @Test("read state is read without merging marker and scroll anchor state")
    func readStateIsReadWithoutMergingMarkerAndScrollAnchorState() async throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()
        try fixture.seedFeedItems([
            fixture.feedItem(itemKey: "note:top", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
            fixture.feedItem(itemKey: "note:anchor", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
            fixture.feedItem(itemKey: "note:marker", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c")
        ])
        try fixture.seedReadState(
            scrollAnchorItemKey: "note:anchor",
            scrollAnchorEventID: eventID("b"),
            scrollAnchorSortAt: 200,
            scrollAnchorTieBreakID: "b",
            markerEventID: eventID("c"),
            markerSortAt: 100,
            lastVisibleTopID: "note:top",
            lastVisibleBottomID: "note:marker"
        )

        let store = try GRDBTimelineRepositoryStore(databasePath: fixture.path)
        let readState = try await store.fetchReadState(feedID: 10, databaseAccountID: 1)
        let window = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 3)
        )
        let missingReadState = try await store.fetchReadState(feedID: 20, databaseAccountID: 1)

        #expect(readState?.scrollAnchorItemKey == "note:anchor")
        #expect(readState?.markerEventID == eventID("c"))
        #expect(readState?.markerSortAt == 100)
        #expect(readState?.scrollAnchorItemKey != readState?.markerEventID)
        #expect(window.anchorItemKey == "note:anchor")
        #expect(window.readState?.lastVisibleTopID == "note:top")
        #expect(missingReadState == nil)
    }

    @Test("read methods do not mutate feed rows read state pending rows resolve jobs or diagnostics")
    func readMethodsDoNotMutateFeedRowsReadStatePendingRowsResolveJobsOrDiagnostics() async throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()
        try fixture.seedFeedItems([
            fixture.feedItem(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 30, tieBreakID: "a"),
            fixture.feedItem(itemKey: "note:pending", sourceEventID: eventID("b"), sortAt: 40, tieBreakID: "b", pendingNew: true)
        ])
        try fixture.seedReadState(scrollAnchorItemKey: "note:visible", markerEventID: eventID("a"), markerSortAt: 30)

        let before = try fixture.auditCounts()
        let beforeReadState = try fixture.readStateSnapshot()
        let store = try GRDBTimelineRepositoryStore(databasePath: fixture.path)

        _ = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 10)
        )
        _ = try await store.fetchReadState(feedID: 10, databaseAccountID: 1)

        #expect(try fixture.auditCounts() == before)
        #expect(try fixture.readStateSnapshot() == beforeReadState)
    }

    @Test("invalid persisted reason and invalid item key return typed issues")
    func invalidPersistedReasonAndInvalidItemKeyReturnTypedIssues() async throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()
        try fixture.seedFeedItems([
            fixture.feedItem(itemKey: "note:valid", sourceEventID: eventID("a"), sortAt: 30, tieBreakID: "a"),
            fixture.feedItem(itemKey: "", sourceEventID: eventID("b"), sortAt: 20, tieBreakID: "b")
        ])
        try fixture.seedInvalidReasonItem(
            itemKey: "note:invalid-reason",
            sourceEventID: eventID("c"),
            reason: "unsupported"
        )

        let store = try GRDBTimelineRepositoryStore(databasePath: fixture.path)
        let window = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(window.rows.map(\.itemKey) == ["note:valid"])
        #expect(window.issues.map(\.kind).contains(.invalidPersistedReason))
        #expect(window.issues.map(\.kind).contains(.invalidItemKey))
    }

    @Test("missing feed returns typed issue and empty initial window")
    func missingFeedReturnsTypedIssueAndEmptyInitialWindow() async throws {
        let fixture = try TimelineRepositoryStoreFixtureDatabase()
        let store = try GRDBTimelineRepositoryStore(databasePath: fixture.path)

        let window = try await store.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 404, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(window.rows.isEmpty)
        #expect(window.readState == nil)
        #expect(window.issues.map(\.kind) == [.missingFeed])
    }

    @Test("Core DTOs are Codable Equatable Sendable and do not import app TimelineEngine types")
    func coreDTOsAreCodableEquatableSendableAndDoNotImportAppTimelineEngineTypes() throws {
        let row = TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: "note:codable",
            sourceEventID: eventID("a"),
            subjectEventID: eventID("b"),
            reason: .quote,
            actorPubkey: pubkey("a"),
            sortAt: 42,
            tieBreakID: "a",
            hiddenReason: nil,
            collapsed: true,
            pendingNew: false,
            insertedAtMS: 100,
            updatedAtMS: 100
        )
        let data = try JSONEncoder().encode(row)
        #expect(try JSONDecoder().decode(TimelineRepositoryFeedItemRow.self, from: data) == row)

        assertSendable(TimelineRepositoryReadRequest.self)
        assertSendable(TimelineRepositoryInitialWindow.self)
        assertSendable(TimelineRepositoryFeedItemRow.self)
        assertSendable(TimelineRepositoryReadStateRow.self)
        assertSendable(TimelineRepositoryStoreIssue.self)
        assertSendable(TimelineRepositoryStoreDiagnostics.self)
        assertSendable(TimelineRepositoryVisiblePolicy.self)

        let source = try String(contentsOf: TimelineRepositoryStoreFixtureDatabase.storeSourceURL())
        #expect(!source.contains("TimelineEngineTypes"))
        #expect(!source.contains("TimelineRepositoryFeedItemDraftRow"))
        #expect(!source.contains("TimelineReadStateDraft"))
        #expect(!source.contains("TimelineEntryID"))
        #expect(!source.contains("import Astrenza"))
    }
}

private final class TimelineRepositoryStoreFixtureDatabase {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AstrenzaTimelineRepositoryStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("timeline-store.sqlite").path

        try withDatabase(flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { database in
            try database.exec("PRAGMA foreign_keys = ON;")
            try database.exec(try Self.officialDDL())
            try database.exec("PRAGMA foreign_keys = ON;")
            try database.exec("""
            INSERT INTO accounts (
              id, pubkey, active, signer_type, created_at_ms, theme_json, client_state_json
            ) VALUES (
              1, '\(pubkey("0"))', 1, 'readonly', 1, '{}', '{}'
            );

            INSERT INTO feeds (
              id, account_id, type, title, params_json, include_replies,
              include_reposts, relay_set_hash, created_at_ms, updated_at_ms
            ) VALUES (
              10, 1, 'home', 'Home', '{}', 0, 1, NULL, 1, 1
            );
            """)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func seedFeed(id: Int64, paramsJSON: String) throws {
        try withDatabase { database in
            try database.exec("""
            INSERT INTO feeds (
              id, account_id, type, title, params_json, include_replies,
              include_reposts, relay_set_hash, created_at_ms, updated_at_ms
            ) VALUES (
              \(id), 1, 'home', 'Home', '\(Self.sql(paramsJSON))', 0, 1, NULL, 1, 1
            );
            """)
        }
    }

    func seedFeedItems(_ items: [FixtureFeedItem], feedID: Int64 = 10) throws {
        try withDatabase { database in
            for item in items {
                try seedEventIfNeeded(item.sourceEventID, pubkey: item.actorPubkey ?? pubkey("0"), database: database)
                if let subjectEventID = item.subjectEventID {
                    try seedEventIfNeeded(subjectEventID, pubkey: item.actorPubkey ?? pubkey("0"), database: database)
                }
                try database.exec("""
                INSERT INTO feed_items (
                  feed_id, item_key, source_event_id, subject_event_id, reason,
                  actor_pubkey, sort_at, tie_break_id, hidden_reason, collapsed,
                  pending_new, inserted_at_ms, updated_at_ms
                ) VALUES (
                  \(feedID), '\(Self.sql(item.itemKey))', '\(item.sourceEventID)',
                  \(Self.sqlNullable(item.subjectEventID)), '\(Self.sql(item.reason))',
                  \(Self.sqlNullable(item.actorPubkey)), \(item.sortAt), '\(Self.sql(item.tieBreakID))',
                  \(Self.sqlNullable(item.hiddenReason)), \(item.collapsed ? 1 : 0),
                  \(item.pendingNew ? 1 : 0), 1, 1
                );
                """)
            }
        }
    }

    func seedInvalidReasonItem(itemKey: String, sourceEventID: String, reason: String) throws {
        try withDatabase { database in
            try seedEventIfNeeded(sourceEventID, pubkey: pubkey("8"), database: database)
            try database.exec("PRAGMA ignore_check_constraints = ON;")
            try database.exec("""
            INSERT INTO feed_items (
              feed_id, item_key, source_event_id, subject_event_id, reason,
              actor_pubkey, sort_at, tie_break_id, hidden_reason, collapsed,
              pending_new, inserted_at_ms, updated_at_ms
            ) VALUES (
              10, '\(Self.sql(itemKey))', '\(sourceEventID)', NULL, '\(Self.sql(reason))',
              '\(pubkey("8"))', 10, 'invalid', NULL, 0, 0, 1, 1
            );
            """)
            try database.exec("PRAGMA ignore_check_constraints = OFF;")
        }
    }

    func seedReadState(
        scrollAnchorItemKey: String?,
        scrollAnchorEventID: String? = nil,
        scrollAnchorSortAt: Int64? = nil,
        scrollAnchorTieBreakID: String? = nil,
        markerEventID: String? = nil,
        markerSortAt: Int64? = nil,
        lastVisibleTopID: String? = nil,
        lastVisibleBottomID: String? = nil
    ) throws {
        try withDatabase { database in
            try database.exec("""
            INSERT INTO feed_read_state (
              account_id, feed_id, marker_sort_at, marker_event_id,
              scroll_anchor_item_key, scroll_anchor_event_id, scroll_anchor_sort_at,
              scroll_anchor_tie_break_id, scroll_anchor_offset_px, viewport_height_px,
              viewport_width_px, content_inset_top_px, content_inset_bottom_px,
              last_visible_top_id, last_visible_bottom_id, restore_fallback_reason,
              client_state_json, last_viewed_at_ms, updated_at_ms
            ) VALUES (
              1, 10, \(Self.intNullable(markerSortAt)), \(Self.sqlNullable(markerEventID)),
              \(Self.sqlNullable(scrollAnchorItemKey)), \(Self.sqlNullable(scrollAnchorEventID)),
              \(Self.intNullable(scrollAnchorSortAt)), \(Self.sqlNullable(scrollAnchorTieBreakID)),
              12, 640, 390, 8, 16, \(Self.sqlNullable(lastVisibleTopID)),
              \(Self.sqlNullable(lastVisibleBottomID)), 'anchorFound', '{}', 2, 3
            );
            """)
        }
    }

    func feedItem(
        feedID: Int64 = 10,
        itemKey: String,
        sourceEventID: String,
        subjectEventID: String? = nil,
        reason: String = "author",
        actorPubkey: String? = pubkey("0"),
        sortAt: Int64,
        tieBreakID: String = "a",
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false
    ) -> FixtureFeedItem {
        FixtureFeedItem(
            feedID: feedID,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: subjectEventID,
            reason: reason,
            actorPubkey: actorPubkey,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew
        )
    }

    func columns(in table: String) throws -> [String] {
        try withDatabase { database in
            try database.queryStrings("PRAGMA table_info(\(table));", column: 1)
        }
    }

    func auditCounts() throws -> FixtureAuditCounts {
        try withDatabase { database in
            FixtureAuditCounts(
                feedItemCount: try database.scalarInt("SELECT COUNT(*) FROM feed_items WHERE feed_id = 10"),
                pendingNewCount: try database.scalarInt("SELECT COUNT(*) FROM feed_items WHERE feed_id = 10 AND pending_new = 1"),
                readStateCount: try database.scalarInt("SELECT COUNT(*) FROM feed_read_state WHERE feed_id = 10"),
                resolveJobCount: try database.scalarInt("SELECT COUNT(*) FROM resolve_jobs"),
                diagnosticsCount: try database.scalarInt("SELECT COUNT(*) FROM timeline_snapshot_diagnostics")
            )
        }
    }

    func readStateSnapshot() throws -> String? {
        try withDatabase { database in
            try database.queryStrings(
                """
                SELECT printf(
                  '%s|%s|%s|%s|%s',
                  IFNULL(marker_event_id, ''),
                  IFNULL(marker_sort_at, ''),
                  IFNULL(scroll_anchor_item_key, ''),
                  IFNULL(scroll_anchor_event_id, ''),
                  IFNULL(updated_at_ms, '')
                )
                FROM feed_read_state
                WHERE account_id = 1 AND feed_id = 10
                """,
                column: 0
            ).first
        }
    }

    private func seedEventIfNeeded(_ id: String, pubkey: String, database: SQLiteFixtureConnection) throws {
        try database.exec("""
        INSERT OR IGNORE INTO events (
          id, pubkey, created_at, kind, content, tags_json, sig, raw_json,
          is_valid, first_seen_at_ms, last_seen_at_ms, seen_count
        ) VALUES (
          '\(id)', '\(pubkey)', 1, 1, '', '[]', '\(String(repeating: "1", count: 128))',
          '{}', 1, 1, 1, 1
        );
        """)
    }

    private func withDatabase<T>(
        flags: Int32 = SQLITE_OPEN_READWRITE,
        _ operation: (SQLiteFixtureConnection) throws -> T
    ) throws -> T {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw SQLiteFixtureError("open failed")
        }
        defer { sqlite3_close(handle) }
        return try operation(SQLiteFixtureConnection(handle: handle))
    }

    static func storeSourceURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            let candidate = directory
                .appendingPathComponent("Sources/AstrenzaCore/TimelineRepositoryStore.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw SQLiteFixtureError("store source not found")
    }

    private static func officialDDL() throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            let candidate = directory
                .appendingPathComponent("Documents/Specifications/astrenza_local_db_schema_v0_2.sql")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate)
            }
            directory.deleteLastPathComponent()
        }
        throw SQLiteFixtureError("official DDL not found")
    }

    private static func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func sqlNullable(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(sql(value))'"
    }

    private static func intNullable(_ value: Int64?) -> String {
        guard let value else { return "NULL" }
        return "\(value)"
    }
}

private struct FixtureFeedItem {
    var feedID: Int64
    var itemKey: String
    var sourceEventID: String
    var subjectEventID: String?
    var reason: String
    var actorPubkey: String?
    var sortAt: Int64
    var tieBreakID: String
    var hiddenReason: String?
    var collapsed: Bool
    var pendingNew: Bool
}

private struct FixtureAuditCounts: Equatable {
    var feedItemCount: Int
    var pendingNewCount: Int
    var readStateCount: Int
    var resolveJobCount: Int
    var diagnosticsCount: Int
}

private struct SQLiteFixtureConnection {
    let handle: OpaquePointer

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "sqlite exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteFixtureError(message)
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        try Int(queryInt64(sql))
    }

    func queryStrings(_ sql: String, column: Int32) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteFixtureError("prepare failed")
        }
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, column) {
                values.append(String(cString: text))
            }
        }
        return values
    }

    private func queryInt64(_ sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteFixtureError("prepare failed")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteFixtureError("no scalar row")
        }
        return sqlite3_column_int64(statement, 0)
    }
}

private struct SQLiteFixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func eventID(_ seed: Character) -> String {
    String(repeating: String(seed), count: 64)
}

private func pubkey(_ seed: Character) -> String {
    String(repeating: String(seed), count: 64)
}

private func assertSendable<T: Sendable>(_: T.Type) {}
