import Foundation
import Testing
import UIKit
@testable import Astrenza

@MainActor
@Suite("TimelineHome collectionView windowing controller harness")
struct TimelineHomeCollectionViewWindowingControllerHarnessTests {
    @Test
    func default_without_flag_uses_legacy_controller_path() {
        let result = WindowingControllerHarness.render(
            arguments: ["Astrenza"],
            routeRestoreDecision: WindowingControllerFixture.legacyRouteDecision()
        )

        #expect(result.controllerPath == .legacy)
        #expect(result.selectedRoute == .legacy)
        #expect(result.usedCollectionViewFlag == false)
        #expect(result.controllerLoadedOffscreen == false)
        #expect(result.controllerItemIDs.isEmpty)
    }

    @Test
    func flagged_clean_route_builds_offscreen_collectionView_controller() {
        let result = WindowingControllerHarness.render()

        #expect(result.controllerPath == .collectionView)
        #expect(result.usedCollectionViewFlag)
        #expect(result.localWindowingAllowed)
        #expect(result.controllerLoadedOffscreen)
        #expect(result.controllerHasCollectionView)
        #expect(result.controllerAttachedToWindow == false)
    }

    @Test
    func initial_visible_rows_match_restore_plan() {
        let result = WindowingControllerHarness.render()

        #expect(result.restorePlanItemIDs == WindowingControllerFixture.initialVisibleItemKeys)
        #expect(result.initialControllerItemIDs == result.restorePlanItemIDs)
        #expect(result.controllerItemIDs == result.restorePlanItemIDs)
    }

    @Test
    func append_older_local_rows_updates_controller_item_ids() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page-1", sortAt: 80, tieBreakID: "m"),
                .init(itemKey: "note:older-page-2", sortAt: 70, tieBreakID: "n")
            ])
        ])

        #expect(result.appendedOlderItemKeys == ["note:older-page-1", "note:older-page-2"])
        #expect(result.controllerItemIDs == [
            "note:newest",
            "note:anchor",
            "note:older",
            "note:older-page-1",
            "note:older-page-2"
        ])
    }

    @Test
    func prepend_newer_local_rows_updates_controller_item_ids() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer-2", sortAt: 350, tieBreakID: "b"),
                .init(itemKey: "note:newer-1", sortAt: 400, tieBreakID: "a")
            ])
        ])

        #expect(result.prependedNewerItemKeys == ["note:newer-1", "note:newer-2"])
        #expect(result.controllerItemIDs == [
            "note:newer-1",
            "note:newer-2",
            "note:newest",
            "note:anchor",
            "note:older"
        ])
    }

    @Test
    func duplicate_rows_are_deduped_before_snapshot_apply() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older", sortAt: 100, tieBreakID: "c"),
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m"),
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "z")
            ])
        ])

        #expect(result.duplicateItemKeysDeduped == ["note:older", "note:older-page"])
        #expect(result.controllerItemIDs == ["note:newest", "note:anchor", "note:older", "note:older-page"])
        #expect(result.controllerItemIDs.filter { $0 == "note:older" }.count == 1)
        #expect(result.controllerItemIDs.filter { $0 == "note:older-page" }.count == 1)
    }

    @Test
    func reconfigure_visible_rows_keeps_item_identity() {
        let result = WindowingControllerHarness.render(reconfigureItemKeys: ["note:anchor", "note:missing"])

        #expect(result.reconfiguredItemKeys == ["note:anchor"])
        #expect(result.reconfigureMissingItemKeys == ["note:missing"])
        #expect(result.itemIDsBeforeReconfigure == WindowingControllerFixture.initialVisibleItemKeys)
        #expect(result.itemIDsAfterReconfigure == result.itemIDsBeforeReconfigure)
        #expect(result.controllerItemIDs == result.itemIDsBeforeReconfigure)
    }

    @Test
    func append_preserves_visible_anchor_identity() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m")
            ])
        ])

        #expect(result.visibleAnchorItemKey == "note:anchor")
        #expect(result.anchorPreservedAfterAppend)
        #expect(result.itemIDsBeforeWindowing.firstIndex(of: "note:anchor") == result.controllerItemIDs.firstIndex(of: "note:anchor"))
    }

    @Test
    func prepend_preserves_visible_anchor_identity() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer-page", sortAt: 400, tieBreakID: "a")
            ])
        ])

        #expect(result.visibleAnchorItemKey == "note:anchor")
        #expect(result.anchorPreservedAfterPrepend)
        #expect(result.itemIDsBeforeWindowing.contains("note:anchor"))
        #expect(result.controllerItemIDs.contains("note:anchor"))
    }

    @Test
    func pending_rows_are_not_applied_to_controller_snapshot() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:pending", sortAt: 500, tieBreakID: "p", pendingNew: true)
            ])
        ])

        #expect(result.pendingItemKeysExcluded == ["note:pending"])
        #expect(!result.controllerItemIDs.contains("note:pending"))
        #expect(result.pendingNewMutated == false)
    }

    @Test
    func hidden_rows_are_not_applied_to_controller_snapshot() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:hidden", sortAt: 50, tieBreakID: "h", hidden: true)
            ])
        ])

        #expect(result.hiddenItemKeysExcluded == ["note:hidden"])
        #expect(!result.controllerItemIDs.contains("note:hidden"))
    }

    @Test
    func snapshot_apply_is_coordinator_owned() throws {
        let result = WindowingControllerHarness.render()
        let controllerSource = try sourceFile(named: "TimelineCollectionViewController.swift")
        let coordinatorSource = try sourceFile(named: "TimelineSnapshotCoordinator.swift")
        let directApplyNeedle = "dataSource." + "apply"

        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(controllerSource.contains("snapshotCoordinator.applyPreservingPosition"))
        #expect(!controllerSource.contains(directApplyNeedle))
        #expect(coordinatorSource.contains(directApplyNeedle))
    }

    @Test
    func root_does_not_call_dataSourceApply() throws {
        let result = WindowingControllerHarness.render()
        let rootSource = try rootSourceFile()
        let directApplyNeedle = "dataSource." + "apply"

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(!rootSource.contains(directApplyNeedle))
    }

    @Test
    func no_network_db_readMarker_pendingNew_side_effects() {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m")
            ]),
            .init(direction: .newer, rows: [
                .init(itemKey: "note:pending", sortAt: 500, tieBreakID: "p", pendingNew: true)
            ])
        ])

        #expect(result.networkStarted == false)
        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.requiresNetworkWork == false)
        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
        #expect(result.readMarkerChanged == false)
        #expect(result.readMarkerAdvanced == false)
        #expect(result.pendingNewMutated == false)
        #expect(result.dataSourceApplyFromRootCalled == false)
    }

    @Test
    func result_is_codable_privacy_safe() throws {
        let result = WindowingControllerHarness.render(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer", sortAt: 400, tieBreakID: "a")
            ]),
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m")
            ])
        ], reconfigureItemKeys: ["note:anchor"])
        let data = try WindowingControllerHarness.encodedData(result)
        Attachment.record(data, named: "timelinehome-windowing-controller-harness-result.json")
        let decoded = try JSONDecoder().decode(WindowingControllerHarnessResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(WindowingControllerHarnessResult.self)
        #expect(decoded == result)
        for fragment in WindowingControllerFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = WindowingControllerSelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(
            suiteName: "TimelineHomeCollectionViewWindowingControllerHarnessTests",
            testCount: 16
        )))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }

    private func sourceFile(named fileName: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
            encoding: .utf8
        )
    }

    private func rootSourceFile() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/AstrenzaRootView.swift"),
            encoding: .utf8
        )
    }
}

private enum WindowingControllerPath: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

private struct WindowingControllerHarnessResult: Codable, Equatable, Sendable {
    var controllerPath: WindowingControllerPath
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var usedCollectionViewFlag: Bool
    var localWindowingAllowed: Bool
    var controllerLoadedOffscreen: Bool
    var controllerHasCollectionView: Bool
    var controllerAttachedToWindow: Bool
    var restorePlanItemIDs: [String]
    var initialControllerItemIDs: [String]
    var itemIDsBeforeWindowing: [String]
    var controllerItemIDs: [String]
    var appendedOlderItemKeys: [String]
    var prependedNewerItemKeys: [String]
    var duplicateItemKeysDeduped: [String]
    var pendingItemKeysExcluded: [String]
    var hiddenItemKeysExcluded: [String]
    var visibleAnchorItemKey: String?
    var anchorPreservedAfterAppend: Bool
    var anchorPreservedAfterPrepend: Bool
    var reconfiguredItemKeys: [String]
    var reconfigureMissingItemKeys: [String]
    var itemIDsBeforeReconfigure: [String]
    var itemIDsAfterReconfigure: [String]
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var requiresNetworkWork: Bool
    var dbWriteAttempted: Bool
    var requiresDBWrite: Bool
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var pendingNewMutated: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
}

private enum WindowingControllerHarness {
    @MainActor
    static func render(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        routeRestoreDecision: TimelineHomeCollectionViewRouteRestoreDecision = WindowingControllerFixture
            .collectionViewRouteDecision(),
        visibleAnchorItemKey: String? = "note:anchor",
        pages: [TimelineHomeCollectionViewLocalPaginationPage] = [],
        reconfigureItemKeys: [String] = []
    ) -> WindowingControllerHarnessResult {
        let windowing = TimelineHomeCollectionViewLocalPaginationWindowingEvaluator.evaluate(
            TimelineHomeCollectionViewLocalPaginationWindowingInput(
                launchArguments: arguments,
                routeRestoreDecision: routeRestoreDecision,
                visibleAnchorItemKey: visibleAnchorItemKey,
                pages: pages
            )
        )
        let restorePlanItemIDs = routeRestoreDecision.restorePlan?.snapshotItemKeys ?? []

        guard windowing.localWindowingAllowed else {
            return result(
                windowing: windowing,
                controllerPath: .legacy,
                restorePlanItemIDs: restorePlanItemIDs,
                initialControllerItemIDs: [],
                itemIDsBeforeWindowing: [],
                controllerItemIDs: [],
                controllerLoadedOffscreen: false,
                controllerHasCollectionView: false,
                controllerAttachedToWindow: false,
                reconfiguredItemKeys: [],
                reconfigureMissingItemKeys: [],
                itemIDsBeforeReconfigure: [],
                itemIDsAfterReconfigure: []
            )
        }

        let controller = TimelineCollectionViewController(
            initialItemIDs: entryIDs(WindowingControllerFixture.initialVisibleItemKeys)
        )
        let beforeLoadState = controller.surfaceState
        controller.loadViewIfNeeded()
        let initialState = controller.surfaceState

        if !pages.isEmpty {
            controller.apply(
                itemIDs: entryIDs(windowing.visibleItemKeys),
                reason: snapshotReason(for: pages),
                animatingDifferences: false
            )
        }

        var reconfiguredItemKeys: [String] = []
        var reconfigureMissingItemKeys: [String] = []
        var itemIDsBeforeReconfigure: [String] = []
        var itemIDsAfterReconfigure: [String] = []

        if !reconfigureItemKeys.isEmpty {
            itemIDsBeforeReconfigure = controller.surfaceState.itemIDs.map(\.rawValue)
            let existing = Set(itemIDsBeforeReconfigure)
            reconfiguredItemKeys = reconfigureItemKeys.filter { existing.contains($0) }
            reconfigureMissingItemKeys = reconfigureItemKeys.filter { !existing.contains($0) }
            controller.applyResolved(
                resolvedIDs: entryIDs(reconfigureItemKeys),
                reason: .profile,
                animatingDifferences: false
            )
            itemIDsAfterReconfigure = controller.surfaceState.itemIDs.map(\.rawValue)
        }

        let finalState = controller.surfaceState
        return result(
            windowing: windowing,
            controllerPath: .collectionView,
            restorePlanItemIDs: restorePlanItemIDs,
            initialControllerItemIDs: initialState.itemIDs.map(\.rawValue),
            itemIDsBeforeWindowing: beforeLoadState.itemIDs.map(\.rawValue),
            controllerItemIDs: finalState.itemIDs.map(\.rawValue),
            controllerLoadedOffscreen: finalState.isViewLoaded,
            controllerHasCollectionView: finalState.hasCollectionView,
            controllerAttachedToWindow: finalState.isAttachedToWindow,
            reconfiguredItemKeys: reconfiguredItemKeys,
            reconfigureMissingItemKeys: reconfigureMissingItemKeys,
            itemIDsBeforeReconfigure: itemIDsBeforeReconfigure,
            itemIDsAfterReconfigure: itemIDsAfterReconfigure
        )
    }

    static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func result(
        windowing: TimelineHomeCollectionViewLocalPaginationWindowingResult,
        controllerPath: WindowingControllerPath,
        restorePlanItemIDs: [String],
        initialControllerItemIDs: [String],
        itemIDsBeforeWindowing: [String],
        controllerItemIDs: [String],
        controllerLoadedOffscreen: Bool,
        controllerHasCollectionView: Bool,
        controllerAttachedToWindow: Bool,
        reconfiguredItemKeys: [String],
        reconfigureMissingItemKeys: [String],
        itemIDsBeforeReconfigure: [String],
        itemIDsAfterReconfigure: [String]
    ) -> WindowingControllerHarnessResult {
        WindowingControllerHarnessResult(
            controllerPath: controllerPath,
            selectedRoute: windowing.selectedRoute,
            usedCollectionViewFlag: windowing.usedCollectionViewFlag,
            localWindowingAllowed: windowing.localWindowingAllowed,
            controllerLoadedOffscreen: controllerLoadedOffscreen,
            controllerHasCollectionView: controllerHasCollectionView,
            controllerAttachedToWindow: controllerAttachedToWindow,
            restorePlanItemIDs: restorePlanItemIDs,
            initialControllerItemIDs: initialControllerItemIDs,
            itemIDsBeforeWindowing: itemIDsBeforeWindowing,
            controllerItemIDs: controllerItemIDs,
            appendedOlderItemKeys: windowing.appendedOlderItemKeys,
            prependedNewerItemKeys: windowing.prependedNewerItemKeys,
            duplicateItemKeysDeduped: windowing.duplicateItemKeysDeduped,
            pendingItemKeysExcluded: windowing.pendingItemKeysExcluded,
            hiddenItemKeysExcluded: windowing.hiddenItemKeysExcluded,
            visibleAnchorItemKey: windowing.visibleAnchorItemKey,
            anchorPreservedAfterAppend: windowing.anchorPreservedAfterAppend,
            anchorPreservedAfterPrepend: windowing.anchorPreservedAfterPrepend,
            reconfiguredItemKeys: reconfiguredItemKeys,
            reconfigureMissingItemKeys: reconfigureMissingItemKeys,
            itemIDsBeforeReconfigure: itemIDsBeforeReconfigure,
            itemIDsAfterReconfigure: itemIDsAfterReconfigure,
            networkStarted: windowing.networkStarted,
            networkWaitedBeforeInteractiveScrollMS: windowing.networkWaitedBeforeInteractiveScrollMS,
            requiresNetworkWork: windowing.requiresNetworkWork,
            dbWriteAttempted: windowing.dbWriteAttempted,
            requiresDBWrite: windowing.requiresDBWrite,
            readMarkerChanged: windowing.readMarkerChanged,
            readMarkerAdvanced: windowing.readMarkerAdvanced,
            pendingNewMutated: windowing.pendingNewMutated,
            dataSourceApplyFromRootCalled: windowing.dataSourceApplyFromRootCalled,
            coordinatorOwnedDataSourceApplyAllowed: windowing.coordinatorOwnedDataSourceApplyAllowed
        )
    }

    private static func entryIDs(_ itemKeys: [String]) -> [TimelineEntryID] {
        itemKeys.map { TimelineEntryID(rawValue: $0) }
    }

    private static func snapshotReason(for pages: [TimelineHomeCollectionViewLocalPaginationPage]) -> TimelineSnapshotReason {
        pages.contains { $0.direction == .newer } ? .debugReload : .olderPageLoaded
    }
}

private enum WindowingControllerFixture {
    static let timestampMS: Int64 = 1_735_000_090_000
    static let initialVisibleItemKeys = ["note:newest", "note:anchor", "note:older"]

    static func collectionViewRouteDecision() -> TimelineHomeCollectionViewRouteRestoreDecision {
        routeDecision(selectedRoute: .collectionView, restorePlan: restorePlan())
    }

    static func legacyRouteDecision() -> TimelineHomeCollectionViewRouteRestoreDecision {
        routeDecision(selectedRoute: .legacy, restorePlan: nil)
    }

    private static func routeDecision(
        selectedRoute: TimelineHomeRootBodyRouteSelection,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    ) -> TimelineHomeCollectionViewRouteRestoreDecision {
        let restorePlanBuilt = selectedRoute == .collectionView && restorePlan != nil
        let artifactSummary = TimelineHomeCollectionViewRouteRestoreArtifactSummary.make(
            selectedRoute: selectedRoute,
            restorePlanBuilt: restorePlanBuilt,
            legacyFallback: selectedRoute == .legacy,
            restorePlan: restorePlanBuilt ? restorePlan : nil,
            issueKinds: []
        )

        return TimelineHomeCollectionViewRouteRestoreDecision(
            selectedRoute: selectedRoute,
            restorePlan: restorePlanBuilt ? restorePlan : nil,
            collectionViewRestorePlanBuilt: restorePlanBuilt,
            legacyRestorePathPreserved: selectedRoute == .legacy,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            networkStarted: false,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            dataSourceApplyFromRootCalled: false,
            noExtraNostrHomeTimelineStore: true,
            artifactSummary: artifactSummary,
            issueKinds: [],
            createdAtMS: timestampMS
        )
    }

    private static func restorePlan() -> TimelineHomeCollectionViewRouteRestorePlan {
        TimelineHomeCollectionViewRouteRestorePlan(
            snapshotItemKeys: initialVisibleItemKeys,
            restoreGateIntent: .protectAnchorRestore,
            restoreGateScope: .timelineArea,
            timelineGateCoversRootShell: false,
            timelineGateCoversTabBar: false,
            timelineGateContinuesGlobalSplash: false,
            requestedAnchorItemKey: "note:anchor",
            restoreCandidateItemKey: "note:anchor",
            fallbackReason: .anchorFound,
            localDBReadWork: true,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            networkStarted: false,
            dataSourceApplyFromRootCalled: false,
            coordinatorOwnedDataSourceApplyAllowed: true,
            pendingNewExcludedCount: 1,
            hiddenExcludedCount: 1,
            issueCount: 0
        )
    }

    static var forbiddenPrivacyFragments: [String] {
        [
            "nsec",
            "secret",
            "privatekey",
            "private_key",
            "raw_json",
            "rawevent",
            "raw_event",
            "mnemonic",
            "keychain",
            "nostr secret",
            "relay url",
            "pubkey",
            "event id",
            "eventid",
            "event_id",
            "private message content phrase",
            "raw content phrase",
            "raw event content phrase",
            "launcharguments",
            "urlsession",
            "websocket",
            "wss://"
        ]
    }
}

private struct WindowingControllerSuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum WindowingControllerSelectedSuiteCounts {
    static let current = [
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewWindowingControllerHarnessTests",
            testCount: 16
        ),
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewLocalPaginationWindowingTests",
            testCount: 20
        ),
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewScrollInteractionTests",
            testCount: 17
        ),
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests",
            testCount: 19
        ),
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests",
            testCount: 21
        ),
        WindowingControllerSuiteCount(
            suiteName: "TimelineHomeCollectionViewSimulatorStartupSmokeTests",
            testCount: 16
        )
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
