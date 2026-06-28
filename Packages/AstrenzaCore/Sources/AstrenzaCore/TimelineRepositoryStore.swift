import Foundation
import GRDB

public protocol TimelineRepositoryStore: Sendable {
    func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow

    func fetchReadState(
        feedID: Int64,
        databaseAccountID: Int64?
    ) async throws -> TimelineRepositoryReadStateRow?

    func fetchAnchorWindow(
        feedID: Int64,
        anchorItemKey: String,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow
}

public struct TimelineRepositoryReadRequest: Codable, Equatable, Sendable {
    public let feedID: Int64
    public let databaseAccountID: Int64?
    public let anchorItemKey: String?

    public init(
        feedID: Int64,
        databaseAccountID: Int64? = nil,
        anchorItemKey: String? = nil
    ) {
        self.feedID = feedID
        self.databaseAccountID = databaseAccountID
        self.anchorItemKey = anchorItemKey
    }
}

public struct TimelineRepositoryInitialWindow: Codable, Equatable, Sendable {
    public let feedID: Int64
    public let rows: [TimelineRepositoryFeedItemRow]
    public let readState: TimelineRepositoryReadStateRow?
    public let anchorItemKey: String?
    public let issues: [TimelineRepositoryStoreIssue]
    public let diagnostics: TimelineRepositoryStoreDiagnostics

    public init(
        feedID: Int64,
        rows: [TimelineRepositoryFeedItemRow],
        readState: TimelineRepositoryReadStateRow?,
        anchorItemKey: String?,
        issues: [TimelineRepositoryStoreIssue],
        diagnostics: TimelineRepositoryStoreDiagnostics
    ) {
        self.feedID = feedID
        self.rows = rows
        self.readState = readState
        self.anchorItemKey = anchorItemKey
        self.issues = issues
        self.diagnostics = diagnostics
    }
}

public struct TimelineRepositoryFeedItemRow: Codable, Equatable, Sendable {
    public let feedID: Int64
    public let itemKey: String
    public let sourceEventID: String
    public let subjectEventID: String?
    public let reason: TimelineRepositoryFeedItemReason
    public let actorPubkey: String?
    public let sortAt: Int64
    public let tieBreakID: String
    public let hiddenReason: String?
    public let collapsed: Bool
    public let pendingNew: Bool
    public let insertedAtMS: Int64
    public let updatedAtMS: Int64

    public init(
        feedID: Int64,
        itemKey: String,
        sourceEventID: String,
        subjectEventID: String? = nil,
        reason: TimelineRepositoryFeedItemReason,
        actorPubkey: String? = nil,
        sortAt: Int64,
        tieBreakID: String,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false,
        insertedAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.feedID = feedID
        self.itemKey = itemKey
        self.sourceEventID = sourceEventID
        self.subjectEventID = subjectEventID
        self.reason = reason
        self.actorPubkey = actorPubkey
        self.sortAt = sortAt
        self.tieBreakID = tieBreakID
        self.hiddenReason = hiddenReason
        self.collapsed = collapsed
        self.pendingNew = pendingNew
        self.insertedAtMS = insertedAtMS
        self.updatedAtMS = updatedAtMS
    }
}

public enum TimelineRepositoryFeedItemReason: String, CaseIterable, Codable, Equatable, Sendable {
    case author
    case reply
    case repost
    case quote
    case mention
    case reaction
    case zap
    case follow
    case manual
}

public struct TimelineRepositoryReadStateRow: Codable, Equatable, Sendable {
    public let databaseAccountID: Int64
    public let feedID: Int64
    public let markerSortAt: Int64?
    public let markerEventID: String?
    public let scrollAnchorItemKey: String?
    public let scrollAnchorEventID: String?
    public let scrollAnchorSortAt: Int64?
    public let scrollAnchorTieBreakID: String?
    public let scrollAnchorOffsetPX: Int?
    public let viewportHeightPX: Int?
    public let viewportWidthPX: Int?
    public let contentInsetTopPX: Int?
    public let contentInsetBottomPX: Int?
    public let lastVisibleTopID: String?
    public let lastVisibleBottomID: String?
    public let restoreFallbackReason: String?
    public let clientStateJSON: String
    public let lastViewedAtMS: Int64
    public let updatedAtMS: Int64

    public init(
        databaseAccountID: Int64,
        feedID: Int64,
        markerSortAt: Int64? = nil,
        markerEventID: String? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: String? = nil,
        scrollAnchorSortAt: Int64? = nil,
        scrollAnchorTieBreakID: String? = nil,
        scrollAnchorOffsetPX: Int? = nil,
        viewportHeightPX: Int? = nil,
        viewportWidthPX: Int? = nil,
        contentInsetTopPX: Int? = nil,
        contentInsetBottomPX: Int? = nil,
        lastVisibleTopID: String? = nil,
        lastVisibleBottomID: String? = nil,
        restoreFallbackReason: String? = nil,
        clientStateJSON: String,
        lastViewedAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.databaseAccountID = databaseAccountID
        self.feedID = feedID
        self.markerSortAt = markerSortAt
        self.markerEventID = markerEventID
        self.scrollAnchorItemKey = scrollAnchorItemKey
        self.scrollAnchorEventID = scrollAnchorEventID
        self.scrollAnchorSortAt = scrollAnchorSortAt
        self.scrollAnchorTieBreakID = scrollAnchorTieBreakID
        self.scrollAnchorOffsetPX = scrollAnchorOffsetPX
        self.viewportHeightPX = viewportHeightPX
        self.viewportWidthPX = viewportWidthPX
        self.contentInsetTopPX = contentInsetTopPX
        self.contentInsetBottomPX = contentInsetBottomPX
        self.lastVisibleTopID = lastVisibleTopID
        self.lastVisibleBottomID = lastVisibleBottomID
        self.restoreFallbackReason = restoreFallbackReason
        self.clientStateJSON = clientStateJSON
        self.lastViewedAtMS = lastViewedAtMS
        self.updatedAtMS = updatedAtMS
    }
}

public struct TimelineRepositoryStoreIssue: Codable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Equatable, Sendable {
        case missingFeed
        case missingAnchor
        case hiddenAnchor
        case pendingAnchor
        case invalidPersistedReason
        case invalidItemKey
        case invalidSortKey
        case malformedReadState
    }

    public let kind: Kind
    public let feedID: Int64?
    public let itemKey: String?

    public init(
        kind: Kind,
        feedID: Int64? = nil,
        itemKey: String? = nil
    ) {
        self.kind = kind
        self.feedID = feedID
        self.itemKey = itemKey
    }
}

public struct TimelineRepositoryStoreDiagnostics: Codable, Equatable, Sendable {
    public let totalFeedItemRowCount: Int
    public let sqlVisibleRowCount: Int
    public let excludedHiddenCount: Int
    public let excludedPendingNewCount: Int
    public let pendingNewIncludedCount: Int
    public let readStatePresent: Bool
    public let readMarkerChanged: Bool
    public let requiresNetworkWork: Bool
    public let requiresExternalMutation: Bool
    public let performedLocalDBRead: Bool
    public let resolveJobRowCount: Int
    public let diagnosticRowCount: Int

    public init(
        totalFeedItemRowCount: Int,
        sqlVisibleRowCount: Int,
        excludedHiddenCount: Int,
        excludedPendingNewCount: Int,
        pendingNewIncludedCount: Int,
        readStatePresent: Bool,
        readMarkerChanged: Bool = false,
        requiresNetworkWork: Bool = false,
        requiresExternalMutation: Bool = false,
        performedLocalDBRead: Bool = true,
        resolveJobRowCount: Int,
        diagnosticRowCount: Int
    ) {
        self.totalFeedItemRowCount = totalFeedItemRowCount
        self.sqlVisibleRowCount = sqlVisibleRowCount
        self.excludedHiddenCount = excludedHiddenCount
        self.excludedPendingNewCount = excludedPendingNewCount
        self.pendingNewIncludedCount = pendingNewIncludedCount
        self.readStatePresent = readStatePresent
        self.readMarkerChanged = readMarkerChanged
        self.requiresNetworkWork = requiresNetworkWork
        self.requiresExternalMutation = requiresExternalMutation
        self.performedLocalDBRead = performedLocalDBRead
        self.resolveJobRowCount = resolveJobRowCount
        self.diagnosticRowCount = diagnosticRowCount
    }
}

public struct TimelineRepositoryVisiblePolicy: Codable, Equatable, Sendable {
    public let maxVisibleCount: Int
    public let includePendingNew: Bool
    public let explicitPendingNewItemKeys: [String]

    public init(
        maxVisibleCount: Int,
        includePendingNew: Bool = false,
        explicitPendingNewItemKeys: [String] = []
    ) {
        self.maxVisibleCount = max(0, maxVisibleCount)
        self.includePendingNew = includePendingNew
        self.explicitPendingNewItemKeys = explicitPendingNewItemKeys
    }

    public static func initialRestore(maxVisibleCount: Int) -> TimelineRepositoryVisiblePolicy {
        TimelineRepositoryVisiblePolicy(maxVisibleCount: maxVisibleCount)
    }

    public static func explicitUserPendingNew(
        itemKeys: [String],
        maxVisibleCount: Int
    ) -> TimelineRepositoryVisiblePolicy {
        TimelineRepositoryVisiblePolicy(
            maxVisibleCount: maxVisibleCount,
            includePendingNew: true,
            explicitPendingNewItemKeys: itemKeys
        )
    }
}

public final class GRDBTimelineRepositoryStore: TimelineRepositoryStore, @unchecked Sendable {
    private let reader: any DatabaseReader

    public init(databaseReader: any DatabaseReader) {
        self.reader = databaseReader
    }

    public convenience init(databasePath: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let pool = try DatabasePool(path: databasePath, configuration: configuration)
        self.init(databaseReader: pool)
    }

    public func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        try await reader.read { db in
            try initialWindow(db: db, request: request, policy: policy)
        }
    }

    public func fetchReadState(
        feedID: Int64,
        databaseAccountID: Int64?
    ) async throws -> TimelineRepositoryReadStateRow? {
        try await reader.read { db in
            try readState(db: db, feedID: feedID, databaseAccountID: databaseAccountID)
        }
    }

    public func fetchAnchorWindow(
        feedID: Int64,
        anchorItemKey: String,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        try await fetchInitialWindow(
            TimelineRepositoryReadRequest(
                feedID: feedID,
                databaseAccountID: nil,
                anchorItemKey: anchorItemKey
            ),
            policy: policy
        )
    }

    private func initialWindow(
        db: Database,
        request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) throws -> TimelineRepositoryInitialWindow {
        guard try feedExists(db: db, feedID: request.feedID) else {
            return TimelineRepositoryInitialWindow(
                feedID: request.feedID,
                rows: [],
                readState: nil,
                anchorItemKey: nil,
                issues: [TimelineRepositoryStoreIssue(kind: .missingFeed, feedID: request.feedID)],
                diagnostics: try diagnostics(
                    db: db,
                    feedID: request.feedID,
                    policy: policy,
                    sqlVisibleRowCount: 0,
                    readStatePresent: false
                )
            )
        }

        var issues: [TimelineRepositoryStoreIssue] = []
        let readState = try readState(
            db: db,
            feedID: request.feedID,
            databaseAccountID: request.databaseAccountID,
            issues: &issues
        )
        let visibleRows = try visibleRows(
            db: db,
            feedID: request.feedID,
            policy: policy,
            issues: &issues
        )
        let anchorItemKey = try selectedAnchorItemKey(
            db: db,
            feedID: request.feedID,
            requestAnchorItemKey: request.anchorItemKey,
            readState: readState,
            visibleRows: visibleRows,
            policy: policy,
            issues: &issues
        )

        let rows = limitedRows(visibleRows, anchorItemKey: anchorItemKey, maxCount: policy.maxVisibleCount)
        return TimelineRepositoryInitialWindow(
            feedID: request.feedID,
            rows: rows,
            readState: readState,
            anchorItemKey: rows.contains(where: { $0.itemKey == anchorItemKey }) ? anchorItemKey : nil,
            issues: issues,
            diagnostics: try diagnostics(
                db: db,
                feedID: request.feedID,
                policy: policy,
                sqlVisibleRowCount: visibleRows.count,
                readStatePresent: readState != nil
            )
        )
    }

    private func selectedAnchorItemKey(
        db: Database,
        feedID: Int64,
        requestAnchorItemKey: String?,
        readState: TimelineRepositoryReadStateRow?,
        visibleRows: [TimelineRepositoryFeedItemRow],
        policy: TimelineRepositoryVisiblePolicy,
        issues: inout [TimelineRepositoryStoreIssue]
    ) throws -> String? {
        guard !visibleRows.isEmpty else {
            return nil
        }

        if let requestAnchorItemKey {
            if visibleRows.contains(where: { $0.itemKey == requestAnchorItemKey }) {
                return requestAnchorItemKey
            }
            if let issue = try anchorIssue(db: db, feedID: feedID, itemKey: requestAnchorItemKey, policy: policy) {
                issues.append(issue)
                guard issue.kind == .missingAnchor else {
                    return nil
                }
            }
            return fallbackAnchorItemKey(readState: readState, visibleRows: visibleRows)
        }

        if let scrollAnchorItemKey = readState?.scrollAnchorItemKey {
            if visibleRows.contains(where: { $0.itemKey == scrollAnchorItemKey }) {
                return scrollAnchorItemKey
            }
            if let issue = try anchorIssue(db: db, feedID: feedID, itemKey: scrollAnchorItemKey, policy: policy) {
                issues.append(issue)
                guard issue.kind == .missingAnchor else {
                    return nil
                }
            }
        }

        return fallbackAnchorItemKey(readState: readState, visibleRows: visibleRows)
    }

    private func fallbackAnchorItemKey(
        readState: TimelineRepositoryReadStateRow?,
        visibleRows: [TimelineRepositoryFeedItemRow]
    ) -> String? {
        guard !visibleRows.isEmpty else {
            return nil
        }

        if let scrollAnchorEventID = readState?.scrollAnchorEventID,
           let row = visibleRows.first(where: { matchesEventID($0, eventID: scrollAnchorEventID) }) {
            return row.itemKey
        }

        if let markerEventID = readState?.markerEventID,
           let row = visibleRows.first(where: { matchesEventID($0, eventID: markerEventID) }) {
            return row.itemKey
        }

        if let markerSortAt = readState?.markerSortAt,
           let row = visibleRows.min(by: { lhs, rhs in
               let lhsDistance = abs(Double(lhs.sortAt) - Double(markerSortAt))
               let rhsDistance = abs(Double(rhs.sortAt) - Double(markerSortAt))
               if lhsDistance != rhsDistance {
                   return lhsDistance < rhsDistance
               }
               return rowSort(lhs: lhs, rhs: rhs)
           }) {
            return row.itemKey
        }

        if let lastVisibleTopID = readState?.lastVisibleTopID,
           visibleRows.contains(where: { $0.itemKey == lastVisibleTopID }) {
            return lastVisibleTopID
        }

        if let lastVisibleBottomID = readState?.lastVisibleBottomID,
           visibleRows.contains(where: { $0.itemKey == lastVisibleBottomID }) {
            return lastVisibleBottomID
        }

        return visibleRows.first?.itemKey
    }

    private func matchesEventID(
        _ row: TimelineRepositoryFeedItemRow,
        eventID: String
    ) -> Bool {
        row.sourceEventID == eventID || row.subjectEventID == eventID
    }

    private func feedExists(db: Database, feedID: Int64) throws -> Bool {
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM feeds WHERE id = ?",
            arguments: [feedID]
        ) ?? 0
        return count > 0
    }

    private func visibleRows(
        db: Database,
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy,
        issues: inout [TimelineRepositoryStoreIssue]
    ) throws -> [TimelineRepositoryFeedItemRow] {
        let predicate = visiblePredicate(feedID: feedID, policy: policy)
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT feed_id, item_key, source_event_id, subject_event_id, reason,
                   actor_pubkey, sort_at, tie_break_id, hidden_reason, collapsed,
                   pending_new, inserted_at_ms, updated_at_ms
            FROM feed_items
            WHERE \(predicate.sql)
            ORDER BY sort_at DESC, tie_break_id ASC
            """,
            arguments: predicate.arguments
        )

        return rows.compactMap { row in
            decodeFeedItemRow(row, issues: &issues)
        }
    }

    private func readState(
        db: Database,
        feedID: Int64,
        databaseAccountID: Int64?
    ) throws -> TimelineRepositoryReadStateRow? {
        var ignoredIssues: [TimelineRepositoryStoreIssue] = []
        return try readState(
            db: db,
            feedID: feedID,
            databaseAccountID: databaseAccountID,
            issues: &ignoredIssues
        )
    }

    private func readState(
        db: Database,
        feedID: Int64,
        databaseAccountID: Int64?,
        issues: inout [TimelineRepositoryStoreIssue]
    ) throws -> TimelineRepositoryReadStateRow? {
        var arguments: StatementArguments = [feedID]
        var accountClause = ""
        if let databaseAccountID {
            accountClause = "AND account_id = ?"
            arguments += [databaseAccountID]
        }

        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT account_id, feed_id, marker_sort_at, marker_event_id,
                   scroll_anchor_item_key, scroll_anchor_event_id, scroll_anchor_sort_at,
                   scroll_anchor_tie_break_id, scroll_anchor_offset_px, viewport_height_px,
                   viewport_width_px, content_inset_top_px, content_inset_bottom_px,
                   last_visible_top_id, last_visible_bottom_id, restore_fallback_reason,
                   client_state_json, last_viewed_at_ms, updated_at_ms
            FROM feed_read_state
            WHERE feed_id = ? \(accountClause)
            ORDER BY account_id ASC
            LIMIT 1
            """,
            arguments: arguments
        )
        return row.map { decodeReadStateRow($0, issues: &issues) }
    }

    private func decodeFeedItemRow(
        _ row: Row,
        issues: inout [TimelineRepositoryStoreIssue]
    ) -> TimelineRepositoryFeedItemRow? {
        let feedID: Int64 = row["feed_id"]
        let itemKey: String = row["item_key"]
        guard !itemKey.isEmpty else {
            issues.append(TimelineRepositoryStoreIssue(kind: .invalidItemKey, feedID: feedID))
            return nil
        }

        let reasonValue: String = row["reason"]
        guard let reason = TimelineRepositoryFeedItemReason(rawValue: reasonValue) else {
            issues.append(TimelineRepositoryStoreIssue(kind: .invalidPersistedReason, feedID: feedID, itemKey: itemKey))
            return nil
        }

        let sortAtValue: DatabaseValue = row["sort_at"]
        guard let sortAt = Int64.fromDatabaseValue(sortAtValue) else {
            issues.append(TimelineRepositoryStoreIssue(kind: .invalidSortKey, feedID: feedID, itemKey: itemKey))
            return nil
        }

        return TimelineRepositoryFeedItemRow(
            feedID: feedID,
            itemKey: itemKey,
            sourceEventID: row["source_event_id"],
            subjectEventID: row["subject_event_id"],
            reason: reason,
            actorPubkey: row["actor_pubkey"],
            sortAt: sortAt,
            tieBreakID: row["tie_break_id"],
            hiddenReason: row["hidden_reason"],
            collapsed: (row["collapsed"] as Int64) == 1,
            pendingNew: (row["pending_new"] as Int64) == 1,
            insertedAtMS: row["inserted_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }

    private func decodeReadStateRow(
        _ row: Row,
        issues: inout [TimelineRepositoryStoreIssue]
    ) -> TimelineRepositoryReadStateRow {
        let feedID: Int64 = row["feed_id"]
        let rawScrollAnchorItemKey: String? = row["scroll_anchor_item_key"]
        let scrollAnchorItemKey = rawScrollAnchorItemKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMalformedScrollAnchorItemKey = rawScrollAnchorItemKey != nil && (scrollAnchorItemKey?.isEmpty ?? true)
        if hasMalformedScrollAnchorItemKey {
            issues.append(TimelineRepositoryStoreIssue(kind: .malformedReadState, feedID: feedID))
        }

        return TimelineRepositoryReadStateRow(
            databaseAccountID: row["account_id"],
            feedID: feedID,
            markerSortAt: row["marker_sort_at"],
            markerEventID: row["marker_event_id"],
            scrollAnchorItemKey: hasMalformedScrollAnchorItemKey ? nil : rawScrollAnchorItemKey,
            scrollAnchorEventID: hasMalformedScrollAnchorItemKey ? nil : row["scroll_anchor_event_id"],
            scrollAnchorSortAt: hasMalformedScrollAnchorItemKey ? nil : row["scroll_anchor_sort_at"],
            scrollAnchorTieBreakID: hasMalformedScrollAnchorItemKey ? nil : row["scroll_anchor_tie_break_id"],
            scrollAnchorOffsetPX: row["scroll_anchor_offset_px"],
            viewportHeightPX: row["viewport_height_px"],
            viewportWidthPX: row["viewport_width_px"],
            contentInsetTopPX: row["content_inset_top_px"],
            contentInsetBottomPX: row["content_inset_bottom_px"],
            lastVisibleTopID: row["last_visible_top_id"],
            lastVisibleBottomID: row["last_visible_bottom_id"],
            restoreFallbackReason: row["restore_fallback_reason"],
            clientStateJSON: row["client_state_json"],
            lastViewedAtMS: row["last_viewed_at_ms"],
            updatedAtMS: row["updated_at_ms"]
        )
    }

    private func diagnostics(
        db: Database,
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy,
        sqlVisibleRowCount: Int,
        readStatePresent: Bool
    ) throws -> TimelineRepositoryStoreDiagnostics {
        TimelineRepositoryStoreDiagnostics(
            totalFeedItemRowCount: try count(
                db: db,
                sql: "SELECT COUNT(*) FROM feed_items WHERE feed_id = ?",
                arguments: [feedID]
            ),
            sqlVisibleRowCount: sqlVisibleRowCount,
            excludedHiddenCount: try count(
                db: db,
                sql: "SELECT COUNT(*) FROM feed_items WHERE feed_id = ? AND hidden_reason IS NOT NULL",
                arguments: [feedID]
            ),
            excludedPendingNewCount: try excludedPendingNewCount(db: db, feedID: feedID, policy: policy),
            pendingNewIncludedCount: try pendingNewIncludedCount(db: db, feedID: feedID, policy: policy),
            readStatePresent: readStatePresent,
            resolveJobRowCount: try count(db: db, sql: "SELECT COUNT(*) FROM resolve_jobs", arguments: []),
            diagnosticRowCount: try count(db: db, sql: "SELECT COUNT(*) FROM timeline_snapshot_diagnostics", arguments: [])
        )
    }

    private func anchorIssue(
        db: Database,
        feedID: Int64,
        itemKey: String,
        policy: TimelineRepositoryVisiblePolicy
    ) throws -> TimelineRepositoryStoreIssue? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT hidden_reason, pending_new
            FROM feed_items
            WHERE feed_id = ? AND item_key = ?
            LIMIT 1
            """,
            arguments: [feedID, itemKey]
        ) else {
            return TimelineRepositoryStoreIssue(kind: .missingAnchor, feedID: feedID, itemKey: itemKey)
        }

        let hiddenReason: String? = row["hidden_reason"]
        if hiddenReason != nil {
            return TimelineRepositoryStoreIssue(kind: .hiddenAnchor, feedID: feedID, itemKey: itemKey)
        }
        let pendingNew = (row["pending_new"] as Int64) == 1
        if pendingNew && (!policy.includePendingNew || !policy.explicitPendingNewItemKeys.contains(itemKey)) {
            return TimelineRepositoryStoreIssue(kind: .pendingAnchor, feedID: feedID, itemKey: itemKey)
        }
        return nil
    }

    private func excludedPendingNewCount(
        db: Database,
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy
    ) throws -> Int {
        let predicate = pendingNewPredicate(feedID: feedID, policy: policy, included: false)
        return try count(db: db, sql: "SELECT COUNT(*) FROM feed_items WHERE \(predicate.sql)", arguments: predicate.arguments)
    }

    private func pendingNewIncludedCount(
        db: Database,
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy
    ) throws -> Int {
        let predicate = pendingNewPredicate(feedID: feedID, policy: policy, included: true)
        return try count(db: db, sql: "SELECT COUNT(*) FROM feed_items WHERE \(predicate.sql)", arguments: predicate.arguments)
    }

    private func count(
        db: Database,
        sql: String,
        arguments: StatementArguments
    ) throws -> Int {
        try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
    }

    private func limitedRows(
        _ rows: [TimelineRepositoryFeedItemRow],
        anchorItemKey: String?,
        maxCount: Int
    ) -> [TimelineRepositoryFeedItemRow] {
        guard maxCount > 0 else { return [] }
        guard rows.count > maxCount else { return rows }
        guard let anchorItemKey, let anchorIndex = rows.firstIndex(where: { $0.itemKey == anchorItemKey }) else {
            return Array(rows.prefix(maxCount))
        }

        let halfWindow = maxCount / 2
        let start = min(max(0, anchorIndex - halfWindow), max(0, rows.count - maxCount))
        return Array(rows[start..<min(rows.count, start + maxCount)])
    }

    private func rowSort(
        lhs: TimelineRepositoryFeedItemRow,
        rhs: TimelineRepositoryFeedItemRow
    ) -> Bool {
        if lhs.sortAt != rhs.sortAt {
            return lhs.sortAt > rhs.sortAt
        }
        return lhs.tieBreakID < rhs.tieBreakID
    }

    private func visiblePredicate(
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy
    ) -> (sql: String, arguments: StatementArguments) {
        var arguments: StatementArguments = [feedID]
        var clauses = [
            "feed_id = ?",
            "hidden_reason IS NULL"
        ]

        if policy.includePendingNew, !policy.explicitPendingNewItemKeys.isEmpty {
            let placeholders = Array(repeating: "?", count: policy.explicitPendingNewItemKeys.count).joined(separator: ", ")
            clauses.append("(pending_new = 0 OR item_key IN (\(placeholders)))")
            arguments += StatementArguments(policy.explicitPendingNewItemKeys)
        } else {
            clauses.append("pending_new = 0")
        }

        return (clauses.joined(separator: " AND "), arguments)
    }

    private func pendingNewPredicate(
        feedID: Int64,
        policy: TimelineRepositoryVisiblePolicy,
        included: Bool
    ) -> (sql: String, arguments: StatementArguments) {
        var arguments: StatementArguments = [feedID]
        var clauses = [
            "feed_id = ?",
            "hidden_reason IS NULL",
            "pending_new = 1"
        ]

        if policy.includePendingNew, !policy.explicitPendingNewItemKeys.isEmpty {
            let placeholders = Array(repeating: "?", count: policy.explicitPendingNewItemKeys.count).joined(separator: ", ")
            clauses.append(included ? "item_key IN (\(placeholders))" : "item_key NOT IN (\(placeholders))")
            arguments += StatementArguments(policy.explicitPendingNewItemKeys)
        } else if included {
            clauses.append("0")
        }

        return (clauses.joined(separator: " AND "), arguments)
    }
}
