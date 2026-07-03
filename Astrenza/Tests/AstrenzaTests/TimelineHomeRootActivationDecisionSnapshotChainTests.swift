import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome Root activation decision snapshot chain")
struct TimelineHomeRootActivationDecisionSnapshotChainTests {
    @Test("chain decodes clean preflight and snapshot fixture")
    func chain_decodes_clean_preflight_and_snapshot_fixture() throws {
        let chain = try decodedChain(cleanFixture())

        #expect(chain.preflightResult.activationPreflightEvaluated)
        #expect(chain.rootRouteDecisionSnapshot.collectionViewDecisionObserved)
        #expect(chain.activationArtifactChainConsumer.activationWouldBeAllowed)
        #expect(chain.result.preflightEvaluated)
        #expect(chain.result.activationWouldBeAllowed)
    }

    @Test("chain decodes blocked preflight fixture")
    func chain_decodes_blocked_preflight_fixture() throws {
        let result = try decodedChain(blockedPreflightFixture()).result

        #expect(result.preflightEvaluated)
        #expect(result.activationWouldBeAllowed == false)
        #expect(result.activationBlockedIssueKinds.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.renderedRoute == .legacy)
    }

    @Test("chain keeps renderedRoute legacy")
    func chain_keeps_renderedRoute_legacy() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.renderedRoute == .legacy)
        #expect(result.rootBodyDecisionRenderedRoute == .legacy)
    }

    @Test("chain keeps activationPerformed false")
    func chain_keeps_activationPerformed_false() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.activationPerformed == false)
    }

    @Test("chain keeps productionRenderSwitchPerformed false")
    func chain_keeps_productionRenderSwitchPerformed_false() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.productionRenderSwitchPerformed == false)
    }

    @Test("chain keeps rollback and manualFallback legacy")
    func chain_keeps_rollback_and_manualFallback_legacy() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test("chain exposes activationWouldBeAllowed")
    func chain_exposes_activationWouldBeAllowed() throws {
        let clean = try decodedChain(cleanFixture()).result
        let blocked = try decodedChain(blockedPreflightFixture()).result

        #expect(clean.activationWouldBeAllowed)
        #expect(blocked.activationWouldBeAllowed == false)
    }

    @Test("chain exposes activation blocked issues")
    func chain_exposes_activation_blocked_issues() throws {
        let result = try decodedChain(blockedPreflightFixture()).result

        #expect(result.activationBlockedIssueKinds == [.explicitCollectionViewLaunchFlag])
    }

    @Test("chain exposes artifact chain issues")
    func chain_exposes_artifact_chain_issues() throws {
        let result = try decodedChain(blockedArtifactChainFixture()).result

        #expect(result.combinedArtifactChainIssueKinds.contains("construction.readiness.renderedRouteLegacy"))
        #expect(result.combinedArtifactChainIssueKinds.contains("activation.constructionGatesClean"))
    }

    @Test("chain propagates dirty root timeline surface construction")
    func chain_propagates_dirty_root_timeline_surface_construction() throws {
        let chain = try decodedChain(dirtyTimelineSurfaceConstructionFixture())
        let consumer = chain.activationArtifactChainConsumer
        let activationResult = consumer.activationConsumer.result
        let result = chain.result

        #expect(consumer.constructionConsumer.timelineSurfaceConstructedFromRoot)
        #expect(result.sideEffectFlags.timelineSurfaceConstructed)
        #expect(result.combinedArtifactChainIssueKinds.contains("construction.offscreen.rootSurfaceConstructionOpen"))
        #expect(result.combinedArtifactChainIssueKinds.contains("activation.artifactChainClean"))
        #expect(result.activationBlockedIssueKinds.contains(.activationArtifactChainClean))
        #expect(result.activationWouldBeAllowed == false)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.rootBodyDecisionRenderedRoute == .legacy)
        #expect(result.sideEffectFlags.rootViewConstructed == false)
        #expect(result.sideEffectFlags.homeTimelineViewConstructed == false)
        #expect(result.sideEffectFlags.nostrHomeTimelineStoreConstructed == false)
        #expect(result.sideEffectFlags.timelineCollectionViewControllerConstructed == false)
        #expect(result.sideEffectFlags.networkStarted == false)
        #expect(result.sideEffectFlags.dbWriteAttempted == false)
        #expect(result.sideEffectFlags.readMarkerChanged == false)
        #expect(result.sideEffectFlags.dataSourceApplyCalled == false)
        #expect(activationResult.rootShellPresentation == .immediate)
        #expect(activationResult.rootShellMustRenderBeforeTimelineRestore)
        #expect(activationResult.timelineRestoreGateScope == .timelineArea)
        #expect(activationResult.timelineGateCoversRootShell == false)
        #expect(activationResult.timelineGateCoversTabBar == false)
        #expect(activationResult.timelineGateContinuesGlobalSplash == false)
    }

    @Test("chain exposes root body decision snapshot")
    func chain_exposes_root_body_decision_snapshot() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.rootBodyDecisionRenderedRoute == .legacy)
        #expect(result.rootBodyDecisionVisibleRoute == .collectionViewPlaceholder)
        #expect(result.diagnostics.rootBodyDecisionDebugSummary.contains("renderedRoute=legacy"))
        #expect(result.diagnostics.rootBodyDecisionArtifactSummary.contains("route=collectionView"))
    }

    @Test("chain side effect flags all false for clean fixture")
    func chain_side_effect_flags_all_false_for_clean_fixture() throws {
        let result = try decodedChain(cleanFixture()).result

        #expect(result.sideEffectFlags.rootViewConstructed == false)
        #expect(result.sideEffectFlags.homeTimelineViewConstructed == false)
        #expect(result.sideEffectFlags.nostrHomeTimelineStoreConstructed == false)
        #expect(result.sideEffectFlags.timelineCollectionViewControllerConstructed == false)
        #expect(result.sideEffectFlags.timelineSurfaceConstructed == false)
        #expect(result.sideEffectFlags.networkStarted == false)
        #expect(result.sideEffectFlags.dbWriteAttempted == false)
        #expect(result.sideEffectFlags.readMarkerChanged == false)
        #expect(result.sideEffectFlags.dataSourceApplyCalled == false)
        #expect(result.sideEffectFlags.dataSourceApplyFromRootCalled == false)
        #expect(result.sideEffectFlags.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
        #expect(result.sideEffectFlags.requiresNetworkWork == false)
        #expect(result.sideEffectFlags.requiresDBWrite == false)
        #expect(result.sideEffectFlags.fileWriteAttempted == false)
        #expect(result.sideEffectFlags.externalTelemetryUploadAttempted == false)
    }

    @Test("chain does not construct Root Home controller store surface")
    func chain_does_not_construct_Root_Home_controller_store_surface() throws {
        _ = try decodedChain(cleanFixture()).result
        let source = try sourceFile(named: "TimelineHomeRootActivationDecisionSnapshotChain.swift")

        assertSendable(TimelineHomeRootActivationDecisionSnapshotResult.self)
        assertSendable(TimelineHomeRootActivationDecisionSnapshotDiagnostics.self)
        assertSendable(TimelineHomeRootActivationDecisionSnapshotSideEffectFlags.self)
        assertSendable(TimelineHomeRootActivationPreflightSnapshotChain.self)
        #expect(!source.contains("AstrenzaRootView("))
        #expect(!source.contains("HomeTimelineView("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
        #expect(!source.contains("Timeline" + "Surface("))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("TimelineSurfaceDependencyContainer"))
        #expect(!source.contains("loadViewIfNeeded"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("deleteItems"))
        #expect(!source.contains("insertItems"))
        #expect(!source.contains("advance" + "Read" + "Marker"))
        #expect(!source.contains("File" + "Manager"))
        #expect(!source.contains("write(to:"))
        #expect(!source.contains("upload"))
        #expect(!source.contains("telemetry"))
        #expect(!source.contains("analytics"))
    }

    @Test("chain result is codable privacy safe")
    func chain_result_is_codable_privacy_safe() throws {
        let result = try decodedChain(cleanFixture()).result
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(
            TimelineHomeRootActivationDecisionSnapshotResult.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)
        #expect(result.preflightEvaluated)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test("selected swift testing suites non zero")
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootActivationDecisionSnapshotChainTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootActivationPreflightTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeActivationArtifactChainConsumerTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }
}

private func decodedChain(
    _ chain: TimelineHomeRootActivationPreflightSnapshotChain
) throws -> TimelineHomeRootActivationPreflightSnapshotChain {
    try TimelineHomeRootActivationPreflightSnapshotChain.decodeFixtureJSON(
        encodedData(chain)
    )
}

private func cleanFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = cleanActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    let preflight = preflight(consumer: consumer)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight,
        rootRouteDecisionSnapshot: activationChain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    )
}

private func blockedPreflightFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = cleanActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    let preflight = preflight(arguments: ["Astrenza"], consumer: consumer)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight,
        rootRouteDecisionSnapshot: makeRootSnapshot(arguments: ["Astrenza"]),
        activationArtifactChainConsumer: consumer
    )
}

private func blockedArtifactChainFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = blockedConstructionActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    let preflight = preflight(consumer: consumer)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight,
        rootRouteDecisionSnapshot: activationChain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    )
}

private func dirtyTimelineSurfaceConstructionFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = dirtyTimelineSurfaceConstructionActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    let preflight = preflight(consumer: consumer)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight,
        rootRouteDecisionSnapshot: activationChain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    )
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
    let constructionChain = cleanConstructionChain()
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: constructionChain,
        activationReadinessResult: evaluateActivation(
            arguments: arguments,
            chain: constructionChain,
            constructionResult: construct(arguments: arguments, chain: constructionChain)
        )
    )
}

private func blockedConstructionActivationChain() -> TimelineHomeActivationArtifactChain {
    let constructionChain = blockedConstructionChain()
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: constructionChain,
        activationReadinessResult: evaluateActivation(
            chain: constructionChain,
            constructionResult: construct(chain: constructionChain)
        )
    )
}

private func dirtyTimelineSurfaceConstructionActivationChain() -> TimelineHomeActivationArtifactChain {
    let constructionChain = dirtyTimelineSurfaceConstructionChain()
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: constructionChain,
        activationReadinessResult: evaluateActivation(
            chain: constructionChain,
            constructionResult: construct(chain: constructionChain)
        )
    )
}

private func evaluateActivation(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    chain: TimelineHomeConstructionArtifactChain,
    constructionResult: TimelineHomeCollectionViewRouteConstructionResult
) -> TimelineHomeCollectionViewRouteActivationResult {
    TimelineHomeCollectionViewRouteActivationReadiness(
        launchArguments: arguments,
        debugOverride: nil,
        constructionResult: constructionResult,
        artifactChain: chain,
        offscreenNoWindowSmokePassed: true,
        initialRestoreSnapshotCoordinatorHarnessPassed: true,
        startupNetworkPatternClean: true,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: false,
        requiresNetworkWork: false,
        requiresDBWrite: false,
        dataSourceApplyCoordinatorOnly: true,
        noExtraNostrHomeTimelineStore: true,
        rootBodyDecisionSnapshotPermitsActivationScope: true,
        createdAtMS: 1_735_000_009_000
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
            createdAtMS: 1_735_000_008_900
        )
    )
}

private func cleanConstructionChain() -> TimelineHomeConstructionArtifactChain {
    let snapshot = makeRootSnapshot(
        arguments: ["Astrenza", "--timeline-engine=collectionView"],
        dependencies: .allAvailable
    )
    let readiness = makeReadiness(
        rootDecisionSnapshot: snapshot,
        preferredConstructionKind: .offscreenOnly
    ).evaluate()
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

private func blockedConstructionChain() -> TimelineHomeConstructionArtifactChain {
    var snapshot = makeRootSnapshot(
        arguments: ["Astrenza", "--timeline-engine=collectionView"],
        dependencies: .allAvailable
    )
    snapshot.renderedRoute = .collectionViewPlaceholder
    snapshot.collectionViewRouteConstructed = true
    snapshot.sideEffectSentinel.networkStarted = true
    snapshot.artifactSummary = artifactSummary(releaseBlockerFlags: [.requiresNetworkWork])
    let readiness = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
    return TimelineHomeConstructionArtifactChain(
        routeDecisionSnapshot: snapshot,
        constructionReadinessResult: readiness,
        offscreenHarnessResult: harnessResult(
            allowed: false,
            constructionKind: .productionClosed,
            artifactSummary: snapshot.artifactSummary
        )
    )
}

private func dirtyTimelineSurfaceConstructionChain() -> TimelineHomeConstructionArtifactChain {
    var chain = cleanConstructionChain()
    chain.offscreenHarnessResult.offscreenConstructionAllowed = false
    chain.offscreenHarnessResult.rejectionReasons = [
        .rootSurfaceConstructionOpen,
        .constructionPlanClosed
    ]
    chain.offscreenHarnessResult.timelineSurfaceConstructedFromRoot = true
    chain.offscreenHarnessResult.controllerLoadedOffscreen = false
    chain.offscreenHarnessResult.controllerItemIDs = []
    chain.offscreenHarnessResult.coordinatorOwnedDataSourceApplyAllowed = false
    return chain
}

private func makeRootSnapshot(
    arguments: [String],
    dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        dependencies: dependencies,
        createdAtMS: 1_735_000_008_500
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_008_600
    )
}

private func makeReadiness(
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
    preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly
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
        preferredConstructionKind: preferredConstructionKind
    )
}

private func harnessResult(
    allowed: Bool,
    constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
    artifactSummary: TimelineHomeRootRouteArtifactSnapshot
) -> TimelineHomeOffscreenConstructionHarnessResult {
    TimelineHomeOffscreenConstructionHarnessResult(
        offscreenConstructionAllowed: allowed,
        rejectionReasons: allowed ? [] : [.readinessBlocked, .unsupportedConstructionKind, .constructionPlanClosed],
        constructionKind: constructionKind,
        renderedRouteAfterConstruction: .legacy,
        routeActivationAllowed: false,
        collectionViewRouteConstructedFromRoot: false,
        timelineSurfaceConstructedFromRoot: false,
        timelineCollectionViewControllerConstructedFromRoot: false,
        controllerLoadedOffscreen: allowed,
        isAttachedToWindow: false,
        networkStarted: allowed == false,
        dbWriteAttempted: false,
        readMarkerAdvanced: false,
        coordinatorOwnedDataSourceApplyAllowed: allowed,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
        controllerItemIDs: allowed ? ["note:visible"] : [],
        diagnosticsArtifactSummary: artifactSummary
    )
}

private func artifactSummary(
    releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
) -> TimelineHomeRootRouteArtifactSnapshot {
    var artifact = makeRootSnapshot(
        arguments: ["Astrenza", "--timeline-engine=collectionView"],
        dependencies: .allAvailable
    ).artifactSummary
    artifact.releaseBlockerFlags = releaseBlockerFlags
    artifact.deterministicSummary = [
        "kind=timeline_home_route_decision",
        "version=1",
        "event=timeline_home_route_preflight_decision",
        "source=rootPreflight",
        "route=collectionView",
        "requested=collectionView",
        "effective=collectionView",
        "fallback=false",
        "collectionViewAllowed=true",
        "missing=[]",
        "issues=[]",
        "runtimeAllowed=true",
        "rolloutAllowed=true",
        "blockers=\(releaseBlockerFlags.map(\.rawValue).debugList)"
    ].joined(separator: " ")
    return artifact
}

private var selectedSwiftTestingSuites: [String] {
    [
        "TimelineHomeRootActivationDecisionSnapshotChainTests",
        "TimelineHomeRootActivationPreflightTests",
        "TimelineHomeActivationArtifactChainConsumerTests",
        "TimelineHomeCollectionViewRouteActivationReadinessConsumerTests",
        "TimelineHomeCollectionViewRouteActivationTests",
        "TimelineHomeRootRouteDecisionSnapshotConsumerTests",
        "TimelineHomeRootRouteDecisionSnapshotTests"
    ]
}

private var requiredResultKeys: Set<String> {
    [
        "activationBlockedIssueKinds",
        "activationPerformed",
        "activationWouldBeAllowed",
        "combinedArtifactChainIssueKinds",
        "diagnostics",
        "manualFallbackRoute",
        "preflightEvaluated",
        "productionRenderSwitchPerformed",
        "renderedRoute",
        "rollbackRoute",
        "rootBodyDecisionRenderedRoute",
        "rootBodyDecisionVisibleRoute",
        "sideEffectFlags"
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
            .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
        encoding: .utf8
    )
}

private func assertSendable<T: Sendable>(_: T.Type) {}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
