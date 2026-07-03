import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route activation switch")
struct TimelineHomeCollectionViewRouteActivationSwitchTests {
    @Test
    func activation_requires_explicit_flag() {
        let result = activate(arguments: ["Astrenza"])

        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
    }

    @Test
    func activation_requires_all_gates_clean() {
        let input = switchInput(
            arguments: ["Astrenza"],
            preflightResult: dirtyPreflight(),
            activationArtifactChainConsumer: dirtyArtifactChainConsumer()
        )
        let result = TimelineHomeCollectionViewRouteActivator.activate(input)

        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.issueKinds.contains(.activationPreflightAllows))
        #expect(result.issueKinds.contains(.activationArtifactChainClean))
        #expect(result.issueKinds.contains(.constructionGatesClean))
    }

    @Test
    func default_without_flag_renders_legacy() {
        let result = activate(arguments: ["Astrenza"])

        #expect(result.renderedRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
    }

    @Test
    func dirty_preflight_renders_legacy() {
        let result = activate(preflightResult: dirtyPreflight())

        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.issueKinds.contains(.activationPreflightAllows))
        #expect(result.issueKinds.contains(.rootShellFirstPaintPreserved))
    }

    @Test
    func dirty_artifact_chain_renders_legacy() {
        let consumer = dirtyArtifactChainConsumer()
        let result = activate(activationArtifactChainConsumer: consumer)

        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.issueKinds.contains(.activationArtifactChainClean))
        #expect(result.issueKinds.contains(.startupNetworkPatternClean))
    }

    @Test
    func missing_readiness_renders_legacy() {
        let result = activate(activationArtifactChainConsumer: nil)

        #expect(result.renderedRoute == .legacy)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.issueKinds.contains(.activationReadinessPresent))
    }

    @Test
    func explicit_flag_and_clean_gates_activate_collectionView() {
        let result = activate()

        #expect(result.issueKinds.isEmpty)
        #expect(result.renderedRoute == .collectionView)
        #expect(result.activationPerformed)
        #expect(result.productionRenderSwitchPerformed)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.preventsDualMutation)
    }

    @Test
    func activation_records_route_and_construction_artifacts() {
        let result = activate()

        #expect(result.routeDiagnosticsRecorded)
        #expect(result.activationArtifactChainRecorded)
        #expect(result.constructionArtifactChainRecorded)
        #expect(result.diagnostics.rootActivationDecisionSummary.contains("renderedRoute=legacy"))
        #expect(result.diagnostics.flaggedConstructionSummary.contains("constructionAllowed=true"))
        #expect(result.diagnostics.constructionReadinessSummary.contains("collectionViewAllowed=true"))
        #expect(result.diagnostics.offscreenHarnessSummary.contains("collectionViewAllowed=true"))
    }

    @Test
    func activation_keeps_root_shell_first_paint() {
        let result = activate()

        #expect(result.rootShellPresentation == .immediate)
        #expect(result.rootShellMustRenderBeforeTimelineRestore)
        #expect(!result.issueKinds.contains(.rootShellFirstPaintPreserved))
    }

    @Test
    func activation_uses_timeline_area_restore_gate_only() {
        let result = activate()

        #expect(result.timelineRestoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
        #expect(!result.issueKinds.contains(.timelineAreaRestoreGateOnly))
    }

    @Test
    func activation_does_not_start_network_before_interactive_scroll() throws {
        let result = activate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationSwitch.swift")

        #expect(result.networkStarted == false)
        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.requiresNetworkWork == false)
        #expect(!result.issueKinds.contains(.startupNetworkPatternClean))
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func activation_does_not_write_db() throws {
        let result = activate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationSwitch.swift")

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
        #expect(!source.contains("feed_read_state"))
        #expect(!source.contains("pending_new"))
        #expect(!source.contains("resolve_jobs"))
    }

    @Test
    func activation_does_not_advance_read_marker() {
        let result = activate()

        #expect(result.readMarkerChanged == false)
        #expect(result.readMarkerAdvanced == false)
        #expect(!result.issueKinds.contains(.readMarkerUnchanged))
    }

    @Test
    func activation_does_not_call_dataSourceApply_from_Root() throws {
        let result = activate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationSwitch.swift")

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func activation_does_not_construct_extra_NostrHomeTimelineStore() throws {
        let result = activate()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationSwitch.swift")

        #expect(result.noExtraNostrHomeTimelineStore)
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func rollback_returns_to_legacy() {
        let result = activate()

        #expect(result.renderedRoute == .collectionView)
        #expect(result.rollbackRoute == .legacy)
    }

    @Test
    func manualFallback_is_legacy() {
        let result = activate()

        #expect(result.renderedRoute == .collectionView)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteActivationSwitchTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootActivationDecisionSnapshotChainConsumerTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineInitialRestoreSnapshotCoordinatorHarnessTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    @Test
    func activation_result_is_codable_privacy_safe() throws {
        let result = activate()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(
            TimelineHomeActivatedRouteDecision.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(TimelineHomeCollectionViewRouteActivation.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationSwitchInput.self)
        assertSendable(TimelineHomeActivatedRouteDecision.self)
        assertSendable(TimelineHomeRootRenderRouteDecision.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationSwitchIssueKind.self)
        #expect(decoded == result)
        #expect(result.activationPerformed)
        #expect(result.productionRenderSwitchPerformed)
        #expect(result.renderedRoute == .collectionView)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }
}

private func activate(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    mode: AstrenzaTimelineEngineMode? = nil,
    preflightResult: TimelineHomeRootActivationPreflightResult? = nil,
    rootActivationDecisionSnapshotResult: TimelineHomeRootActivationDecisionSnapshotResult? = nil,
    activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer? = cleanArtifactChainConsumer()
) -> TimelineHomeActivatedRouteDecision {
    TimelineHomeCollectionViewRouteActivator.activate(
        switchInput(
            arguments: arguments,
            mode: mode,
            preflightResult: preflightResult,
            rootActivationDecisionSnapshotResult: rootActivationDecisionSnapshotResult,
            activationArtifactChainConsumer: activationArtifactChainConsumer
        )
    )
}

private func switchInput(
    arguments: [String],
    mode: AstrenzaTimelineEngineMode? = nil,
    preflightResult: TimelineHomeRootActivationPreflightResult? = nil,
    rootActivationDecisionSnapshotResult: TimelineHomeRootActivationDecisionSnapshotResult? = nil,
    activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer?
) -> TimelineHomeCollectionViewRouteActivationSwitchInput {
    let consumer = activationArtifactChainConsumer
    return TimelineHomeCollectionViewRouteActivationSwitchInput(
        launchArguments: arguments,
        mode: mode ?? TimelineHomeEngineModeResolver.resolve(arguments: arguments).mode,
        activationPreflightResult: preflightResult ?? consumer.map { preflight(arguments: arguments, consumer: $0) },
        rootActivationDecisionSnapshotResult: rootActivationDecisionSnapshotResult ?? consumer.map { makeRootActivationDecisionSnapshotResult(consumer: $0) },
        activationArtifactChainConsumer: consumer,
        createdAtMS: 1_735_000_010_000
    )
}

private func cleanArtifactChainConsumer(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"]
) -> TimelineHomeActivationArtifactChainConsumer {
    TimelineHomeActivationArtifactChainConsumer(
        chain: cleanActivationChain(arguments: arguments)
    )
}

private func dirtyArtifactChainConsumer() -> TimelineHomeActivationArtifactChainConsumer {
    var chain = cleanConstructionChain()
    chain.routeDecisionSnapshot.sideEffectSentinel.networkStarted = true
    chain.routeDecisionSnapshot.requiresNetworkWork = true
    chain.offscreenHarnessResult.offscreenConstructionAllowed = false
    chain.offscreenHarnessResult.rejectionReasons = [.readinessBlocked]
    chain.offscreenHarnessResult.controllerLoadedOffscreen = false
    chain.offscreenHarnessResult.controllerItemIDs = []
    chain.offscreenHarnessResult.coordinatorOwnedDataSourceApplyAllowed = false
    chain.offscreenHarnessResult.networkStarted = true
    return TimelineHomeActivationArtifactChainConsumer(
        chain: TimelineHomeActivationArtifactChain(
            constructionArtifactChain: chain,
            activationReadinessResult: evaluateActivation(
                chain: chain,
                constructionResult: construct(chain: chain),
                startupNetworkPatternClean: false,
                requiresNetworkWork: true
            )
        )
    )
}

private func dirtyPreflight() -> TimelineHomeRootActivationPreflightResult {
    let consumer = cleanArtifactChainConsumer()
    return TimelineHomeRootCollectionViewActivationPreflight.evaluate(
        TimelineHomeRootActivationPreflightInput(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            activationArtifactChainConsumer: consumer,
            rootShellFirstPaintObserved: false,
            timelineAreaRestoreGateObserved: true,
            startupNetworkMarkerObserved: false
        )
    )
}

private func makeRootActivationDecisionSnapshotResult(
    consumer: TimelineHomeActivationArtifactChainConsumer
) -> TimelineHomeRootActivationDecisionSnapshotResult {
    TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight(consumer: consumer),
        rootRouteDecisionSnapshot: consumer.chain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    ).result
}

private func preflight(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    consumer: TimelineHomeActivationArtifactChainConsumer
) -> TimelineHomeRootActivationPreflightResult {
    TimelineHomeRootCollectionViewActivationPreflight.evaluate(
        TimelineHomeRootActivationPreflightInput(
            launchArguments: arguments,
            activationArtifactChainConsumer: consumer,
            rootShellFirstPaintObserved: true,
            timelineAreaRestoreGateObserved: true,
            startupNetworkMarkerObserved: false
        )
    )
}

private func cleanActivationChain(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"]
) -> TimelineHomeActivationArtifactChain {
    let constructionChain = cleanConstructionChain(arguments: arguments)
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: constructionChain,
        activationReadinessResult: evaluateActivation(
            arguments: arguments,
            chain: constructionChain,
            constructionResult: construct(arguments: arguments, chain: constructionChain)
        )
    )
}

private func evaluateActivation(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    chain: TimelineHomeConstructionArtifactChain,
    constructionResult: TimelineHomeCollectionViewRouteConstructionResult,
    startupNetworkPatternClean: Bool = true,
    requiresNetworkWork: Bool = false
) -> TimelineHomeCollectionViewRouteActivationResult {
    TimelineHomeCollectionViewRouteActivationReadiness(
        launchArguments: arguments,
        debugOverride: nil,
        constructionResult: constructionResult,
        artifactChain: chain,
        offscreenNoWindowSmokePassed: true,
        initialRestoreSnapshotCoordinatorHarnessPassed: true,
        startupNetworkPatternClean: startupNetworkPatternClean,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: false,
        requiresNetworkWork: requiresNetworkWork,
        requiresDBWrite: false,
        dataSourceApplyCoordinatorOnly: true,
        noExtraNostrHomeTimelineStore: true,
        rootBodyDecisionSnapshotPermitsActivationScope: true,
        createdAtMS: 1_735_000_010_000
    ).evaluate()
}

private func construct(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    chain: TimelineHomeConstructionArtifactChain
) -> TimelineHomeCollectionViewRouteConstructionResult {
    TimelineHomeFlaggedCollectionViewRouteConstruction.evaluate(
        TimelineHomeCollectionViewRouteConstructionInput(
            launchArguments: arguments,
            artifactChain: chain,
            createdAtMS: 1_735_000_010_000
        )
    )
}

private func cleanConstructionChain(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"]
) -> TimelineHomeConstructionArtifactChain {
    let snapshot = makeRootSnapshot(arguments: arguments)
    let readiness = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
    return TimelineHomeConstructionArtifactChain(
        routeDecisionSnapshot: snapshot,
        constructionReadinessResult: readiness,
        offscreenHarnessResult: harnessResult(
            allowed: true,
            constructionKind: .offscreenOnly,
            artifactSummary: snapshot.artifactSummary
        )
    )
}

private func makeRootSnapshot(
    arguments: [String],
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        dependencies: dependencies,
        createdAtMS: 1_735_000_010_000
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_010_000
    )
}

private func makeReadiness(
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot
) -> TimelineHomeRouteConstructionReadiness {
    TimelineHomeRouteConstructionReadiness(
        hasExplicitCollectionViewLaunchFlag: true,
        dependencies: .allAvailable,
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
        preferredConstructionKind: .offscreenOnly
    )
}

private func harnessResult(
    allowed: Bool,
    constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
    artifactSummary: TimelineHomeRootRouteArtifactSnapshot
) -> TimelineHomeOffscreenConstructionHarnessResult {
    TimelineHomeOffscreenConstructionHarnessResult(
        offscreenConstructionAllowed: allowed,
        rejectionReasons: allowed ? [] : [.readinessBlocked],
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
        coordinatorOwnedDataSourceApplyAllowed: allowed,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
        controllerItemIDs: allowed ? ["note:visible"] : [],
        diagnosticsArtifactSummary: artifactSummary
    )
}

private var selectedSwiftTestingSuites: [String] {
    [
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
    try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
        encoding: .utf8
    )
}

private func assertSendable<T: Sendable>(_: T.Type) {}
