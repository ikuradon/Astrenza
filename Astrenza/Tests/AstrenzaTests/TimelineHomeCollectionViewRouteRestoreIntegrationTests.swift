import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route restore integration")
struct TimelineHomeCollectionViewRouteRestoreIntegrationTests {
    @Test
    func restore_requires_explicit_flag() async throws {
        let store = FakeRouteRestoreRepositoryStore(window: Self.window())
        let result = try await restore(arguments: ["Astrenza"], store: store)

        #expect(result.selectedRoute == .legacy)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.restorePlan == nil)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.legacyRestorePathPreserved)
        #expect(await store.fetchInitialWindowCallCount == 0)
    }

    @Test
    func restore_requires_clean_root_body_wiring_gate() async throws {
        let store = FakeRouteRestoreRepositoryStore(window: Self.window())
        let result = try await restore(
            rootBodyRenderDecision: rootBodyDecision(wiringGateResult: dirtyWiringGateResult()),
            store: store
        )

        #expect(result.selectedRoute == .legacy)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.restorePlan == nil)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.issueKinds.contains(.sameSessionDoubleMutationPrevented))
        #expect(result.legacyRestorePathPreserved)
        #expect(await store.fetchInitialWindowCallCount == 0)
    }

    @Test
    func default_without_flag_keeps_legacy_restore_path() async throws {
        let result = try await restore(arguments: ["Astrenza"])

        #expect(result.selectedRoute == .legacy)
        #expect(result.legacyRestorePathPreserved)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.artifactSummary.restoreDecisionSummary.contains("selectedRoute=legacy"))
    }

    @Test
    func dirty_wiring_gate_keeps_legacy_restore_path() async throws {
        let result = try await restore(rootBodyRenderDecision: rootBodyDecision(wiringGateResult: dirtyWiringGateResult()))

        #expect(result.selectedRoute == .legacy)
        #expect(result.legacyRestorePathPreserved)
        #expect(result.collectionViewRestorePlanBuilt == false)
        #expect(result.issueKinds.contains(.cleanRootBodyWiringGate))
        #expect(result.artifactSummary.restoreDecisionSummary.contains("legacyFallback=true"))
    }

    @Test
    func clean_flagged_route_builds_collectionView_restore_plan() async throws {
        let store = FakeRouteRestoreRepositoryStore(window: Self.window())
        let result = try await restore(store: store)
        let plan = try #require(result.restorePlan)

        #expect(result.issueKinds.isEmpty)
        #expect(result.selectedRoute == .collectionView)
        #expect(result.collectionViewRestorePlanBuilt)
        #expect(plan.snapshotItemKeys == ["note:visible"])
        #expect(plan.restoreGateIntent == .protectAnchorRestore)
        #expect(plan.localDBReadWork)
        #expect(await store.fetchInitialWindowCallCount == 1)
        #expect(await store.networkStartCallCount == 0)
    }

    @Test
    func restore_plan_uses_timeline_area_restore_gate_only() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)

        #expect(plan.restoreGateScope == .timelineArea)
        #expect(plan.timelineGateCoversRootShell == false)
        #expect(plan.timelineGateCoversTabBar == false)
        #expect(plan.timelineGateContinuesGlobalSplash == false)
        #expect(result.issueKinds.contains(.timelineAreaRestoreGateOnly) == false)
    }

    @Test
    func restore_plan_keeps_networkWaitedBeforeInteractiveScrollMS_zero() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)

        #expect(plan.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.requiresNetworkWork == false)
    }

    @Test
    func restore_plan_keeps_readMarkerChanged_false() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)

        #expect(plan.readMarkerChanged == false)
        #expect(result.readMarkerChanged == false)
    }

    @Test
    func restore_plan_does_not_write_db() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)

        #expect(plan.dbWriteAttempted == false)
        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
    }

    @Test
    func restore_plan_does_not_advance_read_marker() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)

        #expect(plan.readMarkerAdvanced == false)
        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func restore_plan_does_not_call_dataSourceApply_from_Root() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteRestore.swift")
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift", inTimelineEngine: false)

        #expect(plan.dataSourceApplyFromRootCalled == false)
        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(plan.coordinatorOwnedDataSourceApplyAllowed)
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!rootSource.contains("dataSource." + "apply"))
    }

    @Test
    func restore_plan_does_not_start_network() async throws {
        let result = try await restore()
        let plan = try #require(result.restorePlan)
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteRestore.swift")

        #expect(plan.networkStarted == false)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func restore_plan_preserves_legacy_rollback() async throws {
        let result = try await restore()

        #expect(result.selectedRoute == .collectionView)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.legacyRestorePathPreserved == false)
    }

    @Test
    func restore_plan_records_local_artifact_summary() async throws {
        let result = try await restore()

        #expect(result.artifactSummary.localOnly)
        #expect(result.artifactSummary.restoreDecisionSummary.contains("selectedRoute=collectionView"))
        #expect(result.artifactSummary.initialRestoreSummary.contains("items=1"))
        #expect(result.artifactSummary.sideEffectSummary.contains("network=false"))
        #expect(result.artifactSummary.deterministicSummary.contains("restorePlanBuilt=true"))
        #expect(!result.artifactSummary.deterministicSummary.contains("note:visible"))
    }

    @Test
    func restore_plan_result_is_codable_privacy_safe() async throws {
        let result = try await restore()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(
            TimelineHomeCollectionViewRouteRestoreDecision.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeCollectionViewRouteRestorePlan.self)
        assertSendable(TimelineHomeCollectionViewRouteRestoreDecision.self)
        assertSendable(TimelineHomeCollectionViewRouteRestoreArtifactSummary.self)
        assertSendable(TimelineHomeCollectionViewRouteRestoreIssueKind.self)
        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredDecisionKeys)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteRestoreIntegrationTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineInitialRestoreSnapshotCoordinatorHarnessTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineSurfaceDependencyContainerTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    fileprivate static func window() -> TimelineRepositoryInitialWindow {
        let rows = [
            row(
                itemKey: "note:visible",
                sourceEventID: eventID("a"),
                sortAt: 300,
                tieBreakID: "a"
            ),
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

private func restore(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    rootBodyRenderDecision: TimelineHomeRootBodyRenderDecision? = nil,
    store: FakeRouteRestoreRepositoryStore = FakeRouteRestoreRepositoryStore(
        window: TimelineHomeCollectionViewRouteRestoreIntegrationTests.window()
    )
) async throws -> TimelineHomeCollectionViewRouteRestoreDecision {
    let container = TimelineSurfaceDependencyContainer.offline(
        mode: TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode,
        repositoryStore: store,
        clock: TimelineFixedClock(nowMS: 1_735_000_040_000)
    )
    return try await TimelineHomeCollectionViewRouteRestoreComposer.compose(
        TimelineHomeCollectionViewRouteRestoreComposerInput(
            launchArguments: arguments,
            rootBodyRenderDecision: rootBodyRenderDecision ?? rootBodyDecision(arguments: arguments),
            container: container,
            readRequest: TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            accountID: .debug,
            timelineKey: .home,
            repositoryPolicy: .initialRestore(maxVisibleCount: 10),
            visibleWindowPolicy: .initialRestore(maxVisibleCount: 10),
            requestedAnchorItemKey: "note:visible",
            createdAtMS: 1_735_000_040_000
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
            createdAtMS: 1_735_000_040_000
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
            createdAtMS: 1_735_000_040_000
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
        createdAtMS: 1_735_000_040_000
    )
}

private actor FakeRouteRestoreRepositoryStore: TimelineRepositoryStore {
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

private var selectedSwiftTestingSuites: [String] {
    [
        "TimelineHomeCollectionViewRouteRestoreIntegrationTests",
        "TimelineHomeRootBodyRenderSwitchTests",
        "TimelineHomeRootBodyActivationWiringGateConsumerTests",
        "TimelineHomeRootBodyActivationWiringGateTests",
        "TimelineHomeCollectionViewRouteActivationSwitchTests",
        "TimelineHomeRootActivationDecisionSnapshotChainConsumerTests",
        "TimelineHomeRootActivationDecisionSnapshotChainTests",
        "TimelineHomeRootActivationPreflightTests",
        "TimelineHomeActivationArtifactChainConsumerTests",
        "TimelineHomeCollectionViewRouteActivationReadinessConsumerTests",
        "TimelineHomeCollectionViewRouteActivationTests",
        "TimelineHomeCollectionViewRouteBehindFlagConstructionTests",
        "TimelineHomeConstructionArtifactChainConsumerTests",
        "TimelineHomeCollectionViewOffscreenConstructionHarnessResultConsumerTests",
        "TimelineHomeCollectionViewOffscreenConstructionHarnessTests",
        "TimelineHomeRouteConstructionPlanConsumerTests",
        "TimelineHomeRouteConstructionReadinessTests",
        "TimelineHomeCollectionViewRouteConstructionTests",
        "TimelineHomeRootRouteDecisionSnapshotConsumerTests",
        "TimelineHomeRootRouteDecisionSnapshotTests",
        "TimelineHomeRootRouteDiagnosticsSinkInjectionTests",
        "TimelineHomeRouteDiagnosticsSinkTests",
        "TimelineHomeRootRouteCallSiteTests",
        "TimelineHomeRootRoutePreflightTests",
        "TimelineHomeRootRouteGuardTests",
        "TimelineHomeRouteDiagnosticsTests",
        "TimelineHomeRouteHostTests",
        "TimelineHomeRouteIntegrationSkeletonTests",
        "TimelineHomeRouteAdapterTests",
        "TimelineHomeLaunchRestoreContractTests",
        "TimelineHomeEngineModeTests",
        "TimelineSurfaceDependencyContainerTests",
        "TimelineCollectionViewControllerSmokeTests",
        "TimelineInitialRestoreSnapshotCoordinatorHarnessTests",
        "TimelineEngineScaffoldTests"
    ]
}

private var requiredDecisionKeys: Set<String> {
    [
        "artifactSummary",
        "collectionViewRestorePlanBuilt",
        "createdAtMS",
        "dataSourceApplyFromRootCalled",
        "dbWriteAttempted",
        "issueKinds",
        "legacyRestorePathPreserved",
        "manualFallbackRoute",
        "networkStarted",
        "networkWaitedBeforeInteractiveScrollMS",
        "noExtraNostrHomeTimelineStore",
        "readMarkerAdvanced",
        "readMarkerChanged",
        "requiresDBWrite",
        "requiresNetworkWork",
        "restorePlan",
        "rollbackRoute",
        "selectedRoute"
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
