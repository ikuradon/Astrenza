import AstrenzaCore
import Foundation
import Testing
import UIKit
@testable import Astrenza

@MainActor
@Suite("TimelineHome collectionView visible restore rows")
struct TimelineHomeCollectionViewVisibleRestoreRowsTests {
    @Test
    func visible_restore_rows_requires_collectionView_flag() async throws {
        let result = try await VisibleRestoreRowsHarness.render(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.visibleItemKeys.isEmpty)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func visible_restore_rows_requires_clean_evaluated_wiring_gate() async throws {
        let result = try await VisibleRestoreRowsHarness.render(wiringGateResult: nil)

        #expect(result.selectedRoute == .legacy)
        #expect(result.visibleItemKeys.isEmpty)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func default_without_flag_keeps_legacy_visible_route() async throws {
        let result = try await VisibleRestoreRowsHarness.render(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.visibleRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test
    func dirty_wiring_gate_keeps_legacy_visible_route() async throws {
        let result = try await VisibleRestoreRowsHarness.render(wiringGateResult: .dirty)

        #expect(result.selectedRoute == .legacy)
        #expect(result.visibleRoute == .legacy)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.visibleItemKeys.isEmpty)
    }

    @Test
    func flagged_clean_route_displays_restored_visible_rows() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.selectedRoute == .collectionView)
        #expect(result.visibleRoute == .collectionView)
        #expect(result.collectionViewRestorePlanBuilt)
        #expect(result.controllerViewLoaded)
        #expect(result.controllerHasCollectionView)
        #expect(result.controllerAttachedToWindow == false)
        #expect(result.visibleItemKeys == VisibleRestoreRowsFixture.expectedVisibleItemKeys)
    }

    @Test
    func restored_visible_rows_match_initial_restore_plan_order() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.restorePlanSnapshotItemKeys == result.initialRestorePlanItemKeys)
        #expect(result.visibleItemKeys == result.initialRestorePlanItemKeys)
        #expect(result.visibleItemKeys == VisibleRestoreRowsFixture.expectedVisibleItemKeys)
    }

    @Test
    func pending_rows_are_not_displayed() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.pendingItemKeysExcluded == ["note:pending"])
        #expect(!result.visibleItemKeys.contains("note:pending"))
        #expect(result.pendingNewExcludedCount == 1)
    }

    @Test
    func hidden_rows_are_not_displayed() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.hiddenItemKeysExcluded == ["note:hidden"])
        #expect(!result.visibleItemKeys.contains("note:hidden"))
        #expect(result.hiddenExcludedCount == 1)
    }

    @Test
    func missing_target_quote_or_repost_rows_remain_visible_if_restore_plan_keeps_them() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.missingTargetVisibleItemKeys == ["quote:missing", "repost:missing"])
        #expect(result.visibleItemKeys.contains("quote:missing"))
        #expect(result.visibleItemKeys.contains("repost:missing"))
    }

    @Test
    func visible_rows_use_timeline_area_restore_gate_only() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.restoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
    }

    @Test
    func visible_rows_keep_networkWaitedBeforeInteractiveScrollMS_zero() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
        #expect(result.storeNetworkStartCallCount == 0)
    }

    @Test
    func visible_rows_keep_readMarkerChanged_false() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.readMarkerChanged == false)
    }

    @Test
    func visible_rows_do_not_write_db() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
    }

    @Test
    func visible_rows_do_not_advance_read_marker() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func visible_rows_do_not_mutate_pending_new() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.pendingNewMutated == false)
        #expect(result.pendingNewExcludedCount == 1)
    }

    @Test
    func visible_rows_do_not_call_dataSourceApply_from_Root() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
    }

    @Test
    func visible_rows_do_not_construct_extra_NostrHomeTimelineStore() async throws {
        let result = try await VisibleRestoreRowsHarness.render()

        #expect(result.noExtraNostrHomeTimelineStore)
    }

    @Test
    func visible_rows_result_is_codable_privacy_safe() async throws {
        let result = try await VisibleRestoreRowsHarness.render()
        let data = try VisibleRestoreRowsHarness.encodedData(result)
        let decoded = try JSONDecoder().decode(VisibleRestoreRowsResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(VisibleRestoreRowsResult.self)
        #expect(decoded == result)
        for fragment in VisibleRestoreRowsFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = VisibleRestoreRowsSelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests", testCount: 19)))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }
}

private enum VisibleRestoreRowsWiringGateState: Sendable {
    case clean
    case dirty
}

private struct VisibleRestoreRowsResult: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var visibleRoute: TimelineHomeRootBodyRouteSelection
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var collectionViewRestorePlanBuilt: Bool
    var controllerViewLoaded: Bool
    var controllerHasCollectionView: Bool
    var controllerAttachedToWindow: Bool
    var restorePlanSnapshotItemKeys: [String]
    var initialRestorePlanItemKeys: [String]
    var visibleItemKeys: [String]
    var pendingItemKeysExcluded: [String]
    var hiddenItemKeysExcluded: [String]
    var missingTargetVisibleItemKeys: [String]
    var restoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var networkStarted: Bool
    var requiresNetworkWork: Bool
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var dbWriteAttempted: Bool
    var requiresDBWrite: Bool
    var pendingNewMutated: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var storeFetchInitialWindowCallCount: Int
    var storeNetworkStartCallCount: Int
    var pendingNewExcludedCount: Int
    var hiddenExcludedCount: Int
    var issueKinds: [TimelineHomeCollectionViewRouteRestoreIssueKind]
}

private enum VisibleRestoreRowsHarness {
    @MainActor
    static func render(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        wiringGateResult: VisibleRestoreRowsWiringGateState? = .clean,
        window: TimelineRepositoryInitialWindow = VisibleRestoreRowsFixture.window()
    ) async throws -> VisibleRestoreRowsResult {
        let store = VisibleRestoreRowsRepositoryStore(window: window)
        let mode = TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: mode,
            repositoryStore: store,
            clock: TimelineFixedClock(nowMS: VisibleRestoreRowsFixture.timestampMS)
        )
        let rootDecision = rootBodyDecision(
            arguments: arguments,
            wiringGateResult: makeWiringGateResult(arguments: arguments, state: wiringGateResult)
        )
        let decision = try await TimelineHomeCollectionViewRouteRestoreComposer.compose(
            TimelineHomeCollectionViewRouteRestoreComposerInput(
                launchArguments: arguments,
                rootBodyRenderDecision: rootDecision,
                container: container,
                readRequest: TimelineRepositoryReadRequest(feedID: VisibleRestoreRowsFixture.feedID, databaseAccountID: 1),
                accountID: .debug,
                timelineKey: .home,
                repositoryPolicy: .initialRestore(maxVisibleCount: 10),
                visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
                requestedAnchorItemKey: "note:visible",
                createdAtMS: VisibleRestoreRowsFixture.timestampMS
            )
        )

        var initialRestorePlanItemKeys: [String] = []
        var controllerState = TimelineCollectionViewControllerSurfaceState(
            isViewLoaded: false,
            hasCollectionView: false,
            isAttachedToWindow: false,
            itemIDs: []
        )

        if decision.collectionViewRestorePlanBuilt {
            let composition = try container.windowComposer.compose(
                window,
                .debug,
                .home,
                .initialRestore(maxVisibleCount: 10)
            )
            let initialPlan = container.makeInitialRestorePlan(
                from: composition,
                requestedAnchorItemKey: "note:visible"
            )
            initialRestorePlanItemKeys = initialPlan.snapshotPlan.itemIDs.map(\.rawValue)

            let controller = container.makeController(
                for: initialPlan,
                accountID: .debug,
                feedID: .debugHome,
                timelineKey: .home
            )
            controller.loadViewIfNeeded()
            controllerState = controller.surfaceState
        }

        let restorePlan = decision.restorePlan
        let visibleItemKeys = controllerState.itemIDs.map(\.rawValue)
        let visibleSet = Set(visibleItemKeys)
        let pendingItemKeysExcluded = window.rows
            .filter(\.pendingNew)
            .map(\.itemKey)
            .filter { !visibleSet.contains($0) }
        let hiddenItemKeysExcluded = window.rows
            .filter { $0.hiddenReason != nil }
            .map(\.itemKey)
            .filter { !visibleSet.contains($0) }
        let missingTargetVisibleItemKeys = window.rows
            .filter { ($0.reason == .quote || $0.reason == .repost) && $0.subjectEventID == nil }
            .map(\.itemKey)
            .filter { visibleSet.contains($0) }

        return VisibleRestoreRowsResult(
            selectedRoute: decision.selectedRoute,
            visibleRoute: visibleItemKeys.isEmpty ? .legacy : .collectionView,
            rollbackRoute: decision.rollbackRoute,
            manualFallbackRoute: decision.manualFallbackRoute,
            collectionViewRestorePlanBuilt: decision.collectionViewRestorePlanBuilt,
            controllerViewLoaded: controllerState.isViewLoaded,
            controllerHasCollectionView: controllerState.hasCollectionView,
            controllerAttachedToWindow: controllerState.isAttachedToWindow,
            restorePlanSnapshotItemKeys: restorePlan?.snapshotItemKeys ?? [],
            initialRestorePlanItemKeys: initialRestorePlanItemKeys,
            visibleItemKeys: visibleItemKeys,
            pendingItemKeysExcluded: pendingItemKeysExcluded,
            hiddenItemKeysExcluded: hiddenItemKeysExcluded,
            missingTargetVisibleItemKeys: missingTargetVisibleItemKeys,
            restoreGateScope: restorePlan?.restoreGateScope,
            timelineGateCoversRootShell: restorePlan?.timelineGateCoversRootShell ?? rootDecision.timelineGateCoversRootShell,
            timelineGateCoversTabBar: restorePlan?.timelineGateCoversTabBar ?? rootDecision.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: restorePlan?.timelineGateContinuesGlobalSplash
                ?? rootDecision.timelineGateContinuesGlobalSplash,
            networkWaitedBeforeInteractiveScrollMS: decision.networkWaitedBeforeInteractiveScrollMS,
            networkStarted: decision.networkStarted,
            requiresNetworkWork: decision.requiresNetworkWork,
            readMarkerChanged: decision.readMarkerChanged,
            readMarkerAdvanced: decision.readMarkerAdvanced,
            dbWriteAttempted: decision.dbWriteAttempted,
            requiresDBWrite: decision.requiresDBWrite,
            pendingNewMutated: visibleSet.contains("note:pending"),
            dataSourceApplyFromRootCalled: decision.dataSourceApplyFromRootCalled,
            coordinatorOwnedDataSourceApplyAllowed: restorePlan?.coordinatorOwnedDataSourceApplyAllowed ?? false,
            noExtraNostrHomeTimelineStore: decision.noExtraNostrHomeTimelineStore,
            storeFetchInitialWindowCallCount: await store.fetchInitialWindowCallCount,
            storeNetworkStartCallCount: await store.networkStartCallCount,
            pendingNewExcludedCount: restorePlan?.pendingNewExcludedCount ?? 0,
            hiddenExcludedCount: restorePlan?.hiddenExcludedCount ?? 0,
            issueKinds: decision.issueKinds
        )
    }

    static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func makeWiringGateResult(
        arguments: [String],
        state: VisibleRestoreRowsWiringGateState?
    ) -> TimelineHomeRootBodyActivationWiringResult? {
        guard let state else { return nil }
        switch state {
        case .clean:
            return cleanWiringGateResult(arguments: arguments)
        case .dirty:
            return dirtyWiringGateResult(arguments: arguments)
        }
    }

    private static func rootBodyDecision(
        arguments: [String],
        wiringGateResult: TimelineHomeRootBodyActivationWiringResult?
    ) -> TimelineHomeRootBodyRenderDecision {
        TimelineHomeRootBodyRenderSwitch.decide(
            TimelineHomeRootBodyRenderSwitchInput(
                launchArguments: arguments,
                wiringGateResult: wiringGateResult,
                rootShellPresentation: .immediate,
                rootShellMustRenderBeforeTimelineRestore: true,
                timelineRestoreGateScope: .timelineArea,
                timelineGateCoversRootShell: false,
                timelineGateCoversTabBar: false,
                timelineGateContinuesGlobalSplash: false,
                networkStartedBeforeInteractiveScroll: false,
                networkWaitedBeforeInteractiveScrollMS: 0,
                dbWriteAttempted: false,
                readMarkerAdvanced: false,
                dataSourceApplyFromRootCalled: false,
                extraNostrHomeTimelineStoreConstructed: false,
                createdAtMS: VisibleRestoreRowsFixture.timestampMS
            )
        )
    }

    private static func cleanWiringGateResult(
        arguments: [String]
    ) -> TimelineHomeRootBodyActivationWiringResult {
        TimelineHomeRootBodyActivationWiringGate.evaluate(
            TimelineHomeRootBodyActivationWiringInput(
                launchArguments: arguments,
                activationSwitchResult: cleanActivationSwitchResult(),
                context: .defaultClean(),
                createdAtMS: VisibleRestoreRowsFixture.timestampMS
            )
        )
    }

    private static func dirtyWiringGateResult(
        arguments: [String]
    ) -> TimelineHomeRootBodyActivationWiringResult {
        TimelineHomeRootBodyActivationWiringGate.evaluate(
            TimelineHomeRootBodyActivationWiringInput(
                launchArguments: arguments,
                activationSwitchResult: cleanActivationSwitchResult(),
                context: .defaultClean(mutatingLegacyAndCollectionViewInSameSession: true),
                createdAtMS: VisibleRestoreRowsFixture.timestampMS
            )
        )
    }

    private static func cleanActivationSwitchResult() -> TimelineHomeActivatedRouteDecision {
        TimelineHomeActivatedRouteDecision(
            activationWouldBeAllowed: true,
            activationPerformed: true,
            productionRenderSwitchPerformed: true,
            renderedRoute: .collectionView,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            routeDecision: TimelineHomeRootRenderRouteDecision(
                renderedRoute: .collectionView,
                rollbackRoute: .legacy,
                manualFallbackRoute: .legacy
            ),
            issueKinds: [],
            diagnostics: TimelineHomeCollectionViewRouteActivationSwitchDiagnostics(
                rootActivationDecisionSummary: "renderedRoute=legacy activationWouldBeAllowed=true",
                activationArtifactChainSummary: "activationWouldBeAllowed=true",
                activationReadinessSummary: "activationWouldBeAllowed=true",
                flaggedConstructionSummary: "constructionAllowed=true",
                constructionReadinessSummary: "collectionViewAllowed=true",
                offscreenHarnessSummary: "collectionViewAllowed=true",
                sideEffectSummary: "network=false,dbWrite=false,readMarker=false"
            ),
            routeDiagnosticsRecorded: true,
            activationArtifactChainRecorded: true,
            constructionArtifactChainRecorded: true,
            rootShellPresentation: .immediate,
            rootShellMustRenderBeforeTimelineRestore: true,
            timelineRestoreGateScope: .timelineArea,
            timelineGateCoversRootShell: false,
            timelineGateCoversTabBar: false,
            timelineGateContinuesGlobalSplash: false,
            networkStarted: false,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            dataSourceApplyFromRootCalled: false,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
            coordinatorOwnedDataSourceApplyAllowed: true,
            noExtraNostrHomeTimelineStore: true,
            preventsDualMutation: true,
            createdAtMS: VisibleRestoreRowsFixture.timestampMS
        )
    }
}

private enum VisibleRestoreRowsFixture {
    static let feedID: Int64 = 10
    static let timestampMS: Int64 = 1_735_000_050_000
    static let expectedVisibleItemKeys = ["note:visible", "quote:missing", "repost:missing"]

    static func window() -> TimelineRepositoryInitialWindow {
        let rows = [
            row(
                itemKey: "note:pending",
                sourceEventID: eventID("a"),
                pendingNew: true,
                sortAt: 600,
                tieBreakID: "a"
            ),
            row(
                itemKey: "note:hidden",
                sourceEventID: eventID("b"),
                hiddenReason: "muted",
                sortAt: 550,
                tieBreakID: "b"
            ),
            row(
                itemKey: "note:visible",
                sourceEventID: eventID("c"),
                sortAt: 500,
                tieBreakID: "c"
            ),
            row(
                itemKey: "quote:missing",
                sourceEventID: eventID("d"),
                subjectEventID: nil,
                reason: .quote,
                sortAt: 450,
                tieBreakID: "d"
            ),
            row(
                itemKey: "repost:missing",
                sourceEventID: eventID("e"),
                subjectEventID: nil,
                reason: .repost,
                sortAt: 400,
                tieBreakID: "e"
            )
        ]

        return TimelineRepositoryInitialWindow(
            feedID: feedID,
            rows: rows,
            readState: readState(scrollAnchorItemKey: "note:visible", scrollAnchorEventID: eventID("c")),
            anchorItemKey: "note:visible",
            issues: [],
            diagnostics: TimelineRepositoryStoreDiagnostics(
                totalFeedItemRowCount: rows.count,
                sqlVisibleRowCount: expectedVisibleItemKeys.count,
                excludedHiddenCount: 1,
                excludedPendingNewCount: 1,
                pendingNewIncludedCount: 0,
                readStatePresent: true,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresExternalMutation: false,
                performedLocalDBRead: true,
                resolveJobRowCount: 0,
                diagnosticRowCount: 0
            )
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
            "raw content phrase",
            "raw event content phrase",
            "private message content phrase",
            "relay url",
            "pubkey",
            "event id",
            "eventid",
            "event_id",
            "bearer",
            "launcharguments"
        ]
    }

    private static func row(
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
            feedID: feedID,
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

    private static func readState(
        scrollAnchorItemKey: String,
        scrollAnchorEventID: String
    ) -> TimelineRepositoryReadStateRow {
        TimelineRepositoryReadStateRow(
            databaseAccountID: 1,
            feedID: feedID,
            scrollAnchorItemKey: scrollAnchorItemKey,
            scrollAnchorEventID: scrollAnchorEventID,
            scrollAnchorOffsetPX: 12,
            viewportHeightPX: 640,
            viewportWidthPX: 390,
            contentInsetTopPX: 8,
            contentInsetBottomPX: 16,
            clientStateJSON: "{}",
            lastViewedAtMS: 1_000,
            updatedAtMS: 2_000
        )
    }

    private static func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }
}

private actor VisibleRestoreRowsRepositoryStore: TimelineRepositoryStore {
    let window: TimelineRepositoryInitialWindow
    private(set) var fetchInitialWindowCallCount = 0
    private(set) var networkStartCallCount = 0

    init(window: TimelineRepositoryInitialWindow) {
        self.window = window
    }

    func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        fetchInitialWindowCallCount += 1
        return window
    }

    func fetchReadState(
        feedID: Int64,
        databaseAccountID: Int64?
    ) async throws -> TimelineRepositoryReadStateRow? {
        window.readState
    }

    func fetchAnchorWindow(
        feedID: Int64,
        anchorItemKey: String,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        window
    }
}

private struct VisibleRestoreRowsSuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum VisibleRestoreRowsSelectedSuiteCounts {
    static let current = [
        VisibleRestoreRowsSuiteCount(suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests", testCount: 19),
        VisibleRestoreRowsSuiteCount(suiteName: "TimelineHomeCollectionViewRouteRestoreIntegrationTests", testCount: 16),
        VisibleRestoreRowsSuiteCount(suiteName: "TimelineCollectionViewControllerSmokeTests", testCount: 3),
        VisibleRestoreRowsSuiteCount(suiteName: "TimelineInitialRestoreSnapshotCoordinatorHarnessTests", testCount: 8)
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
