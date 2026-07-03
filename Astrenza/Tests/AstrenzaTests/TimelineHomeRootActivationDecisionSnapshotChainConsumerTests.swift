import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome root activation decision snapshot chain consumer")
struct TimelineHomeRootActivationDecisionSnapshotChainConsumerTests {
    @Test("decodes clean chain fixture JSON")
    func decodes_clean_chain_fixture_json() throws {
        let consumer = try makeConsumer(for: cleanFixture())

        #expect(consumer.preflightEvaluated)
        #expect(consumer.activationWouldBeAllowed)
        #expect(consumer.activationPerformed == false)
        #expect(consumer.timelineSurfaceConstructed == false)
    }

    @Test("decodes blocked preflight fixture JSON")
    func decodes_blocked_preflight_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedPreflightFixture())

        #expect(consumer.preflightEvaluated)
        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.activationBlockedIssueKinds == [.explicitCollectionViewLaunchFlag])
        #expect(consumer.renderedRoute == .legacy)
    }

    @Test("decodes dirty timelineSurfaceConstructed fixture JSON")
    func decodes_dirty_timeline_surface_constructed_fixture_json() throws {
        let consumer = try makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.timelineSurfaceConstructed)
        #expect(consumer.sideEffectFlags.timelineSurfaceConstructed)
        #expect(consumer.combinedArtifactChainIssueKinds.contains("construction.offscreen.rootSurfaceConstructionOpen"))
        #expect(consumer.activationBlockedIssueKinds == dirtySurfaceActivationIssues)
    }

    @Test("deterministic debug summary for clean chain")
    func deterministic_debug_summary_for_clean_chain() throws {
        let consumer = try makeConsumer(for: cleanFixture())

        #expect(consumer.debugSummary.deterministicText == expectedCleanDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedCleanDebugSummary)
    }

    @Test("deterministic debug summary for dirty surface chain")
    func deterministic_debug_summary_for_dirty_surface_chain() throws {
        let consumer = try makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())

        #expect(consumer.debugSummary.deterministicText == expectedDirtySurfaceDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedDirtySurfaceDebugSummary)
    }

    @Test("query activation and preflight state")
    func query_activation_and_preflight_state() throws {
        let clean = try makeConsumer(for: cleanFixture())
        let blocked = try makeConsumer(for: blockedPreflightFixture())

        #expect(clean.preflightEvaluated)
        #expect(clean.activationWouldBeAllowed)
        #expect(clean.activationPerformed == false)
        #expect(clean.productionRenderSwitchPerformed == false)
        #expect(blocked.preflightEvaluated)
        #expect(blocked.activationWouldBeAllowed == false)
        #expect(blocked.activationPerformed == false)
        #expect(blocked.productionRenderSwitchPerformed == false)
    }

    @Test("query rendered rollback and manualFallback routes stay legacy")
    func query_rendered_rollback_and_manual_fallback_routes_stay_legacy() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.renderedRoute == .legacy })
        #expect(consumers.allSatisfy { $0.rollbackRoute == .legacy })
        #expect(consumers.allSatisfy { $0.manualFallbackRoute == .legacy })
    }

    @Test("query root body decision visible and rendered routes")
    func query_root_body_decision_visible_and_rendered_routes() throws {
        let clean = try makeConsumer(for: cleanFixture())
        let blocked = try makeConsumer(for: blockedPreflightFixture())

        #expect(clean.rootBodyDecisionRenderedRoute == .legacy)
        #expect(clean.rootBodyDecisionVisibleRoute == .collectionViewPlaceholder)
        #expect(blocked.rootBodyDecisionRenderedRoute == .legacy)
        #expect(blocked.rootBodyDecisionVisibleRoute == .legacy)
    }

    @Test("query activation blocked issues")
    func query_activation_blocked_issues() throws {
        let clean = try makeConsumer(for: cleanFixture())
        let blockedPreflight = try makeConsumer(for: blockedPreflightFixture())
        let dirtySurface = try makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())

        #expect(clean.activationBlockedIssueKinds.isEmpty)
        #expect(blockedPreflight.activationBlockedIssueKinds == [.explicitCollectionViewLaunchFlag])
        #expect(dirtySurface.activationBlockedIssueKinds == dirtySurfaceActivationIssues)
    }

    @Test("query artifact chain issues")
    func query_artifact_chain_issues() throws {
        let clean = try makeConsumer(for: cleanFixture())
        let blocked = try makeConsumer(for: blockedArtifactChainFixture())
        let dirtySurface = try makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())

        #expect(clean.combinedArtifactChainIssueKinds.isEmpty)
        #expect(blocked.combinedArtifactChainIssueKinds.contains("construction.readiness.renderedRouteLegacy"))
        #expect(blocked.combinedArtifactChainIssueKinds.contains("activation.constructionGatesClean"))
        #expect(dirtySurface.combinedArtifactChainIssueKinds == dirtySurfaceCombinedIssues)
    }

    @Test("query side-effect flags including timelineSurfaceConstructed")
    func query_side_effect_flags_including_timeline_surface_constructed() throws {
        let clean = try makeConsumer(for: cleanFixture())
        let dirtySurface = try makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())

        #expect(clean.sideEffectFlags.timelineSurfaceConstructed == false)
        #expect(clean.timelineSurfaceConstructed == false)
        #expect(clean.sideEffectFlags.rootViewConstructed == false)
        #expect(clean.sideEffectFlags.homeTimelineViewConstructed == false)
        #expect(clean.sideEffectFlags.nostrHomeTimelineStoreConstructed == false)
        #expect(clean.sideEffectFlags.timelineCollectionViewControllerConstructed == false)
        #expect(clean.sideEffectFlags.networkStarted == false)
        #expect(clean.sideEffectFlags.dbWriteAttempted == false)
        #expect(clean.sideEffectFlags.readMarkerChanged == false)
        #expect(clean.sideEffectFlags.dataSourceApplyCalled == false)
        #expect(clean.sideEffectFlags.dataSourceApplyFromRootCalled == false)
        #expect(clean.sideEffectFlags.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
        #expect(clean.sideEffectFlags.requiresNetworkWork == false)
        #expect(clean.sideEffectFlags.requiresDBWrite == false)
        #expect(clean.sideEffectFlags.fileWriteAttempted == false)
        #expect(clean.sideEffectFlags.externalTelemetryUploadAttempted == false)
        #expect(dirtySurface.timelineSurfaceConstructed)
        #expect(dirtySurface.sideEffectFlags.timelineSurfaceConstructed)
        #expect(dirtySurface.sideEffectFlags.rootViewConstructed == false)
        #expect(dirtySurface.sideEffectFlags.homeTimelineViewConstructed == false)
        #expect(dirtySurface.sideEffectFlags.nostrHomeTimelineStoreConstructed == false)
        #expect(dirtySurface.sideEffectFlags.timelineCollectionViewControllerConstructed == false)
        #expect(dirtySurface.sideEffectFlags.networkStarted == false)
        #expect(dirtySurface.sideEffectFlags.dbWriteAttempted == false)
        #expect(dirtySurface.sideEffectFlags.readMarkerChanged == false)
        #expect(dirtySurface.sideEffectFlags.dataSourceApplyCalled == false)
    }

    @Test("query diagnostics and artifact summaries")
    func query_diagnostics_and_artifact_summaries() throws {
        let consumer = try makeConsumer(for: cleanFixture())

        #expect(consumer.diagnostics.rootBodyDecisionDebugSummary == expectedRootDecisionDebugSummary)
        #expect(consumer.diagnostics.rootBodyDecisionArtifactSummary == expectedReadyArtifactSummary)
        #expect(consumer.diagnostics.activationArtifactChainSummary == expectedActivationChainDebugSummary)
        #expect(consumer.diagnostics.activationReadinessSummary == expectedAllowedActivationArtifactSummary)
        #expect(consumer.diagnostics.flaggedConstructionSummary == expectedAllowedFlaggedConstructionSummary)
        #expect(consumer.diagnostics.constructionReadinessSummary == expectedReadyArtifactSummary)
        #expect(consumer.diagnostics.offscreenHarnessSummary == expectedReadyArtifactSummary)
        #expect(consumer.diagnostics.sideEffectSummary == expectedActivationChainSideEffectSummary)
    }

    @Test("privacy forbidden fragments absent from encoded chain and summary")
    func privacy_forbidden_fragments_absent_from_encoded_chain_and_summary() throws {
        let chainJSON = try encodedJSONString(cleanFixture()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: cleanFixture())).debugSummary)
            .lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!chainJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: cleanFixture())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeRootActivationDecisionSnapshotChainConsumer.self,
            from: encoded
        )
        let source = try sourceFile(
            named: "TimelineHomeRootActivationDecisionSnapshotChainConsumer.swift"
        )

        assertSendable(TimelineHomeRootActivationDecisionSnapshotChainReader.self)
        assertSendable(TimelineHomeRootActivationDecisionSnapshotChainConsumer.self)
        assertSendable(TimelineHomeRootActivationDecisionSnapshotDebugSummary.self)
        #expect(decoded == consumer)
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
}

private func makeConsumer(
    for chain: TimelineHomeRootActivationPreflightSnapshotChain
) throws -> TimelineHomeRootActivationDecisionSnapshotChainConsumer {
    try TimelineHomeRootActivationDecisionSnapshotChainConsumer.decodeFixtureJSON(
        encodedData(chain)
    )
}

private func allFixtureConsumers() throws -> [TimelineHomeRootActivationDecisionSnapshotChainConsumer] {
    try [
        makeConsumer(for: cleanFixture()),
        makeConsumer(for: blockedPreflightFixture()),
        makeConsumer(for: blockedArtifactChainFixture()),
        makeConsumer(for: dirtyTimelineSurfaceConstructionFixture())
    ]
}

private func cleanFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = cleanActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight(consumer: consumer),
        rootRouteDecisionSnapshot: activationChain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    )
}

private func blockedPreflightFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = cleanActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight(arguments: ["Astrenza"], consumer: consumer),
        rootRouteDecisionSnapshot: makeRootSnapshot(arguments: ["Astrenza"]),
        activationArtifactChainConsumer: consumer
    )
}

private func blockedArtifactChainFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = blockedConstructionActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight(consumer: consumer),
        rootRouteDecisionSnapshot: activationChain.constructionArtifactChain.routeDecisionSnapshot,
        activationArtifactChainConsumer: consumer
    )
}

private func dirtyTimelineSurfaceConstructionFixture() -> TimelineHomeRootActivationPreflightSnapshotChain {
    let activationChain = dirtyTimelineSurfaceConstructionActivationChain()
    let consumer = TimelineHomeActivationArtifactChainConsumer(chain: activationChain)
    return TimelineHomeRootActivationPreflightSnapshotChain(
        preflightResult: preflight(consumer: consumer),
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

private var expectedReadyArtifactSummary: String {
    "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
}

private var expectedRootDecisionDebugSummary: String {
    "renderedRoute=legacy visibleRoute=collectionViewPlaceholder observedCollectionView=true constructedCollectionView=false fallbackIssues=[] readMarkerChanged=false requiresNetworkWork=false requiresDBWrite=false dataSourceApplyCalled=false diagnosticsRecordCount=1 releaseBlockers=[] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false) artifactSummary={\(expectedReadyArtifactSummary)}"
}

private var expectedAllowedFlaggedConstructionSummary: String {
    [
        "requestedRoute=collectionView",
        "constructionAllowed=true",
        "constructionKind=offscreenOnly",
        "renderedRouteAfterConstruction=legacy",
        "routeActivationAllowed=false",
        "issues=[]",
        "chainIssues=[]",
        "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false)",
        "routeDecision={\(expectedReadyArtifactSummary)}",
        "constructionReadiness={\(expectedReadyArtifactSummary)}",
        "offscreenHarness={\(expectedReadyArtifactSummary)}"
    ].joined(separator: " ")
}

private var expectedAllowedActivationArtifactSummary: String {
    [
        "activationWouldBeAllowed=true",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "renderedRoute=legacy",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "issues=[]",
        "chainIssues=[]",
        "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false)",
        "routeDecision={\(expectedReadyArtifactSummary)}",
        "constructionReadiness={\(expectedReadyArtifactSummary)}",
        "offscreenHarness={\(expectedReadyArtifactSummary)}",
        "flaggedConstruction={\(expectedAllowedFlaggedConstructionSummary)}"
    ].joined(separator: " ")
}

private var expectedActivationChainSideEffectSummary: String {
    "root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false,dataSourceApplyFromRoot=false,extraNostrStore=false"
}

private var expectedActivationChainDebugSummary: String {
    [
        "constructionReady=true",
        "constructionAllowed=true",
        "offscreenHarnessAllowed=true",
        "activationWouldBeAllowed=true",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "renderedRoute=legacy",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "constructionIssues=[]",
        "activationIssues=[]",
        "activationPairIssues=[]",
        "combinedIssues=[]",
        "releaseBlockers=[]",
        "sideEffects(\(expectedActivationChainSideEffectSummary))",
        "startupNetworkClean=true",
        "readMarkerChanged=false",
        "requiresNetworkWork=false",
        "requiresDBWrite=false",
        "dataSourceApplyFromRoot=false",
        "extraNostrHomeTimelineStoreConstructed=false",
        "diagnostics(route={\(expectedReadyArtifactSummary)},construction={\(expectedReadyArtifactSummary)},offscreen={\(expectedReadyArtifactSummary)},flagged={\(expectedAllowedFlaggedConstructionSummary)},activation={\(expectedAllowedActivationArtifactSummary)})"
    ].joined(separator: " ")
}

private var expectedCleanDebugSummary: String {
    [
        "preflightEvaluated=true",
        "activationWouldBeAllowed=true",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "renderedRoute=legacy",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "rootBody(rendered=legacy,visible=collectionViewPlaceholder)",
        "activationIssues=[]",
        "artifactIssues=[]",
        "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,timelineSurface=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,dataSourceApplyFromRoot=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false,fileWrite=false,externalTelemetryUpload=false)",
        "diagnostics(rootDebug={\(expectedRootDecisionDebugSummary)},rootArtifact={\(expectedReadyArtifactSummary)},activationChain={\(expectedActivationChainDebugSummary)},activationReadiness={\(expectedAllowedActivationArtifactSummary)},flaggedConstruction={\(expectedAllowedFlaggedConstructionSummary)},constructionReadiness={\(expectedReadyArtifactSummary)},offscreenHarness={\(expectedReadyArtifactSummary)},sideEffects={\(expectedActivationChainSideEffectSummary)})"
    ].joined(separator: " ")
}

private var dirtySurfaceCombinedIssues: [String] {
    [
        "construction.offscreen.rootSurfaceConstructionOpen",
        "construction.offscreen.constructionPlanClosed",
        "activation.flaggedConstructionResultClean",
        "activation.artifactChainClean",
        "activation.offscreenNoWindowSmokePassed",
        "activation.dataSourceApplyCoordinatorOnly",
    ]
}

private var dirtySurfaceActivationIssues: [TimelineHomeRootActivationPreflightIssue] {
    [
        .activationArtifactChainClean,
        .activationReadinessClean
    ]
}

private var expectedDirtySurfaceDebugSummary: String {
    [
        "preflightEvaluated=true",
        "activationWouldBeAllowed=false",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "renderedRoute=legacy",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "rootBody(rendered=legacy,visible=collectionViewPlaceholder)",
        "activationIssues=\(dirtySurfaceActivationIssues.map(\.rawValue).debugList)",
        "artifactIssues=\(dirtySurfaceCombinedIssues.debugList)",
        "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,timelineSurface=true,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,dataSourceApplyFromRoot=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false,fileWrite=false,externalTelemetryUpload=false)"
    ].joined(separator: " ")
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

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    try #require(String(data: encodedData(value), encoding: .utf8))
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
