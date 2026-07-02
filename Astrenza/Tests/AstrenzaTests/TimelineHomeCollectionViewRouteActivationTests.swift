import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route activation readiness")
struct TimelineHomeCollectionViewRouteActivationTests {
    @Test
    func activation_requires_explicit_flag() {
        let result = evaluate(arguments: ["Astrenza"])

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .explicitCollectionViewLaunchFlag))
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func activation_requires_all_construction_gates() {
        let chain = readinessDirtyChain()
        let result = evaluate(chain: chain, constructionResult: construct(chain: chain))

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .constructionGatesClean))
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func default_legacy_rendering_remains_default() throws {
        let result = evaluate(arguments: ["Astrenza", "--timeline-engine=legacy"])
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.renderedRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(rootSource.contains("HomeTimelineView"))
        #expect(rootSource.contains("NostrHomeTimelineStore"))
        #expect(!rootSource.contains("renderedRoute == .collectionView"))
        #expect(!rootSource.contains("Timeline" + "Surface("))
        #expect(!rootSource.contains("Timeline" + "CollectionViewController("))
    }

    @Test
    func activation_does_not_start_network_before_interactive_scroll() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationReadiness.swift")

        #expect(result.activationWouldBeAllowed)
        #expect(result.networkStarted == false)
        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.requiresNetworkWork == false)
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func activation_does_not_advance_read_marker() {
        let result = evaluate()

        #expect(result.readMarkerChanged == false)
        #expect(result.readMarkerAdvanced == false)
        #expect(result.activationPerformed == false)
    }

    @Test
    func activation_does_not_write_db() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationReadiness.swift")

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
        #expect(!source.contains("feed_read_state"))
        #expect(!source.contains("pending_new"))
        #expect(!source.contains("resolve_jobs"))
    }

    @Test
    func activation_does_not_call_dataSourceApply_from_Root() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationReadiness.swift")

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func activation_does_not_construct_extra_NostrHomeTimelineStore() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationReadiness.swift")

        #expect(result.noExtraNostrHomeTimelineStore)
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func activation_records_route_and_construction_artifacts() {
        let result = evaluate()

        #expect(result.activationWouldBeAllowed)
        #expect(result.artifactSummary.routeDecisionSummary.contains("route=collectionView"))
        #expect(result.artifactSummary.constructionReadinessSummary.contains("collectionViewAllowed=true"))
        #expect(result.artifactSummary.offscreenHarnessSummary.contains("collectionViewAllowed=true"))
        #expect(result.artifactSummary.flaggedConstructionSummary.contains("constructionAllowed=true"))
        #expect(result.artifactSummary.activationIssueKinds.isEmpty)
    }

    @Test
    func activation_uses_timeline_area_restore_gate_only() {
        let result = evaluate()

        #expect(result.timelineRestoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
        #expect(!result.issues.contains(gate: .timelineAreaRestoreGateOnly))
    }

    @Test
    func activation_keeps_root_shell_first_paint() {
        let result = evaluate()

        #expect(result.rootShellPresentation == .immediate)
        #expect(result.rootShellMustRenderBeforeTimelineRestore)
        #expect(!result.issues.contains(gate: .rootShellFirstPaintPreserved))
    }

    @Test
    func activation_rollback_returns_to_legacy() {
        let result = evaluate()

        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.productionRenderSwitchPerformed == false)
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteActivationTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineInitialRestoreSnapshotCoordinatorHarnessTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    @Test
    func activation_rejects_dirty_artifact_chain() {
        var chain = cleanChain()
        chain.routeDecisionSnapshot.sideEffectSentinel.networkStarted = true
        let result = evaluate(chain: chain, constructionResult: construct(chain: chain))

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .artifactChainClean))
        #expect(result.artifactSummary.chainIssueKinds.contains("artifact.sideEffectsDirty"))
    }

    @Test
    func activation_rejects_dirty_flagged_construction_result_and_reports_side_effects() {
        var constructionResult = construct()
        constructionResult.networkStarted = true
        constructionResult.dbWriteAttempted = true
        constructionResult.readMarkerAdvanced = true
        constructionResult.dataSourceApplyFromRootCalled = true
        let result = evaluate(constructionResult: constructionResult)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.networkStarted)
        #expect(result.dbWriteAttempted)
        #expect(result.readMarkerAdvanced)
        #expect(result.dataSourceApplyFromRootCalled)
    }

    @Test
    func activation_rejects_construction_result_with_non_collectionView_requestedRoute() {
        var constructionResult = construct()
        constructionResult.requestedRoute = .legacy

        let result = evaluate(constructionResult: constructionResult)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
    }

    @Test
    func activation_rejects_unattempted_construction_result() {
        var constructionResult = construct()
        constructionResult.constructionAttempted = false

        let result = evaluate(constructionResult: constructionResult)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
    }

    @Test
    func activation_rejects_closed_or_invalid_constructionKind() {
        var constructionResult = construct()
        constructionResult.constructionKind = .productionClosed

        let result = evaluate(constructionResult: constructionResult)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
    }

    @Test
    func activation_rejects_stale_construction_identity_even_when_clean_flags_are_true() {
        var constructionResult = construct()
        constructionResult.artifactSummary.routeDecisionSummary = "stale-route-decision"

        let result = evaluate(constructionResult: constructionResult)

        #expect(constructionResult.constructionAllowed)
        #expect(constructionResult.issueKinds.isEmpty)
        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .flaggedConstructionResultClean))
        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
    }

    @Test
    func activation_rejects_missing_restore_harness() {
        let result = evaluate(initialRestoreSnapshotCoordinatorHarnessPassed: false)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .initialRestoreSnapshotCoordinatorHarnessPassed))
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func activation_rejects_startup_network_dirty_marker() {
        let result = evaluate(
            startupNetworkPatternClean: false,
            networkWaitedBeforeInteractiveScrollMS: 1
        )

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .startupNetworkPatternClean))
        #expect(result.issues.contains(gate: .networkWaitedBeforeInteractiveScrollZero))
    }

    @Test
    func activation_rejects_root_body_snapshot_without_activation_scope() {
        let result = evaluate(rootBodyDecisionSnapshotPermitsActivationScope: false)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(gate: .rootBodyDecisionSnapshotPermitsActivationScope))
        #expect(result.activationPerformed == false)
    }

    @Test
    func startup_forbidden_literal_scan_does_not_hit_activation_test_literals() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)

        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func activation_result_is_codable_privacy_safe() throws {
        let result = evaluate()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(
            TimelineHomeCollectionViewRouteActivationResult.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeCollectionViewRouteActivationReadiness.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationGate.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationIssue.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationResult.self)
        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }
}

private func evaluate(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    debugOverride: TimelineHomeRouteDebugOverride? = nil,
    chain: TimelineHomeConstructionArtifactChain = cleanChain(),
    constructionResult: TimelineHomeCollectionViewRouteConstructionResult? = nil,
    offscreenNoWindowSmokePassed: Bool = true,
    initialRestoreSnapshotCoordinatorHarnessPassed: Bool = true,
    startupNetworkPatternClean: Bool = true,
    networkWaitedBeforeInteractiveScrollMS: Double = 0,
    readMarkerChanged: Bool = false,
    requiresNetworkWork: Bool = false,
    requiresDBWrite: Bool = false,
    dataSourceApplyCoordinatorOnly: Bool = true,
    noExtraNostrHomeTimelineStore: Bool = true,
    rootBodyDecisionSnapshotPermitsActivationScope: Bool = true
) -> TimelineHomeCollectionViewRouteActivationResult {
    TimelineHomeCollectionViewRouteActivationReadiness(
        launchArguments: arguments,
        debugOverride: debugOverride,
        constructionResult: constructionResult ?? construct(
            arguments: arguments,
            debugOverride: debugOverride,
            chain: chain
        ),
        artifactChain: chain,
        offscreenNoWindowSmokePassed: offscreenNoWindowSmokePassed,
        initialRestoreSnapshotCoordinatorHarnessPassed: initialRestoreSnapshotCoordinatorHarnessPassed,
        startupNetworkPatternClean: startupNetworkPatternClean,
        networkWaitedBeforeInteractiveScrollMS: networkWaitedBeforeInteractiveScrollMS,
        readMarkerChanged: readMarkerChanged,
        requiresNetworkWork: requiresNetworkWork,
        requiresDBWrite: requiresDBWrite,
        dataSourceApplyCoordinatorOnly: dataSourceApplyCoordinatorOnly,
        noExtraNostrHomeTimelineStore: noExtraNostrHomeTimelineStore,
        rootBodyDecisionSnapshotPermitsActivationScope: rootBodyDecisionSnapshotPermitsActivationScope,
        createdAtMS: 1_735_000_006_000
    ).evaluate()
}

private func construct(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    debugOverride: TimelineHomeRouteDebugOverride? = nil,
    chain: TimelineHomeConstructionArtifactChain? = cleanChain()
) -> TimelineHomeCollectionViewRouteConstructionResult {
    TimelineHomeFlaggedCollectionViewRouteConstruction.evaluate(
        TimelineHomeCollectionViewRouteConstructionInput(
            launchArguments: arguments,
            debugOverride: debugOverride,
            artifactChain: chain,
            createdAtMS: 1_735_000_006_000
        )
    )
}

private func cleanChain(
    kind: TimelineHomeCollectionViewRouteConstructionKind = .offscreenOnly
) -> TimelineHomeConstructionArtifactChain {
    let snapshot = makeSnapshot()
    let readiness = makeReadiness(
        rootDecisionSnapshot: snapshot,
        preferredConstructionKind: kind
    ).evaluate()
    return TimelineHomeConstructionArtifactChain(
        routeDecisionSnapshot: snapshot,
        constructionReadinessResult: readiness,
        offscreenHarnessResult: harnessResult(
            allowed: true,
            constructionKind: kind,
            artifactSummary: snapshot.artifactSummary
        )
    )
}

private func readinessDirtyChain() -> TimelineHomeConstructionArtifactChain {
    var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
    dependencies.repositoryStoreAvailable = false
    let snapshot = makeSnapshot(dependencies: dependencies)
    let readiness = makeReadiness(
        dependencies: dependencies,
        rootDecisionSnapshot: snapshot,
        preferredConstructionKind: .offscreenOnly
    ).evaluate()
    return TimelineHomeConstructionArtifactChain(
        routeDecisionSnapshot: snapshot,
        constructionReadinessResult: readiness,
        offscreenHarnessResult: harnessResult(
            allowed: false,
            rejectionReasons: [.readinessBlocked],
            constructionKind: readiness.plan.constructionKind,
            artifactSummary: snapshot.artifactSummary
        )
    )
}

private func makeReadiness(
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable,
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
    preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind
) -> TimelineHomeRouteConstructionReadiness {
    TimelineHomeRouteConstructionReadiness(
        hasExplicitCollectionViewLaunchFlag: true,
        dependencies: dependencies,
        rootNoOpPreflightComplete: true,
        routeDiagnosticsSinkInjectionComplete: true,
        rootDecisionSnapshot: rootDecisionSnapshot,
        snapshotConsumerAvailable: true,
        offscreenControllerSmokePassed: true,
        initialRestoreSnapshotCoordinatorHarnessPassed: true,
        startupNetworkPatternClean: true,
        selectedSwiftTestingSuitesNonZero: true,
        dataSourceApplyCoordinatorOnly: true,
        noExtraNostrHomeTimelineStore: true,
        artifactPrivacyGuardPassed: true,
        preferredConstructionKind: preferredConstructionKind
    )
}

private func makeSnapshot(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        dependencies: dependencies,
        createdAtMS: 1_735_000_006_000
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_006_000
    )
}

private func harnessResult(
    allowed: Bool,
    rejectionReasons: [TimelineHomeOffscreenConstructionRejection] = [],
    constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
    coordinatorOwnedDataSourceApplyAllowed: Bool = true,
    forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool = false,
    artifactSummary: TimelineHomeRootRouteArtifactSnapshot
) -> TimelineHomeOffscreenConstructionHarnessResult {
    TimelineHomeOffscreenConstructionHarnessResult(
        offscreenConstructionAllowed: allowed,
        rejectionReasons: rejectionReasons,
        constructionKind: constructionKind,
        renderedRouteAfterConstruction: .legacy,
        routeActivationAllowed: false,
        collectionViewRouteConstructedFromRoot: false,
        timelineSurfaceConstructedFromRoot: false,
        timelineCollectionViewControllerConstructedFromRoot: false,
        controllerLoadedOffscreen: allowed,
        isAttachedToWindow: false,
        networkStarted: false,
        dbWriteAttempted: false,
        readMarkerAdvanced: false,
        coordinatorOwnedDataSourceApplyAllowed: coordinatorOwnedDataSourceApplyAllowed,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: forbiddenDataSourceApplyOutsideCoordinatorCalled,
        controllerItemIDs: allowed ? ["note:visible"] : [],
        diagnosticsArtifactSummary: artifactSummary
    )
}

private var selectedSwiftTestingSuites: [String] {
    [
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

private var requiredResultKeys: Set<String> {
    [
        "activationPerformed",
        "activationWouldBeAllowed",
        "artifactSummary",
        "constructionResult",
        "coordinatorOwnedDataSourceApplyAllowed",
        "createdAtMS",
        "dataSourceApplyFromRootCalled",
        "dbWriteAttempted",
        "issues",
        "manualFallbackRoute",
        "networkStarted",
        "networkWaitedBeforeInteractiveScrollMS",
        "noExtraNostrHomeTimelineStore",
        "productionRenderSwitchPerformed",
        "readMarkerAdvanced",
        "readMarkerChanged",
        "renderedRoute",
        "requiresDBWrite",
        "requiresNetworkWork",
        "rollbackRoute",
        "rootShellMustRenderBeforeTimelineRestore",
        "rootShellPresentation",
        "timelineGateContinuesGlobalSplash",
        "timelineGateCoversRootShell",
        "timelineGateCoversTabBar",
        "timelineRestoreGateScope"
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
        "event_id"
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

private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func sourceFile(named fileName: String) throws -> String {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let appRoot = testDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        appRoot.appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
        appRoot.appendingPathComponent("Sources/AstrenzaApp/\(fileName)"),
        appRoot.appendingPathComponent("Sources/AstrenzaApp/Nostr/\(fileName)")
    ]

    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
        return try String(contentsOf: candidate, encoding: .utf8)
    }

    throw CocoaError(.fileNoSuchFile)
}

private func assertSendable<T: Sendable>(_: T.Type) {}

private extension [TimelineHomeCollectionViewRouteActivationIssue] {
    func contains(gate: TimelineHomeCollectionViewRouteActivationGate) -> Bool {
        contains { $0.gate == gate }
    }
}
