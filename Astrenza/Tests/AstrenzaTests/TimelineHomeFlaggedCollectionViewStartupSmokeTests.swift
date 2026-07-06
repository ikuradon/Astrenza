import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome flagged collectionView startup smoke")
struct TimelineHomeFlaggedCollectionViewStartupSmokeTests {
    @Test
    func flagged_startup_requires_collectionView_launch_arg() async throws {
        let result = try await startupSmoke(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.renderedRoute == .legacy)
        #expect(result.usedCollectionViewFlag == false)
        #expect(result.collectionViewStartupSmokeEvaluated == false)
        #expect(result.artifactSummary.routeDecisionSummary.contains("selectedRoute=legacy"))
    }

    @Test
    func default_startup_remains_legacy() async throws {
        let result = try await startupSmoke(arguments: ["Astrenza"])

        #expect(result.defaultStartupRemainsLegacy)
        #expect(result.selectedRoute == .legacy)
        #expect(result.renderedRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test
    func flagged_startup_requires_clean_wiring_gate() async throws {
        let result = try await startupSmoke(
            rootBodyRenderDecision: rootBodyDecision(wiringGateResult: dirtyWiringGateResult())
        )

        #expect(result.selectedRoute == .legacy)
        #expect(result.renderedRoute == .legacy)
        #expect(result.collectionViewStartupSmokeEvaluated == false)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
    }

    @Test
    func flagged_startup_uses_collectionView_route_decision() async throws {
        let result = try await startupSmoke()

        #expect(result.issueKinds.isEmpty)
        #expect(result.usedCollectionViewFlag)
        #expect(result.selectedRoute == .collectionView)
        #expect(result.renderedRoute == .collectionView)
        #expect(result.collectionViewStartupSmokeEvaluated)
        #expect(result.artifactSummary.routeDecisionSummary.contains("selectedRoute=collectionView"))
    }

    @Test
    func flagged_startup_preserves_root_shell_first_paint() async throws {
        let result = try await startupSmoke()

        #expect(result.rootShellFirstPaintPreserved)
        #expect(result.rootShellPresentation == .immediate)
        #expect(result.rootShellMustRenderBeforeTimelineRestore)
    }

    @Test
    func flagged_startup_uses_timeline_area_restore_gate_only() async throws {
        let result = try await startupSmoke()

        #expect(result.timelineRestoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
    }

    @Test
    func flagged_startup_networkWaitedBeforeInteractiveScrollMS_zero() async throws {
        let result = try await startupSmoke()

        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.artifactSummary.sideEffectSummary.contains("networkWaitMS=0"))
    }

    @Test
    func flagged_startup_readMarkerChanged_false() async throws {
        let result = try await startupSmoke()

        #expect(result.readMarkerChanged == false)
    }

    @Test
    func flagged_startup_does_not_start_network() async throws {
        let result = try await startupSmoke()
        let source = try sourceFile(named: "TimelineHomeCollectionViewStartupSmoke.swift")

        #expect(result.startupNetworkPatternHits.isEmpty)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func flagged_startup_does_not_write_db() async throws {
        let result = try await startupSmoke()
        let source = try sourceFile(named: "TimelineHomeCollectionViewStartupSmoke.swift")

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
        #expect(!source.contains("feed" + "_read" + "_state"))
        #expect(!source.contains("pending" + "_new"))
        #expect(!source.contains("resolve" + "_jobs"))
    }

    @Test
    func flagged_startup_does_not_advance_read_marker() async throws {
        let result = try await startupSmoke()

        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func flagged_startup_does_not_mutate_pending_new() async throws {
        let result = try await startupSmoke()

        #expect(result.pendingNewMutationAttempted == false)
        #expect(result.pendingNewVisibleMutationAttempted == false)
        #expect(result.artifactSummary.initialRestoreSummary.contains("pendingExcluded=1"))
    }

    @Test
    func flagged_startup_does_not_call_dataSourceApply_from_Root() async throws {
        let result = try await startupSmoke()
        let source = try sourceFile(named: "TimelineHomeCollectionViewStartupSmoke.swift")
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift", inTimelineEngine: false)

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!rootSource.contains("dataSource." + "apply"))
    }

    @Test
    func flagged_startup_does_not_construct_extra_NostrHomeTimelineStore() async throws {
        let result = try await startupSmoke()
        let source = try sourceFile(named: "TimelineHomeCollectionViewStartupSmoke.swift")

        #expect(result.extraNostrHomeTimelineStoreConstructed == false)
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func flagged_startup_result_bundle_scan_has_no_forbidden_patterns() async throws {
        let cleanScan = TimelineHomeFlaggedStartupResultBundleScanner.scan(text: "Test run with 1 test passed")
        let dirtyScan = TimelineHomeFlaggedStartupResultBundleScanner.scan(
            text: ["boot", "URL" + "Session" + "Web" + "Socket" + "Task", "blocked"].joined(separator: "\n")
        )
        let result = try await startupSmoke(resultBundleScan: cleanScan)

        #expect(cleanScan.passed)
        #expect(cleanScan.patternHits.isEmpty)
        #expect(dirtyScan.passed == false)
        #expect(dirtyScan.patternHits.map(\.pattern).contains("URL" + "Session" + "Web" + "Socket" + "Task"))
        #expect(result.resultBundleScanPassed)
        #expect(result.startupNetworkPatternHits.isEmpty)
    }

    @Test
    func flagged_startup_dirty_result_bundle_scan_blocks_collectionView_smoke_gate() async throws {
        let dirtyScan = TimelineHomeFlaggedStartupResultBundleScanner.scan(
            text: ["boot", "URL" + "Session" + "Web" + "Socket" + "Task", "blocked"].joined(separator: "\n")
        )
        let result = try await startupSmoke(resultBundleScan: dirtyScan)

        #expect(result.resultBundleScanPassed == false)
        #expect(result.issueKinds.contains(.resultBundleScanClean))
        #expect(result.collectionViewStartupSmokeEvaluated == false)
        #expect(result.selectedRoute == .legacy)
        #expect(result.renderedRoute == .legacy)
        #expect(result.startupNetworkPatternHits.isEmpty == false)
    }

    @Test
    func flagged_startup_blocks_stale_collectionView_restore_without_launch_arg() async throws {
        let staleCollectionViewRestore = try await restoreDecision(rootBodyRenderDecision: rootBodyDecision())
        let result = TimelineHomeFlaggedCollectionViewStartupSmoke.evaluate(
            TimelineHomeFlaggedStartupSmokeInput(
                launchArguments: ["Astrenza"],
                rootBodyRenderDecision: rootBodyDecision(arguments: ["Astrenza"]),
                restoreDecision: staleCollectionViewRestore,
                resultBundleScan: .clean,
                createdAtMS: 1_735_000_050_000
            )
        )

        #expect(staleCollectionViewRestore.selectedRoute == .collectionView)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.collectionViewStartupSmokeEvaluated == false)
        #expect(result.selectedRoute == .legacy)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func startup_smoke_result_is_codable_privacy_safe() async throws {
        let result = try await startupSmoke()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(TimelineHomeFlaggedStartupSmokeResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeCollectionViewStartupSmokeArtifact.self)
        assertSendable(TimelineHomeFlaggedStartupResultBundleScanner.self)
        assertSendable(TimelineHomeFlaggedStartupSmokeResult.self)
        assertSendable(TimelineHomeFlaggedStartupSmokeIssueKind.self)
        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)
        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeFlaggedCollectionViewStartupSmokeTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteRestoreIntegrationTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootBodyRenderSwitchTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    fileprivate static func window() -> TimelineRepositoryInitialWindow {
        let rows = [
            row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 300, tieBreakID: "a"),
            row(
                itemKey: "note:pending",
                sourceEventID: eventID("b"),
                pendingNew: true,
                sortAt: 400,
                tieBreakID: "b"
            )
        ]

        return TimelineRepositoryInitialWindow(
            feedID: 10,
            rows: rows,
            readState: readState(scrollAnchorItemKey: "note:visible", scrollAnchorEventID: eventID("a")),
            anchorItemKey: "note:visible",
            issues: [],
            diagnostics: TimelineRepositoryStoreDiagnostics(
                totalFeedItemRowCount: rows.count,
                sqlVisibleRowCount: 1,
                excludedHiddenCount: 0,
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

    fileprivate static func row(
        itemKey: String,
        sourceEventID: String,
        pendingNew: Bool = false,
        sortAt: Int64,
        tieBreakID: String
    ) -> TimelineRepositoryFeedItemRow {
        TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: sourceEventID,
            reason: .author,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            pendingNew: pendingNew,
            insertedAtMS: 1,
            updatedAtMS: 2
        )
    }

    fileprivate static func readState(
        scrollAnchorItemKey: String,
        scrollAnchorEventID: String
    ) -> TimelineRepositoryReadStateRow {
        TimelineRepositoryReadStateRow(
            databaseAccountID: 1,
            feedID: 10,
            scrollAnchorItemKey: scrollAnchorItemKey,
            scrollAnchorEventID: scrollAnchorEventID,
            scrollAnchorOffsetPX: 12,
            viewportHeightPX: 640,
            viewportWidthPX: 390,
            contentInsetTopPX: 8,
            contentInsetBottomPX: 16,
            clientStateJSON: "{}",
            lastViewedAtMS: 1000,
            updatedAtMS: 2000
        )
    }

    fileprivate static func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }
}

private func startupSmoke(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    rootBodyRenderDecision: TimelineHomeRootBodyRenderDecision? = nil,
    store: FakeStartupSmokeRepositoryStore = FakeStartupSmokeRepositoryStore(
        window: TimelineHomeFlaggedCollectionViewStartupSmokeTests.window()
    ),
    resultBundleScan: TimelineHomeStartupResultBundleScan = .clean
) async throws -> TimelineHomeFlaggedStartupSmokeResult {
    let rootDecision = rootBodyRenderDecision ?? rootBodyDecision(arguments: arguments)
    let restoreDecision = try await restoreDecision(
        arguments: arguments,
        rootBodyRenderDecision: rootDecision,
        store: store
    )
    return TimelineHomeFlaggedCollectionViewStartupSmoke.evaluate(
        TimelineHomeFlaggedStartupSmokeInput(
            launchArguments: arguments,
            rootBodyRenderDecision: rootDecision,
            restoreDecision: restoreDecision,
            resultBundleScan: resultBundleScan,
            createdAtMS: 1_735_000_050_000
        )
    )
}

private func restoreDecision(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    rootBodyRenderDecision: TimelineHomeRootBodyRenderDecision,
    store: FakeStartupSmokeRepositoryStore = FakeStartupSmokeRepositoryStore(
        window: TimelineHomeFlaggedCollectionViewStartupSmokeTests.window()
    )
) async throws -> TimelineHomeCollectionViewRouteRestoreDecision {
    let container = TimelineSurfaceDependencyContainer.offline(
        mode: TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode,
        repositoryStore: store,
        clock: TimelineFixedClock(nowMS: 1_735_000_050_000)
    )
    return try await TimelineHomeCollectionViewRouteRestoreComposer.compose(
        TimelineHomeCollectionViewRouteRestoreComposerInput(
            launchArguments: arguments,
            rootBodyRenderDecision: rootBodyRenderDecision,
            container: container,
            readRequest: TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            accountID: .debug,
            timelineKey: .home,
            repositoryPolicy: .initialRestore(maxVisibleCount: 10),
            visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
            requestedAnchorItemKey: "note:visible",
            createdAtMS: 1_735_000_050_000
        )
    )
}

private func rootBodyDecision(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    wiringGateResult: TimelineHomeRootBodyActivationWiringResult? = cleanWiringGateResult()
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
            createdAtMS: 1_735_000_050_000
        )
    )
}

private func cleanWiringGateResult(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    context: TimelineHomeRootBodyActivationWiringContext = .defaultClean()
) -> TimelineHomeRootBodyActivationWiringResult {
    TimelineHomeRootBodyActivationWiringGate.evaluate(
        TimelineHomeRootBodyActivationWiringInput(
            launchArguments: arguments,
            activationSwitchResult: cleanActivationSwitchResult(),
            context: context,
            createdAtMS: 1_735_000_050_000
        )
    )
}

private func dirtyWiringGateResult() -> TimelineHomeRootBodyActivationWiringResult {
    cleanWiringGateResult(context: .defaultClean(mutatingLegacyAndCollectionViewInSameSession: true))
}

private func cleanActivationSwitchResult() -> TimelineHomeActivatedRouteDecision {
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
        createdAtMS: 1_735_000_050_000
    )
}

private actor FakeStartupSmokeRepositoryStore: TimelineRepositoryStore {
    let window: TimelineRepositoryInitialWindow

    init(window: TimelineRepositoryInitialWindow) {
        self.window = window
    }

    func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        window
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

private var selectedSwiftTestingSuites: [String] {
    [
        "TimelineHomeFlaggedCollectionViewStartupSmokeTests",
        "TimelineHomeCollectionViewRouteRestoreIntegrationTests",
        "TimelineHomeRootBodyRenderSwitchTests",
        "TimelineCollectionViewControllerSmokeTests",
        "TimelineInitialRestoreSnapshotCoordinatorHarnessTests",
        "TimelineEngineScaffoldTests"
    ]
}

private var requiredResultKeys: Set<String> {
    [
        "artifactSummary",
        "collectionViewStartupSmokeEvaluated",
        "coordinatorOwnedDataSourceApplyAllowed",
        "createdAtMS",
        "dataSourceApplyFromRootCalled",
        "dbWriteAttempted",
        "defaultStartupRemainsLegacy",
        "extraNostrHomeTimelineStoreConstructed",
        "issueKinds",
        "launchArguments",
        "manualFallbackRoute",
        "networkStarted",
        "networkWaitedBeforeInteractiveScrollMS",
        "pendingNewMutationAttempted",
        "pendingNewVisibleMutationAttempted",
        "readMarkerAdvanced",
        "readMarkerChanged",
        "renderedRoute",
        "requiresDBWrite",
        "requiresNetworkWork",
        "resultBundleScanPassed",
        "rollbackRoute",
        "rootShellFirstPaintPreserved",
        "rootShellMustRenderBeforeTimelineRestore",
        "rootShellPresentation",
        "selectedRoute",
        "startupNetworkPatternHits",
        "timelineGateContinuesGlobalSplash",
        "timelineGateCoversRootShell",
        "timelineGateCoversTabBar",
        "timelineRestoreGateScope",
        "usedCollectionViewFlag"
    ]
}

private var forbiddenStartupNetworkTokens: [String] {
    [
        "Local" + "Data" + "Task",
        "ATS " + "failure",
        "n" + "w_",
        "Web" + "Socket",
        "URL" + "Session" + "Web" + "Socket" + "Task",
        "ws" + "s://",
        "set" + "Default" + "Relays",
        "URL" + "Session",
        "relay " + "connection " + "attempts"
    ]
}

private var forbiddenPrivacyFragments: [String] {
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
        "raw event content phrase",
        "private message content phrase",
        "relay url",
        "pubkey",
        "event id",
        "eventid",
        "event_id",
        "bearer"
    ]
}

private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func sourceFile(
    named fileName: String,
    inTimelineEngine: Bool = true
) throws -> String {
    let appRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/AstrenzaApp")
    let candidate = inTimelineEngine
        ? appRoot.appendingPathComponent("TimelineEngine/\(fileName)")
        : appRoot.appendingPathComponent(fileName)
    return try String(contentsOf: candidate, encoding: .utf8)
}

private func assertSendable<T: Sendable>(_: T.Type) {}
