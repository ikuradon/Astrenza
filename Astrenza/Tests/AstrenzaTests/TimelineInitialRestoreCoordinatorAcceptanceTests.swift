import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineInitialRestoreCoordinatorAcceptance")
struct TimelineInitialRestoreCoordinatorAcceptanceTests {
    @Test("valid restore plan maps to coordinator snapshot expectation")
    func validRestorePlanMapsToCoordinatorSnapshotExpectation() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:middle", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
                row(itemKey: "note:oldest", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c")
            ],
            anchorItemKey: "note:middle"
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.snapshot.reason == .initialRestore)
        #expect(expectation.snapshot.mutationStyle == .snapshot)
        #expect(expectation.snapshot.itemIDs.map(\.rawValue) == ["note:newest", "note:middle", "note:oldest"])
        #expect(expectation.snapshot.mutationPlan == plan.snapshotPlan.snapshotMutationPlan)
        #expect(expectation.snapshot.reconfigureIDs.isEmpty)
        #expect(expectation.snapshot.insertedIDs.isEmpty)
        #expect(expectation.snapshot.deletedIDs.isEmpty)
        #expect(expectation.expectsDataSourceApply == false)
        #expect(expectation.expectsResolveReconfigure == false)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
    }

    @Test("anchor present maps to restore candidate expectation")
    func anchorPresentMapsToRestoreCandidateExpectation() throws {
        let plan = try restorePlan(
            readState: readState(scrollAnchorItemKey: "note:anchor", scrollAnchorEventID: eventID("b")),
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:anchor", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:anchor",
            requestedAnchorItemKey: "note:anchor"
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.anchor.requestedAnchorItemKey == "note:anchor")
        #expect(expectation.anchor.restoreCandidateItemKey == "note:anchor")
        #expect(expectation.anchor.restoreCandidateEntryID?.rawValue == "note:anchor")
        #expect(expectation.anchor.fallbackReason == .anchorFound)
        #expect(expectation.anchor.requiresAnchorRestoration)
        #expect(expectation.anchor.restoreGateIntent == .protectAnchorRestore)
    }

    @Test("missing anchor maps fallback expectation")
    func missingAnchorMapsFallbackExpectation() throws {
        let plan = try restorePlan(
            readState: readState(
                markerEventID: eventID("b"),
                markerSortAt: 200,
                scrollAnchorItemKey: "note:missing"
            ),
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:marker", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:missing",
            requestedAnchorItemKey: "note:missing"
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.anchor.requestedAnchorItemKey == "note:missing")
        #expect(expectation.anchor.restoreCandidateItemKey == "note:marker")
        #expect(expectation.anchor.fallbackReason == .missingAnchorUsedMarker)
        #expect(expectation.anchor.requiresAnchorRestoration)
        #expect(expectation.diagnostics.fallbackReason == .missingAnchorUsedMarker)
    }

    @Test("empty local cache maps empty restore gate expectation")
    func emptyLocalCacheMapsEmptyRestoreGateExpectation() throws {
        let plan = try restorePlan(rows: [], anchorItemKey: nil)

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.snapshot.itemIDs.isEmpty)
        #expect(expectation.anchor.restoreCandidateItemKey == nil)
        #expect(expectation.anchor.restoreCandidateEntryID == nil)
        #expect(expectation.anchor.requiresAnchorRestoration == false)
        #expect(expectation.anchor.restoreGateIntent == .emptyLocalCache)
        #expect(expectation.diagnostics.snapshotItemCount == 0)
        #expect(expectation.expectsDataSourceApply == false)
    }

    @Test("repository issues remain attached to diagnostics expectation")
    func repositoryIssuesRemainAttachedToDiagnosticsExpectation() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: "note:visible",
            issues: [
                TimelineRepositoryStoreIssue(kind: .missingAnchor, feedID: 10, itemKey: "note:missing"),
                TimelineRepositoryStoreIssue(kind: .hiddenAnchor, feedID: 10, itemKey: "note:hidden")
            ],
            diagnostics: Self.diagnostics(totalFeedItemRowCount: 3, sqlVisibleRowCount: 1, excludedHiddenCount: 1)
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.diagnostics.issueCount == 4)
        #expect(expectation.diagnostics.repositoryIssueCount == 2)
        #expect(expectation.diagnostics.boundaryIssueCount == 2)
        #expect(expectation.diagnostics.repositoryIssueDiagnostics.map(\.issue.kind) == [.missingAnchor, .hiddenAnchor])
        #expect(expectation.diagnostics.boundaryIssues.compactMap(\.itemKey).sorted() == ["note:hidden", "note:missing"])
        #expect(expectation.issues.count == 4)
    }

    @Test("pending rows remain excluded without insert mutation")
    func pendingRowsRemainExcludedWithoutInsertMutation() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:pending", sourceEventID: eventID("b"), pendingNew: true, sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:visible",
            diagnostics: Self.diagnostics(totalFeedItemRowCount: 2, sqlVisibleRowCount: 1, excludedPendingNewCount: 1)
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.snapshot.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(expectation.snapshot.insertedIDs.isEmpty)
        #expect(expectation.diagnostics.pendingNewExcludedCount == 1)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
    }

    @Test("hidden rows remain excluded without insert mutation")
    func hiddenRowsRemainExcludedWithoutInsertMutation() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:hidden", sourceEventID: eventID("c"), hiddenReason: "muted", sortAt: 100, tieBreakID: "c")
            ],
            anchorItemKey: "note:visible",
            diagnostics: Self.diagnostics(totalFeedItemRowCount: 2, sqlVisibleRowCount: 1, excludedHiddenCount: 1)
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.snapshot.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(expectation.snapshot.insertedIDs.isEmpty)
        #expect(expectation.diagnostics.hiddenExcludedCount == 1)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
    }

    @Test("missing target quote and repost rows stay in snapshot expectation")
    func missingTargetQuoteAndRepostRowsStayInSnapshotExpectation() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "quote:missing", sourceEventID: eventID("d"), subjectEventID: nil, reason: .quote, sortAt: 300, tieBreakID: "d"),
                row(itemKey: "repost:missing", sourceEventID: eventID("e"), subjectEventID: nil, reason: .repost, sortAt: 200, tieBreakID: "e")
            ],
            anchorItemKey: "quote:missing"
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.snapshot.itemIDs.map(\.rawValue) == ["quote:missing", "repost:missing"])
        #expect(expectation.snapshot.deletedIDs.isEmpty)
        #expect(expectation.expectsResolveReconfigure == false)
    }

    @Test("restore gate diagnostics record through diagnostics recorder")
    func restoreGateDiagnosticsRecordThroughDiagnosticsRecorder() throws {
        let timestampMS: Int64 = 1_735_000_000_000
        let plan = try restorePlan(
            readState: readState(scrollAnchorItemKey: "note:visible", scrollAnchorEventID: eventID("a")),
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: "note:visible",
            requestedAnchorItemKey: "note:visible",
            localInitialWindowQueryDurationMS: 12,
            initialSnapshotApplyDurationMS: 8,
            anchorRestoreDurationMS: 2,
            restoreGateDurationMS: 22
        )
        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(
            for: plan,
            restoreGateTimestampMS: timestampMS
        )
        let recorder = TimelineDiagnosticsRecorder()

        let diagnostics = recorder.recordRestoreGateDiagnostics(expectation.diagnostics.restoreGateDiagnostics)
        let export = recorder.export()

        #expect(diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(diagnostics.readMarkerChanged == false)
        #expect(diagnostics.requiresNetworkWork == false)
        #expect(diagnostics.requiresDBWork == false)
        #expect(diagnostics.fallbackPresentation == .inlineSkeleton)
        #expect(export.restoreGateDiagnostics == [expectation.diagnostics.restoreGateDiagnostics])
        #expect(export.summary.restoreGateMetrics.totalAttempts == 1)
        #expect(export.summary.restoreGateMetrics.networkWaitedBeforeInteractiveScrollViolationCount == 0)
    }

    @Test("initial restore expectation has no direct apply insert delete or reconfigure")
    func initialRestoreExpectationHasNoDirectApplyInsertDeleteOrReconfigure() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: "note:visible"
        )

        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(for: plan)

        #expect(expectation.expectsDataSourceApply == false)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
        #expect(expectation.expectsResolveReconfigure == false)
        #expect(expectation.snapshot.reconfigureIDs.isEmpty)
        #expect(expectation.snapshot.insertedIDs.isEmpty)
        #expect(expectation.snapshot.deletedIDs.isEmpty)
    }

    private func restorePlan(
        readState: TimelineRepositoryReadStateRow? = nil,
        rows: [TimelineRepositoryFeedItemRow],
        anchorItemKey: String?,
        requestedAnchorItemKey: String? = nil,
        issues: [TimelineRepositoryStoreIssue] = [],
        diagnostics: TimelineRepositoryStoreDiagnostics = Self.diagnostics(),
        localInitialWindowQueryDurationMS: Double = 0,
        initialSnapshotApplyDurationMS: Double = 0,
        anchorRestoreDurationMS: Double = 0,
        restoreGateDurationMS: Double = 0
    ) throws -> TimelineInitialRestorePlan {
        let composition = try TimelineRepositoryStoreWindowComposer.compose(
            TimelineRepositoryInitialWindow(
                feedID: 10,
                rows: rows,
                readState: readState,
                anchorItemKey: anchorItemKey,
                issues: issues,
                diagnostics: diagnostics
            ),
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        return TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composition,
            requestedAnchorItemKey: requestedAnchorItemKey,
            localInitialWindowQueryDurationMS: localInitialWindowQueryDurationMS,
            initialSnapshotApplyDurationMS: initialSnapshotApplyDurationMS,
            anchorRestoreDurationMS: anchorRestoreDurationMS,
            restoreGateDurationMS: restoreGateDurationMS
        ))
    }

    private func row(
        itemKey: String,
        sourceEventID: String,
        subjectEventID: String? = nil,
        reason: AstrenzaCore.TimelineRepositoryFeedItemReason = .author,
        hiddenReason: String? = nil,
        pendingNew: Bool = false,
        sortAt: Int64,
        tieBreakID: String
    ) -> TimelineRepositoryFeedItemRow {
        TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: subjectEventID,
            reason: reason,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            hiddenReason: hiddenReason,
            pendingNew: pendingNew,
            insertedAtMS: 1,
            updatedAtMS: 2
        )
    }

    private func readState(
        markerEventID: String? = nil,
        markerSortAt: Int64? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: String? = nil
    ) -> TimelineRepositoryReadStateRow {
        TimelineRepositoryReadStateRow(
            databaseAccountID: 1,
            feedID: 10,
            markerSortAt: markerSortAt,
            markerEventID: markerEventID,
            scrollAnchorItemKey: scrollAnchorItemKey,
            scrollAnchorEventID: scrollAnchorEventID,
            scrollAnchorSortAt: nil,
            scrollAnchorTieBreakID: nil,
            scrollAnchorOffsetPX: 12,
            viewportHeightPX: 640,
            viewportWidthPX: 390,
            contentInsetTopPX: 8,
            contentInsetBottomPX: 16,
            lastVisibleTopID: nil,
            lastVisibleBottomID: nil,
            restoreFallbackReason: nil,
            clientStateJSON: "{}",
            lastViewedAtMS: 1000,
            updatedAtMS: 2000
        )
    }

    private func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }

    private static func diagnostics(
        totalFeedItemRowCount: Int = 0,
        sqlVisibleRowCount: Int = 0,
        excludedHiddenCount: Int = 0,
        excludedPendingNewCount: Int = 0,
        pendingNewIncludedCount: Int = 0,
        readStatePresent: Bool = false
    ) -> TimelineRepositoryStoreDiagnostics {
        TimelineRepositoryStoreDiagnostics(
            totalFeedItemRowCount: totalFeedItemRowCount,
            sqlVisibleRowCount: sqlVisibleRowCount,
            excludedHiddenCount: excludedHiddenCount,
            excludedPendingNewCount: excludedPendingNewCount,
            pendingNewIncludedCount: pendingNewIncludedCount,
            readStatePresent: readStatePresent,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresExternalMutation: false,
            performedLocalDBRead: true,
            resolveJobRowCount: 0,
            diagnosticRowCount: 0
        )
    }
}
