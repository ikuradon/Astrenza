import AstrenzaCore
import Foundation

struct TimelineRepositoryStoreWindowComposition: Equatable, Codable, Sendable {
    var draftRows: [TimelineRepositoryFeedItemDraftRow]
    var readState: TimelineReadStateDraft?
    var initialWindow: TimelineInitialWindowDraft
    var storeIssueDiagnostics: [TimelineRepositoryStoreDiagnosticRecord]
    var compositionDiagnostics: TimelineRepositoryStoreWindowCompositionDiagnostics
    var issues: [TimelineRepositoryStoreWindowCompositionIssue]
}

struct TimelineRepositoryStoreWindowCompositionDiagnostics: Equatable, Codable, Sendable {
    var totalFeedItemRowCount: Int
    var sqlVisibleRowCount: Int
    var excludedHiddenCount: Int
    var excludedPendingNewCount: Int
    var pendingNewIncludedCount: Int
    var readStatePresent: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
    var performedLocalDBRead: Bool
    var requiresExternalMutation: Bool
    var resolveJobRowCount: Int
    var diagnosticRowCount: Int
    var storeIssueCount: Int
    var boundaryIssueCount: Int
}

struct TimelineRepositoryStoreWindowCompositionIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case unsupportedReasonMapping
        case invalidEventIDMapping
        case invalidPubkeyMapping
        case invalidFallbackReasonMapping
        case missingRequiredItemKey
    }

    var kind: Kind
    var itemKey: String?
    var field: String
    var valueLength: Int?
}

enum TimelineRepositoryStoreWindowCompositionError: Error, Equatable, Codable, Sendable {
    case issue(TimelineRepositoryStoreWindowCompositionIssue)
}

enum TimelineRepositoryStoreWindowComposer {
    static func compose(
        _ window: TimelineRepositoryInitialWindow,
        accountID: AccountID,
        timelineKey: TimelineKey,
        policy: TimelineVisibleWindowPolicy,
        boundary: any TimelineRepositoryBoundaryProtocol = FixtureTimelineRepositoryBoundary()
    ) throws -> TimelineRepositoryStoreWindowComposition {
        let draftRows = try window.rows.map(feedItemDraft)
        let readState = try window.readState.map {
            try readStateDraft(from: $0, accountID: accountID, timelineKey: timelineKey)
        }
        let storeIssueDiagnostics = TimelineRepositoryStoreDiagnosticsMapper.records(
            for: window.issues,
            diagnostics: window.diagnostics
        )
        let mappedBoundaryIssues = storeIssueDiagnostics.compactMap(\.boundaryIssue)
        var initialWindow = boundary.initialWindow(TimelineInitialWindowRequest(
            feedID: FeedID(rawValue: window.feedID),
            rows: draftRows,
            readState: readState,
            policy: policy
        ))
        initialWindow.issues.append(contentsOf: mappedBoundaryIssues)
        if let anchorItemKey = window.anchorItemKey,
           initialWindow.visibleRows.contains(where: { $0.itemKey == anchorItemKey }) {
            initialWindow.anchorItemKey = anchorItemKey
        }

        return TimelineRepositoryStoreWindowComposition(
            draftRows: draftRows,
            readState: readState,
            initialWindow: initialWindow,
            storeIssueDiagnostics: storeIssueDiagnostics,
            compositionDiagnostics: compositionDiagnostics(
                from: window.diagnostics,
                storeIssueCount: window.issues.count,
                boundaryIssueCount: initialWindow.issues.count
            ),
            issues: []
        )
    }

    private static func feedItemDraft(
        from row: TimelineRepositoryFeedItemRow
    ) throws -> TimelineRepositoryFeedItemDraftRow {
        let trimmedItemKey = row.itemKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedItemKey.isEmpty else {
            throw error(kind: .missingRequiredItemKey, itemKey: row.itemKey, field: "itemKey", value: row.itemKey)
        }
        guard isValidPersistedID(row.sourceEventID) else {
            throw error(kind: .invalidEventIDMapping, itemKey: row.itemKey, field: "sourceEventID", value: row.sourceEventID)
        }
        if let subjectEventID = row.subjectEventID {
            guard isValidPersistedID(subjectEventID) else {
                throw error(kind: .invalidEventIDMapping, itemKey: row.itemKey, field: "subjectEventID", value: subjectEventID)
            }
        }
        if let actorPubkey = row.actorPubkey {
            guard isValidPersistedID(actorPubkey) else {
                throw error(kind: .invalidPubkeyMapping, itemKey: row.itemKey, field: "actorPubkey", value: actorPubkey)
            }
        }
        guard let reason = TimelineRepositoryFeedItemReason(rawValue: row.reason.rawValue) else {
            throw error(kind: .unsupportedReasonMapping, itemKey: row.itemKey, field: "reason", value: row.reason.rawValue)
        }

        return TimelineRepositoryFeedItemDraftRow(
            itemKey: trimmedItemKey,
            sourceEventID: EventID(hex: row.sourceEventID),
            subjectEventID: row.subjectEventID.map(EventID.init(hex:)),
            reason: reason,
            actorPubkey: row.actorPubkey,
            sortAt: row.sortAt,
            tieBreakID: row.tieBreakID,
            hiddenReason: row.hiddenReason,
            collapsed: row.collapsed,
            pendingNew: row.pendingNew,
            isMissingTargetFallbackCapable: isMissingTargetFallbackCapable(row)
        )
    }

    private static func readStateDraft(
        from row: TimelineRepositoryReadStateRow,
        accountID: AccountID,
        timelineKey: TimelineKey
    ) throws -> TimelineReadStateDraft {
        try validateOptionalEventID(row.markerEventID, itemKey: nil, field: "markerEventID")
        try validateOptionalEventID(row.scrollAnchorEventID, itemKey: row.scrollAnchorItemKey, field: "scrollAnchorEventID")
        let fallbackReason = try fallbackReason(from: row.restoreFallbackReason, itemKey: row.scrollAnchorItemKey)

        return TimelineReadStateDraft(
            accountID: accountID,
            feedID: FeedID(rawValue: row.feedID),
            timelineKey: timelineKey,
            scrollAnchorItemKey: row.scrollAnchorItemKey,
            scrollAnchorEventID: row.scrollAnchorEventID.map(EventID.init(hex:)),
            scrollAnchorSortAt: row.scrollAnchorSortAt,
            scrollAnchorTieBreakID: row.scrollAnchorTieBreakID,
            scrollAnchorOffsetPX: row.scrollAnchorOffsetPX,
            viewportHeightPX: row.viewportHeightPX,
            viewportWidthPX: row.viewportWidthPX,
            contentInsetTopPX: row.contentInsetTopPX,
            contentInsetBottomPX: row.contentInsetBottomPX,
            markerEventID: row.markerEventID.map(EventID.init(hex:)),
            markerSortAt: row.markerSortAt,
            lastVisibleTopItemKey: row.lastVisibleTopID,
            lastVisibleBottomItemKey: row.lastVisibleBottomID,
            restoreFallbackReason: fallbackReason,
            savedAtMS: row.updatedAtMS,
            schemaVersion: 2
        )
    }

    private static func compositionDiagnostics(
        from diagnostics: TimelineRepositoryStoreDiagnostics,
        storeIssueCount: Int,
        boundaryIssueCount: Int
    ) -> TimelineRepositoryStoreWindowCompositionDiagnostics {
        TimelineRepositoryStoreWindowCompositionDiagnostics(
            totalFeedItemRowCount: diagnostics.totalFeedItemRowCount,
            sqlVisibleRowCount: diagnostics.sqlVisibleRowCount,
            excludedHiddenCount: diagnostics.excludedHiddenCount,
            excludedPendingNewCount: diagnostics.excludedPendingNewCount,
            pendingNewIncludedCount: diagnostics.pendingNewIncludedCount,
            readStatePresent: diagnostics.readStatePresent,
            readMarkerChanged: diagnostics.readMarkerChanged,
            requiresNetworkWork: diagnostics.requiresNetworkWork,
            requiresDBWork: diagnostics.requiresExternalMutation,
            performedLocalDBRead: diagnostics.performedLocalDBRead,
            requiresExternalMutation: diagnostics.requiresExternalMutation,
            resolveJobRowCount: diagnostics.resolveJobRowCount,
            diagnosticRowCount: diagnostics.diagnosticRowCount,
            storeIssueCount: storeIssueCount,
            boundaryIssueCount: boundaryIssueCount
        )
    }

    private static func isMissingTargetFallbackCapable(
        _ row: TimelineRepositoryFeedItemRow
    ) -> Bool {
        row.subjectEventID == nil && (row.reason == .quote || row.reason == .repost)
    }

    private static func fallbackReason(
        from rawValue: String?,
        itemKey: String?
    ) throws -> TimelineRepositoryBoundaryFallbackReason? {
        guard let rawValue else { return nil }
        guard let reason = TimelineRepositoryBoundaryFallbackReason(rawValue: rawValue) else {
            throw error(kind: .invalidFallbackReasonMapping, itemKey: itemKey, field: "restoreFallbackReason", value: rawValue)
        }
        return reason
    }

    private static func validateOptionalEventID(
        _ value: String?,
        itemKey: String?,
        field: String
    ) throws {
        guard let value else { return }
        guard isValidPersistedID(value) else {
            throw error(kind: .invalidEventIDMapping, itemKey: itemKey, field: field, value: value)
        }
    }

    private static func isValidPersistedID(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private static func error(
        kind: TimelineRepositoryStoreWindowCompositionIssue.Kind,
        itemKey: String?,
        field: String,
        value: String
    ) -> TimelineRepositoryStoreWindowCompositionError {
        TimelineRepositoryStoreWindowCompositionError.issue(TimelineRepositoryStoreWindowCompositionIssue(
            kind: kind,
            itemKey: itemKey,
            field: field,
            valueLength: value.count
        ))
    }
}
