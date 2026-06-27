import Foundation
import SQLite3
import Testing
@testable import Astrenza

@Suite("TimelineRepositoryDBAdapterReadOnly")
struct TimelineRepositoryDBAdapterReadOnlyTests {
    private let adapter = TimelineRepositoryDBAdapter(configuration: .testDefault)

    @Test("fixture DB feed_items produce deterministic initial window")
    func fixtureDBFeedItemsProduceDeterministicInitialWindow() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:older-b", sourceEventID: "older-b", sortAt: 10, tieBreakID: "b"),
            feedItem("note:newest", sourceEventID: "newest", sortAt: 20, tieBreakID: "z"),
            feedItem("note:older-a", sourceEventID: "older-a", sortAt: 10, tieBreakID: "a")
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:newest", "note:older-a", "note:older-b"])
        #expect(output.initialWindow.diagnostics.fallbackReason == .noReadStateUsedNewest)
        #expect(!output.initialWindow.diagnostics.readMarkerChanged)
        #expect(!output.initialWindow.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresExternalDBWork)
        #expect(output.diagnostics.performedLocalDBRead)
    }

    @Test("hidden_reason rows are excluded by default")
    func hiddenReasonRowsAreExcludedByDefault() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:visible", sourceEventID: "visible", sortAt: 20),
            feedItem("note:hidden", sourceEventID: "hidden", sortAt: 30, hiddenReason: "muted")
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:visible"])
        #expect(output.initialWindow.diagnostics.excludedHiddenCount == 1)
        #expect(output.issues.isEmpty)
    }

    @Test("pending_new rows are excluded by default")
    func pendingNewRowsAreExcludedByDefault() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:pending", sourceEventID: "pending", sortAt: 30, pendingNew: true),
            feedItem("note:visible", sourceEventID: "visible", sortAt: 20)
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:visible"])
        #expect(output.initialWindow.diagnostics.excludedPendingNewCount == 1)
        #expect(output.initialWindow.diagnostics.pendingNewIncludedCount == 0)
    }

    @Test("explicit user action policy includes pending_new through boundary delegation")
    func explicitUserActionPolicyIncludesPendingNewThroughBoundaryDelegation() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:pending", sourceEventID: "pending", sortAt: 30, pendingNew: true),
            feedItem("note:visible", sourceEventID: "visible", sortAt: 20)
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .explicitUserPendingNew(itemKeys: ["note:pending"], maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:pending", "note:visible"])
        #expect(output.initialWindow.diagnostics.pendingNewIncludedCount == 1)
        #expect(output.initialWindow.diagnostics.pendingNewInclusionReason == .explicitUserAction)
        #expect(!output.initialWindow.diagnostics.readMarkerChanged)
    }

    @Test("collapsed and missing-target fallback rows remain represented")
    func collapsedAndMissingTargetFallbackRowsRemainRepresented() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:collapsed", sourceEventID: "collapsed", sortAt: 30, collapsed: true),
            feedItem(
                "repost:missing-target",
                sourceEventID: "repost-source",
                subjectEventID: "missing-target",
                reason: "repost",
                sortAt: 20
            )
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        let fallbackRow = try #require(output.initialWindow.visibleRows.first { $0.itemKey == "repost:missing-target" })
        #expect(output.initialWindow.visibleItemKeys == ["note:collapsed", "repost:missing-target"])
        #expect(output.initialWindow.diagnostics.collapsedCount == 1)
        #expect(fallbackRow.isMissingTargetFallbackCapable)
    }

    @Test("feed_read_state anchor item restores around anchor")
    func feedReadStateAnchorItemRestoresAroundAnchor() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems(windowRows())
        try database.seedReadState(readState(scrollAnchorItemKey: "note:anchor"))

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 3)
        )

        #expect(output.initialWindow.anchorItemKey == "note:anchor")
        #expect(output.initialWindow.anchorSource == .scrollAnchor)
        #expect(output.initialWindow.diagnostics.fallbackReason == .anchorFound)
        #expect(output.initialWindow.visibleItemKeys == ["note:newer", "note:anchor", "note:older"])
    }

    @Test("missing anchor falls back to marker event")
    func missingAnchorFallsBackToMarkerEvent() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems(windowRows())
        try database.seedReadState(readState(
            markerEventID: "older",
            scrollAnchorItemKey: "note:missing-anchor",
            scrollAnchorEventID: "missing-anchor-event"
        ))

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 3)
        )

        #expect(output.initialWindow.anchorItemKey == "note:older")
        #expect(output.initialWindow.anchorSource == .readMarker)
        #expect(output.initialWindow.diagnostics.fallbackReason == .missingAnchorUsedMarker)
        #expect(output.issues.contains { $0.kind == .missingAnchor && $0.itemKey == "note:missing-anchor" })
    }

    @Test("marker_sort_at fallback chooses nearest represented row")
    func markerSortAtFallbackChoosesNearestRepresentedRow() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems(windowRows())
        try database.seedReadState(readState(markerSortAt: 19))

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 3)
        )

        #expect(output.initialWindow.anchorItemKey == "note:anchor")
        #expect(output.initialWindow.anchorSource == .readMarker)
        #expect(output.initialWindow.diagnostics.fallbackReason == .markerSortFound)
    }

    @Test("no read state falls back to newest and empty feed returns empty fallback")
    func noReadStateFallsBackToNewestAndEmptyFeedReturnsEmptyFallback() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems(windowRows())
        let emptyDatabase = try TimelineRepositoryDBFixtureDatabase()

        let newestOutput = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 3)
        )
        let emptyOutput = try adapter.initialWindow(
            databasePath: emptyDatabase.path,
            policy: .initialRestore(maxVisibleCount: 3)
        )

        #expect(newestOutput.initialWindow.anchorItemKey == "note:newest")
        #expect(newestOutput.initialWindow.diagnostics.fallbackReason == .noReadStateUsedNewest)
        #expect(emptyOutput.initialWindow.visibleRows.isEmpty)
        #expect(emptyOutput.initialWindow.anchorSource == .none)
        #expect(emptyOutput.initialWindow.diagnostics.fallbackReason == .noVisibleRows)
    }

    @Test("invalid persisted reason returns typed issue")
    func invalidPersistedReasonReturnsTypedIssue() throws {
        let database = try TimelineRepositoryDBFixtureDatabase(allowInvalidFixtureRows: true)
        try database.seedFeedItems([
            feedItem("note:bad-reason", sourceEventID: "bad-reason", reason: "unknown", sortAt: 20),
            feedItem("note:valid", sourceEventID: "valid", sortAt: 10)
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:valid"])
        #expect(output.issues.contains { issue in
            issue.kind == .invalidPersistedFeedItemReason
                && issue.itemKey == "note:bad-reason"
                && issue.rawValue == "unknown"
        })
        #expect(output.diagnostics.invalidPersistenceRowCount == 1)
    }

    @Test("invalid item_key returns typed issue")
    func invalidItemKeyReturnsTypedIssue() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("   ", sourceEventID: "invalid-item", sortAt: 20),
            feedItem("note:valid", sourceEventID: "valid", sortAt: 10)
        ])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.initialWindow.visibleItemKeys == ["note:valid"])
        #expect(output.issues.contains { issue in
            issue.kind == .invalidPersistedItemKey
                && issue.itemKey == "   "
                && issue.eventID == EventID(hex: "invalid-item")
        })
    }

    @Test("adapter does not mutate read marker pending rows resolve jobs or diagnostics")
    func adapterDoesNotMutateReadMarkerPendingRowsResolveJobsOrDiagnostics() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([
            feedItem("note:pending", sourceEventID: "pending", sortAt: 30, pendingNew: true),
            feedItem("note:visible", sourceEventID: "visible", sortAt: 20)
        ])
        try database.seedReadState(readState(markerEventID: "visible", markerSortAt: 20))

        let before = try database.auditCounts()
        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )
        let after = try database.auditCounts()

        #expect(before == after)
        #expect(!output.initialWindow.diagnostics.readMarkerChanged)
        #expect(!output.diagnostics.readMarkerChanged)
        #expect(output.diagnostics.writeAttemptCount == 0)
        #expect(output.diagnostics.resolveJobWriteCount == 0)
        #expect(output.diagnostics.diagnosticsWriteCount == 0)
    }

    @Test("adapter diagnostics distinguish local DB read from network or external DB work")
    func adapterDiagnosticsDistinguishLocalDBReadFromNetworkOrExternalDBWork() throws {
        let database = try TimelineRepositoryDBFixtureDatabase()
        try database.seedFeedItems([feedItem("note:visible", sourceEventID: "visible", sortAt: 20)])

        let output = try adapter.initialWindow(
            databasePath: database.path,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(output.diagnostics.performedLocalDBRead)
        #expect(!output.diagnostics.requiresNetworkWork)
        #expect(!output.diagnostics.requiresExternalDBWork)
        #expect(!output.initialWindow.diagnostics.requiresNetworkWork)
        #expect(!output.initialWindow.diagnostics.requiresDBWork)
    }

    @Test("adapter models are Codable Equatable and Sendable")
    func adapterModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineRepositoryDBAdapterConfiguration.self)
        assertSendable(TimelineRepositoryDBAdapterIssue.self)
        assertSendable(TimelineRepositoryDBAdapterDiagnostics.self)
        assertSendable(TimelineRepositoryDBAdapterOutput.self)

        let issue = TimelineRepositoryDBAdapterIssue(
            kind: .invalidPersistedFeedItemReason,
            itemKey: "note:bad",
            eventID: EventID(hex: "bad"),
            rawValue: "unknown"
        )
        let diagnostics = TimelineRepositoryDBAdapterDiagnostics(
            feedItemRowCount: 1,
            readStatePresent: true,
            invalidPersistenceRowCount: 1,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresExternalDBWork: false,
            performedLocalDBRead: true,
            writeAttemptCount: 0,
            resolveJobWriteCount: 0,
            diagnosticsWriteCount: 0
        )

        try assertCodableRoundTrip(TimelineRepositoryDBAdapterConfiguration.testDefault)
        try assertCodableRoundTrip(issue)
        try assertCodableRoundTrip(diagnostics)
    }

    private func windowRows() -> [TimelineRepositoryDBFixtureFeedItem] {
        [
            feedItem("note:newest", sourceEventID: "newest", sortAt: 30, tieBreakID: "newest"),
            feedItem("note:newer", sourceEventID: "newer", sortAt: 25, tieBreakID: "newer"),
            feedItem("note:anchor", sourceEventID: "anchor", sortAt: 20, tieBreakID: "anchor"),
            feedItem("note:older", sourceEventID: "older", sortAt: 10, tieBreakID: "older")
        ]
    }

    private func feedItem(
        _ itemKey: String,
        sourceEventID: String,
        subjectEventID: String? = nil,
        reason: String = "author",
        actorPubkey: String? = "pubkey",
        sortAt: Int64,
        tieBreakID: String? = nil,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false
    ) -> TimelineRepositoryDBFixtureFeedItem {
        TimelineRepositoryDBFixtureFeedItem(
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: subjectEventID,
            reason: reason,
            actorPubkey: actorPubkey,
            sortAt: sortAt,
            tieBreakID: tieBreakID ?? sourceEventID,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew
        )
    }

    private func readState(
        markerEventID: String? = nil,
        markerSortAt: Int64? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: String? = nil
    ) -> TimelineRepositoryDBFixtureReadState {
        TimelineRepositoryDBFixtureReadState(
            markerEventID: markerEventID,
            markerSortAt: markerSortAt,
            scrollAnchorItemKey: scrollAnchorItemKey,
            scrollAnchorEventID: scrollAnchorEventID
        )
    }

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

    private func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)

        #expect(decoded == value)
    }
}

private struct TimelineRepositoryDBAdapterConfiguration: Equatable, Codable, Sendable {
    var accountID: AccountID
    var databaseAccountID: Int64
    var feedID: FeedID
    var timelineKey: TimelineKey

    static let testDefault = TimelineRepositoryDBAdapterConfiguration(
        accountID: .debug,
        databaseAccountID: 1,
        feedID: .debugHome,
        timelineKey: .home
    )
}

private struct TimelineRepositoryDBAdapterIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case invalidPersistedFeedItemReason
        case invalidPersistedItemKey
        case invalidPersistedSortKey
        case invalidReadStateAnchorShape
        case pendingNewVisibleWithoutExplicitUserAction
        case hiddenRowVisibleWithoutPolicy
        case readMarkerAdvanceAttempted
        case duplicateItemKey
        case missingAnchor
        case missingScrollAnchorEvent
        case missingMarker
        case missingLastVisible
        case timelineEntriesOnlyAnchorDerivationAttempted
    }

    var kind: Kind
    var itemKey: String?
    var eventID: EventID?
    var rawValue: String?
}

private struct TimelineRepositoryDBAdapterDiagnostics: Equatable, Codable, Sendable {
    var feedItemRowCount: Int
    var readStatePresent: Bool
    var invalidPersistenceRowCount: Int
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresExternalDBWork: Bool
    var performedLocalDBRead: Bool
    var writeAttemptCount: Int
    var resolveJobWriteCount: Int
    var diagnosticsWriteCount: Int
}

private struct TimelineRepositoryDBAdapterOutput: Equatable, Codable, Sendable {
    var initialWindow: TimelineInitialWindowDraft
    var issues: [TimelineRepositoryDBAdapterIssue]
    var diagnostics: TimelineRepositoryDBAdapterDiagnostics
}

private struct TimelineRepositoryDBAdapter: Sendable {
    var configuration: TimelineRepositoryDBAdapterConfiguration

    func initialWindow(
        databasePath: String,
        policy: TimelineVisibleWindowPolicy
    ) throws -> TimelineRepositoryDBAdapterOutput {
        let database = try TimelineRepositorySQLiteDatabase(
            path: databasePath,
            flags: SQLITE_OPEN_READONLY
        )
        let rawRows = try readFeedItems(from: database)
        let readStateMapping = try readState(from: database)
        var issues: [TimelineRepositoryDBAdapterIssue] = []
        let rows = rawRows.compactMap { row in
            mapFeedItem(row, issues: &issues)
        }

        if let issue = readStateMapping.issue {
            issues.append(issue)
        }

        let initialWindow = FixtureTimelineRepositoryBoundary().initialWindow(
            TimelineInitialWindowRequest(
                feedID: configuration.feedID,
                rows: rows,
                readState: readStateMapping.readState,
                policy: policy
            )
        )
        issues.append(contentsOf: initialWindow.issues.map(TimelineRepositoryDBAdapterIssue.init))

        return TimelineRepositoryDBAdapterOutput(
            initialWindow: initialWindow,
            issues: issues,
            diagnostics: TimelineRepositoryDBAdapterDiagnostics(
                feedItemRowCount: rawRows.count,
                readStatePresent: readStateMapping.readState != nil,
                invalidPersistenceRowCount: issues.filter(\.isInvalidPersistenceIssue).count,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresExternalDBWork: false,
                performedLocalDBRead: true,
                writeAttemptCount: 0,
                resolveJobWriteCount: 0,
                diagnosticsWriteCount: 0
            )
        )
    }

    private func readFeedItems(
        from database: TimelineRepositorySQLiteDatabase
    ) throws -> [TimelineRepositoryDBFeedItemRow] {
        try database.query(
            """
            SELECT item_key, source_event_id, subject_event_id, reason, actor_pubkey,
                   sort_at, tie_break_id, hidden_reason, collapsed, pending_new
            FROM feed_items
            WHERE feed_id = ?
            ORDER BY sort_at DESC, tie_break_id ASC
            """,
            bindings: [.int64(configuration.feedID.rawValue)]
        ) { row in
            TimelineRepositoryDBFeedItemRow(
                itemKey: row.string(0) ?? "",
                sourceEventID: row.string(1) ?? "",
                subjectEventID: row.string(2),
                reason: row.string(3) ?? "",
                actorPubkey: row.string(4),
                sortAt: row.int64(5),
                tieBreakID: row.string(6) ?? "",
                hiddenReason: row.string(7),
                collapsed: row.bool(8),
                pendingNew: row.bool(9)
            )
        }
    }

    private func readState(
        from database: TimelineRepositorySQLiteDatabase
    ) throws -> (readState: TimelineReadStateDraft?, issue: TimelineRepositoryDBAdapterIssue?) {
        let rows = try database.query(
            """
            SELECT marker_sort_at, marker_event_id,
                   scroll_anchor_item_key, scroll_anchor_event_id,
                   scroll_anchor_sort_at, scroll_anchor_tie_break_id,
                   scroll_anchor_offset_px,
                   viewport_height_px, viewport_width_px,
                   content_inset_top_px, content_inset_bottom_px,
                   last_visible_top_id, last_visible_bottom_id,
                   restore_fallback_reason, last_viewed_at_ms
            FROM feed_read_state
            WHERE account_id = ?
              AND feed_id = ?
            LIMIT 1
            """,
            bindings: [.int64(configuration.databaseAccountID), .int64(configuration.feedID.rawValue)]
        ) { row in
            TimelineRepositoryDBReadStateRow(
                markerSortAt: row.int64(0),
                markerEventID: row.string(1),
                scrollAnchorItemKey: row.string(2),
                scrollAnchorEventID: row.string(3),
                scrollAnchorSortAt: row.int64(4),
                scrollAnchorTieBreakID: row.string(5),
                scrollAnchorOffsetPX: row.int(6),
                viewportHeightPX: row.int(7),
                viewportWidthPX: row.int(8),
                contentInsetTopPX: row.int(9),
                contentInsetBottomPX: row.int(10),
                lastVisibleTopItemKey: row.string(11),
                lastVisibleBottomItemKey: row.string(12),
                restoreFallbackReason: row.string(13),
                savedAtMS: row.int64(14)
            )
        }

        guard let row = rows.first else {
            return (nil, nil)
        }

        let invalidAnchorShape = row.scrollAnchorItemKey != nil
            && (row.scrollAnchorEventID == nil
                || row.scrollAnchorSortAt == nil
                || row.scrollAnchorTieBreakID == nil)
        let issue = invalidAnchorShape
            ? TimelineRepositoryDBAdapterIssue(
                kind: .invalidReadStateAnchorShape,
                itemKey: row.scrollAnchorItemKey,
                eventID: row.scrollAnchorEventID.map(EventID.init(hex:)),
                rawValue: nil
            )
            : nil

        return (
            TimelineReadStateDraft(
                accountID: configuration.accountID,
                feedID: configuration.feedID,
                timelineKey: configuration.timelineKey,
                scrollAnchorItemKey: invalidAnchorShape ? nil : row.scrollAnchorItemKey,
                scrollAnchorEventID: invalidAnchorShape ? nil : row.scrollAnchorEventID.map(EventID.init(hex:)),
                scrollAnchorSortAt: invalidAnchorShape ? nil : row.scrollAnchorSortAt,
                scrollAnchorTieBreakID: invalidAnchorShape ? nil : row.scrollAnchorTieBreakID,
                scrollAnchorOffsetPX: row.scrollAnchorOffsetPX,
                viewportHeightPX: row.viewportHeightPX,
                viewportWidthPX: row.viewportWidthPX,
                contentInsetTopPX: row.contentInsetTopPX,
                contentInsetBottomPX: row.contentInsetBottomPX,
                markerEventID: row.markerEventID.map(EventID.init(hex:)),
                markerSortAt: row.markerSortAt,
                lastVisibleTopItemKey: row.lastVisibleTopItemKey,
                lastVisibleBottomItemKey: row.lastVisibleBottomItemKey,
                restoreFallbackReason: row.restoreFallbackReason
                    .flatMap(TimelineRepositoryBoundaryFallbackReason.init(rawValue:)),
                savedAtMS: row.savedAtMS,
                schemaVersion: 2
            ),
            issue
        )
    }

    private func mapFeedItem(
        _ row: TimelineRepositoryDBFeedItemRow,
        issues: inout [TimelineRepositoryDBAdapterIssue]
    ) -> TimelineRepositoryFeedItemDraftRow? {
        let trimmedItemKey = row.itemKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedItemKey.isEmpty else {
            issues.append(TimelineRepositoryDBAdapterIssue(
                kind: .invalidPersistedItemKey,
                itemKey: row.itemKey,
                eventID: EventID(hex: row.sourceEventID),
                rawValue: nil
            ))
            return nil
        }

        guard let sortAt = row.sortAt else {
            issues.append(TimelineRepositoryDBAdapterIssue(
                kind: .invalidPersistedSortKey,
                itemKey: row.itemKey,
                eventID: EventID(hex: row.sourceEventID),
                rawValue: nil
            ))
            return nil
        }

        guard let reason = TimelineRepositoryFeedItemReason(rawValue: row.reason) else {
            issues.append(TimelineRepositoryDBAdapterIssue(
                kind: .invalidPersistedFeedItemReason,
                itemKey: row.itemKey,
                eventID: EventID(hex: row.sourceEventID),
                rawValue: row.reason
            ))
            return nil
        }

        return TimelineRepositoryFeedItemDraftRow(
            itemKey: trimmedItemKey,
            sourceEventID: EventID(hex: row.sourceEventID),
            subjectEventID: row.subjectEventID.map(EventID.init(hex:)),
            reason: reason,
            actorPubkey: row.actorPubkey,
            sortAt: sortAt,
            tieBreakID: row.tieBreakID,
            hiddenReason: row.hiddenReason,
            collapsed: row.collapsed,
            pendingNew: row.pendingNew,
            isMissingTargetFallbackCapable: isMissingTargetFallbackCapable(
                reason: reason,
                subjectEventID: row.subjectEventID
            )
        )
    }

    private func isMissingTargetFallbackCapable(
        reason: TimelineRepositoryFeedItemReason,
        subjectEventID: String?
    ) -> Bool {
        guard subjectEventID != nil else {
            return false
        }
        switch reason {
        case .repost, .quote:
            return true
        case .author, .reply, .mention, .reaction, .zap, .follow, .manual:
            return false
        }
    }
}

private struct TimelineRepositoryDBFeedItemRow: Equatable, Sendable {
    var itemKey: String
    var sourceEventID: String
    var subjectEventID: String?
    var reason: String
    var actorPubkey: String?
    var sortAt: Int64?
    var tieBreakID: String
    var hiddenReason: String?
    var collapsed: Bool
    var pendingNew: Bool
}

private struct TimelineRepositoryDBReadStateRow: Equatable, Sendable {
    var markerSortAt: Int64?
    var markerEventID: String?
    var scrollAnchorItemKey: String?
    var scrollAnchorEventID: String?
    var scrollAnchorSortAt: Int64?
    var scrollAnchorTieBreakID: String?
    var scrollAnchorOffsetPX: Int?
    var viewportHeightPX: Int?
    var viewportWidthPX: Int?
    var contentInsetTopPX: Int?
    var contentInsetBottomPX: Int?
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?
    var restoreFallbackReason: String?
    var savedAtMS: Int64?
}

private extension TimelineRepositoryDBAdapterIssue {
    init(_ issue: TimelineRepositoryBoundaryIssue) {
        self.init(
            kind: Kind(issue.kind),
            itemKey: issue.itemKey,
            eventID: issue.eventID,
            rawValue: nil
        )
    }

    var isInvalidPersistenceIssue: Bool {
        switch kind {
        case .invalidPersistedFeedItemReason,
             .invalidPersistedItemKey,
             .invalidPersistedSortKey,
             .invalidReadStateAnchorShape:
            return true
        case .pendingNewVisibleWithoutExplicitUserAction,
             .hiddenRowVisibleWithoutPolicy,
             .readMarkerAdvanceAttempted,
             .duplicateItemKey,
             .missingAnchor,
             .missingScrollAnchorEvent,
             .missingMarker,
             .missingLastVisible,
             .timelineEntriesOnlyAnchorDerivationAttempted:
            return false
        }
    }
}

private extension TimelineRepositoryDBAdapterIssue.Kind {
    init(_ kind: TimelineRepositoryBoundaryIssue.Kind) {
        switch kind {
        case .duplicateItemKey:
            self = .duplicateItemKey
        case .missingAnchor:
            self = .missingAnchor
        case .missingScrollAnchorEvent:
            self = .missingScrollAnchorEvent
        case .missingMarker:
            self = .missingMarker
        case .missingLastVisible:
            self = .missingLastVisible
        case .invalidSortKey:
            self = .invalidPersistedSortKey
        case .invalidItemKey:
            self = .invalidPersistedItemKey
        case .pendingNewIncludedWithoutExplicitUserAction:
            self = .pendingNewVisibleWithoutExplicitUserAction
        case .hiddenRowIncludedByMistake:
            self = .hiddenRowVisibleWithoutPolicy
        case .timelineEntriesOnlyAnchorDerivationAttempted:
            self = .timelineEntriesOnlyAnchorDerivationAttempted
        case .readMarkerAdvanceAttempted:
            self = .readMarkerAdvanceAttempted
        }
    }
}

private struct TimelineRepositoryDBFixtureFeedItem: Equatable, Sendable {
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

private struct TimelineRepositoryDBFixtureReadState: Equatable, Sendable {
    var markerEventID: String?
    var markerSortAt: Int64?
    var scrollAnchorItemKey: String?
    var scrollAnchorEventID: String?
    var scrollAnchorSortAt: Int64?
    var scrollAnchorTieBreakID: String?
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?

    init(
        markerEventID: String? = nil,
        markerSortAt: Int64? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: String? = nil,
        scrollAnchorSortAt: Int64? = nil,
        scrollAnchorTieBreakID: String? = nil,
        lastVisibleTopItemKey: String? = nil,
        lastVisibleBottomItemKey: String? = nil
    ) {
        self.markerEventID = markerEventID
        self.markerSortAt = markerSortAt
        self.scrollAnchorItemKey = scrollAnchorItemKey
        self.scrollAnchorEventID = scrollAnchorEventID
        self.scrollAnchorSortAt = scrollAnchorSortAt
        self.scrollAnchorTieBreakID = scrollAnchorTieBreakID
        self.lastVisibleTopItemKey = lastVisibleTopItemKey
        self.lastVisibleBottomItemKey = lastVisibleBottomItemKey
    }
}

private struct TimelineRepositoryDBFixtureAuditCounts: Equatable, Sendable {
    var feedItemCount: Int
    var pendingNewCount: Int
    var resolveJobCount: Int
    var diagnosticsCount: Int
    var markerEventID: String?
    var markerSortAt: Int64?
}

private final class TimelineRepositoryDBFixtureDatabase {
    let path: String

    private let directoryURL: URL
    private let allowInvalidFixtureRows: Bool
    private let database: TimelineRepositorySQLiteDatabase

    init(allowInvalidFixtureRows: Bool = false) throws {
        self.allowInvalidFixtureRows = allowInvalidFixtureRows
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AstrenzaTimelineRepositoryDBAdapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        path = directoryURL.appendingPathComponent("fixture.sqlite").path
        database = try TimelineRepositorySQLiteDatabase(
            path: path,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        )
        try installSchema()
        try seedAccountAndFeed()
    }

    deinit {
        try? database.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func seedFeedItems(_ items: [TimelineRepositoryDBFixtureFeedItem]) throws {
        if allowInvalidFixtureRows {
            try database.execute("PRAGMA ignore_check_constraints = ON")
        }
        defer {
            if allowInvalidFixtureRows {
                try? database.execute("PRAGMA ignore_check_constraints = OFF")
            }
        }

        for item in items {
            try insertEvent(id: item.sourceEventID)
            if let subjectEventID = item.subjectEventID {
                try insertEvent(id: subjectEventID)
            }
            try database.execute(
                """
                INSERT INTO feed_items (
                  feed_id, item_key, source_event_id, subject_event_id, reason,
                  actor_pubkey, sort_at, tie_break_id, hidden_reason, collapsed,
                  pending_new, inserted_at_ms, updated_at_ms
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue),
                    .text(item.itemKey),
                    .text(item.sourceEventID),
                    item.subjectEventID.map(SQLiteBinding.text) ?? .null,
                    .text(item.reason),
                    item.actorPubkey.map(SQLiteBinding.text) ?? .null,
                    .int64(item.sortAt),
                    .text(item.tieBreakID),
                    item.hiddenReason.map(SQLiteBinding.text) ?? .null,
                    .int(item.collapsed ? 1 : 0),
                    .int(item.pendingNew ? 1 : 0),
                    .int64(1_780_000_000_000),
                    .int64(1_780_000_000_001)
                ]
            )
        }
    }

    func seedReadState(_ readState: TimelineRepositoryDBFixtureReadState) throws {
        let resolvedAnchor = try resolvedAnchorFields(for: readState)
        try database.execute(
            """
            INSERT INTO feed_read_state (
              account_id, feed_id, marker_sort_at, marker_event_id,
              scroll_anchor_item_key, scroll_anchor_event_id,
              scroll_anchor_sort_at, scroll_anchor_tie_break_id,
              scroll_anchor_offset_px, viewport_height_px, viewport_width_px,
              content_inset_top_px, content_inset_bottom_px,
              last_visible_top_id, last_visible_bottom_id,
              restore_fallback_reason, client_state_json,
              last_viewed_at_ms, updated_at_ms
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.databaseAccountID),
                .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue),
                readState.markerSortAt.map(SQLiteBinding.int64) ?? .null,
                readState.markerEventID.map(SQLiteBinding.text) ?? .null,
                readState.scrollAnchorItemKey.map(SQLiteBinding.text) ?? .null,
                resolvedAnchor.eventID.map(SQLiteBinding.text) ?? .null,
                resolvedAnchor.sortAt.map(SQLiteBinding.int64) ?? .null,
                resolvedAnchor.tieBreakID.map(SQLiteBinding.text) ?? .null,
                .int(0),
                .int(844),
                .int(390),
                .int(8),
                .int(16),
                readState.lastVisibleTopItemKey.map(SQLiteBinding.text) ?? .null,
                readState.lastVisibleBottomItemKey.map(SQLiteBinding.text) ?? .null,
                .null,
                .text("{}"),
                .int64(1_780_000_000_100),
                .int64(1_780_000_000_101)
            ]
        )
    }

    func auditCounts() throws -> TimelineRepositoryDBFixtureAuditCounts {
        TimelineRepositoryDBFixtureAuditCounts(
            feedItemCount: try database.scalarInt(
                "SELECT COUNT(*) FROM feed_items WHERE feed_id = ?",
                bindings: [.int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue)]
            ),
            pendingNewCount: try database.scalarInt(
                "SELECT COUNT(*) FROM feed_items WHERE feed_id = ? AND pending_new = 1",
                bindings: [.int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue)]
            ),
            resolveJobCount: try database.scalarInt("SELECT COUNT(*) FROM resolve_jobs"),
            diagnosticsCount: try database.scalarInt("SELECT COUNT(*) FROM timeline_snapshot_diagnostics"),
            markerEventID: try database.scalarString("SELECT marker_event_id FROM feed_read_state LIMIT 1"),
            markerSortAt: try database.scalarInt64("SELECT marker_sort_at FROM feed_read_state LIMIT 1")
        )
    }

    private func installSchema() throws {
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute(
            """
            CREATE TABLE accounts (
              id INTEGER PRIMARY KEY
            );

            CREATE TABLE events (
              id TEXT PRIMARY KEY
            );

            CREATE TABLE feeds (
              id INTEGER PRIMARY KEY,
              account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
              type TEXT NOT NULL CHECK (type IN ('home','notifications','profile','list','hashtag','search','thread','global','relay')),
              params_json TEXT NOT NULL DEFAULT '{}',
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              UNIQUE (account_id, type, params_json)
            );

            CREATE TABLE feed_items (
              feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
              item_key TEXT NOT NULL,
              source_event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
              subject_event_id TEXT,
              reason TEXT NOT NULL CHECK (reason IN ('author','reply','repost','quote','mention','reaction','zap','follow','manual')),
              actor_pubkey TEXT,
              sort_at INTEGER NOT NULL,
              tie_break_id TEXT NOT NULL,
              hidden_reason TEXT,
              collapsed INTEGER NOT NULL DEFAULT 0 CHECK (collapsed IN (0,1)),
              pending_new INTEGER NOT NULL DEFAULT 0 CHECK (pending_new IN (0,1)),
              inserted_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              PRIMARY KEY (feed_id, item_key)
            ) WITHOUT ROWID;

            CREATE INDEX idx_feed_items_order
              ON feed_items(feed_id, sort_at DESC, tie_break_id ASC);
            CREATE INDEX idx_feed_items_subject
              ON feed_items(subject_event_id);
            CREATE INDEX idx_feed_items_source
              ON feed_items(source_event_id);

            CREATE TABLE feed_read_state (
              account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
              feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
              marker_sort_at INTEGER,
              marker_event_id TEXT,
              scroll_anchor_item_key TEXT,
              scroll_anchor_event_id TEXT,
              scroll_anchor_sort_at INTEGER,
              scroll_anchor_tie_break_id TEXT,
              scroll_anchor_offset_px INTEGER NOT NULL DEFAULT 0,
              viewport_height_px INTEGER,
              viewport_width_px INTEGER,
              content_inset_top_px INTEGER,
              content_inset_bottom_px INTEGER,
              last_visible_top_id TEXT,
              last_visible_bottom_id TEXT,
              restore_fallback_reason TEXT,
              client_state_json TEXT NOT NULL DEFAULT '{}',
              last_viewed_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              PRIMARY KEY (account_id, feed_id)
            ) WITHOUT ROWID;

            CREATE TABLE resolve_jobs (
              id INTEGER PRIMARY KEY,
              feed_id INTEGER REFERENCES feeds(id) ON DELETE CASCADE,
              item_key TEXT
            );

            CREATE TABLE timeline_snapshot_diagnostics (
              id INTEGER PRIMARY KEY,
              feed_id INTEGER REFERENCES feeds(id) ON DELETE CASCADE,
              read_marker_changed INTEGER NOT NULL DEFAULT 0 CHECK (read_marker_changed IN (0,1))
            );
            """
        )
    }

    private func seedAccountAndFeed() throws {
        try database.execute(
            "INSERT INTO accounts (id) VALUES (?)",
            bindings: [.int64(TimelineRepositoryDBAdapterConfiguration.testDefault.databaseAccountID)]
        )
        try database.execute(
            """
            INSERT INTO feeds (id, account_id, type, params_json, created_at_ms, updated_at_ms)
            VALUES (?, ?, 'home', '{}', ?, ?)
            """,
            bindings: [
                .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue),
                .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.databaseAccountID),
                .int64(1_780_000_000_000),
                .int64(1_780_000_000_001)
            ]
        )
    }

    private func insertEvent(id: String) throws {
        try database.execute(
            "INSERT OR IGNORE INTO events (id) VALUES (?)",
            bindings: [.text(id)]
        )
    }

    private func resolvedAnchorFields(
        for readState: TimelineRepositoryDBFixtureReadState
    ) throws -> (eventID: String?, sortAt: Int64?, tieBreakID: String?) {
        guard let itemKey = readState.scrollAnchorItemKey else {
            return (readState.scrollAnchorEventID, readState.scrollAnchorSortAt, readState.scrollAnchorTieBreakID)
        }

        let rows = try database.query(
            """
            SELECT source_event_id, sort_at, tie_break_id
            FROM feed_items
            WHERE feed_id = ?
              AND item_key = ?
            LIMIT 1
            """,
            bindings: [
                .int64(TimelineRepositoryDBAdapterConfiguration.testDefault.feedID.rawValue),
                .text(itemKey)
            ]
        ) { row in
            (
                eventID: row.string(0),
                sortAt: row.int64(1),
                tieBreakID: row.string(2)
            )
        }

        if let row = rows.first {
            return (
                readState.scrollAnchorEventID ?? row.eventID,
                readState.scrollAnchorSortAt ?? row.sortAt,
                readState.scrollAnchorTieBreakID ?? row.tieBreakID
            )
        }

        if let eventID = readState.scrollAnchorEventID {
            return (
                eventID,
                readState.scrollAnchorSortAt ?? 0,
                readState.scrollAnchorTieBreakID ?? eventID
            )
        }

        return (nil, nil, nil)
    }
}

private final class TimelineRepositorySQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String, flags: Int32) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK,
              let openedHandle = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite open error"
            if let handle {
                sqlite3_close(handle)
            }
            throw TimelineRepositorySQLiteError(message)
        }
        self.handle = openedHandle
    }

    deinit {
        try? close()
    }

    func close() throws {
        guard let handle else {
            return
        }
        self.handle = nil
        guard sqlite3_close(handle) == SQLITE_OK else {
            throw TimelineRepositorySQLiteError("SQLite close failed")
        }
    }

    func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let handle = try requiredHandle()
        if bindings.isEmpty {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw error()
            }
            return
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error()
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteBinding] = [],
        map: (SQLiteRow) throws -> T
    ) throws -> [T] {
        let handle = try requiredHandle()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw error()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var output: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                output.append(try map(SQLiteRow(statement: statement)))
            } else if result == SQLITE_DONE {
                return output
            } else {
                throw error()
            }
        }
    }

    func scalarInt(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int {
        try scalarInt64(sql, bindings: bindings).map(Int.init) ?? 0
    }

    func scalarInt64(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int64? {
        try query(sql, bindings: bindings) { row in row.int64(0) }.first ?? nil
    }

    func scalarString(_ sql: String, bindings: [SQLiteBinding] = []) throws -> String? {
        try query(sql, bindings: bindings) { row in row.string(0) }.first ?? nil
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .int(let value):
                result = sqlite3_bind_int(statement, position, Int32(value))
            case .int64(let value):
                result = sqlite3_bind_int64(statement, position, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            }
            guard result == SQLITE_OK else {
                throw error()
            }
        }
    }

    private func requiredHandle() throws -> OpaquePointer {
        guard let handle else {
            throw TimelineRepositorySQLiteError("SQLite database is closed")
        }
        return handle
    }

    private func error() -> TimelineRepositorySQLiteError {
        guard let handle else {
            return TimelineRepositorySQLiteError("SQLite database is closed")
        }
        return TimelineRepositorySQLiteError(String(cString: sqlite3_errmsg(handle)))
    }
}

private struct SQLiteRow {
    var statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    func int(_ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, index))
    }

    func int64(_ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    func bool(_ index: Int32) -> Bool {
        (int(index) ?? 0) != 0
    }
}

private enum SQLiteBinding {
    case null
    case int(Int)
    case int64(Int64)
    case text(String)
}

private struct TimelineRepositorySQLiteError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
