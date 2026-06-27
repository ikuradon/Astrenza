import Foundation

struct AccountID: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let debug = AccountID(rawValue: "debug-account")
}

struct EventID: Hashable, Codable, Sendable {
    let hex: String

    init(hex: String) {
        self.hex = hex
    }
}

struct FeedID: Hashable, Codable, Sendable {
    let rawValue: Int64

    init(rawValue: Int64) {
        self.rawValue = rawValue
    }

    static let debugHome = FeedID(rawValue: 0)
}

struct TimelineKey: Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let home = TimelineKey(rawValue: "home")
}

struct TimelineEntryID: Codable, Sendable {
    let rawValue: String
    let sourceEventID: EventID?
    let sortAt: Int64?
    let tieBreakID: String?

    init(
        rawValue: String,
        sourceEventID: EventID? = nil,
        sortAt: Int64? = nil,
        tieBreakID: String? = nil
    ) {
        self.rawValue = rawValue
        self.sourceEventID = sourceEventID
        self.sortAt = sortAt
        self.tieBreakID = tieBreakID
    }

    static let debugItems = [
        TimelineEntryID(rawValue: "debug:timeline-engine:001", sortAt: 300, tieBreakID: "001"),
        TimelineEntryID(rawValue: "debug:timeline-engine:002", sortAt: 200, tieBreakID: "002"),
        TimelineEntryID(rawValue: "debug:timeline-engine:003", sortAt: 100, tieBreakID: "003")
    ]
}

extension TimelineEntryID: Hashable {
    static func == (lhs: TimelineEntryID, rhs: TimelineEntryID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum TimelineSection: Hashable, Codable, Sendable {
    case main
}

enum ResolveApplyReason: Equatable, Codable, Sendable {
    case profile
    case bodyMention
    case media
    case linkPreview
    case repost
    case quote
    case replyParent
    case stats
    case visibility
    case publishStatePlaceholder
    case debug

    var snapshotReason: TimelineSnapshotReason {
        .reconfigure(self)
    }
}

enum TimelineSnapshotReason: Equatable, Codable, Sendable {
    case initialRestore
    case userInsertedPendingNew
    case olderPageLoaded
    case gapFilled
    case reconfigure(ResolveApplyReason)
    case filterChanged
    case accountSwitched
    case timelineSwitched
    case debugReload

    var advancesReadMarker: Bool {
        false
    }
}

struct TimelineVisualAnchor: Codable, Equatable, Sendable {
    var accountID: AccountID
    var feedID: FeedID
    var timelineKey: TimelineKey
    var anchorItemKey: String
    var anchorEventID: EventID?
    var anchorSortAt: Int64
    var anchorTieBreakID: String
    var cellTopDeltaFromViewportTop: Double
    var viewportHeight: Double
    var viewportWidth: Double
    var contentInsetTop: Double
    var contentInsetBottom: Double
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?
    var markerEventID: EventID?
    var markerSortAt: Int64?
    var capturedAtMS: Int64
    var schemaVersion: Int
}

enum TimelineMutationStyle: String, Equatable, Codable, Sendable {
    case snapshot
    case reconfigure
}

enum TimelinePendingNewInsertionDecision: String, Equatable, Codable, Sendable {
    case allowed
    case blocked
}

struct TimelineSnapshotMutationPlan: Equatable, Sendable {
    var reason: TimelineSnapshotReason
    var mutationStyle: TimelineMutationStyle
    var itemIDs: [TimelineEntryID]
    var reconfigureIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
}

protocol TimelineRepositoryBoundaryProtocol: Sendable {
    func initialWindow(_ request: TimelineInitialWindowRequest) -> TimelineInitialWindowDraft
}

enum TimelineRepositoryFeedItemReason: String, CaseIterable, Codable, Sendable {
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

struct TimelineRepositoryFeedItemDraftRow: Equatable, Codable, Sendable {
    var itemKey: String
    var sourceEventID: EventID
    var subjectEventID: EventID?
    var reason: TimelineRepositoryFeedItemReason
    var actorPubkey: String?
    var sortAt: Int64?
    var tieBreakID: String
    var hiddenReason: String?
    var collapsed: Bool
    var pendingNew: Bool
    var isMissingTargetFallbackCapable: Bool

    init(
        itemKey: String,
        sourceEventID: EventID,
        subjectEventID: EventID? = nil,
        reason: TimelineRepositoryFeedItemReason,
        actorPubkey: String? = nil,
        sortAt: Int64?,
        tieBreakID: String,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false,
        isMissingTargetFallbackCapable: Bool = false
    ) {
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
        self.isMissingTargetFallbackCapable = isMissingTargetFallbackCapable
    }

    var entryID: TimelineEntryID? {
        guard let sortAt else { return nil }
        return TimelineEntryID(
            rawValue: itemKey,
            sourceEventID: sourceEventID,
            sortAt: sortAt,
            tieBreakID: tieBreakID
        )
    }
}

struct TimelineReadStateDraft: Equatable, Codable, Sendable {
    var accountID: AccountID?
    var feedID: FeedID?
    var timelineKey: TimelineKey?
    var scrollAnchorItemKey: String?
    var scrollAnchorEventID: EventID?
    var scrollAnchorSortAt: Int64?
    var scrollAnchorTieBreakID: String?
    var scrollAnchorOffsetPX: Int?
    var viewportHeightPX: Int?
    var viewportWidthPX: Int?
    var contentInsetTopPX: Int?
    var contentInsetBottomPX: Int?
    var markerItemKey: String?
    var markerEventID: EventID?
    var markerSortAt: Int64?
    var lastVisibleTopItemKey: String?
    var lastVisibleBottomItemKey: String?
    var restoreFallbackReason: TimelineRepositoryBoundaryFallbackReason?
    var savedAtMS: Int64?
    var schemaVersion: Int?

    init(
        accountID: AccountID? = nil,
        feedID: FeedID? = nil,
        timelineKey: TimelineKey? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: EventID? = nil,
        scrollAnchorSortAt: Int64? = nil,
        scrollAnchorTieBreakID: String? = nil,
        scrollAnchorOffsetPX: Int? = nil,
        viewportHeightPX: Int? = nil,
        viewportWidthPX: Int? = nil,
        contentInsetTopPX: Int? = nil,
        contentInsetBottomPX: Int? = nil,
        markerItemKey: String? = nil,
        markerEventID: EventID? = nil,
        markerSortAt: Int64? = nil,
        lastVisibleTopItemKey: String? = nil,
        lastVisibleBottomItemKey: String? = nil,
        restoreFallbackReason: TimelineRepositoryBoundaryFallbackReason? = nil,
        savedAtMS: Int64? = nil,
        schemaVersion: Int? = nil
    ) {
        self.accountID = accountID
        self.feedID = feedID
        self.timelineKey = timelineKey
        self.scrollAnchorItemKey = scrollAnchorItemKey
        self.scrollAnchorEventID = scrollAnchorEventID
        self.scrollAnchorSortAt = scrollAnchorSortAt
        self.scrollAnchorTieBreakID = scrollAnchorTieBreakID
        self.scrollAnchorOffsetPX = scrollAnchorOffsetPX
        self.viewportHeightPX = viewportHeightPX
        self.viewportWidthPX = viewportWidthPX
        self.contentInsetTopPX = contentInsetTopPX
        self.contentInsetBottomPX = contentInsetBottomPX
        self.markerItemKey = markerItemKey
        self.markerEventID = markerEventID
        self.markerSortAt = markerSortAt
        self.lastVisibleTopItemKey = lastVisibleTopItemKey
        self.lastVisibleBottomItemKey = lastVisibleBottomItemKey
        self.restoreFallbackReason = restoreFallbackReason
        self.savedAtMS = savedAtMS
        self.schemaVersion = schemaVersion
    }
}

enum TimelinePendingNewInclusionReason: String, Codable, Sendable {
    case explicitUserAction
}

struct TimelineVisibleWindowPolicy: Equatable, Codable, Sendable {
    var maxVisibleCount: Int
    var includePendingNew: Bool
    var pendingNewInclusionReason: TimelinePendingNewInclusionReason?
    var explicitPendingNewItemKeys: [String]
    var forcedHiddenItemKeys: [String]

    init(
        maxVisibleCount: Int,
        includePendingNew: Bool = false,
        pendingNewInclusionReason: TimelinePendingNewInclusionReason? = nil,
        explicitPendingNewItemKeys: [String] = [],
        forcedHiddenItemKeys: [String] = []
    ) {
        self.maxVisibleCount = max(0, maxVisibleCount)
        self.includePendingNew = includePendingNew
        self.pendingNewInclusionReason = pendingNewInclusionReason
        self.explicitPendingNewItemKeys = explicitPendingNewItemKeys
        self.forcedHiddenItemKeys = forcedHiddenItemKeys
    }

    static func initialRestore(maxVisibleCount: Int) -> TimelineVisibleWindowPolicy {
        TimelineVisibleWindowPolicy(maxVisibleCount: maxVisibleCount)
    }

    static func explicitUserPendingNew(
        itemKeys: [String],
        maxVisibleCount: Int
    ) -> TimelineVisibleWindowPolicy {
        TimelineVisibleWindowPolicy(
            maxVisibleCount: maxVisibleCount,
            includePendingNew: true,
            pendingNewInclusionReason: .explicitUserAction,
            explicitPendingNewItemKeys: itemKeys
        )
    }
}

struct TimelineInitialWindowRequest: Equatable, Codable, Sendable {
    var feedID: FeedID
    var rows: [TimelineRepositoryFeedItemDraftRow]
    var readState: TimelineReadStateDraft?
    var policy: TimelineVisibleWindowPolicy
    var attemptsTimelineEntriesOnlyAnchorDerivation: Bool
    var attemptsReadMarkerAdvance: Bool

    init(
        feedID: FeedID,
        rows: [TimelineRepositoryFeedItemDraftRow],
        readState: TimelineReadStateDraft? = nil,
        policy: TimelineVisibleWindowPolicy,
        attemptsTimelineEntriesOnlyAnchorDerivation: Bool = false,
        attemptsReadMarkerAdvance: Bool = false
    ) {
        self.feedID = feedID
        self.rows = rows
        self.readState = readState
        self.policy = policy
        self.attemptsTimelineEntriesOnlyAnchorDerivation = attemptsTimelineEntriesOnlyAnchorDerivation
        self.attemptsReadMarkerAdvance = attemptsReadMarkerAdvance
    }
}

enum TimelineInitialWindowAnchorSource: String, Codable, Sendable {
    case scrollAnchor
    case readMarker
    case lastVisible
    case newest
    case none
}

enum TimelineRepositoryBoundaryFallbackReason: String, Codable, Sendable {
    case anchorFound
    case scrollAnchorEventFound
    case markerFound
    case markerEventFound
    case markerSortFound
    case lastVisibleTopFound
    case lastVisibleBottomFound
    case missingAnchorUsedScrollEvent
    case missingAnchorUsedMarker
    case missingAnchorAndMarkerUsedLastVisibleTop
    case missingAnchorAndMarkerUsedLastVisibleBottom
    case missingAnchorUsedNewest
    case missingAnchorAndMarkerUsedNewest
    case missingMarkerUsedNewest
    case noReadStateUsedNewest
    case noVisibleRows
}

struct TimelineRepositoryBoundaryIssue: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case duplicateItemKey
        case missingAnchor
        case missingScrollAnchorEvent
        case missingMarker
        case missingLastVisible
        case invalidSortKey
        case invalidItemKey
        case pendingNewIncludedWithoutExplicitUserAction
        case hiddenRowIncludedByMistake
        case timelineEntriesOnlyAnchorDerivationAttempted
        case readMarkerAdvanceAttempted
    }

    var kind: Kind
    var itemKey: String?
    var eventID: EventID?

    init(
        kind: Kind,
        itemKey: String? = nil,
        eventID: EventID? = nil
    ) {
        self.kind = kind
        self.itemKey = itemKey
        self.eventID = eventID
    }
}

struct TimelineRepositoryBoundaryDiagnostics: Equatable, Codable, Sendable {
    var inputCount: Int
    var visibleOutputCount: Int
    var excludedPendingNewCount: Int
    var pendingNewIncludedCount: Int
    var pendingNewInclusionReason: TimelinePendingNewInclusionReason?
    var excludedHiddenCount: Int
    var collapsedCount: Int
    var duplicateItemKeyCount: Int
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var fallbackItemKey: String?
    var requestedAnchorItemKey: String?
    var requestedAnchorEventID: EventID?
    var requestedMarkerEventID: EventID?
    var requestedLastVisibleTopItemKey: String?
    var requestedLastVisibleBottomItemKey: String?
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
}

struct TimelineInitialWindowDraft: Equatable, Codable, Sendable {
    var feedID: FeedID
    var visibleRows: [TimelineRepositoryFeedItemDraftRow]
    var visibleEntryIDs: [TimelineEntryID]
    var anchorItemKey: String?
    var anchorSource: TimelineInitialWindowAnchorSource
    var diagnostics: TimelineRepositoryBoundaryDiagnostics
    var issues: [TimelineRepositoryBoundaryIssue]

    var visibleItemKeys: [String] {
        visibleRows.map(\.itemKey)
    }
}

struct FixtureTimelineRepositoryBoundary: TimelineRepositoryBoundaryProtocol, Equatable, Codable {
    init() {}

    func initialWindow(_ request: TimelineInitialWindowRequest) -> TimelineInitialWindowDraft {
        var issues = initialIssues(for: request)
        let normalizedRows = normalizedValidRows(from: request.rows, issues: &issues)
        let dedupedRows = deduplicatedRows(from: normalizedRows, issues: &issues)
        let visibleCandidates = visibleRows(
            from: dedupedRows,
            policy: request.policy,
            issues: &issues
        )
        let anchor = selectedAnchor(
            readState: request.readState,
            visibleRows: visibleCandidates,
            issues: &issues
        )
        let visibleRows = windowRows(
            visibleCandidates,
            around: anchor.itemKey,
            limit: request.policy.maxVisibleCount
        )
        let visibleEntryIDs = visibleRows.compactMap(\.entryID)

        return TimelineInitialWindowDraft(
            feedID: request.feedID,
            visibleRows: visibleRows,
            visibleEntryIDs: visibleEntryIDs,
            anchorItemKey: anchor.itemKey,
            anchorSource: anchor.source,
            diagnostics: diagnostics(
                request: request,
                visibleRows: visibleRows,
                visibleCandidates: visibleCandidates,
                dedupedRows: dedupedRows,
                duplicateItemKeyCount: issues.filter { $0.kind == .duplicateItemKey }.count,
                fallbackReason: anchor.fallbackReason,
                fallbackItemKey: anchor.itemKey
            ),
            issues: issues
        )
    }

    private func initialIssues(
        for request: TimelineInitialWindowRequest
    ) -> [TimelineRepositoryBoundaryIssue] {
        var issues: [TimelineRepositoryBoundaryIssue] = []

        if request.attemptsTimelineEntriesOnlyAnchorDerivation {
            issues.append(TimelineRepositoryBoundaryIssue(
                kind: .timelineEntriesOnlyAnchorDerivationAttempted
            ))
        }
        if request.attemptsReadMarkerAdvance {
            issues.append(TimelineRepositoryBoundaryIssue(
                kind: .readMarkerAdvanceAttempted
            ))
        }

        return issues
    }

    private func normalizedValidRows(
        from rows: [TimelineRepositoryFeedItemDraftRow],
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) -> [TimelineRepositoryFeedItemDraftRow] {
        rows.compactMap { row in
            let trimmedItemKey = row.itemKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedItemKey.isEmpty else {
                issues.append(TimelineRepositoryBoundaryIssue(
                    kind: .invalidItemKey,
                    itemKey: row.itemKey,
                    eventID: row.sourceEventID
                ))
                return nil
            }
            guard row.sortAt != nil else {
                issues.append(TimelineRepositoryBoundaryIssue(
                    kind: .invalidSortKey,
                    itemKey: row.itemKey,
                    eventID: row.sourceEventID
                ))
                return nil
            }

            var normalized = row
            normalized.itemKey = trimmedItemKey
            return normalized
        }
    }

    private func deduplicatedRows(
        from rows: [TimelineRepositoryFeedItemDraftRow],
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) -> [TimelineRepositoryFeedItemDraftRow] {
        var seen = Set<String>()
        var deduped: [TimelineRepositoryFeedItemDraftRow] = []

        for row in rows.sorted(by: rowSort) {
            guard seen.insert(row.itemKey).inserted else {
                issues.append(TimelineRepositoryBoundaryIssue(
                    kind: .duplicateItemKey,
                    itemKey: row.itemKey,
                    eventID: row.sourceEventID
                ))
                continue
            }
            deduped.append(row)
        }

        return deduped
    }

    private func visibleRows(
        from rows: [TimelineRepositoryFeedItemDraftRow],
        policy: TimelineVisibleWindowPolicy,
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) -> [TimelineRepositoryFeedItemDraftRow] {
        let explicitPendingKeys = Set(policy.explicitPendingNewItemKeys)
        let forcedHiddenKeys = Set(policy.forcedHiddenItemKeys)

        return rows.filter { row in
            if row.hiddenReason != nil {
                if forcedHiddenKeys.contains(row.itemKey) {
                    issues.append(TimelineRepositoryBoundaryIssue(
                        kind: .hiddenRowIncludedByMistake,
                        itemKey: row.itemKey,
                        eventID: row.sourceEventID
                    ))
                }
                return false
            }

            guard row.pendingNew else {
                return true
            }

            guard policy.includePendingNew,
                  policy.pendingNewInclusionReason == .explicitUserAction,
                  (explicitPendingKeys.isEmpty || explicitPendingKeys.contains(row.itemKey)) else {
                if policy.includePendingNew {
                    issues.append(TimelineRepositoryBoundaryIssue(
                        kind: .pendingNewIncludedWithoutExplicitUserAction,
                        itemKey: row.itemKey,
                        eventID: row.sourceEventID
                    ))
                }
                return false
            }

            return true
        }
    }

    private func selectedAnchor(
        readState: TimelineReadStateDraft?,
        visibleRows: [TimelineRepositoryFeedItemDraftRow],
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) -> (
        itemKey: String?,
        source: TimelineInitialWindowAnchorSource,
        fallbackReason: TimelineRepositoryBoundaryFallbackReason
    ) {
        guard !visibleRows.isEmpty else {
            return (nil, .none, .noVisibleRows)
        }
        guard let readState else {
            return (visibleRows[0].itemKey, .newest, .noReadStateUsedNewest)
        }

        if let anchorItemKey = readState.scrollAnchorItemKey {
            if visibleRows.contains(where: { $0.itemKey == anchorItemKey }) {
                return (anchorItemKey, .scrollAnchor, .anchorFound)
            }

            issues.append(TimelineRepositoryBoundaryIssue(
                kind: .missingAnchor,
                itemKey: anchorItemKey
            ))

            if let scrollAnchorEventRow = scrollAnchorEventRow(readState: readState, visibleRows: visibleRows) {
                return (scrollAnchorEventRow.itemKey, .scrollAnchor, .missingAnchorUsedScrollEvent)
            }
            appendMissingScrollAnchorEventIssueIfNeeded(readState, issues: &issues)

            if let markerFallback = markerFallback(readState: readState, visibleRows: visibleRows, issues: &issues) {
                return (markerFallback.row.itemKey, .readMarker, .missingAnchorUsedMarker)
            }

            if let lastVisibleFallback = lastVisibleFallback(readState: readState, visibleRows: visibleRows) {
                let reason: TimelineRepositoryBoundaryFallbackReason = lastVisibleFallback.reason == .lastVisibleTopFound
                    ? .missingAnchorAndMarkerUsedLastVisibleTop
                    : .missingAnchorAndMarkerUsedLastVisibleBottom
                return (lastVisibleFallback.row.itemKey, .lastVisible, reason)
            }

            appendMissingLastVisibleIssueIfNeeded(readState, issues: &issues)

            if readState.hasMarker {
                appendMissingMarkerIssueIfNeeded(readState, issues: &issues)
                return (visibleRows[0].itemKey, .newest, .missingAnchorAndMarkerUsedNewest)
            }

            return (visibleRows[0].itemKey, .newest, .missingAnchorUsedNewest)
        }

        if let scrollAnchorEventRow = scrollAnchorEventRow(readState: readState, visibleRows: visibleRows) {
            return (scrollAnchorEventRow.itemKey, .scrollAnchor, .scrollAnchorEventFound)
        }
        appendMissingScrollAnchorEventIssueIfNeeded(readState, issues: &issues)

        if let markerFallback = markerFallback(readState: readState, visibleRows: visibleRows, issues: &issues) {
            return (markerFallback.row.itemKey, .readMarker, markerFallback.reason)
        }

        if readState.hasMarker {
            appendMissingMarkerIssueIfNeeded(readState, issues: &issues)
            return (visibleRows[0].itemKey, .newest, .missingMarkerUsedNewest)
        }

        if let lastVisibleFallback = lastVisibleFallback(readState: readState, visibleRows: visibleRows) {
            return (lastVisibleFallback.row.itemKey, .lastVisible, lastVisibleFallback.reason)
        }
        appendMissingLastVisibleIssueIfNeeded(readState, issues: &issues)

        return (visibleRows[0].itemKey, .newest, .noReadStateUsedNewest)
    }

    private func scrollAnchorEventRow(
        readState: TimelineReadStateDraft,
        visibleRows: [TimelineRepositoryFeedItemDraftRow]
    ) -> TimelineRepositoryFeedItemDraftRow? {
        guard let scrollAnchorEventID = readState.scrollAnchorEventID else { return nil }
        return visibleRows.sorted(by: rowSort).first { row in
            row.sourceEventID == scrollAnchorEventID || row.subjectEventID == scrollAnchorEventID
        }
    }

    private func markerFallback(
        readState: TimelineReadStateDraft,
        visibleRows: [TimelineRepositoryFeedItemDraftRow],
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) -> (
        row: TimelineRepositoryFeedItemDraftRow,
        reason: TimelineRepositoryBoundaryFallbackReason
    )? {
        let sortedRows = visibleRows.sorted(by: rowSort)

        if let markerItemKey = readState.markerItemKey,
           let row = sortedRows.first(where: { $0.itemKey == markerItemKey }) {
            return (row, .markerFound)
        }
        if let markerEventID = readState.markerEventID {
            if let row = sortedRows.first(where: { row in
                row.sourceEventID == markerEventID || row.subjectEventID == markerEventID
            }) {
                return (row, .markerEventFound)
            }
            issues.append(TimelineRepositoryBoundaryIssue(
                kind: .missingMarker,
                itemKey: readState.markerItemKey,
                eventID: readState.markerEventID
            ))
        }
        if let markerSortAt = readState.markerSortAt {
            let row = sortedRows.min { lhs, rhs in
                let lhsDistance = abs(Double(lhs.sortAt ?? .min) - Double(markerSortAt))
                let rhsDistance = abs(Double(rhs.sortAt ?? .min) - Double(markerSortAt))

                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }

                return rowSort(lhs: lhs, rhs: rhs)
            }
            return row.map { ($0, .markerSortFound) }
        }
        return nil
    }

    private func lastVisibleFallback(
        readState: TimelineReadStateDraft,
        visibleRows: [TimelineRepositoryFeedItemDraftRow]
    ) -> (
        row: TimelineRepositoryFeedItemDraftRow,
        reason: TimelineRepositoryBoundaryFallbackReason
    )? {
        let sortedRows = visibleRows.sorted(by: rowSort)
        if let topItemKey = readState.lastVisibleTopItemKey,
           let row = sortedRows.first(where: { $0.itemKey == topItemKey }) {
            return (row, .lastVisibleTopFound)
        }
        if let bottomItemKey = readState.lastVisibleBottomItemKey,
           let row = sortedRows.first(where: { $0.itemKey == bottomItemKey }) {
            return (row, .lastVisibleBottomFound)
        }
        return nil
    }

    private func appendMissingScrollAnchorEventIssueIfNeeded(
        _ readState: TimelineReadStateDraft,
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) {
        guard readState.scrollAnchorEventID != nil else { return }
        issues.append(TimelineRepositoryBoundaryIssue(
            kind: .missingScrollAnchorEvent,
            eventID: readState.scrollAnchorEventID
        ))
    }

    private func appendMissingMarkerIssueIfNeeded(
        _ readState: TimelineReadStateDraft,
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) {
        guard readState.hasMarker else { return }
        let alreadyRecorded = issues.contains { issue in
            issue.kind == .missingMarker
                && issue.itemKey == readState.markerItemKey
                && issue.eventID == readState.markerEventID
        }
        guard !alreadyRecorded else { return }
        issues.append(TimelineRepositoryBoundaryIssue(
            kind: .missingMarker,
            itemKey: readState.markerItemKey,
            eventID: readState.markerEventID
        ))
    }

    private func appendMissingLastVisibleIssueIfNeeded(
        _ readState: TimelineReadStateDraft,
        issues: inout [TimelineRepositoryBoundaryIssue]
    ) {
        guard readState.hasLastVisible else { return }
        issues.append(TimelineRepositoryBoundaryIssue(
            kind: .missingLastVisible,
            itemKey: readState.lastVisibleTopItemKey ?? readState.lastVisibleBottomItemKey
        ))
    }

    private func windowRows(
        _ rows: [TimelineRepositoryFeedItemDraftRow],
        around anchorItemKey: String?,
        limit: Int
    ) -> [TimelineRepositoryFeedItemDraftRow] {
        guard limit > 0 else { return [] }
        guard rows.count > limit else { return rows }
        guard let anchorItemKey,
              let anchorIndex = rows.firstIndex(where: { $0.itemKey == anchorItemKey }) else {
            return Array(rows.prefix(limit))
        }

        let halfWindow = limit / 2
        let maximumStartIndex = max(0, rows.count - limit)
        let startIndex = min(max(0, anchorIndex - halfWindow), maximumStartIndex)
        let endIndex = min(rows.count, startIndex + limit)
        return Array(rows[startIndex..<endIndex])
    }

    private func diagnostics(
        request: TimelineInitialWindowRequest,
        visibleRows: [TimelineRepositoryFeedItemDraftRow],
        visibleCandidates: [TimelineRepositoryFeedItemDraftRow],
        dedupedRows: [TimelineRepositoryFeedItemDraftRow],
        duplicateItemKeyCount: Int,
        fallbackReason: TimelineRepositoryBoundaryFallbackReason,
        fallbackItemKey: String?
    ) -> TimelineRepositoryBoundaryDiagnostics {
        TimelineRepositoryBoundaryDiagnostics(
            inputCount: request.rows.count,
            visibleOutputCount: visibleRows.count,
            excludedPendingNewCount: dedupedRows.filter { row in
                row.pendingNew && !visibleCandidates.contains(where: { $0.itemKey == row.itemKey })
            }.count,
            pendingNewIncludedCount: visibleRows.filter(\.pendingNew).count,
            pendingNewInclusionReason: visibleRows.contains { $0.pendingNew }
                ? request.policy.pendingNewInclusionReason
                : nil,
            excludedHiddenCount: dedupedRows.filter { $0.hiddenReason != nil }.count,
            collapsedCount: visibleRows.filter(\.collapsed).count,
            duplicateItemKeyCount: duplicateItemKeyCount,
            fallbackReason: fallbackReason,
            fallbackItemKey: fallbackItemKey,
            requestedAnchorItemKey: request.readState?.scrollAnchorItemKey,
            requestedAnchorEventID: request.readState?.scrollAnchorEventID,
            requestedMarkerEventID: request.readState?.markerEventID,
            requestedLastVisibleTopItemKey: request.readState?.lastVisibleTopItemKey,
            requestedLastVisibleBottomItemKey: request.readState?.lastVisibleBottomItemKey,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWork: false
        )
    }

    private func rowSort(
        lhs: TimelineRepositoryFeedItemDraftRow,
        rhs: TimelineRepositoryFeedItemDraftRow
    ) -> Bool {
        if lhs.sortAt != rhs.sortAt {
            return (lhs.sortAt ?? .min) > (rhs.sortAt ?? .min)
        }
        return lhs.tieBreakID < rhs.tieBreakID
    }
}

private extension TimelineReadStateDraft {
    var hasMarker: Bool {
        markerItemKey != nil || markerEventID != nil || markerSortAt != nil
    }

    var hasLastVisible: Bool {
        lastVisibleTopItemKey != nil || lastVisibleBottomItemKey != nil
    }
}
