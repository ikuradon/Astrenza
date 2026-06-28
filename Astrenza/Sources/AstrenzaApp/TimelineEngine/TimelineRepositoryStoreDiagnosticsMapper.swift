import AstrenzaCore
import Foundation

struct TimelineRepositoryStoreIssueEnvelope: Equatable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case missingFeed
        case missingAnchor
        case hiddenAnchor
        case pendingAnchor
        case invalidPersistedReason
        case invalidItemKey
        case invalidSortKey
        case malformedReadState

        init(_ coreKind: TimelineRepositoryStoreIssue.Kind) {
            switch coreKind {
            case .missingFeed:
                self = .missingFeed
            case .missingAnchor:
                self = .missingAnchor
            case .hiddenAnchor:
                self = .hiddenAnchor
            case .pendingAnchor:
                self = .pendingAnchor
            case .invalidPersistedReason:
                self = .invalidPersistedReason
            case .invalidItemKey:
                self = .invalidItemKey
            case .invalidSortKey:
                self = .invalidSortKey
            case .malformedReadState:
                self = .malformedReadState
            }
        }
    }

    var kind: Kind
    var feedID: FeedID?
    var itemKey: String?

    init(_ issue: TimelineRepositoryStoreIssue) {
        self.kind = Kind(issue.kind)
        self.feedID = issue.feedID.map(FeedID.init(rawValue:))
        self.itemKey = issue.itemKey
    }
}

enum TimelineRepositoryStoreDiagnosticCategory: String, Codable, Sendable {
    case emptyFeed
    case restoreFallback
    case pendingNewPolicy
    case localDataIntegrity
    case readStateRestore
}

enum TimelineRepositoryStoreFallbackRelevance: String, Codable, Sendable {
    case none
    case emptyFeed
    case missingAnchor
    case hiddenAnchor
    case pendingAnchor
    case readStateSanitized
}

enum TimelineRepositoryStoreDiagnosticDisposition: String, Codable, Sendable {
    case debugOnly
    case releaseBlocking
}

struct TimelineRepositoryStoreDiagnosticRecord: Equatable, Codable, Sendable {
    var issue: TimelineRepositoryStoreIssueEnvelope
    var category: TimelineRepositoryStoreDiagnosticCategory
    var fallbackRelevance: TimelineRepositoryStoreFallbackRelevance
    var disposition: TimelineRepositoryStoreDiagnosticDisposition
    var boundaryIssue: TimelineRepositoryBoundaryIssue?
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
    var snapshotMutationStyle: TimelineMutationStyle?
    var insertsVisibleSnapshotItems: Bool
    var deletesVisibleSnapshotItems: Bool
    var localDebugOnly: Bool
    var externalDestinationCreated: Bool
    var sensitivePayloadKeys: [String]
}

struct TimelineRepositoryStoreIssueCoverageEntry: Equatable, Codable, Sendable {
    var coreKind: TimelineRepositoryStoreIssue.Kind
    var appKind: TimelineRepositoryStoreIssueEnvelope.Kind
    var coverageName: String
}

enum TimelineRepositoryStoreDiagnosticsMapper {
    static let coverageEntries: [TimelineRepositoryStoreIssueCoverageEntry] = [
        coverage(.missingFeed, "missingFeedMapsToEmptyFeedDiagnostic"),
        coverage(.missingAnchor, "allCoreIssueKindsMapToAppOwnedDiagnosticRecords"),
        coverage(.hiddenAnchor, "hiddenAnchorMapsToFallbackDiagnosticWithHiddenSpecificReason"),
        coverage(.pendingAnchor, "pendingAnchorMapsToPendingPolicyDiagnostic"),
        coverage(.invalidPersistedReason, "diagnosticRecordsAreCodableEquatableAndSendable"),
        coverage(.invalidItemKey, "allCoreIssueKindsMapToAppOwnedDiagnosticRecords"),
        coverage(.invalidSortKey, "invalidSortKeyMapsToPersistedRowDiagnostic"),
        coverage(.malformedReadState, "malformedReadStateMapsToReadStateDiagnosticWithoutCrashing")
    ]

    static func records(
        for issues: [TimelineRepositoryStoreIssue],
        diagnostics: TimelineRepositoryStoreDiagnostics
    ) -> [TimelineRepositoryStoreDiagnosticRecord] {
        issues.map { issue in
            record(for: issue, diagnostics: diagnostics)
        }
    }

    static func record(
        for issue: TimelineRepositoryStoreIssue,
        diagnostics: TimelineRepositoryStoreDiagnostics
    ) -> TimelineRepositoryStoreDiagnosticRecord {
        let envelope = TimelineRepositoryStoreIssueEnvelope(issue)
        let mapping = mapping(for: envelope)

        return TimelineRepositoryStoreDiagnosticRecord(
            issue: envelope,
            category: mapping.category,
            fallbackRelevance: mapping.fallbackRelevance,
            disposition: mapping.disposition,
            boundaryIssue: mapping.boundaryIssue,
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
            snapshotMutationStyle: nil,
            insertsVisibleSnapshotItems: false,
            deletesVisibleSnapshotItems: false,
            localDebugOnly: true,
            externalDestinationCreated: false,
            sensitivePayloadKeys: []
        )
    }

    private static func coverage(
        _ coreKind: TimelineRepositoryStoreIssue.Kind,
        _ coverageName: String
    ) -> TimelineRepositoryStoreIssueCoverageEntry {
        TimelineRepositoryStoreIssueCoverageEntry(
            coreKind: coreKind,
            appKind: TimelineRepositoryStoreIssueEnvelope.Kind(coreKind),
            coverageName: coverageName
        )
    }

    private static func mapping(
        for envelope: TimelineRepositoryStoreIssueEnvelope
    ) -> (
        category: TimelineRepositoryStoreDiagnosticCategory,
        fallbackRelevance: TimelineRepositoryStoreFallbackRelevance,
        disposition: TimelineRepositoryStoreDiagnosticDisposition,
        boundaryIssue: TimelineRepositoryBoundaryIssue?
    ) {
        switch envelope.kind {
        case .missingFeed:
            return (.emptyFeed, .emptyFeed, .debugOnly, nil)
        case .missingAnchor:
            return (.restoreFallback, .missingAnchor, .debugOnly, missingAnchorIssue(envelope.itemKey))
        case .hiddenAnchor:
            return (.restoreFallback, .hiddenAnchor, .debugOnly, missingAnchorIssue(envelope.itemKey))
        case .pendingAnchor:
            return (.pendingNewPolicy, .pendingAnchor, .debugOnly, missingAnchorIssue(envelope.itemKey))
        case .invalidPersistedReason:
            return (.localDataIntegrity, .none, .releaseBlocking, nil)
        case .invalidItemKey:
            return (
                .localDataIntegrity,
                .none,
                .releaseBlocking,
                TimelineRepositoryBoundaryIssue(kind: .invalidItemKey, itemKey: envelope.itemKey)
            )
        case .invalidSortKey:
            return (
                .localDataIntegrity,
                .none,
                .releaseBlocking,
                TimelineRepositoryBoundaryIssue(kind: .invalidSortKey, itemKey: envelope.itemKey)
            )
        case .malformedReadState:
            return (.readStateRestore, .readStateSanitized, .releaseBlocking, nil)
        }
    }

    private static func missingAnchorIssue(_ itemKey: String?) -> TimelineRepositoryBoundaryIssue {
        TimelineRepositoryBoundaryIssue(kind: .missingAnchor, itemKey: itemKey)
    }
}
