import Foundation

struct TimelineInitialRestoreInput: Equatable, Codable, Sendable {
    var composition: TimelineRepositoryStoreWindowComposition
    var requestedAnchorItemKey: String?
    var localInitialWindowQueryDurationMS: Double
    var initialSnapshotApplyDurationMS: Double
    var anchorRestoreDurationMS: Double
    var restoreGateDurationMS: Double

    init(
        composition: TimelineRepositoryStoreWindowComposition,
        requestedAnchorItemKey: String? = nil,
        localInitialWindowQueryDurationMS: Double = 0,
        initialSnapshotApplyDurationMS: Double = 0,
        anchorRestoreDurationMS: Double = 0,
        restoreGateDurationMS: Double = 0
    ) {
        self.composition = composition
        self.requestedAnchorItemKey = requestedAnchorItemKey
        self.localInitialWindowQueryDurationMS = localInitialWindowQueryDurationMS
        self.initialSnapshotApplyDurationMS = initialSnapshotApplyDurationMS
        self.anchorRestoreDurationMS = anchorRestoreDurationMS
        self.restoreGateDurationMS = restoreGateDurationMS
    }
}

struct TimelineInitialRestorePlan: Equatable, Codable, Sendable {
    var snapshotPlan: TimelineInitialRestoreSnapshotPlan
    var anchorPlan: TimelineInitialRestoreAnchorPlan
    var restoreGateIntent: TimelineInitialRestoreGateIntent
    var diagnostics: TimelineInitialRestoreDiagnostics
    var issues: [TimelineInitialRestoreIssue]

    func restoreGateDiagnostics(timestampMS: Int64) -> TimelineRestoreGateDiagnostics {
        TimelineRestoreGateMetricBuilder.diagnostics(
            localInitialWindowQueryDurationMS: diagnostics.localInitialWindowQueryDurationMS,
            initialSnapshotApplyDurationMS: diagnostics.initialSnapshotApplyDurationMS,
            anchorRestoreDurationMS: diagnostics.anchorRestoreDurationMS,
            restoreGateDurationMS: diagnostics.restoreGateDurationMS,
            firstInteractiveScrollAllowedAtMS: timestampMS,
            networkWaitedBeforeInteractiveScrollMS: diagnostics.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: diagnostics.readMarkerChanged,
            fallbackPresentation: restoreGateIntent.fallbackPresentation,
            timestampMS: timestampMS
        )
    }
}

enum TimelineInitialRestoreGateIntent: String, Equatable, Codable, Sendable {
    case noGate
    case protectAnchorRestore
    case emptyLocalCache
    case recoverableFailure

    var fallbackPresentation: TimelineRestoreGateFallbackPresentation? {
        switch self {
        case .noGate:
            nil
        case .protectAnchorRestore:
            .inlineSkeleton
        case .emptyLocalCache:
            .emptyState
        case .recoverableFailure:
            .recoverableState
        }
    }
}

struct TimelineInitialRestoreSnapshotPlan: Equatable, Codable, Sendable {
    var reason: TimelineSnapshotReason
    var mutationStyle: TimelineMutationStyle
    var itemIDs: [TimelineEntryID]
    var reconfigureIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var callsDataSourceApply: Bool

    var snapshotMutationPlan: TimelineSnapshotMutationPlan {
        TimelineSnapshotMutationPlan(
            reason: reason,
            mutationStyle: mutationStyle,
            itemIDs: itemIDs,
            reconfigureIDs: reconfigureIDs,
            insertedIDs: insertedIDs,
            deletedIDs: deletedIDs
        )
    }
}

struct TimelineInitialRestoreAnchorPlan: Equatable, Codable, Sendable {
    var requestedAnchorItemKey: String?
    var candidateItemKey: String?
    var candidateEntryID: TimelineEntryID?
    var anchorSource: TimelineInitialWindowAnchorSource
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var scrollAnchorOffsetPX: Int?
    var viewportHeightPX: Int?
    var viewportWidthPX: Int?
    var contentInsetTopPX: Int?
    var contentInsetBottomPX: Int?
    var savedAtMS: Int64?

    var requiresAnchorRestoration: Bool {
        guard candidateItemKey != nil else { return false }
        switch anchorSource {
        case .scrollAnchor, .readMarker, .lastVisible:
            return true
        case .newest:
            return requestedAnchorItemKey != nil && requestedAnchorItemKey == candidateItemKey
        case .none:
            return false
        }
    }
}

struct TimelineInitialRestoreDiagnostics: Equatable, Codable, Sendable {
    var inputRowCount: Int
    var snapshotItemCount: Int
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
    var localDBReadWork: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var pendingNewExcludedCount: Int
    var hiddenExcludedCount: Int
    var issueCount: Int
    var repositoryIssueDiagnostics: [TimelineRepositoryStoreDiagnosticRecord]
    var boundaryIssues: [TimelineRepositoryBoundaryIssue]
    var localInitialWindowQueryDurationMS: Double
    var initialSnapshotApplyDurationMS: Double
    var anchorRestoreDurationMS: Double
    var restoreGateDurationMS: Double
}

struct TimelineInitialRestoreIssue: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case invalidSnapshotEntryID
        case repositoryStoreIssue
        case boundaryIssue
        case compositionIssue
        case readMarkerChanged
        case networkWorkRequired
        case externalDBWorkRequired
    }

    var kind: Kind
    var itemKey: String?
    var field: String?
}

enum TimelineInitialRestoreUseCase {
    static func makePlan(input: TimelineInitialRestoreInput) -> TimelineInitialRestorePlan {
        let composition = input.composition
        let visibleRows = composition.initialWindow.visibleRows
        let validationIssues = invalidEntryIssues(in: visibleRows)
        let isInvalid = !validationIssues.isEmpty
        let itemIDs = isInvalid ? [] : composition.initialWindow.visibleEntryIDs
        let anchorPlan = makeAnchorPlan(from: composition, requestedAnchorItemKey: input.requestedAnchorItemKey)
        let issues = makeIssues(from: composition, validationIssues: validationIssues)
        let snapshotPlan = TimelineInitialRestoreSnapshotPlan(
            reason: .initialRestore,
            mutationStyle: .snapshot,
            itemIDs: itemIDs,
            reconfigureIDs: [],
            insertedIDs: [],
            deletedIDs: [],
            callsDataSourceApply: false
        )
        let diagnostics = makeDiagnostics(
            input: input,
            composition: composition,
            snapshotItemCount: itemIDs.count,
            anchorPlan: anchorPlan,
            issueCount: issues.count
        )

        return TimelineInitialRestorePlan(
            snapshotPlan: snapshotPlan,
            anchorPlan: anchorPlan,
            restoreGateIntent: restoreGateIntent(
                isInvalid: isInvalid,
                itemIDs: itemIDs,
                anchorPlan: anchorPlan
            ),
            diagnostics: diagnostics,
            issues: issues
        )
    }

    private static func invalidEntryIssues(
        in visibleRows: [TimelineRepositoryFeedItemDraftRow]
    ) -> [TimelineInitialRestoreIssue] {
        visibleRows.compactMap { row in
            guard row.entryID != nil else {
                return TimelineInitialRestoreIssue(
                    kind: .invalidSnapshotEntryID,
                    itemKey: row.itemKey,
                    field: "visibleRows.entryID"
                )
            }
            return nil
        }
    }

    private static func makeAnchorPlan(
        from composition: TimelineRepositoryStoreWindowComposition,
        requestedAnchorItemKey: String?
    ) -> TimelineInitialRestoreAnchorPlan {
        let initialWindow = composition.initialWindow
        let candidateEntryID = initialWindow.anchorItemKey.flatMap { anchorItemKey in
            initialWindow.visibleRows.first { $0.itemKey == anchorItemKey }?.entryID
        }
        let requestedAnchorItemKey = requestedAnchorItemKey
            ?? initialWindow.diagnostics.requestedAnchorItemKey
            ?? composition.readState?.scrollAnchorItemKey

        return TimelineInitialRestoreAnchorPlan(
            requestedAnchorItemKey: requestedAnchorItemKey,
            candidateItemKey: candidateEntryID == nil ? nil : initialWindow.anchorItemKey,
            candidateEntryID: candidateEntryID,
            anchorSource: candidateEntryID == nil ? .none : initialWindow.anchorSource,
            fallbackReason: initialWindow.diagnostics.fallbackReason,
            scrollAnchorOffsetPX: composition.readState?.scrollAnchorOffsetPX,
            viewportHeightPX: composition.readState?.viewportHeightPX,
            viewportWidthPX: composition.readState?.viewportWidthPX,
            contentInsetTopPX: composition.readState?.contentInsetTopPX,
            contentInsetBottomPX: composition.readState?.contentInsetBottomPX,
            savedAtMS: composition.readState?.savedAtMS
        )
    }

    private static func makeIssues(
        from composition: TimelineRepositoryStoreWindowComposition,
        validationIssues: [TimelineInitialRestoreIssue]
    ) -> [TimelineInitialRestoreIssue] {
        validationIssues
            + composition.storeIssueDiagnostics.map { record in
                TimelineInitialRestoreIssue(
                    kind: .repositoryStoreIssue,
                    itemKey: record.issue.itemKey,
                    field: record.issue.kind.rawValue
                )
            }
            + composition.initialWindow.issues.map { issue in
                TimelineInitialRestoreIssue(
                    kind: .boundaryIssue,
                    itemKey: issue.itemKey,
                    field: issue.kind.rawValue
                )
            }
            + composition.issues.map { issue in
                TimelineInitialRestoreIssue(
                    kind: .compositionIssue,
                    itemKey: issue.itemKey,
                    field: issue.kind.rawValue
                )
            }
            + invariantIssues(from: composition)
    }

    private static func invariantIssues(
        from composition: TimelineRepositoryStoreWindowComposition
    ) -> [TimelineInitialRestoreIssue] {
        var issues: [TimelineInitialRestoreIssue] = []
        if composition.initialWindow.diagnostics.readMarkerChanged
            || composition.compositionDiagnostics.readMarkerChanged {
            issues.append(TimelineInitialRestoreIssue(
                kind: .readMarkerChanged,
                itemKey: nil,
                field: "readMarkerChanged"
            ))
        }
        if composition.initialWindow.diagnostics.requiresNetworkWork
            || composition.compositionDiagnostics.requiresNetworkWork {
            issues.append(TimelineInitialRestoreIssue(
                kind: .networkWorkRequired,
                itemKey: nil,
                field: "requiresNetworkWork"
            ))
        }
        if composition.initialWindow.diagnostics.requiresDBWork
            || composition.compositionDiagnostics.requiresDBWork
            || composition.compositionDiagnostics.requiresExternalMutation {
            issues.append(TimelineInitialRestoreIssue(
                kind: .externalDBWorkRequired,
                itemKey: nil,
                field: "requiresDBWork"
            ))
        }
        return issues
    }

    private static func makeDiagnostics(
        input: TimelineInitialRestoreInput,
        composition: TimelineRepositoryStoreWindowComposition,
        snapshotItemCount: Int,
        anchorPlan: TimelineInitialRestoreAnchorPlan,
        issueCount: Int
    ) -> TimelineInitialRestoreDiagnostics {
        TimelineInitialRestoreDiagnostics(
            inputRowCount: nonZeroOrFallback(
                composition.compositionDiagnostics.totalFeedItemRowCount,
                fallback: composition.draftRows.count
            ),
            snapshotItemCount: snapshotItemCount,
            fallbackReason: anchorPlan.fallbackReason,
            readMarkerChanged: composition.initialWindow.diagnostics.readMarkerChanged
                || composition.compositionDiagnostics.readMarkerChanged,
            requiresNetworkWork: composition.initialWindow.diagnostics.requiresNetworkWork
                || composition.compositionDiagnostics.requiresNetworkWork,
            requiresDBWork: composition.initialWindow.diagnostics.requiresDBWork
                || composition.compositionDiagnostics.requiresDBWork
                || composition.compositionDiagnostics.requiresExternalMutation,
            localDBReadWork: composition.compositionDiagnostics.performedLocalDBRead,
            networkWaitedBeforeInteractiveScrollMS: 0,
            pendingNewExcludedCount: max(
                composition.initialWindow.diagnostics.excludedPendingNewCount,
                composition.compositionDiagnostics.excludedPendingNewCount
            ),
            hiddenExcludedCount: max(
                composition.initialWindow.diagnostics.excludedHiddenCount,
                composition.compositionDiagnostics.excludedHiddenCount
            ),
            issueCount: issueCount,
            repositoryIssueDiagnostics: composition.storeIssueDiagnostics,
            boundaryIssues: composition.initialWindow.issues,
            localInitialWindowQueryDurationMS: input.localInitialWindowQueryDurationMS,
            initialSnapshotApplyDurationMS: input.initialSnapshotApplyDurationMS,
            anchorRestoreDurationMS: input.anchorRestoreDurationMS,
            restoreGateDurationMS: input.restoreGateDurationMS
        )
    }

    private static func restoreGateIntent(
        isInvalid: Bool,
        itemIDs: [TimelineEntryID],
        anchorPlan: TimelineInitialRestoreAnchorPlan
    ) -> TimelineInitialRestoreGateIntent {
        if isInvalid {
            return .recoverableFailure
        }
        if itemIDs.isEmpty {
            return .emptyLocalCache
        }
        return anchorPlan.requiresAnchorRestoration ? .protectAnchorRestore : .noGate
    }

    private static func nonZeroOrFallback(_ value: Int, fallback: Int) -> Int {
        value == 0 ? fallback : value
    }
}
