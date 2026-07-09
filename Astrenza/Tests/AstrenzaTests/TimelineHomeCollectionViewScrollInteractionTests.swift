import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView scroll interaction")
struct TimelineHomeCollectionViewScrollInteractionTests {
    @Test
    func default_without_flag_uses_legacy_scroll_interaction_path() async throws {
        let result = try await ScrollInteractionHarness.evaluate(arguments: ["Astrenza"])

        #expect(result.scrollInteractionPath == .legacy)
        #expect(result.selectedRoute == .legacy)
        #expect(result.interactiveScrollAllowed == false)
        #expect(result.visibleItemKeys.isEmpty)
        #expect(result.topVisibleItemKey == nil)
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func flagged_clean_route_allows_interactive_scroll_state() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.scrollInteractionPath == .collectionView)
        #expect(result.selectedRoute == .collectionView)
        #expect(result.usedCollectionViewFlag)
        #expect(result.collectionViewRestorePlanBuilt)
        #expect(result.interactiveScrollAllowed)
        #expect(result.topVisibleItemKey == "note:anchor")
    }

    @Test
    func user_scroll_after_restore_updates_top_visible_identity() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:older")
        ])

        #expect(result.restoredTopVisibleItemKey == "note:anchor")
        #expect(result.topVisibleItemKey == "note:older")
        #expect(result.userScrollUpdatedTopVisibleIdentity)
    }

    @Test
    func local_refresh_preserves_user_scroll_anchor() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:older"),
            .localRefresh(itemKeys: ["note:newest", "note:anchor", "note:older"])
        ])

        #expect(result.topVisibleItemKey == "note:older")
        #expect(result.localRefreshPreservedUserScrollAnchor)
    }

    @Test
    func prepend_local_rows_preserves_visible_anchor() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:anchor"),
            .prependLocalRows(itemKeys: ["note:incoming"])
        ])

        #expect(result.visibleItemKeys == ["note:incoming", "note:newest", "note:anchor", "note:older"])
        #expect(result.topVisibleItemKey == "note:anchor")
        #expect(result.prependPreservedVisibleAnchor)
    }

    @Test
    func append_local_rows_does_not_jump_top_visible_row() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:anchor"),
            .appendLocalRows(itemKeys: ["note:older-page"])
        ])

        #expect(result.visibleItemKeys == ["note:newest", "note:anchor", "note:older", "note:older-page"])
        #expect(result.topVisibleItemKey == "note:anchor")
        #expect(result.appendDidNotJumpTopVisibleRow)
    }

    @Test
    func reconfigure_visible_rows_does_not_change_anchor() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:anchor"),
            .reconfigureVisibleRows(itemKeys: ["note:anchor"])
        ])

        #expect(result.topVisibleItemKey == "note:anchor")
        #expect(result.reconfigureDidNotChangeAnchor)
        #expect(result.reconfiguredItemKeys == ["note:anchor"])
    }

    @Test
    func empty_refresh_preserves_empty_state_without_jump() async throws {
        let result = try await ScrollInteractionHarness.evaluate(
            window: ScrollInteractionFixture.window(rows: [], readState: nil, anchorItemKey: nil),
            requestedAnchorItemKey: nil,
            events: [
                .emptyRefresh
            ]
        )

        #expect(result.scrollInteractionPath == .collectionView)
        #expect(result.visibleItemKeys.isEmpty)
        #expect(result.topVisibleItemKey == nil)
        #expect(result.emptyRefreshPreservedEmptyStateWithoutJump)
    }

    @Test
    func scroll_interaction_uses_timeline_area_restore_gate_only() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.restoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
    }

    @Test
    func scroll_interaction_keeps_networkWaitedBeforeInteractiveScrollMS_zero() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
        #expect(result.storeNetworkStartCallCount == 0)
    }

    @Test
    func scroll_interaction_keeps_readMarkerChanged_false() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.readMarkerChanged == false)
    }

    @Test
    func scroll_interaction_does_not_write_db() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
    }

    @Test
    func scroll_interaction_does_not_advance_read_marker() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func scroll_interaction_does_not_mutate_pending_new() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.pendingNewMutated == false)
        #expect(!result.visibleItemKeys.contains("note:pending"))
    }

    @Test
    func scroll_interaction_does_not_call_dataSourceApply_from_Root() async throws {
        let result = try await ScrollInteractionHarness.evaluate()

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
    }

    @Test
    func scroll_interaction_result_is_codable_privacy_safe() async throws {
        let result = try await ScrollInteractionHarness.evaluate(events: [
            .userScroll(topVisibleItemKey: "note:older"),
            .prependLocalRows(itemKeys: ["note:incoming"]),
            .appendLocalRows(itemKeys: ["note:older-page"]),
            .reconfigureVisibleRows(itemKeys: ["note:anchor"])
        ])
        let data = try ScrollInteractionHarness.encodedData(result.interaction)
        Attachment.record(data, named: "timelinehome-scroll-interaction-result.json")
        let decoded = try JSONDecoder().decode(TimelineHomeCollectionViewScrollInteractionResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(TimelineHomeCollectionViewScrollInteractionResult.self)
        #expect(decoded == result.interaction)
        for fragment in ScrollInteractionFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = ScrollInteractionSelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(
            suiteName: "TimelineHomeCollectionViewScrollInteractionTests",
            testCount: 17
        )))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }
}

private struct ScrollInteractionHarnessResult: Codable, Equatable, Sendable {
    var interaction: TimelineHomeCollectionViewScrollInteractionResult
    var storeFetchInitialWindowCallCount: Int
    var storeNetworkStartCallCount: Int

    var scrollInteractionPath: TimelineHomeCollectionViewScrollInteractionPath { interaction.scrollInteractionPath }
    var selectedRoute: TimelineHomeRootBodyRouteSelection { interaction.selectedRoute }
    var usedCollectionViewFlag: Bool { interaction.usedCollectionViewFlag }
    var collectionViewRestorePlanBuilt: Bool { interaction.collectionViewRestorePlanBuilt }
    var interactiveScrollAllowed: Bool { interaction.interactiveScrollAllowed }
    var restoredTopVisibleItemKey: String? { interaction.restoredTopVisibleItemKey }
    var topVisibleItemKey: String? { interaction.topVisibleItemKey }
    var visibleItemKeys: [String] { interaction.visibleItemKeys }
    var userScrollUpdatedTopVisibleIdentity: Bool { interaction.userScrollUpdatedTopVisibleIdentity }
    var localRefreshPreservedUserScrollAnchor: Bool { interaction.localRefreshPreservedUserScrollAnchor }
    var prependPreservedVisibleAnchor: Bool { interaction.prependPreservedVisibleAnchor }
    var appendDidNotJumpTopVisibleRow: Bool { interaction.appendDidNotJumpTopVisibleRow }
    var reconfigureDidNotChangeAnchor: Bool { interaction.reconfigureDidNotChangeAnchor }
    var emptyRefreshPreservedEmptyStateWithoutJump: Bool { interaction.emptyRefreshPreservedEmptyStateWithoutJump }
    var reconfiguredItemKeys: [String] { interaction.reconfiguredItemKeys }
    var restoreGateScope: TimelineRestoreGateScope? { interaction.restoreGateScope }
    var timelineGateCoversRootShell: Bool { interaction.timelineGateCoversRootShell }
    var timelineGateCoversTabBar: Bool { interaction.timelineGateCoversTabBar }
    var timelineGateContinuesGlobalSplash: Bool { interaction.timelineGateContinuesGlobalSplash }
    var networkWaitedBeforeInteractiveScrollMS: Double { interaction.sideEffects.networkWaitedBeforeInteractiveScrollMS }
    var networkStarted: Bool { interaction.sideEffects.networkStarted }
    var requiresNetworkWork: Bool { interaction.sideEffects.requiresNetworkWork }
    var readMarkerChanged: Bool { interaction.sideEffects.readMarkerChanged }
    var readMarkerAdvanced: Bool { interaction.sideEffects.readMarkerAdvanced }
    var dbWriteAttempted: Bool { interaction.sideEffects.dbWriteAttempted }
    var requiresDBWrite: Bool { interaction.sideEffects.requiresDBWrite }
    var pendingNewMutated: Bool { interaction.sideEffects.pendingNewMutated }
    var dataSourceApplyFromRootCalled: Bool { interaction.sideEffects.dataSourceApplyFromRootCalled }
    var coordinatorOwnedDataSourceApplyAllowed: Bool { interaction.sideEffects.coordinatorOwnedDataSourceApplyAllowed }
}

private enum ScrollInteractionHarness {
    static func evaluate(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        wiringGateResult: ScrollInteractionWiringGateState? = .clean,
        window: TimelineRepositoryInitialWindow = ScrollInteractionFixture.defaultWindow(),
        requestedAnchorItemKey: String? = "note:anchor",
        events: [TimelineHomeCollectionViewScrollInteractionEvent] = []
    ) async throws -> ScrollInteractionHarnessResult {
        let store = ScrollInteractionRepositoryStore(window: window)
        let mode = TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: mode,
            repositoryStore: store,
            clock: TimelineFixedClock(nowMS: ScrollInteractionFixture.timestampMS)
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
                    feedID: ScrollInteractionFixture.feedID,
                    databaseAccountID: 1
                ),
                accountID: .debug,
                timelineKey: .home,
                repositoryPolicy: .initialRestore(maxVisibleCount: 10),
                visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
                requestedAnchorItemKey: requestedAnchorItemKey,
                createdAtMS: ScrollInteractionFixture.timestampMS
            )
        )
        let interaction = TimelineHomeCollectionViewScrollInteractionEvaluator.evaluate(
            TimelineHomeCollectionViewScrollInteractionInput(
                launchArguments: arguments,
                routeRestoreDecision: decision,
                events: events
            )
        )

        return ScrollInteractionHarnessResult(
            interaction: interaction,
            storeFetchInitialWindowCallCount: await store.fetchInitialWindowCallCount,
            storeNetworkStartCallCount: await store.networkStartCallCount
        )
    }

    static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func makeWiringGateResult(
        arguments: [String],
        state: ScrollInteractionWiringGateState?
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
                createdAtMS: ScrollInteractionFixture.timestampMS
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
                createdAtMS: ScrollInteractionFixture.timestampMS
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
                createdAtMS: ScrollInteractionFixture.timestampMS
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
            createdAtMS: ScrollInteractionFixture.timestampMS
        )
    }
}

private enum ScrollInteractionWiringGateState: Sendable {
    case clean
    case dirty
}

private enum ScrollInteractionFixture {
    static let feedID: Int64 = 10
    static let timestampMS: Int64 = 1_735_000_070_000

    static func defaultWindow() -> TimelineRepositoryInitialWindow {
        window(
            rows: [
                row(itemKey: "note:newest", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
                row(itemKey: "note:anchor", sourceEventID: eventID("b"), sortAt: 200, tieBreakID: "b"),
                row(itemKey: "note:older", sourceEventID: eventID("c"), sortAt: 100, tieBreakID: "c"),
                row(
                    itemKey: "note:pending",
                    sourceEventID: eventID("d"),
                    pendingNew: true,
                    sortAt: 50,
                    tieBreakID: "d"
                )
            ],
            readState: readState(scrollAnchorItemKey: "note:anchor", scrollAnchorEventID: eventID("b")),
            anchorItemKey: "note:anchor",
            excludedPendingNewCount: 1
        )
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
            "relay url",
            "pubkey",
            "event id",
            "eventid",
            "event_id",
            "private message content phrase",
            "raw content phrase",
            "raw event content phrase",
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

private actor ScrollInteractionRepositoryStore: TimelineRepositoryStore {
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

private struct ScrollInteractionSuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum ScrollInteractionSelectedSuiteCounts {
    static let current = [
        ScrollInteractionSuiteCount(suiteName: "TimelineHomeCollectionViewScrollInteractionTests", testCount: 17),
        ScrollInteractionSuiteCount(suiteName: "TimelineHomeCollectionViewRestoredRowDisplayQualityTests", testCount: 11),
        ScrollInteractionSuiteCount(suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests", testCount: 19),
        ScrollInteractionSuiteCount(suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests", testCount: 21),
        ScrollInteractionSuiteCount(suiteName: "TimelineHomeCollectionViewSimulatorStartupSmokeTests", testCount: 16)
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
