import AstrenzaCore
import Foundation
import Testing
import UIKit
@testable import Astrenza

@MainActor
@Suite("TimelineInitialRestoreSnapshotCoordinatorHarness")
struct TimelineInitialRestoreSnapshotCoordinatorHarnessTests {
    @Test("valid initial restore applies snapshot item IDs through coordinator path")
    func validInitialRestoreAppliesSnapshotItemIDsThroughCoordinatorPath() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:middle", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
                row(itemKey: "note:oldest", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c")
            ],
            anchorItemKey: "note:middle"
        )
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.itemIDs.map(\.rawValue) == ["note:newest", "note:middle", "note:oldest"])
        #expect(result.itemIDs == plan.snapshotPlan.itemIDs)
        #expect(result.expectation.snapshot.reason == .initialRestore)
        #expect(result.expectation.snapshot.mutationStyle == .snapshot)
        #expect(result.expectation.snapshot.reconfigureIDs.isEmpty)
        #expect(result.expectation.snapshot.insertedIDs.isEmpty)
        #expect(result.expectation.snapshot.deletedIDs.isEmpty)
        #expect(result.expectation.expectsDataSourceApply == false)
        #expect(result.expectation.expectsInsertOrDeleteMutation == false)
        #expect(result.expectation.expectsResolveReconfigure == false)
        #expect(result.mutationRecord.mutationReason == .initialRestore)
        #expect(result.mutationRecord.readMarkerChanged == false)
        #expect(result.restoreGateDiagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
    }

    @Test("anchor present plan keeps anchor candidate identity")
    func anchorPresentPlanKeepsAnchorCandidateIdentity() throws {
        let anchorID = eventID("b")
        let plan = try restorePlan(
            readState: readState(scrollAnchorItemKey: "note:anchor", scrollAnchorEventID: anchorID),
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:anchor", sourceEventID: anchorID, sortAt: 200, tieBreakID: "b")
            ],
            anchorItemKey: "note:anchor",
            requestedAnchorItemKey: "note:anchor"
        )
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.expectation.anchor.requestedAnchorItemKey == "note:anchor")
        #expect(result.expectation.anchor.restoreCandidateItemKey == "note:anchor")
        #expect(result.expectation.anchor.restoreCandidateEntryID?.rawValue == "note:anchor")
        #expect(result.expectation.anchor.fallbackReason == .anchorFound)
        #expect(result.expectation.anchor.requiresAnchorRestoration)
        #expect(result.expectation.anchor.restoreGateIntent == .protectAnchorRestore)
        #expect(result.mutationRecord.readMarkerChanged == false)
    }

    @Test("missing anchor plan propagates fallback reason")
    func missingAnchorPlanPropagatesFallbackReason() throws {
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
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.expectation.anchor.requestedAnchorItemKey == "note:missing")
        #expect(result.expectation.anchor.restoreCandidateItemKey == "note:marker")
        #expect(result.expectation.anchor.fallbackReason == .missingAnchorUsedMarker)
        #expect(result.expectation.diagnostics.fallbackReason == .missingAnchorUsedMarker)
        #expect(result.restoreGateDiagnostics.readMarkerChanged == false)
        #expect(result.restoreGateDiagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
    }

    @Test("empty local cache applies empty snapshot and empty restore gate expectation")
    func emptyLocalCacheAppliesEmptySnapshotAndEmptyRestoreGateExpectation() throws {
        let plan = try restorePlan(rows: [], anchorItemKey: nil)
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.itemIDs.isEmpty)
        #expect(result.expectation.snapshot.itemIDs.isEmpty)
        #expect(result.expectation.anchor.restoreCandidateItemKey == nil)
        #expect(result.expectation.anchor.requiresAnchorRestoration == false)
        #expect(result.expectation.anchor.restoreGateIntent == .emptyLocalCache)
        #expect(result.expectation.diagnostics.snapshotItemCount == 0)
        #expect(result.mutationRecord.readMarkerChanged == false)
    }

    @Test("repository issue diagnostics are preserved")
    func repositoryIssueDiagnosticsArePreserved() throws {
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
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.expectation.diagnostics.issueCount == 4)
        #expect(result.expectation.diagnostics.repositoryIssueCount == 2)
        #expect(result.expectation.diagnostics.boundaryIssueCount == 2)
        #expect(result.expectation.diagnostics.repositoryIssueDiagnostics.map(\.issue.kind) == [.missingAnchor, .hiddenAnchor])
        #expect(result.expectation.diagnostics.boundaryIssues.compactMap(\.itemKey).sorted() == ["note:hidden", "note:missing"])
        #expect(result.diagnosticsExport.summary.restoreGateMetrics.networkWaitedBeforeInteractiveScrollViolationCount == 0)
    }

    @Test("pending and hidden rows stay out while missing target quote and repost stay visible")
    func pendingAndHiddenRowsStayOutWhileMissingTargetQuoteAndRepostStayVisible() throws {
        let plan = try restorePlan(
            rows: [
                row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 400, tieBreakID: "a"),
                row(itemKey: "quote:missing", sourceEventID: eventID("b"), subjectEventID: nil, reason: .quote, sortAt: 300, tieBreakID: "b"),
                row(itemKey: "repost:missing", sourceEventID: eventID("c"), subjectEventID: nil, reason: .repost, sortAt: 200, tieBreakID: "c"),
                row(itemKey: "note:pending", sourceEventID: eventID("d"), pendingNew: true, sortAt: 500, tieBreakID: "d"),
                row(itemKey: "note:hidden", sourceEventID: eventID("e"), hiddenReason: "muted", sortAt: 100, tieBreakID: "e")
            ],
            anchorItemKey: "note:visible",
            diagnostics: Self.diagnostics(totalFeedItemRowCount: 5, sqlVisibleRowCount: 3, excludedHiddenCount: 1, excludedPendingNewCount: 1)
        )
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        let result = harness.applyInitialRestore(plan)

        #expect(result.itemIDs.map(\.rawValue) == ["note:visible", "quote:missing", "repost:missing"])
        #expect(!result.itemIDs.contains(TimelineEntryID(rawValue: "note:pending")))
        #expect(!result.itemIDs.contains(TimelineEntryID(rawValue: "note:hidden")))
        #expect(result.expectation.diagnostics.pendingNewExcludedCount == 1)
        #expect(result.expectation.diagnostics.hiddenExcludedCount == 1)
        #expect(result.expectation.snapshot.insertedIDs.isEmpty)
        #expect(result.expectation.snapshot.deletedIDs.isEmpty)
        #expect(result.expectation.snapshot.reconfigureIDs.isEmpty)
    }

    @Test("runtime mutation records fallback without read marker movement")
    func runtimeMutationRecordsFallbackWithoutReadMarkerMovement() throws {
        let removedID = TimelineEntryID(rawValue: "note:removed")
        let survivorID = TimelineEntryID(rawValue: "note:survivor")
        let plan = try restorePlan(
            rows: [
                row(itemKey: survivorID.rawValue, sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
            ],
            anchorItemKey: survivorID.rawValue
        )
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()
        harness.seedVisibleSnapshot(itemIDs: [removedID])

        let result = harness.applyInitialRestore(plan)

        #expect(result.itemIDs == [survivorID])
        #expect(result.mutationRecord.fallbackReason == TimelineRestoreFallbackReason(
            kind: .anchorItemMissing,
            anchorItemKey: removedID.rawValue
        ))
        #expect(result.mutationRecord.readMarkerChanged == false)
    }

    @Test("harness stays offscreen and source keeps coordinator boundary")
    func harnessStaysOffscreenAndSourceKeepsCoordinatorBoundary() throws {
        let harness = TimelineInitialRestoreSnapshotCoordinatorHarness()

        #expect(harness.isAttachedToWindow == false)

        let coordinatorSource = try sourceFile(named: "TimelineSnapshotCoordinator.swift")
        let nonCoordinatorSource = try [
            "TimelineCollectionViewController.swift",
            "TimelineSurfaceDependencyContainer.swift",
            "TimelineInitialRestoreUseCase.swift",
            "TimelineInitialRestoreCoordinatorAdapter.swift",
            testFileName
        ]
            .map(sourceFile(named:))
            .joined(separator: "\n")
        let directApplyPattern = "dataSource." + "apply"
        let removeItemsPattern = "delete" + "Items"
        let addItemsPattern = "insert" + "Items"
        let rootPattern = "Astrenza" + "RootView"
        let homePattern = "Home" + "TimelineView"
        let splashPattern = "Astrenza" + "StartupSplashView"
        let legacyFeedPattern = "Timeline" + "FeedView"

        #expect(coordinatorSource.contains(directApplyPattern))
        #expect(!nonCoordinatorSource.contains(directApplyPattern))
        #expect(!nonCoordinatorSource.contains(removeItemsPattern))
        #expect(!nonCoordinatorSource.contains(addItemsPattern))
        #expect(!nonCoordinatorSource.contains(rootPattern))
        #expect(!nonCoordinatorSource.contains(homePattern))
        #expect(!nonCoordinatorSource.contains(splashPattern))
        #expect(!nonCoordinatorSource.contains(legacyFeedPattern))
    }

    private func restorePlan(
        readState: TimelineRepositoryReadStateRow? = nil,
        rows: [TimelineRepositoryFeedItemRow],
        anchorItemKey: String?,
        requestedAnchorItemKey: String? = nil,
        issues: [TimelineRepositoryStoreIssue] = [],
        diagnostics: TimelineRepositoryStoreDiagnostics = TimelineInitialRestoreSnapshotCoordinatorHarnessTests.diagnostics()
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
            requestedAnchorItemKey: requestedAnchorItemKey
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

    private func eventID(_ letter: Character) -> String {
        String(repeating: String(letter), count: 64)
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

    private var testFileName: String {
        URL(fileURLWithPath: #filePath).lastPathComponent
    }

    private func sourceFile(named fileName: String) throws -> String {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url: URL
        if fileName == testFileName {
            url = testDirectory.appendingPathComponent(fileName)
        } else {
            url = testDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private struct TimelineInitialRestoreSnapshotCoordinatorHarnessResult {
    var itemIDs: [TimelineEntryID]
    var expectation: TimelineInitialRestoreCoordinatorExpectation
    var mutationRecord: TimelineSnapshotMutationRecord
    var restoreGateDiagnostics: TimelineRestoreGateDiagnostics
    var diagnosticsExport: TimelineDiagnosticsExport
}

@MainActor
private final class TimelineInitialRestoreSnapshotCoordinatorHarness {
    private let collectionView: TimelineInitialRestoreSnapshotHarnessCollectionView
    private let coordinator: TimelineSnapshotCoordinator
    private let diagnosticsRecorder: TimelineDiagnosticsRecorder
    private let timestampMS: Int64

    init(
        accountID: AccountID = .debug,
        feedID: FeedID = .debugHome,
        timelineKey: TimelineKey = .home,
        timestampMS: Int64 = 1_735_000_000_000
    ) {
        let collectionView = TimelineInitialRestoreSnapshotHarnessCollectionView()
        let diagnosticsRecorder = TimelineDiagnosticsRecorder()
        let coordinator = TimelineSnapshotCoordinator(
            dataSource: Self.makeDataSource(for: collectionView),
            positionRecorder: TimelinePositionRecorder(
                accountID: accountID,
                feedID: feedID,
                timelineKey: timelineKey
            ),
            visibleRangeTracker: TimelineVisibleRangeTracker(),
            diagnosticsRecorder: diagnosticsRecorder
        )

        self.collectionView = collectionView
        self.coordinator = coordinator
        self.diagnosticsRecorder = diagnosticsRecorder
        self.timestampMS = timestampMS
    }

    var isAttachedToWindow: Bool {
        collectionView.window != nil
    }

    func seedVisibleSnapshot(itemIDs: [TimelineEntryID]) {
        _ = coordinator.applyPreservingPosition(
            itemIDs: itemIDs,
            reason: .debugReload,
            in: collectionView,
            animatingDifferences: false
        )
        collectionView.installVisibleItemFrames(count: itemIDs.count)
    }

    func applyInitialRestore(
        _ plan: TimelineInitialRestorePlan
    ) -> TimelineInitialRestoreSnapshotCoordinatorHarnessResult {
        let expectation = TimelineInitialRestoreCoordinatorAdapter.expectation(
            for: plan,
            restoreGateTimestampMS: timestampMS
        )
        let record = coordinator.applyPreservingPosition(
            itemIDs: expectation.snapshot.itemIDs,
            reason: expectation.snapshot.reason,
            in: collectionView,
            reconfigureIDs: expectation.snapshot.reconfigureIDs,
            animatingDifferences: false
        )
        let restoreGateDiagnostics = diagnosticsRecorder.recordRestoreGateDiagnostics(
            expectation.diagnostics.restoreGateDiagnostics
        )

        return TimelineInitialRestoreSnapshotCoordinatorHarnessResult(
            itemIDs: coordinator.currentItemIDs,
            expectation: expectation,
            mutationRecord: record,
            restoreGateDiagnostics: restoreGateDiagnostics,
            diagnosticsExport: diagnosticsRecorder.export()
        )
    }

    private static func makeDataSource(
        for collectionView: UICollectionView
    ) -> TimelineSnapshotCoordinator.DataSource {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        return TimelineSnapshotCoordinator.DataSource(collectionView: collectionView) { collectionView, indexPath, _ in
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }
}

@MainActor
private final class TimelineInitialRestoreSnapshotHarnessCollectionView: UICollectionView {
    private var diagnosticVisibleIndexPaths: [IndexPath] = []
    private var diagnosticAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 72)
        super.init(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480),
            collectionViewLayout: layout
        )
        contentSize = CGSize(width: 320, height: 1_000)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var indexPathsForVisibleItems: [IndexPath] {
        diagnosticVisibleIndexPaths
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        diagnosticAttributes[indexPath]
    }

    func installVisibleItemFrames(count: Int) {
        diagnosticVisibleIndexPaths = (0..<count).map { IndexPath(item: $0, section: 0) }
        diagnosticAttributes = Dictionary(
            uniqueKeysWithValues: diagnosticVisibleIndexPaths.map { indexPath in
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(
                    x: 0,
                    y: CGFloat(indexPath.item * 80),
                    width: 320,
                    height: 72
                )
                return (indexPath, attributes)
            }
        )
        contentSize = CGSize(width: 320, height: max(1_000, count * 80))
    }
}
