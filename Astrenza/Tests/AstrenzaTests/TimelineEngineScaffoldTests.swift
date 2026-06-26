import Foundation
import Testing
import UIKit
@testable import Astrenza

@Suite("TimelineEngine scaffold")
struct TimelineEngineScaffoldTests {
    @Test("App-hosted XCTest disables startup network without forcing mock timeline")
    func appHostedXCTestDisablesStartupNetworkWithoutForcingMockTimeline() {
        let launchMode = AstrenzaLaunchMode(
            arguments: ["/tmp/Astrenza.app/Astrenza"],
            environment: ["XCTestConfigurationFilePath": "/tmp/AstrenzaTests.xctestconfiguration"],
            userDefaults: nil
        )

        #expect(launchMode.disablesNetworkStartup)
        #expect(!launchMode.usesMockTimeline)
    }

    @Test("Production launch keeps startup network enabled unless explicitly disabled")
    func productionLaunchKeepsStartupNetworkEnabledUnlessExplicitlyDisabled() {
        let productionLaunchMode = AstrenzaLaunchMode(
            arguments: ["/Applications/Astrenza.app/Astrenza"],
            environment: [:],
            userDefaults: nil
        )
        let explicitlyDisabledLaunchMode = AstrenzaLaunchMode(
            arguments: ["-AstrenzaDisableNetworkStartup"],
            environment: [:],
            userDefaults: nil
        )

        #expect(!productionLaunchMode.disablesNetworkStartup)
        #expect(explicitlyDisabledLaunchMode.disablesNetworkStartup)
    }

    @Test("TimelineEntryID identity is stable item key only")
    func timelineEntryIDIdentityIsStableItemKeyOnly() throws {
        let eventID = EventID(hex: String(repeating: "a", count: 64))
        let first = TimelineEntryID(
            rawValue: "home:100:a",
            sourceEventID: eventID,
            sortAt: 100,
            tieBreakID: "a"
        )
        let second = TimelineEntryID(
            rawValue: "home:100:a",
            sourceEventID: EventID(hex: String(repeating: "b", count: 64)),
            sortAt: 200,
            tieBreakID: "b"
        )

        #expect(first == second)
        #expect(Set([first, second]).count == 1)

        let data = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(TimelineEntryID.self, from: data)

        #expect(decoded.rawValue == first.rawValue)
        #expect(decoded.sourceEventID == eventID)
        #expect(decoded.sortAt == 100)
        #expect(decoded.tieBreakID == "a")
    }

    @Test("TimelineVisualAnchor is stable item key based and codable")
    func timelineVisualAnchorIsStableItemKeyBasedAndCodable() throws {
        let anchor = TimelineVisualAnchor(
            accountID: AccountID(rawValue: "account-a"),
            feedID: FeedID(rawValue: 1),
            timelineKey: TimelineKey(rawValue: "home"),
            anchorItemKey: "home:100:a",
            anchorEventID: EventID(hex: String(repeating: "c", count: 64)),
            anchorSortAt: 100,
            anchorTieBreakID: "a",
            cellTopDeltaFromViewportTop: -12.5,
            viewportHeight: 844,
            viewportWidth: 390,
            contentInsetTop: 0,
            contentInsetBottom: 34,
            lastVisibleTopItemKey: "home:100:a",
            lastVisibleBottomItemKey: "home:096:d",
            markerEventID: nil,
            markerSortAt: nil,
            capturedAtMS: 1_735_000_000_000,
            schemaVersion: 1
        )

        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(TimelineVisualAnchor.self, from: data)

        #expect(decoded == anchor)
    }

    @Test("Snapshot and resolve reasons never advance read marker")
    func snapshotAndResolveReasonsNeverAdvanceReadMarker() throws {
        let reason = TimelineSnapshotReason.reconfigure(.media)

        #expect(!TimelineSnapshotReason.initialRestore.advancesReadMarker)
        #expect(!TimelineSnapshotReason.userInsertedPendingNew.advancesReadMarker)
        #expect(!reason.advancesReadMarker)
        #expect(ResolveApplyReason.media.snapshotReason == reason)

        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(TimelineSnapshotReason.self, from: data)

        #expect(decoded == reason)
    }

    @Test("Resolve coordinator produces reconfigure intent for existing IDs only")
    func resolveCoordinatorProducesReconfigureIntentForExistingIDsOnly() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let resolved = [
            TimelineEntryID(rawValue: "home:099:b"),
            TimelineEntryID(rawValue: "home:098:c"),
            TimelineEntryID(rawValue: "home:099:b")
        ]

        let intent = TimelineResolveApplyCoordinator().reconfigureIntent(
            resolvedIDs: resolved,
            existingIDs: existing,
            reason: .profile
        )

        #expect(intent.reason == .profile)
        #expect(intent.mutationStyle == .reconfigure)
        #expect(intent.entryIDs == [TimelineEntryID(rawValue: "home:099:b")])
        #expect(intent.missingIDs == [TimelineEntryID(rawValue: "home:098:c")])
        #expect(intent.insertedIDs.isEmpty)
        #expect(intent.deletedIDs.isEmpty)
    }

    @Test("Position recorder selects anchor by stable ID and viewport delta")
    func positionRecorderSelectsAnchorByStableIDAndViewportDelta() throws {
        let frames = [
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:100:a"), minY: 80, maxY: 150),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:099:b"), minY: 160, maxY: 240),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:098:c"), minY: 250, maxY: 320)
        ]

        let selection = try #require(TimelinePositionRecorder.anchorSelection(
            visibleFrames: frames,
            viewportTop: 100
        ))

        #expect(selection.anchorItemKey == "home:100:a")
        #expect(selection.cellTopDeltaFromViewportTop == -20)
        #expect(selection.lastVisibleTopItemKey == "home:100:a")
        #expect(selection.lastVisibleBottomItemKey == "home:098:c")
    }

    @Test("Position recorder chooses first visible candidate at or below viewport top")
    func positionRecorderChoosesFirstVisibleCandidateAtOrBelowViewportTop() throws {
        let frames = [
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:101:above"), minY: 20, maxY: 99),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:100:anchor"), minY: 120, maxY: 180),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:099:tail"), minY: 190, maxY: 260)
        ]

        let selection = try #require(TimelinePositionRecorder.chooseAnchorCandidate(
            visibleFrames: frames,
            viewportTop: 100
        ))

        #expect(selection.anchorItemKey == "home:100:anchor")
        #expect(selection.cellTopDeltaFromViewportTop == 20)
        #expect(selection.lastVisibleTopItemKey == "home:100:anchor")
        #expect(selection.lastVisibleBottomItemKey == "home:099:tail")
    }

    @Test("Position recorder computes unclamped restore content offset target")
    func positionRecorderComputesUnclampedRestoreContentOffsetTarget() {
        let target = TimelinePositionRecorder.computeContentOffsetTarget(
            anchorFrameMinY: 240,
            savedCellTopDeltaFromViewportTop: -12,
            adjustedContentInsetTop: 20,
            boundsHeight: 400,
            contentHeight: 1_000,
            adjustedContentInsetBottom: 30
        )

        #expect(target == 232)
    }

    @Test("Position recorder clamps restore offset to valid scroll range")
    func positionRecorderClampsRestoreOffsetToValidScrollRange() {
        let top = TimelinePositionRecorder.clampContentOffsetTarget(
            -200,
            adjustedContentInsetTop: 20,
            boundsHeight: 400,
            contentHeight: 1_000,
            adjustedContentInsetBottom: 30
        )
        let bottom = TimelinePositionRecorder.clampContentOffsetTarget(
            900,
            adjustedContentInsetTop: 20,
            boundsHeight: 400,
            contentHeight: 1_000,
            adjustedContentInsetBottom: 30
        )

        #expect(top == -20)
        #expect(bottom == 630)
    }

    @MainActor
    @Test("Position recorder restore reports fallback when anchor item is missing")
    func positionRecorderRestoreReportsFallbackWhenAnchorItemIsMissing() {
        let collectionView = RestoreDiagnosticsCollectionView()
        let anchor = Self.anchor(itemKey: "home:100:a", delta: -8)

        let result = Self.positionRecorder().restore(anchor: anchor, in: collectionView) { _ in
            nil
        }

        #expect(result == .skipped(reason: TimelineRestoreFallbackReason(
            kind: .anchorItemMissing,
            anchorItemKey: "home:100:a"
        )))
        #expect(result.fallbackReason?.kind == .anchorItemMissing)
        #expect(result.fallbackReason?.anchorItemKey == "home:100:a")
    }

    @MainActor
    @Test("Position recorder restore reports fallback when layout attributes stay missing")
    func positionRecorderRestoreReportsFallbackWhenLayoutAttributesStayMissing() {
        let collectionView = RestoreDiagnosticsCollectionView()
        let indexPath = IndexPath(item: 0, section: 0)
        let anchor = Self.anchor(itemKey: "home:100:a", delta: -8)

        let result = Self.positionRecorder().restore(anchor: anchor, in: collectionView) { _ in
            indexPath
        }

        #expect(result == .failed(reason: TimelineRestoreFallbackReason(
            kind: .layoutAttributesMissing,
            anchorItemKey: "home:100:a"
        )))
        #expect(collectionView.scrollRequests == [indexPath])
    }

    @MainActor
    @Test("Position recorder restore records fallback when layout attributes recover after scroll")
    func positionRecorderRestoreRecordsFallbackWhenLayoutAttributesRecoverAfterScroll() {
        let collectionView = RestoreDiagnosticsCollectionView()
        let indexPath = IndexPath(item: 0, section: 0)
        collectionView.attributesInstalledAfterScroll[indexPath] = Self.attributes(
            indexPath: indexPath,
            minY: 80,
            height: 72
        )
        let anchor = Self.anchor(itemKey: "home:100:a", delta: -8)

        let result = Self.positionRecorder().restore(anchor: anchor, in: collectionView) { _ in
            indexPath
        }

        #expect(result == .attemptedFallback(reason: TimelineRestoreFallbackReason(
            kind: .layoutAttributesMissing,
            anchorItemKey: "home:100:a"
        )))
        #expect(collectionView.scrollRequests == [indexPath])
    }

    @Test("Position recorder computes structured anchor delta for same item")
    func positionRecorderComputesStructuredAnchorDeltaForSameItem() throws {
        let before = Self.anchor(itemKey: "home:100:a", delta: -8)
        let after = Self.anchor(itemKey: "home:100:a", delta: -5)

        let delta = try #require(TimelinePositionRecorder.computeAnchorDelta(before: before, after: after))

        #expect(delta.anchorItemKey == "home:100:a")
        #expect(delta.beforeCellTopDeltaFromViewportTop == -8)
        #expect(delta.afterCellTopDeltaFromViewportTop == -5)
        #expect(delta.deltaPoints == 3)
    }

    @Test("Snapshot coordinator filters reconfigure IDs without mutating item identity")
    func snapshotCoordinatorFiltersReconfigureIDsWithoutMutatingItemIdentity() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let plan = TimelineSnapshotCoordinator.makeMutationPlan(
            currentIDs: existing,
            proposedIDs: existing,
            reconfigureIDs: [
                TimelineEntryID(rawValue: "home:099:b"),
                TimelineEntryID(rawValue: "home:098:c")
            ],
            reason: .reconfigure(.quote)
        )

        #expect(plan.itemIDs == existing)
        #expect(plan.reconfigureIDs == [TimelineEntryID(rawValue: "home:099:b")])
        #expect(plan.insertedIDs.isEmpty)
        #expect(plan.deletedIDs.isEmpty)
    }

    @Test("Snapshot coordinator creates codable mutation record with read marker unchanged by default")
    func snapshotCoordinatorCreatesCodableMutationRecordWithReadMarkerUnchangedByDefault() throws {
        let before = Self.anchor(itemKey: "home:100:a", delta: -8)
        let after = Self.anchor(itemKey: "home:100:a", delta: -6)
        let visibleBefore = [TimelineEntryID(rawValue: "home:100:a")]
        let visibleAfter = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]

        let record = TimelineSnapshotCoordinator.makeMutationRecord(
            reason: .gapFilled,
            anchorBefore: before,
            anchorAfter: after,
            visibleIDsBefore: visibleBefore,
            visibleIDsAfter: visibleAfter,
            timestampMS: 1_735_000_000_000
        )

        #expect(record.mutationReason == .gapFilled)
        #expect(record.anchorBefore?.anchorItemKey == "home:100:a")
        #expect(record.anchorAfter?.anchorItemKey == "home:100:a")
        #expect(record.anchorDelta?.deltaPoints == 2)
        #expect(record.visibleIDsBefore == visibleBefore)
        #expect(record.visibleIDsAfter == visibleAfter)
        #expect(record.timestampMS == 1_735_000_000_000)
        #expect(record.fallbackReason == nil)
        #expect(record.readMarkerChanged == false)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TimelineSnapshotMutationRecord.self, from: data)

        #expect(decoded == record)
    }

    @MainActor
    @Test("Snapshot coordinator records restore fallback reason from runtime restore")
    func snapshotCoordinatorRecordsRestoreFallbackReasonFromRuntimeRestore() throws {
        let anchorID = TimelineEntryID(rawValue: "home:100:a")
        let survivingID = TimelineEntryID(rawValue: "home:099:b")
        let indexPath = IndexPath(item: 0, section: 0)
        let collectionView = RestoreDiagnosticsCollectionView()
        collectionView.diagnosticVisibleIndexPaths = [indexPath]
        collectionView.diagnosticAttributes[indexPath] = Self.attributes(
            indexPath: indexPath,
            minY: 80,
            height: 72
        )
        let diagnosticsRecorder = TimelineDiagnosticsRecorder()
        let coordinator = TimelineSnapshotCoordinator(
            dataSource: Self.dataSource(for: collectionView),
            positionRecorder: Self.positionRecorder(),
            visibleRangeTracker: TimelineVisibleRangeTracker(),
            diagnosticsRecorder: diagnosticsRecorder
        )

        _ = coordinator.applyPreservingPosition(
            itemIDs: [anchorID, survivingID],
            reason: .initialRestore,
            in: collectionView,
            animatingDifferences: false
        )
        let record = coordinator.applyPreservingPosition(
            itemIDs: [survivingID],
            reason: .olderPageLoaded,
            in: collectionView,
            animatingDifferences: false
        )

        #expect(record.fallbackReason == TimelineRestoreFallbackReason(
            kind: .anchorItemMissing,
            anchorItemKey: "home:100:a"
        ))
        #expect(record.readMarkerChanged == false)
        #expect(diagnosticsRecorder.records.last == record)
    }

    @Test("Restore fallback reason is codable and equatable")
    func restoreFallbackReasonIsCodableAndEquatable() throws {
        let reason = TimelineRestoreFallbackReason(
            kind: .anchorItemMissing,
            anchorItemKey: "home:100:a"
        )

        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(TimelineRestoreFallbackReason.self, from: data)

        #expect(decoded == reason)
    }

    @Test("Restore result carries codable fallback reason")
    func restoreResultCarriesCodableFallbackReason() throws {
        let result = TimelineRestoreResult.failed(reason: TimelineRestoreFallbackReason(
            kind: .layoutAttributesMissing,
            anchorItemKey: "home:100:a"
        ))

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TimelineRestoreResult.self, from: data)

        #expect(decoded == result)
        #expect(decoded.fallbackReason == TimelineRestoreFallbackReason(
            kind: .layoutAttributesMissing,
            anchorItemKey: "home:100:a"
        ))
    }

    @Test("Restore gate metric placeholder is codable")
    func restoreGateMetricPlaceholderIsCodable() throws {
        let metric = TimelineRestoreGateMetric(
            stage: .anchorRestoring,
            durationMS: 12,
            timestampMS: 1_735_000_000_123,
            exceededBudget: false
        )

        let data = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(TimelineRestoreGateMetric.self, from: data)

        #expect(decoded == metric)
    }

    @Test("Snapshot coordinator identifies reconfigure-only mutations")
    func snapshotCoordinatorIdentifiesReconfigureOnlyMutations() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let plan = TimelineSnapshotCoordinator.makeMutationPlan(
            currentIDs: existing,
            proposedIDs: existing,
            reconfigureIDs: [TimelineEntryID(rawValue: "home:099:b")],
            reason: .reconfigure(.media)
        )

        #expect(TimelineSnapshotCoordinator.isReconfigureOnlyMutation(plan))
    }

    @Test("Pending new insertion requires explicit user insertion reason")
    func pendingNewInsertionRequiresExplicitUserInsertionReason() {
        let pendingID = TimelineEntryID(rawValue: "home:pending:new")

        #expect(TimelineSnapshotCoordinator.pendingNewInsertionDecision(
            pendingNewIDs: [pendingID],
            reason: .userInsertedPendingNew
        ) == .allowed)
        #expect(TimelineSnapshotCoordinator.pendingNewInsertionDecision(
            pendingNewIDs: [pendingID],
            reason: .initialRestore
        ) == .blocked)
        #expect(TimelineSnapshotCoordinator.pendingNewInsertionDecision(
            pendingNewIDs: [],
            reason: .initialRestore
        ) == .allowed)
    }

    @Test("Resolve intent preserves IDs and reports skipped unknown IDs")
    func resolveIntentPreservesIDsAndReportsSkippedUnknownIDs() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let skipped = TimelineEntryID(rawValue: "home:098:unknown")

        let intent = TimelineResolveApplyCoordinator().reconfigureIntent(
            resolvedIDs: [
                TimelineEntryID(rawValue: "home:099:b"),
                skipped,
                TimelineEntryID(rawValue: "home:100:a")
            ],
            existingIDs: existing,
            reason: .media
        )

        #expect(intent.mutationStyle == .reconfigure)
        #expect(intent.entryIDs == [
            TimelineEntryID(rawValue: "home:099:b"),
            TimelineEntryID(rawValue: "home:100:a")
        ])
        #expect(intent.skippedIDs == [skipped])
        #expect(intent.insertedIDs.isEmpty)
        #expect(intent.deletedIDs.isEmpty)
    }

    private static func positionRecorder() -> TimelinePositionRecorder {
        TimelinePositionRecorder(
            accountID: AccountID(rawValue: "account-a"),
            feedID: FeedID(rawValue: 1),
            timelineKey: TimelineKey(rawValue: "home")
        )
    }

    @MainActor
    private static func dataSource(
        for collectionView: UICollectionView
    ) -> TimelineSnapshotCoordinator.DataSource {
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        return TimelineSnapshotCoordinator.DataSource(collectionView: collectionView) { collectionView, indexPath, _ in
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }
    }

    private static func attributes(
        indexPath: IndexPath,
        minY: CGFloat,
        height: CGFloat
    ) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(x: 0, y: minY, width: 320, height: height)
        return attributes
    }

    private static func anchor(
        itemKey: String,
        delta: Double,
        capturedAtMS: Int64 = 1_735_000_000_000
    ) -> TimelineVisualAnchor {
        TimelineVisualAnchor(
            accountID: AccountID(rawValue: "account-a"),
            feedID: FeedID(rawValue: 1),
            timelineKey: TimelineKey(rawValue: "home"),
            anchorItemKey: itemKey,
            anchorEventID: nil,
            anchorSortAt: 100,
            anchorTieBreakID: itemKey,
            cellTopDeltaFromViewportTop: delta,
            viewportHeight: 844,
            viewportWidth: 390,
            contentInsetTop: 0,
            contentInsetBottom: 34,
            lastVisibleTopItemKey: itemKey,
            lastVisibleBottomItemKey: itemKey,
            markerEventID: nil,
            markerSortAt: nil,
            capturedAtMS: capturedAtMS,
            schemaVersion: 1
        )
    }
}

@MainActor
private final class RestoreDiagnosticsCollectionView: UICollectionView {
    var diagnosticVisibleIndexPaths: [IndexPath] = []
    var diagnosticAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    var attributesInstalledAfterScroll: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    var scrollRequests: [IndexPath] = []

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 72)
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 480), collectionViewLayout: layout)
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

    override func scrollToItem(
        at indexPath: IndexPath,
        at scrollPosition: UICollectionView.ScrollPosition,
        animated: Bool
    ) {
        scrollRequests.append(indexPath)
        diagnosticAttributes.merge(attributesInstalledAfterScroll) { current, _ in current }
    }
}
