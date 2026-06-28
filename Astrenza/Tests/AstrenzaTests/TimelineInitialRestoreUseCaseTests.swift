import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineInitialRestoreUseCase")
struct TimelineInitialRestoreUseCaseTests {
    @Test("valid composed window produces stable initial snapshot plan")
    func validComposedWindowProducesStableInitialSnapshotPlan() throws {
        let composed = try composition(
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:middle", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
                row(itemKey: "note:oldest", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c")
            ],
            anchorItemKey: "note:middle"
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed,
            requestedAnchorItemKey: "note:middle"
        ))

        #expect(plan.snapshotPlan.reason == .initialRestore)
        #expect(plan.snapshotPlan.mutationStyle == .snapshot)
        #expect(plan.snapshotPlan.itemIDs.map(\.rawValue) == ["note:newest", "note:middle", "note:oldest"])
        #expect(plan.snapshotPlan.reconfigureIDs.isEmpty)
        #expect(plan.snapshotPlan.insertedIDs.isEmpty)
        #expect(plan.snapshotPlan.deletedIDs.isEmpty)
        #expect(plan.snapshotPlan.callsDataSourceApply == false)
        #expect(plan.snapshotPlan.snapshotMutationPlan.reason == .initialRestore)
        #expect(plan.snapshotPlan.snapshotMutationPlan.itemIDs == plan.snapshotPlan.itemIDs)
    }

    @Test("anchor present becomes protected anchor restore plan")
    func anchorPresentBecomesProtectedAnchorRestorePlan() throws {
        let composed = try composition(
            readState: readState(scrollAnchorItemKey: "note:anchor", scrollAnchorEventID: eventID("b")),
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:anchor", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:anchor"
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed,
            requestedAnchorItemKey: "note:anchor"
        ))

        #expect(plan.anchorPlan.requestedAnchorItemKey == "note:anchor")
        #expect(plan.anchorPlan.candidateItemKey == "note:anchor")
        #expect(plan.anchorPlan.anchorSource == .scrollAnchor)
        #expect(plan.anchorPlan.fallbackReason == .anchorFound)
        #expect(plan.anchorPlan.requiresAnchorRestoration)
        #expect(plan.restoreGateIntent == .protectAnchorRestore)
    }

    @Test("missing anchor falls back with existing fallback reason")
    func missingAnchorFallsBackWithExistingFallbackReason() throws {
        let composed = try composition(
            readState: readState(
                markerEventID: eventID("b"),
                markerSortAt: 200,
                scrollAnchorItemKey: "note:missing"
            ),
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:marker", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:missing"
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed,
            requestedAnchorItemKey: "note:missing"
        ))

        #expect(plan.anchorPlan.requestedAnchorItemKey == "note:missing")
        #expect(plan.anchorPlan.candidateItemKey == "note:marker")
        #expect(plan.anchorPlan.anchorSource == .readMarker)
        #expect(plan.anchorPlan.fallbackReason == .missingAnchorUsedMarker)
        #expect(plan.restoreGateIntent == .protectAnchorRestore)
    }

    @Test("empty local cache produces empty plan instead of failure")
    func emptyLocalCacheProducesEmptyPlanInsteadOfFailure() throws {
        let composed = try composition(rows: [], anchorItemKey: nil)

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.snapshotPlan.itemIDs.isEmpty)
        #expect(plan.anchorPlan.candidateItemKey == nil)
        #expect(plan.anchorPlan.anchorSource == .none)
        #expect(plan.restoreGateIntent == .emptyLocalCache)
        #expect(plan.diagnostics.inputRowCount == 0)
        #expect(plan.diagnostics.snapshotItemCount == 0)
        #expect(plan.issues.isEmpty)
    }

    @Test("repository issues are carried into restore diagnostics")
    func repositoryIssuesAreCarriedIntoRestoreDiagnostics() throws {
        let composed = try composition(
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

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.diagnostics.repositoryIssueDiagnostics.map(\.issue.kind) == [.missingAnchor, .hiddenAnchor])
        #expect(plan.diagnostics.boundaryIssues.compactMap(\.itemKey).sorted() == ["note:hidden", "note:missing"])
        #expect(plan.diagnostics.issueCount == 4)
        #expect(plan.issues.contains { $0.kind == .repositoryStoreIssue && $0.itemKey == "note:missing" })
        #expect(plan.issues.contains { $0.kind == .repositoryStoreIssue && $0.itemKey == "note:hidden" })
        #expect(plan.issues.contains { $0.kind == .boundaryIssue && $0.itemKey == "note:missing" })
        #expect(plan.issues.contains { $0.kind == .boundaryIssue && $0.itemKey == "note:hidden" })
    }

    @Test("diagnostics keep read marker and network wait inert")
    func diagnosticsKeepReadMarkerAndNetworkWaitInert() throws {
        let composed = try composition(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: "note:visible",
            diagnostics: Self.diagnostics(
                totalFeedItemRowCount: 4,
                sqlVisibleRowCount: 1,
                excludedHiddenCount: 1,
                excludedPendingNewCount: 2,
                readStatePresent: true
            )
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.diagnostics.readMarkerChanged == false)
        #expect(plan.diagnostics.requiresNetworkWork == false)
        #expect(plan.diagnostics.requiresDBWork == false)
        #expect(plan.diagnostics.localDBReadWork == true)
        #expect(plan.diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(plan.diagnostics.pendingNewExcludedCount == 2)
        #expect(plan.diagnostics.hiddenExcludedCount == 1)
    }

    @Test("pending and hidden rows remain excluded from visible snapshot")
    func pendingAndHiddenRowsRemainExcludedFromVisibleSnapshot() throws {
        let composed = try composition(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:pending", sourceEventID: eventID("b"), pendingNew: true, sortAt: 200, tieBreakID: "b"),
                row(itemKey: "note:hidden", sourceEventID: eventID("c"), hiddenReason: "muted", sortAt: 100, tieBreakID: "c")
            ],
            anchorItemKey: "note:visible",
            diagnostics: Self.diagnostics(totalFeedItemRowCount: 3, sqlVisibleRowCount: 1, excludedHiddenCount: 1, excludedPendingNewCount: 1)
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.snapshotPlan.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(!plan.snapshotPlan.itemIDs.contains(TimelineEntryID(rawValue: "note:pending")))
        #expect(!plan.snapshotPlan.itemIDs.contains(TimelineEntryID(rawValue: "note:hidden")))
        #expect(plan.diagnostics.pendingNewExcludedCount == 1)
        #expect(plan.diagnostics.hiddenExcludedCount == 1)
    }

    @Test("missing target quote and repost rows remain in initial snapshot")
    func missingTargetQuoteAndRepostRowsRemainInInitialSnapshot() throws {
        let composed = try composition(
            rows: [
                row(itemKey: "quote:missing", sourceEventID: eventID("d"), subjectEventID: nil, reason: .quote, sortAt: 300, tieBreakID: "d"),
                row(itemKey: "repost:missing", sourceEventID: eventID("e"), subjectEventID: nil, reason: .repost, sortAt: 200, tieBreakID: "e")
            ],
            anchorItemKey: "quote:missing"
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.snapshotPlan.itemIDs.map(\.rawValue) == ["quote:missing", "repost:missing"])
        let fallbackCapabilities = composed.initialWindow.visibleRows.map(\.isMissingTargetFallbackCapable)
        #expect(fallbackCapabilities == [true, true])
    }

    @Test("invalid input returns recoverable failure plan")
    func invalidInputReturnsRecoverableFailurePlan() {
        let invalidRow = TimelineRepositoryFeedItemDraftRow(
            itemKey: "note:invalid",
            sourceEventID: EventID(hex: eventID("a")),
            reason: .author,
            sortAt: nil,
            tieBreakID: "a"
        )
        let invalidDraft = TimelineInitialWindowDraft(
            feedID: FeedID(rawValue: 10),
            visibleRows: [invalidRow],
            visibleEntryIDs: [],
            anchorItemKey: "note:invalid",
            anchorSource: .scrollAnchor,
            diagnostics: boundaryDiagnostics(
                inputCount: 1,
                visibleOutputCount: 1,
                fallbackReason: .anchorFound,
                fallbackItemKey: "note:invalid"
            ),
            issues: []
        )
        let composed = TimelineRepositoryStoreWindowComposition(
            draftRows: [invalidRow],
            readState: nil,
            initialWindow: invalidDraft,
            storeIssueDiagnostics: [],
            compositionDiagnostics: compositionDiagnostics(inputRowCount: 1, snapshotRowCount: 1),
            issues: []
        )

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))

        #expect(plan.restoreGateIntent == .recoverableFailure)
        #expect(plan.snapshotPlan.itemIDs.isEmpty)
        #expect(plan.issues.contains { $0.kind == .invalidSnapshotEntryID && $0.itemKey == "note:invalid" })
    }

    @Test("restore plan diagnostics can be recorded without network wait")
    func restorePlanDiagnosticsCanBeRecordedWithoutNetworkWait() throws {
        let composed = try composition(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: "note:visible"
        )
        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: composed
        ))
        let recorder = TimelineDiagnosticsRecorder()

        let diagnostics = recorder.recordRestoreGateDiagnostics(
            plan.restoreGateDiagnostics(timestampMS: 1_735_000_000_000)
        )

        #expect(diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(diagnostics.readMarkerChanged == false)
        #expect(diagnostics.requiresNetworkWork == false)
        #expect(diagnostics.requiresDBWork == false)
        #expect(recorder.export().summary.restoreGateMetrics.networkWaitedBeforeInteractiveScrollViolationCount == 0)
    }

    @Test("restore use case models are Codable Equatable and Sendable")
    func restoreUseCaseModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineInitialRestoreInput.self)
        assertSendable(TimelineInitialRestorePlan.self)
        assertSendable(TimelineInitialRestoreIssue.self)
        assertSendable(TimelineInitialRestoreDiagnostics.self)
        assertSendable(TimelineInitialRestoreSnapshotPlan.self)
        assertSendable(TimelineInitialRestoreAnchorPlan.self)

        let plan = TimelineInitialRestoreUseCase.makePlan(input: TimelineInitialRestoreInput(
            composition: try composition(
                rows: [
                    row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
                ],
                anchorItemKey: "note:visible"
            )
        ))

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(TimelineInitialRestorePlan.self, from: data)

        #expect(decoded == plan)
    }

    private func composition(
        readState: TimelineRepositoryReadStateRow? = nil,
        rows: [TimelineRepositoryFeedItemRow],
        anchorItemKey: String?,
        issues: [TimelineRepositoryStoreIssue] = [],
        diagnostics: TimelineRepositoryStoreDiagnostics = Self.diagnostics()
    ) throws -> TimelineRepositoryStoreWindowComposition {
        try TimelineRepositoryStoreWindowComposer.compose(
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

    private func boundaryDiagnostics(
        inputCount: Int,
        visibleOutputCount: Int,
        fallbackReason: TimelineRepositoryBoundaryFallbackReason,
        fallbackItemKey: String?
    ) -> TimelineRepositoryBoundaryDiagnostics {
        TimelineRepositoryBoundaryDiagnostics(
            inputCount: inputCount,
            visibleOutputCount: visibleOutputCount,
            excludedPendingNewCount: 0,
            pendingNewIncludedCount: 0,
            pendingNewInclusionReason: nil,
            excludedHiddenCount: 0,
            collapsedCount: 0,
            duplicateItemKeyCount: 0,
            fallbackReason: fallbackReason,
            fallbackItemKey: fallbackItemKey,
            requestedAnchorItemKey: nil,
            requestedAnchorEventID: nil,
            requestedMarkerEventID: nil,
            requestedLastVisibleTopItemKey: nil,
            requestedLastVisibleBottomItemKey: nil,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWork: false
        )
    }

    private func compositionDiagnostics(
        inputRowCount: Int,
        snapshotRowCount: Int
    ) -> TimelineRepositoryStoreWindowCompositionDiagnostics {
        TimelineRepositoryStoreWindowCompositionDiagnostics(
            totalFeedItemRowCount: inputRowCount,
            sqlVisibleRowCount: snapshotRowCount,
            excludedHiddenCount: 0,
            excludedPendingNewCount: 0,
            pendingNewIncludedCount: 0,
            readStatePresent: false,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWork: false,
            performedLocalDBRead: true,
            requiresExternalMutation: false,
            resolveJobRowCount: 0,
            diagnosticRowCount: 0,
            storeIssueCount: 0,
            boundaryIssueCount: 0
        )
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
