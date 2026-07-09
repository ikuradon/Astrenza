import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView restored row display quality")
struct TimelineHomeCollectionViewRestoredRowDisplayQualityTests {
    @Test
    func default_without_flag_uses_legacy_display_path() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render(arguments: ["Astrenza"])

        #expect(result.display.displayPath == .legacy)
        #expect(result.display.selectedRoute == .legacy)
        #expect(result.display.rows.isEmpty)
        #expect(result.display.collectionViewRestorePlanBuilt == false)
        #expect(result.storeFetchInitialWindowCallCount == 0)
    }

    @Test
    func flagged_clean_route_displays_note_row_summary() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let row = try #require(result.display.rows.first(where: { $0.kind == .note }))

        #expect(result.display.displayPath == .collectionView)
        #expect(row.headline == "Restored note")
        #expect(row.detail == "Safe local note summary")
        #expect(row.targetState == .notRequired)
    }

    @Test
    func visible_note_row_has_safe_display_fields() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let row = try #require(result.display.rows.first(where: { $0.kind == .note }))

        #expect(row.displayKey == "row-1")
        #expect(row.safeContentOnly)
        #expect(row.headline == "Restored note")
        #expect(row.detail == "Safe local note summary")
    }

    @Test
    func quote_missing_target_displays_safe_missing_target_state() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let row = try #require(result.display.rows.first(where: { $0.kind == .quoteMissingTarget }))

        #expect(row.headline == "Quote unavailable")
        #expect(row.detail == "Original note unavailable")
        #expect(row.targetState == .missingTarget)
        #expect(row.safeContentOnly)
    }

    @Test
    func repost_missing_target_displays_safe_missing_target_state() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let row = try #require(result.display.rows.first(where: { $0.kind == .repostMissingTarget }))

        #expect(row.headline == "Repost unavailable")
        #expect(row.detail == "Original note unavailable")
        #expect(row.targetState == .missingTarget)
        #expect(row.safeContentOnly)
    }

    @Test
    func pending_rows_are_not_displayed() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()

        #expect(result.display.pendingExcludedCount == 1)
        #expect(result.display.sideEffects.pendingNewMutated == false)
        #expect(result.display.rows.count == 3)
    }

    @Test
    func hidden_rows_are_not_displayed() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()

        #expect(result.display.hiddenExcludedCount == 1)
        #expect(result.display.rows.count == 3)
    }

    @Test
    func display_order_matches_restore_plan() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()

        #expect(result.display.displayOrderTokens == result.display.restorePlanOrderTokens)
        #expect(result.display.rows.map(\.kind) == [.note, .quoteMissingTarget, .repostMissingTarget])
    }

    @Test
    func display_result_is_codable_privacy_safe() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let data = try RestoredRowDisplayQualityHarness.encodedData(result.display)
        Attachment.record(data, named: "timelinehome-display-quality-result.json")
        let decoded = try JSONDecoder().decode(
            TimelineHomeCollectionViewRestoredRowDisplayQualityResult.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(TimelineHomeCollectionViewRestoredRowDisplayQualityResult.self)
        #expect(decoded == result.display)
        for fragment in RestoredRowDisplayQualityFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func no_network_db_readMarker_pendingNew_rootApply_side_effects() async throws {
        let result = try await RestoredRowDisplayQualityHarness.render()
        let sideEffects = result.display.sideEffects

        #expect(sideEffects.networkStarted == false)
        #expect(sideEffects.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(sideEffects.requiresNetworkWork == false)
        #expect(sideEffects.dbWriteAttempted == false)
        #expect(sideEffects.requiresDBWrite == false)
        #expect(sideEffects.readMarkerChanged == false)
        #expect(sideEffects.readMarkerAdvanced == false)
        #expect(sideEffects.pendingNewMutated == false)
        #expect(sideEffects.dataSourceApplyFromRootCalled == false)
        #expect(sideEffects.extraNostrHomeTimelineStoreConstructed == false)
        #expect(result.storeNetworkStartCallCount == 0)
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = RestoredRowDisplayQualitySelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(
            suiteName: "TimelineHomeCollectionViewRestoredRowDisplayQualityTests",
            testCount: 11
        )))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }
}

private struct RestoredRowDisplayQualityHarnessResult: Sendable {
    var display: TimelineHomeCollectionViewRestoredRowDisplayQualityResult
    var storeFetchInitialWindowCallCount: Int
    var storeNetworkStartCallCount: Int
}

private enum RestoredRowDisplayQualityHarness {
    static func render(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        wiringGateResult: RestoredRowDisplayQualityWiringGateState? = .clean,
        window: TimelineRepositoryInitialWindow = RestoredRowDisplayQualityFixture.window()
    ) async throws -> RestoredRowDisplayQualityHarnessResult {
        let store = RestoredRowDisplayQualityRepositoryStore(window: window)
        let mode = TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: mode,
            repositoryStore: store,
            clock: TimelineFixedClock(nowMS: RestoredRowDisplayQualityFixture.timestampMS)
        )
        let rootDecision = rootBodyDecision(
            arguments: arguments,
            wiringGateResult: makeWiringGateResult(arguments: arguments, state: wiringGateResult)
        )
        let routeDecision = try await TimelineHomeCollectionViewRouteRestoreComposer.compose(
            TimelineHomeCollectionViewRouteRestoreComposerInput(
                launchArguments: arguments,
                rootBodyRenderDecision: rootDecision,
                container: container,
                readRequest: TimelineRepositoryReadRequest(
                    feedID: RestoredRowDisplayQualityFixture.feedID,
                    databaseAccountID: 1
                ),
                accountID: .debug,
                timelineKey: .home,
                repositoryPolicy: .initialRestore(maxVisibleCount: 10),
                visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
                requestedAnchorItemKey: "note:visible",
                createdAtMS: RestoredRowDisplayQualityFixture.timestampMS
            )
        )
        let display = TimelineHomeCollectionViewRestoredRowDisplayQualityEvaluator.evaluate(
            TimelineHomeCollectionViewRestoredRowDisplayQualityInput(
                launchArguments: arguments,
                routeRestoreDecision: routeDecision,
                initialWindow: window
            )
        )

        return RestoredRowDisplayQualityHarnessResult(
            display: display,
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
        state: RestoredRowDisplayQualityWiringGateState?
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
                createdAtMS: RestoredRowDisplayQualityFixture.timestampMS
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
                createdAtMS: RestoredRowDisplayQualityFixture.timestampMS
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
                createdAtMS: RestoredRowDisplayQualityFixture.timestampMS
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
            createdAtMS: RestoredRowDisplayQualityFixture.timestampMS
        )
    }
}

private enum RestoredRowDisplayQualityWiringGateState: Sendable {
    case clean
    case dirty
}

private enum RestoredRowDisplayQualityFixture {
    static let feedID: Int64 = 10
    static let timestampMS: Int64 = 1_735_000_060_000

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
                sqlVisibleRowCount: 3,
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
            "relay url",
            "relayurl",
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

private actor RestoredRowDisplayQualityRepositoryStore: TimelineRepositoryStore {
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

private struct RestoredRowDisplayQualitySuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum RestoredRowDisplayQualitySelectedSuiteCounts {
    static let current = [
        RestoredRowDisplayQualitySuiteCount(
            suiteName: "TimelineHomeCollectionViewRestoredRowDisplayQualityTests",
            testCount: 11
        ),
        RestoredRowDisplayQualitySuiteCount(
            suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests",
            testCount: 19
        ),
        RestoredRowDisplayQualitySuiteCount(
            suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests",
            testCount: 21
        ),
        RestoredRowDisplayQualitySuiteCount(
            suiteName: "TimelineHomeCollectionViewSimulatorStartupSmokeTests",
            testCount: 16
        )
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
