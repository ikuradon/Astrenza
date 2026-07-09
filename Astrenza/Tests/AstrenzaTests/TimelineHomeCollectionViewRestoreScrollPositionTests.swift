import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@MainActor
@Suite("TimelineHome collectionView restore scroll position")
struct TimelineHomeCollectionViewRestoreScrollPositionTests {
    @Test
    func restore_scroll_requires_collectionView_flag() async throws {
        let result = try await RestoreScrollPositionHarness.render(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.scrollPath == .legacy)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.anchorEntryID == nil)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func restore_scroll_requires_clean_evaluated_wiring_gate() async throws {
        let result = try await RestoreScrollPositionHarness.render(wiringGateResult: nil)

        #expect(result.selectedRoute == .legacy)
        #expect(result.scrollPath == .legacy)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.anchorEntryID == nil)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func default_without_flag_keeps_legacy_scroll_path() async throws {
        let result = try await RestoreScrollPositionHarness.render(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.scrollPath == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test
    func dirty_wiring_gate_keeps_legacy_scroll_path() async throws {
        let result = try await RestoreScrollPositionHarness.render(wiringGateResult: .dirty)

        #expect(result.selectedRoute == .legacy)
        #expect(result.scrollPath == .legacy)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.anchorEntryID == nil)
    }

    @Test
    func flagged_clean_route_restores_anchor_to_expected_visible_row() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.selectedRoute == .collectionView)
        #expect(result.scrollPath == .collectionView)
        #expect(result.collectionViewRestorePlanBuilt)
        #expect(result.anchorEntryID == "note:anchor")
        #expect(result.visibleEntryIDs.contains("note:anchor"))
        #expect(result.fallbackReason == .anchorFound)
        #expect(result.preservePositionIntent == .protectAnchorRestore)
    }

    @Test
    func restored_top_visible_row_matches_restore_plan_anchor() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.restorePlanAnchorEntryID == "note:anchor")
        #expect(result.topVisibleEntryID == result.restorePlanAnchorEntryID)
        #expect(result.topVisibleEntryID == result.anchorEntryID)
    }

    @Test
    func missing_anchor_falls_back_to_first_visible_restore_row() async throws {
        let result = try await RestoreScrollPositionHarness.render(
            window: RestoreScrollPositionFixture.window(
                rows: RestoreScrollPositionFixture.anchorRows(),
                readState: RestoreScrollPositionFixture.readState(scrollAnchorItemKey: "note:missing"),
                anchorItemKey: nil
            ),
            requestedAnchorItemKey: "note:missing"
        )

        #expect(result.selectedRoute == .collectionView)
        #expect(result.anchorEntryID == "note:newest")
        #expect(result.topVisibleEntryID == "note:newest")
        #expect(result.visibleEntryIDs.first == "note:newest")
        #expect(result.fallbackReason == .missingAnchorUsedNewest)
    }

    @Test
    func empty_restore_plan_has_no_scroll_anchor() async throws {
        let result = try await RestoreScrollPositionHarness.render(
            window: RestoreScrollPositionFixture.window(rows: [], readState: nil, anchorItemKey: nil),
            requestedAnchorItemKey: nil
        )

        #expect(result.selectedRoute == .collectionView)
        #expect(result.collectionViewRestorePlanBuilt)
        #expect(result.visibleEntryIDs.isEmpty)
        #expect(result.anchorEntryID == nil)
        #expect(result.topVisibleEntryID == nil)
        #expect(result.preservePositionIntent == .emptyLocalCache)
        #expect(result.fallbackReason == .noVisibleRows)
    }

    @Test
    func pending_anchor_row_is_not_restored_as_visible_anchor() async throws {
        let result = try await RestoreScrollPositionHarness.render(
            window: RestoreScrollPositionFixture.window(
                rows: RestoreScrollPositionFixture.pendingAnchorRows(),
                readState: RestoreScrollPositionFixture.readState(scrollAnchorItemKey: "note:pending"),
                anchorItemKey: "note:pending",
                excludedPendingNewCount: 1
            ),
            requestedAnchorItemKey: "note:pending"
        )

        #expect(result.selectedRoute == .collectionView)
        #expect(result.anchorEntryID == "note:visible")
        #expect(result.topVisibleEntryID == "note:visible")
        #expect(!result.visibleEntryIDs.contains("note:pending"))
        #expect(result.pendingNewExcludedCount == 1)
        #expect(result.fallbackReason == .missingAnchorUsedNewest)
    }

    @Test
    func hidden_anchor_row_is_not_restored_as_visible_anchor() async throws {
        let result = try await RestoreScrollPositionHarness.render(
            window: RestoreScrollPositionFixture.window(
                rows: RestoreScrollPositionFixture.hiddenAnchorRows(),
                readState: RestoreScrollPositionFixture.readState(scrollAnchorItemKey: "note:hidden"),
                anchorItemKey: "note:hidden",
                excludedHiddenCount: 1
            ),
            requestedAnchorItemKey: "note:hidden"
        )

        #expect(result.selectedRoute == .collectionView)
        #expect(result.anchorEntryID == "note:visible")
        #expect(result.topVisibleEntryID == "note:visible")
        #expect(!result.visibleEntryIDs.contains("note:hidden"))
        #expect(result.hiddenExcludedCount == 1)
        #expect(result.fallbackReason == .missingAnchorUsedNewest)
    }

    @Test
    func same_sort_anchor_uses_stable_tie_break_order() async throws {
        let result = try await RestoreScrollPositionHarness.render(
            window: RestoreScrollPositionFixture.window(
                rows: RestoreScrollPositionFixture.sameSortRows(),
                readState: RestoreScrollPositionFixture.readState(scrollAnchorItemKey: "note:b"),
                anchorItemKey: "note:b"
            ),
            requestedAnchorItemKey: "note:b"
        )

        #expect(result.visibleEntryIDs == ["note:a", "note:b", "note:c"])
        #expect(result.anchorEntryID == "note:b")
        #expect(result.topVisibleEntryID == "note:b")
        #expect(result.fallbackReason == .anchorFound)
    }

    @Test
    func restore_scroll_uses_timeline_area_restore_gate_only() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.restoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
    }

    @Test
    func restore_scroll_keeps_networkWaitedBeforeInteractiveScrollMS_zero() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
        #expect(result.storeNetworkStartCallCount == 0)
    }

    @Test
    func restore_scroll_keeps_readMarkerChanged_false() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.readMarkerChanged == false)
    }

    @Test
    func restore_scroll_does_not_write_db() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
    }

    @Test
    func restore_scroll_does_not_advance_read_marker() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func restore_scroll_does_not_mutate_pending_new() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.pendingNewMutated == false)
        #expect(result.pendingNewExcludedCount == 1)
        #expect(!result.visibleEntryIDs.contains("note:pending"))
    }

    @Test
    func restore_scroll_does_not_call_dataSourceApply_from_Root() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
    }

    @Test
    func restore_scroll_does_not_construct_extra_NostrHomeTimelineStore() async throws {
        let result = try await RestoreScrollPositionHarness.render()

        #expect(result.noExtraNostrHomeTimelineStore)
    }

    @Test
    func restore_scroll_result_is_codable_privacy_safe() async throws {
        let result = try await RestoreScrollPositionHarness.render()
        let data = try RestoreScrollPositionHarness.encodedData(result)
        let decoded = try JSONDecoder().decode(RestoreScrollPositionResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(RestoreScrollPositionResult.self)
        #expect(decoded == result)
        for fragment in RestoreScrollPositionFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = RestoreScrollPositionSelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests", testCount: 21)))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }
}

private enum RestoreScrollPositionWiringGateState: Sendable {
    case clean
    case dirty
}

private enum RestoreScrollPath: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

private struct RestoreScrollPositionResult: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var scrollPath: RestoreScrollPath
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var collectionViewRestorePlanBuilt: Bool
    var anchorEntryID: String?
    var restorePlanAnchorEntryID: String?
    var topVisibleEntryID: String?
    var visibleEntryIDs: [String]
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason?
    var preservePositionIntent: TimelineInitialRestoreGateIntent?
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

private enum RestoreScrollPositionHarness {
    @MainActor
    static func render(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        wiringGateResult: RestoreScrollPositionWiringGateState? = .clean,
        window: TimelineRepositoryInitialWindow = RestoreScrollPositionFixture.defaultWindow(),
        requestedAnchorItemKey: String? = "note:anchor"
    ) async throws -> RestoreScrollPositionResult {
        let store = RestoreScrollPositionRepositoryStore(window: window)
        let mode = TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: mode,
            repositoryStore: store,
            clock: TimelineFixedClock(nowMS: RestoreScrollPositionFixture.timestampMS)
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
                readRequest: TimelineRepositoryReadRequest(
                    feedID: RestoreScrollPositionFixture.feedID,
                    databaseAccountID: 1
                ),
                accountID: .debug,
                timelineKey: .home,
                repositoryPolicy: .initialRestore(maxVisibleCount: 10),
                visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
                requestedAnchorItemKey: requestedAnchorItemKey,
                createdAtMS: RestoreScrollPositionFixture.timestampMS
            )
        )

        let restorePlan = decision.restorePlan
        let visibleEntryIDs = restorePlan?.snapshotItemKeys ?? []
        let anchorEntryID = restorePlan?.restoreCandidateItemKey
        let topVisibleEntryID = anchorEntryID.flatMap { visibleEntryIDs.contains($0) ? $0 : nil }
            ?? visibleEntryIDs.first
        let visibleSet = Set(visibleEntryIDs)

        return RestoreScrollPositionResult(
            selectedRoute: decision.selectedRoute,
            scrollPath: decision.collectionViewRestorePlanBuilt ? .collectionView : .legacy,
            rollbackRoute: decision.rollbackRoute,
            manualFallbackRoute: decision.manualFallbackRoute,
            collectionViewRestorePlanBuilt: decision.collectionViewRestorePlanBuilt,
            anchorEntryID: anchorEntryID,
            restorePlanAnchorEntryID: restorePlan?.restoreCandidateItemKey,
            topVisibleEntryID: topVisibleEntryID,
            visibleEntryIDs: visibleEntryIDs,
            fallbackReason: restorePlan?.fallbackReason,
            preservePositionIntent: restorePlan?.restoreGateIntent,
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
        state: RestoreScrollPositionWiringGateState?
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
                createdAtMS: RestoreScrollPositionFixture.timestampMS
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
                createdAtMS: RestoreScrollPositionFixture.timestampMS
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
                createdAtMS: RestoreScrollPositionFixture.timestampMS
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
            createdAtMS: RestoreScrollPositionFixture.timestampMS
        )
    }
}

private enum RestoreScrollPositionFixture {
    static let feedID: Int64 = 10
    static let timestampMS: Int64 = 1_735_000_060_000

    static func defaultWindow() -> TimelineRepositoryInitialWindow {
        window(
            rows: anchorRows() + [
                row(
                    itemKey: "note:pending",
                    sourceEventID: eventID("d"),
                    pendingNew: true,
                    sortAt: 250,
                    tieBreakID: "d"
                )
            ],
            readState: readState(scrollAnchorItemKey: "note:anchor", scrollAnchorEventID: eventID("b")),
            anchorItemKey: "note:anchor",
            excludedPendingNewCount: 1
        )
    }

    static func anchorRows() -> [TimelineRepositoryFeedItemRow] {
        [
            row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
            row(itemKey: "note:anchor", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
            row(itemKey: "note:older", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c")
        ]
    }

    static func pendingAnchorRows() -> [TimelineRepositoryFeedItemRow] {
        [
            row(
                itemKey: "note:pending",
                sourceEventID: eventID("a"),
                pendingNew: true,
                sortAt: 300,
                tieBreakID: "a"
            ),
            row(itemKey: "note:visible", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
        ]
    }

    static func hiddenAnchorRows() -> [TimelineRepositoryFeedItemRow] {
        [
            row(
                itemKey: "note:hidden",
                sourceEventID: eventID("a"),
                hiddenReason: "muted",
                sortAt: 300,
                tieBreakID: "a"
            ),
            row(itemKey: "note:visible", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
        ]
    }

    static func sameSortRows() -> [TimelineRepositoryFeedItemRow] {
        [
            row(itemKey: "note:c", sourceEventID: eventID("c"), sortAt: 200, tieBreakID: "c"),
            row(itemKey: "note:a", sourceEventID: eventID("a"), sortAt: 200, tieBreakID: "a"),
            row(itemKey: "note:b", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b")
        ]
    }

    static func window(
        rows: [TimelineRepositoryFeedItemRow],
        readState: TimelineRepositoryReadStateRow?,
        anchorItemKey: String?,
        excludedHiddenCount: Int = 0,
        excludedPendingNewCount: Int = 0
    ) -> TimelineRepositoryInitialWindow {
        TimelineRepositoryInitialWindow(
            feedID: feedID,
            rows: rows,
            readState: readState,
            anchorItemKey: anchorItemKey,
            issues: [],
            diagnostics: TimelineRepositoryStoreDiagnostics(
                totalFeedItemRowCount: rows.count,
                sqlVisibleRowCount: rows.count - excludedHiddenCount - excludedPendingNewCount,
                excludedHiddenCount: excludedHiddenCount,
                excludedPendingNewCount: excludedPendingNewCount,
                pendingNewIncludedCount: 0,
                readStatePresent: readState != nil,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresExternalMutation: false,
                performedLocalDBRead: true,
                resolveJobRowCount: 0,
                diagnosticRowCount: 0
            )
        )
    }

    static func readState(
        scrollAnchorItemKey: String?,
        scrollAnchorEventID: String? = nil
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

    private static func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }
}

private actor RestoreScrollPositionRepositoryStore: TimelineRepositoryStore {
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

private struct RestoreScrollPositionSuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum RestoreScrollPositionSelectedSuiteCounts {
    static let current = [
        RestoreScrollPositionSuiteCount(
            suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests",
            testCount: 21
        ),
        RestoreScrollPositionSuiteCount(suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests", testCount: 19),
        RestoreScrollPositionSuiteCount(suiteName: "TimelineHomeCollectionViewSimulatorStartupSmokeTests", testCount: 16),
        RestoreScrollPositionSuiteCount(suiteName: "TimelineHomeCollectionViewRouteRestoreIntegrationTests", testCount: 16)
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
