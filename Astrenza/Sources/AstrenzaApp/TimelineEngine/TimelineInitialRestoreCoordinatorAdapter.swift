import Foundation

struct TimelineInitialRestoreCoordinatorExpectation: Equatable, Sendable {
    var snapshot: TimelineInitialRestoreSnapshotExpectation
    var anchor: TimelineInitialRestoreAnchorExpectation
    var diagnostics: TimelineInitialRestoreDiagnosticsExpectation
    var issues: [TimelineInitialRestoreIssue]
    var expectsDataSourceApply: Bool
    var expectsResolveReconfigure: Bool
    var expectsInsertOrDeleteMutation: Bool
}

struct TimelineInitialRestoreSnapshotExpectation: Equatable, Sendable {
    var reason: TimelineSnapshotReason
    var mutationStyle: TimelineMutationStyle
    var itemIDs: [TimelineEntryID]
    var reconfigureIDs: [TimelineEntryID]
    var insertedIDs: [TimelineEntryID]
    var deletedIDs: [TimelineEntryID]
    var mutationPlan: TimelineSnapshotMutationPlan
}

struct TimelineInitialRestoreAnchorExpectation: Equatable, Sendable {
    var requestedAnchorItemKey: String?
    var restoreCandidateItemKey: String?
    var restoreCandidateEntryID: TimelineEntryID?
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var requiresAnchorRestoration: Bool
    var restoreGateIntent: TimelineInitialRestoreGateIntent
}

struct TimelineInitialRestoreDiagnosticsExpectation: Equatable, Sendable {
    var snapshotReason: TimelineSnapshotReason
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWork: Bool
    var localDBReadWork: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var inputRowCount: Int
    var snapshotItemCount: Int
    var pendingNewExcludedCount: Int
    var hiddenExcludedCount: Int
    var issueCount: Int
    var repositoryIssueCount: Int
    var boundaryIssueCount: Int
    var repositoryIssueDiagnostics: [TimelineRepositoryStoreDiagnosticRecord]
    var boundaryIssues: [TimelineRepositoryBoundaryIssue]
    var restoreGateDiagnostics: TimelineRestoreGateDiagnostics
}

enum TimelineInitialRestoreCoordinatorAdapter {
    static func expectation(
        for plan: TimelineInitialRestorePlan,
        restoreGateTimestampMS: Int64 = 0
    ) -> TimelineInitialRestoreCoordinatorExpectation {
        let snapshot = snapshotExpectation(from: plan.snapshotPlan)
        return TimelineInitialRestoreCoordinatorExpectation(
            snapshot: snapshot,
            anchor: anchorExpectation(from: plan),
            diagnostics: diagnosticsExpectation(from: plan, restoreGateTimestampMS: restoreGateTimestampMS),
            issues: plan.issues,
            expectsDataSourceApply: plan.snapshotPlan.callsDataSourceApply,
            expectsResolveReconfigure: snapshot.mutationStyle == .reconfigure || !snapshot.reconfigureIDs.isEmpty,
            expectsInsertOrDeleteMutation: !snapshot.insertedIDs.isEmpty || !snapshot.deletedIDs.isEmpty
        )
    }

    private static func snapshotExpectation(
        from snapshotPlan: TimelineInitialRestoreSnapshotPlan
    ) -> TimelineInitialRestoreSnapshotExpectation {
        TimelineInitialRestoreSnapshotExpectation(
            reason: snapshotPlan.reason,
            mutationStyle: snapshotPlan.mutationStyle,
            itemIDs: snapshotPlan.itemIDs,
            reconfigureIDs: snapshotPlan.reconfigureIDs,
            insertedIDs: snapshotPlan.insertedIDs,
            deletedIDs: snapshotPlan.deletedIDs,
            mutationPlan: snapshotPlan.snapshotMutationPlan
        )
    }

    private static func anchorExpectation(
        from plan: TimelineInitialRestorePlan
    ) -> TimelineInitialRestoreAnchorExpectation {
        TimelineInitialRestoreAnchorExpectation(
            requestedAnchorItemKey: plan.anchorPlan.requestedAnchorItemKey,
            restoreCandidateItemKey: plan.anchorPlan.candidateItemKey,
            restoreCandidateEntryID: plan.anchorPlan.candidateEntryID,
            fallbackReason: plan.anchorPlan.fallbackReason,
            requiresAnchorRestoration: plan.anchorPlan.requiresAnchorRestoration,
            restoreGateIntent: plan.restoreGateIntent
        )
    }

    private static func diagnosticsExpectation(
        from plan: TimelineInitialRestorePlan,
        restoreGateTimestampMS: Int64
    ) -> TimelineInitialRestoreDiagnosticsExpectation {
        let diagnostics = plan.diagnostics
        return TimelineInitialRestoreDiagnosticsExpectation(
            snapshotReason: plan.snapshotPlan.reason,
            fallbackReason: diagnostics.fallbackReason,
            readMarkerChanged: diagnostics.readMarkerChanged,
            requiresNetworkWork: diagnostics.requiresNetworkWork,
            requiresDBWork: diagnostics.requiresDBWork,
            localDBReadWork: diagnostics.localDBReadWork,
            networkWaitedBeforeInteractiveScrollMS: diagnostics.networkWaitedBeforeInteractiveScrollMS,
            inputRowCount: diagnostics.inputRowCount,
            snapshotItemCount: diagnostics.snapshotItemCount,
            pendingNewExcludedCount: diagnostics.pendingNewExcludedCount,
            hiddenExcludedCount: diagnostics.hiddenExcludedCount,
            issueCount: diagnostics.issueCount,
            repositoryIssueCount: diagnostics.repositoryIssueDiagnostics.count,
            boundaryIssueCount: diagnostics.boundaryIssues.count,
            repositoryIssueDiagnostics: diagnostics.repositoryIssueDiagnostics,
            boundaryIssues: diagnostics.boundaryIssues,
            restoreGateDiagnostics: plan.restoreGateDiagnostics(timestampMS: restoreGateTimestampMS)
        )
    }
}
