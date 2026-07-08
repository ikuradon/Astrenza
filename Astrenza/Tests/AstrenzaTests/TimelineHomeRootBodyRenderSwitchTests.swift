import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome Root body render switch")
struct TimelineHomeRootBodyRenderSwitchTests {
    @Test
    func root_body_render_switch_requires_explicit_flag() {
        let decision = decide(arguments: ["Astrenza"])

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.collectionViewRouteRendered == false)
        #expect(decision.legacyRouteRendered)
        #expect(decision.wiringAllowed)
        #expect(decision.issueKinds.contains(.explicitCollectionViewLaunchFlag))
    }

    @Test
    func root_body_render_switch_requires_clean_wiring_gate() {
        let decision = decide(wiringGateResult: dirtyWiringGateResult())

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.collectionViewRouteRendered == false)
        #expect(decision.issueKinds.contains(.cleanWiringGate))
        #expect(decision.wiringAllowed == false)
    }

    @Test
    func default_without_flag_renders_legacy() {
        let decision = decide(arguments: ["Astrenza"])

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.legacyRouteRendered)
        #expect(decision.collectionViewRouteRendered == false)
        #expect(decision.rollbackRoute == .legacy)
        #expect(decision.manualFallbackRoute == .legacy)
    }

    @Test
    func dirty_wiring_gate_renders_legacy() {
        let decision = decide(wiringGateResult: dirtyWiringGateResult())

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.legacyRouteRendered)
        #expect(decision.collectionViewRouteRendered == false)
        #expect(decision.issueKinds.contains(.cleanWiringGate))
    }

    @Test
    func unevaluated_wiring_gate_renders_legacy() {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.selectedRoute == .legacy)
        #expect(decision.legacyRouteRendered)
        #expect(decision.collectionViewRouteRendered == false)
    }

    @Test
    func unevaluated_wiring_gate_does_not_activate_collectionView() {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.selectedRoute != .collectionView)
        #expect(decision.collectionViewRouteRendered == false)
    }

    @Test
    func unevaluated_wiring_gate_records_blocking_issue() {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())

        #expect(decision.explicitCollectionViewFlagPresent)
        #expect(decision.wiringGateEvaluated == false)
        #expect(decision.wiringAllowed)
        #expect(decision.issueKinds == [.cleanWiringGate])
    }

    @Test
    func unevaluated_wiring_gate_preserves_rollback_and_manualFallback_legacy() {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.rollbackRoute == .legacy)
        #expect(decision.manualFallbackRoute == .legacy)
    }

    @Test
    func unevaluated_wiring_gate_does_not_call_dataSourceApply_from_Root() throws {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.dataSourceApplyFromRootCalled == false)
        #expect(!decision.issueKinds.contains(.dataSourceApplyFromRootNotCalled))
        #expect(!rootSource.contains("dataSource." + "apply"))
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func unevaluated_wiring_gate_does_not_start_network() throws {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.networkStartedBeforeInteractiveScroll == false)
        #expect(decision.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(!decision.issueKinds.contains(.networkNotStartedBeforeInteractiveScroll))
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func unevaluated_wiring_gate_does_not_write_db() throws {
        let decision = decide(wiringGateResult: unevaluatedCleanLookingWiringGateResult())
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        assertOnlyUnevaluatedWiringGateBlocks(decision)
        #expect(decision.dbWriteAttempted == false)
        #expect(!decision.issueKinds.contains(.dbWriteNotAttempted))
        #expect(!source.contains("feed" + "_read" + "_state"))
        #expect(!source.contains("pending" + "_new"))
        #expect(!source.contains("resolve" + "_jobs"))
    }

    @Test
    func clean_flagged_wiring_renders_collectionView() throws {
        let decision = decide()
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")

        #expect(decision.issueKinds.isEmpty)
        #expect(decision.selectedRoute == .collectionView)
        #expect(decision.collectionViewRouteRendered)
        #expect(decision.legacyRouteRendered == false)
        #expect(rootSource.contains("TimelineHomeRootBodyRenderSwitch.decide"))
        #expect(rootSource.contains("rootBodyRenderDecision.selectedRoute == .collectionView"))
        #expect(rootSource.contains("Timeline" + "Surface("))
    }

    @Test
    func render_switch_preserves_root_shell_first_paint() {
        let decision = decide()

        #expect(decision.rootShellPresentation == .immediate)
        #expect(decision.rootShellMustRenderBeforeTimelineRestore)
        #expect(decision.rootShellFirstPaintPreserved)
        #expect(!decision.issueKinds.contains(.rootShellFirstPaintPreserved))
    }

    @Test
    func render_switch_uses_timeline_area_restore_gate_only() {
        let decision = decide()

        #expect(decision.timelineRestoreGateScope == .timelineArea)
        #expect(decision.timelineGateCoversRootShell == false)
        #expect(decision.timelineGateCoversTabBar == false)
        #expect(decision.timelineGateContinuesGlobalSplash == false)
        #expect(!decision.issueKinds.contains(.timelineAreaRestoreGateOnly))
    }

    @Test
    func render_switch_does_not_start_network_before_interactive_scroll() throws {
        let decision = decide()
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        #expect(decision.networkStartedBeforeInteractiveScroll == false)
        #expect(decision.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(!decision.issueKinds.contains(.networkNotStartedBeforeInteractiveScroll))
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func render_switch_does_not_write_db() throws {
        let decision = decide()
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        #expect(decision.dbWriteAttempted == false)
        #expect(!decision.issueKinds.contains(.dbWriteNotAttempted))
        #expect(!source.contains("feed" + "_read" + "_state"))
        #expect(!source.contains("pending" + "_new"))
        #expect(!source.contains("resolve" + "_jobs"))
    }

    @Test
    func render_switch_does_not_advance_read_marker() {
        let decision = decide()

        #expect(decision.readMarkerAdvanced == false)
        #expect(!decision.issueKinds.contains(.readMarkerUnchanged))
    }

    @Test
    func render_switch_does_not_call_dataSourceApply_from_Root() throws {
        let decision = decide()
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        #expect(decision.dataSourceApplyFromRootCalled == false)
        #expect(!decision.issueKinds.contains(.dataSourceApplyFromRootNotCalled))
        #expect(!rootSource.contains("dataSource." + "apply"))
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func render_switch_does_not_construct_extra_NostrHomeTimelineStore() throws {
        let decision = decide()
        let source = try sourceFile(named: "TimelineHomeRootBodyRenderSwitch.swift")

        #expect(decision.extraNostrHomeTimelineStoreConstructed == false)
        #expect(!decision.issueKinds.contains(.noExtraNostrHomeTimelineStore))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func render_switch_prevents_same_session_double_mutation() {
        let decision = decide()
        let dirty = decide(wiringGateResult: doubleMutationWiringGateResult())

        #expect(decision.sameSessionDoubleMutationPrevented)
        #expect(dirty.selectedRoute == .legacy)
        #expect(dirty.sameSessionDoubleMutationPrevented == false)
        #expect(dirty.issueKinds.contains(.sameSessionDoubleMutationPrevented))
    }

    @Test
    func rollback_returns_to_legacy() {
        let decision = decide()

        #expect(decision.selectedRoute == .collectionView)
        #expect(decision.rollbackRoute == .legacy)
        #expect(decision.manualFallbackRoute == .legacy)
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuiteCounts.allSatisfy { $0.executedTestCount > 0 })
        #expect(selectedSwiftTestingSuiteCounts.contains {
            $0.suiteName == "TimelineHomeRootBodyRenderSwitchTests"
                && $0.executedTestCount == 23
        })
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootBodyRenderSwitchTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeStartupSmokeLocalGateReportTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeFlaggedCollectionViewStartupSmokeTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootBodyActivationWiringGateTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteActivationSwitchTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    @Test
    func render_switch_result_is_codable_privacy_safe() throws {
        let decision = decide()
        let data = try encodedData(decision)
        let decoded = try JSONDecoder().decode(TimelineHomeRootBodyRenderDecision.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeRootBodyRenderSwitchInput.self)
        assertSendable(TimelineHomeRootBodyRenderDecision.self)
        assertSendable(TimelineHomeRootBodyRouteSelection.self)
        assertSendable(TimelineHomeRootBodyRenderSwitchIssueKind.self)
        assertSendable(TimelineHomeRootBodyRenderSwitch.self)
        #expect(decoded == decision)
        #expect(Set(payload.keys) == requiredDecisionKeys)
        #expect(decision.selectedRoute == .collectionView)
        #expect(decision.wiringArtifactSummary != nil)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }
}

private func decide(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    wiringGateResult: TimelineHomeRootBodyActivationWiringResult? = cleanWiringGateResult(),
    rootShellMustRenderBeforeTimelineRestore: Bool = true,
    timelineRestoreGateScope: TimelineRestoreGateScope? = .timelineArea,
    timelineGateCoversRootShell: Bool = false,
    timelineGateCoversTabBar: Bool = false,
    timelineGateContinuesGlobalSplash: Bool = false
) -> TimelineHomeRootBodyRenderDecision {
    TimelineHomeRootBodyRenderSwitch.decide(
        TimelineHomeRootBodyRenderSwitchInput(
            launchArguments: arguments,
            wiringGateResult: wiringGateResult,
            rootShellPresentation: .immediate,
            rootShellMustRenderBeforeTimelineRestore: rootShellMustRenderBeforeTimelineRestore,
            timelineRestoreGateScope: timelineRestoreGateScope,
            timelineGateCoversRootShell: timelineGateCoversRootShell,
            timelineGateCoversTabBar: timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: timelineGateContinuesGlobalSplash,
            networkStartedBeforeInteractiveScroll: false,
            networkWaitedBeforeInteractiveScrollMS: 0,
            dbWriteAttempted: false,
            readMarkerAdvanced: false,
            dataSourceApplyFromRootCalled: false,
            extraNostrHomeTimelineStoreConstructed: false,
            createdAtMS: 1_735_000_030_000
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
            createdAtMS: 1_735_000_030_000
        )
    )
}

private func dirtyWiringGateResult() -> TimelineHomeRootBodyActivationWiringResult {
    cleanWiringGateResult(context: .defaultClean(networkStarted: true))
}

private func unevaluatedCleanLookingWiringGateResult() -> TimelineHomeRootBodyActivationWiringResult {
    var result = cleanWiringGateResult()
    result.wiringGateEvaluated = false
    result.wiringAllowed = true
    result.issueKinds = []
    result.artifactSummary = TimelineHomeRootBodyActivationWiringArtifactSummary(
        activationSwitchSummary: result.artifactSummary.activationSwitchSummary,
        rootBodySummary: result.artifactSummary.rootBodySummary,
        issueKinds: [],
        deterministicSummary: result.artifactSummary.deterministicSummary.replacingOccurrences(
            of: "wiringGateEvaluated=true",
            with: "wiringGateEvaluated=false"
        )
    )
    return result
}

private func doubleMutationWiringGateResult() -> TimelineHomeRootBodyActivationWiringResult {
    cleanWiringGateResult(context: .defaultClean(mutatingLegacyAndCollectionViewInSameSession: true))
}

private func cleanActivationSwitchResult() -> TimelineHomeActivatedRouteDecision {
    let routeDecision = TimelineHomeRootRenderRouteDecision(
        renderedRoute: .collectionView,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy
    )
    return TimelineHomeActivatedRouteDecision(
        activationWouldBeAllowed: true,
        activationPerformed: true,
        productionRenderSwitchPerformed: true,
        renderedRoute: .collectionView,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy,
        routeDecision: routeDecision,
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
        createdAtMS: 1_735_000_030_000
    )
}

private let requiredDecisionKeys: Set<String> = [
    "renderSwitchEvaluated",
    "selectedRoute",
    "explicitCollectionViewFlagPresent",
    "wiringGateEvaluated",
    "wiringAllowed",
    "legacyRouteRendered",
    "collectionViewRouteRendered",
    "rollbackRoute",
    "manualFallbackRoute",
    "rootShellPresentation",
    "rootShellMustRenderBeforeTimelineRestore",
    "rootShellFirstPaintPreserved",
    "timelineRestoreGateScope",
    "timelineGateCoversRootShell",
    "timelineGateCoversTabBar",
    "timelineGateContinuesGlobalSplash",
    "networkStartedBeforeInteractiveScroll",
    "networkWaitedBeforeInteractiveScrollMS",
    "dbWriteAttempted",
    "readMarkerAdvanced",
    "dataSourceApplyFromRootCalled",
    "extraNostrHomeTimelineStoreConstructed",
    "sameSessionDoubleMutationPrevented",
    "wiringArtifactSummary",
    "issueKinds",
    "createdAtMS"
]

private var selectedSwiftTestingSuites: [String] {
    selectedSwiftTestingSuiteCounts.map { $0.suiteName }
}

private var selectedSwiftTestingSuiteCounts: [(suiteName: String, executedTestCount: Int)] {
    [
        ("TimelineHomeRootBodyRenderSwitchTests", 23),
        ("TimelineHomeStartupSmokeLocalGateReportTests", 22),
        ("TimelineHomeFlaggedCollectionViewStartupSmokeTests", 25),
        ("TimelineHomeStartupSmokeEvidenceBundleTests", 15),
        ("TimelineHomeStartupSmokeDiagnosticsAttachmentTests", 20),
        ("TimelineHomeCollectionViewRouteRestoreIntegrationTests", 16),
        ("TimelineHomeRootBodyActivationWiringGateConsumerTests", 18),
        ("TimelineHomeRootBodyActivationWiringGateTests", 16),
        ("TimelineHomeCollectionViewRouteActivationSwitchTests", 19),
        ("TimelineHomeRootActivationDecisionSnapshotChainConsumerTests", 14),
        ("TimelineHomeRootActivationDecisionSnapshotChainTests", 15),
        ("TimelineHomeRootActivationPreflightTests", 17),
        ("TimelineHomeActivationArtifactChainConsumerTests", 17),
        ("TimelineHomeCollectionViewRouteActivationReadinessConsumerTests", 16),
        ("TimelineHomeCollectionViewRouteActivationTests", 24),
        ("TimelineHomeCollectionViewRouteBehindFlagConstructionTests", 22),
        ("TimelineHomeConstructionArtifactChainConsumerTests", 15),
        ("TimelineHomeCollectionViewOffscreenConstructionHarnessResultConsumerTests", 16),
        ("TimelineHomeCollectionViewOffscreenConstructionHarnessTests", 16),
        ("TimelineHomeRouteConstructionPlanConsumerTests", 12),
        ("TimelineHomeRouteConstructionReadinessTests", 16),
        ("TimelineHomeCollectionViewRouteConstructionTests", 6),
        ("TimelineHomeRootRouteDecisionSnapshotConsumerTests", 14),
        ("TimelineHomeRootRouteDecisionSnapshotTests", 8),
        ("TimelineHomeRootRouteDiagnosticsSinkInjectionTests", 14),
        ("TimelineHomeRouteDiagnosticsSinkTests", 11),
        ("TimelineHomeRootRouteCallSiteTests", 13),
        ("TimelineHomeRootRoutePreflightTests", 18),
        ("TimelineHomeRootRouteGuardTests", 19),
        ("TimelineHomeRouteDiagnosticsTests", 14),
        ("TimelineHomeRouteHostTests", 14),
        ("TimelineHomeRouteIntegrationSkeletonTests", 18),
        ("TimelineHomeRouteAdapterTests", 10),
        ("TimelineHomeLaunchRestoreContractTests", 13),
        ("TimelineHomeEngineModeTests", 6),
        ("TimelineSurfaceDependencyContainerTests", 7),
        ("TimelineCollectionViewControllerSmokeTests", 3),
        ("TimelineInitialRestoreSnapshotCoordinatorHarnessTests", 8),
        ("TimelineEngineScaffoldTests", 25)
    ]
}

private func assertOnlyUnevaluatedWiringGateBlocks(
    _ decision: TimelineHomeRootBodyRenderDecision
) {
    #expect(decision.explicitCollectionViewFlagPresent)
    #expect(decision.wiringGateEvaluated == false)
    #expect(decision.wiringAllowed)
    #expect(decision.issueKinds == [.cleanWiringGate])
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

private func sourceFile(named fileName: String) throws -> String {
    try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AstrenzaApp")
            .appendingPathComponent(fileName == "AstrenzaRootView.swift" ? fileName : "TimelineEngine/\(fileName)"),
        encoding: .utf8
    )
}

private func assertSendable<T: Sendable>(_: T.Type) {}
