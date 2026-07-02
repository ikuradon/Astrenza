import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome activation artifact chain consumer")
struct TimelineHomeActivationArtifactChainConsumerTests {
    @Test("decodes clean activation chain fixture JSON")
    func decodes_clean_activation_chain_fixture_json() throws {
        let consumer = try makeConsumer(for: cleanActivationChain())

        #expect(consumer.constructionReady)
        #expect(consumer.constructionAllowed)
        #expect(consumer.offscreenHarnessAllowed)
        #expect(consumer.activationWouldBeAllowed)
    }

    @Test("decodes blocked construction chain fixture JSON")
    func decodes_blocked_construction_chain_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedConstructionActivationChain())

        #expect(consumer.constructionReady == false)
        #expect(consumer.constructionAllowed == false)
        #expect(consumer.offscreenHarnessAllowed == false)
        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.constructionBlockedIssueKinds.contains("readiness.renderedRouteLegacy"))
    }

    @Test("decodes blocked activation readiness fixture JSON")
    func decodes_blocked_activation_readiness_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedActivationReadinessChain())

        #expect(consumer.constructionReady)
        #expect(consumer.constructionAllowed)
        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.activationBlockedIssueKinds == missingFlagActivationIssues)
    }

    @Test("deterministic debug summary for clean chain")
    func deterministic_debug_summary_for_clean_chain() throws {
        let consumer = try makeConsumer(for: cleanActivationChain())

        #expect(consumer.debugSummary.deterministicText == expectedCleanDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedCleanDebugSummary)
    }

    @Test("deterministic debug summary for blocked chain")
    func deterministic_debug_summary_for_blocked_chain() throws {
        let consumer = try makeConsumer(for: blockedConstructionActivationChain())

        #expect(consumer.debugSummary.deterministicText == expectedBlockedConstructionDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedBlockedConstructionDebugSummary)
    }

    @Test("query construction and activation readiness")
    func query_construction_and_activation_readiness() throws {
        let clean = try makeConsumer(for: cleanActivationChain())
        let blockedConstruction = try makeConsumer(for: blockedConstructionActivationChain())
        let blockedActivation = try makeConsumer(for: blockedActivationReadinessChain())

        #expect(clean.constructionReady)
        #expect(clean.activationWouldBeAllowed)
        #expect(blockedConstruction.constructionReady == false)
        #expect(blockedConstruction.activationWouldBeAllowed == false)
        #expect(blockedActivation.constructionReady)
        #expect(blockedActivation.activationWouldBeAllowed == false)
    }

    @Test("query activationPerformed remains false")
    func query_activation_performed_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.activationPerformed == false })
    }

    @Test("query productionRenderSwitchPerformed remains false")
    func query_production_render_switch_performed_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.productionRenderSwitchPerformed == false })
    }

    @Test("query rendered rollback and manualFallback routes stay legacy")
    func query_rendered_rollback_and_manual_fallback_routes_stay_legacy() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.renderedRoute == .legacy })
        #expect(consumers.allSatisfy { $0.rollbackRoute == .legacy })
        #expect(consumers.allSatisfy { $0.manualFallbackRoute == .legacy })
    }

    @Test("query combined blocked issue kinds")
    func query_combined_blocked_issue_kinds() throws {
        let blockedConstruction = try makeConsumer(for: blockedConstructionActivationChain())
        let blockedActivation = try makeConsumer(for: blockedActivationReadinessChain())

        #expect(blockedConstruction.combinedBlockedIssueKinds.contains("construction.readiness.renderedRouteLegacy"))
        #expect(blockedConstruction.combinedBlockedIssueKinds.contains("activation.constructionGatesClean"))
        #expect(blockedActivation.combinedBlockedIssueKinds == missingFlagActivationIssues.map { "activation.\($0.rawValue)" })
    }

    @Test("detects stale activation result paired with different construction chain")
    func detects_stale_activation_result_paired_with_different_construction_chain() throws {
        let consumer = try makeConsumer(for: staleActivationPairChain())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.activationBlockedIssueKinds.contains(.artifactChainClean))
        #expect(consumer.activationArtifactPairIssueKinds.contains("routeDecisionSummaryMismatch"))
        #expect(consumer.activationArtifactPairIssueKinds.contains("constructionReadinessSummaryMismatch"))
        #expect(consumer.activationArtifactPairIssueKinds.contains("offscreenHarnessSummaryMismatch"))
        #expect(consumer.activationArtifactPairIssueKinds.contains("chainIssueKindsMismatch"))
        #expect(consumer.activationArtifactPairIssueKinds.contains("deterministicSummaryMismatch"))
        #expect(consumer.combinedBlockedIssueKinds.contains("activation.artifactChainClean"))
        #expect(consumer.combinedBlockedIssueKinds.contains("activationPair.routeDecisionSummaryMismatch"))
    }

    @Test("query release blocker flags")
    func query_release_blocker_flags() throws {
        let clean = try makeConsumer(for: cleanActivationChain())
        let blockedConstruction = try makeConsumer(for: blockedConstructionActivationChain())

        #expect(clean.releaseBlockerFlags.isEmpty)
        #expect(blockedConstruction.releaseBlockerFlags == [.requiresNetworkWork])
    }

    @Test("query side-effect flags all false for safe fixture")
    func query_side_effect_flags_all_false_for_safe_fixture() throws {
        let consumer = try makeConsumer(for: cleanActivationChain())

        #expect(consumer.sideEffectFlags.rootViewConstructed == false)
        #expect(consumer.sideEffectFlags.homeTimelineViewConstructed == false)
        #expect(consumer.sideEffectFlags.nostrHomeTimelineStoreConstructed == false)
        #expect(consumer.sideEffectFlags.timelineCollectionViewControllerConstructed == false)
        #expect(consumer.sideEffectFlags.networkStarted == false)
        #expect(consumer.sideEffectFlags.dbWriteAttempted == false)
        #expect(consumer.sideEffectFlags.readMarkerChanged == false)
        #expect(consumer.sideEffectFlags.dataSourceApplyCalled == false)
        #expect(consumer.sideEffectFlags.dataSourceApplyFromRootCalled == false)
        #expect(consumer.sideEffectFlags.extraNostrHomeTimelineStoreConstructed == false)
        #expect(consumer.sideEffectFlags.requiresNetworkWork == false)
        #expect(consumer.sideEffectFlags.requiresDBWrite == false)
    }

    @Test("query dirty activation side-effect flags are aggregated")
    func query_dirty_activation_side_effect_flags_are_aggregated() throws {
        let consumer = try makeConsumer(for: dirtyActivationSideEffectChain())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.readMarkerChanged)
        #expect(consumer.requiresDBWrite)
        #expect(consumer.dataSourceApplyFromRootCalled)
        #expect(consumer.extraNostrHomeTimelineStoreConstructed)
        #expect(consumer.sideEffectFlags.dbWriteAttempted)
        #expect(consumer.sideEffectFlags.readMarkerChanged)
        #expect(consumer.sideEffectFlags.dataSourceApplyCalled)
        #expect(consumer.sideEffectFlags.forbiddenDataSourceApplyOutsideCoordinatorCalled)
        #expect(consumer.sideEffectFlags.requiresDBWrite)
        #expect(consumer.sideEffectFlags.dataSourceApplyFromRootCalled)
        #expect(consumer.sideEffectFlags.extraNostrHomeTimelineStoreConstructed)
    }

    @Test("query diagnostics artifact summaries from all stages")
    func query_diagnostics_artifact_summaries_from_all_stages() throws {
        let consumer = try makeConsumer(for: cleanActivationChain())

        #expect(consumer.diagnosticsSummary.routeDecision == expectedReadyArtifactSummary)
        #expect(consumer.diagnosticsSummary.constructionReadiness == expectedReadyArtifactSummary)
        #expect(consumer.diagnosticsSummary.offscreenHarness == expectedReadyArtifactSummary)
        #expect(consumer.diagnosticsSummary.flaggedConstruction == expectedAllowedFlaggedConstructionSummary)
        #expect(consumer.diagnosticsSummary.activation == expectedAllowedActivationArtifactSummary)
    }

    @Test("privacy forbidden fragments absent from encoded chain and summary")
    func privacy_forbidden_fragments_absent_from_encoded_chain_and_summary() throws {
        let chainJSON = try encodedJSONString(cleanActivationChain()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: cleanActivationChain())).debugSummary)
            .lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!chainJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: cleanActivationChain())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeActivationArtifactChainConsumer.self,
            from: encoded
        )
        let source = try sourceFile(named: "TimelineHomeActivationArtifactChainConsumer.swift")

        assertSendable(TimelineHomeActivationArtifactChain.self)
        assertSendable(TimelineHomeCollectionViewActivationArtifactChainReader.self)
        assertSendable(TimelineHomeActivationArtifactChainConsumer.self)
        assertSendable(TimelineHomeActivationArtifactChainDebugSummary.self)
        assertSendable(TimelineHomeActivationArtifactChainDiagnosticsSummary.self)
        assertSendable(TimelineHomeActivationArtifactChainSideEffectFlags.self)
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

    private var expectedReadyArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedBlockedArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[requiresNetworkWork]"
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

    private var expectedBlockedFlaggedConstructionSummary: String {
        [
            "requestedRoute=collectionView",
            "constructionAllowed=false",
            "constructionKind=productionClosed",
            "renderedRouteAfterConstruction=legacy",
            "routeActivationAllowed=false",
            "issues=[readinessDirty,offscreenHarnessRejected,artifactChainDirty]",
            "chainIssues=[readiness.renderedRouteLegacy,readiness.collectionViewRouteNotConstructed,readiness.sideEffectSentinelClean,readiness.artifactReleaseBlockerFlagsEmpty,offscreen.readinessBlocked,offscreen.unsupportedConstructionKind,offscreen.constructionPlanClosed,artifact.renderedRouteNotLegacy,artifact.collectionViewRouteConstructedFromRoot,artifact.releaseBlockersPresent,artifact.sideEffectsDirty]",
            "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=true,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false)",
            "routeDecision={\(expectedBlockedArtifactSummary)}",
            "constructionReadiness={\(expectedBlockedArtifactSummary)}",
            "offscreenHarness={\(expectedBlockedArtifactSummary)}"
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

    private var expectedBlockedActivationArtifactSummary: String {
        [
            "activationWouldBeAllowed=false",
            "activationPerformed=false",
            "productionRenderSwitchPerformed=false",
            "renderedRoute=legacy",
            "rollbackRoute=legacy",
            "manualFallbackRoute=legacy",
            "issues=[constructionGatesClean,flaggedConstructionResultClean,artifactChainClean,offscreenNoWindowSmokePassed,dataSourceApplyCoordinatorOnly]",
            "chainIssues=[readiness.renderedRouteLegacy,readiness.collectionViewRouteNotConstructed,readiness.sideEffectSentinelClean,readiness.artifactReleaseBlockerFlagsEmpty,offscreen.readinessBlocked,offscreen.unsupportedConstructionKind,offscreen.constructionPlanClosed,artifact.renderedRouteNotLegacy,artifact.collectionViewRouteConstructedFromRoot,artifact.releaseBlockersPresent,artifact.sideEffectsDirty]",
            "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=true,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false)",
            "routeDecision={\(expectedBlockedArtifactSummary)}",
            "constructionReadiness={\(expectedBlockedArtifactSummary)}",
            "offscreenHarness={\(expectedBlockedArtifactSummary)}",
            "flaggedConstruction={\(expectedBlockedFlaggedConstructionSummary)}"
        ].joined(separator: " ")
    }

    private var expectedCleanDebugSummary: String {
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
            "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false,dataSourceApplyFromRoot=false,extraNostrStore=false)",
            "startupNetworkClean=true",
            "readMarkerChanged=false",
            "requiresNetworkWork=false",
            "requiresDBWrite=false",
            "dataSourceApplyFromRoot=false",
            "extraNostrHomeTimelineStoreConstructed=false",
            "diagnostics(route={\(expectedReadyArtifactSummary)},construction={\(expectedReadyArtifactSummary)},offscreen={\(expectedReadyArtifactSummary)},flagged={\(expectedAllowedFlaggedConstructionSummary)},activation={\(expectedAllowedActivationArtifactSummary)})"
        ].joined(separator: " ")
    }

    private var expectedBlockedConstructionDebugSummary: String {
        [
            "constructionReady=false",
            "constructionAllowed=false",
            "offscreenHarnessAllowed=false",
            "activationWouldBeAllowed=false",
            "activationPerformed=false",
            "productionRenderSwitchPerformed=false",
            "renderedRoute=legacy",
            "rollbackRoute=legacy",
            "manualFallbackRoute=legacy",
            "constructionIssues=[readiness.renderedRouteLegacy,readiness.collectionViewRouteNotConstructed,readiness.sideEffectSentinelClean,readiness.artifactReleaseBlockerFlagsEmpty,offscreen.readinessBlocked,offscreen.unsupportedConstructionKind,offscreen.constructionPlanClosed]",
            "activationIssues=[constructionGatesClean,flaggedConstructionResultClean,artifactChainClean,offscreenNoWindowSmokePassed,dataSourceApplyCoordinatorOnly]",
            "activationPairIssues=[]",
            "combinedIssues=[construction.readiness.renderedRouteLegacy,construction.readiness.collectionViewRouteNotConstructed,construction.readiness.sideEffectSentinelClean,construction.readiness.artifactReleaseBlockerFlagsEmpty,construction.offscreen.readinessBlocked,construction.offscreen.unsupportedConstructionKind,construction.offscreen.constructionPlanClosed,activation.constructionGatesClean,activation.flaggedConstructionResultClean,activation.artifactChainClean,activation.offscreenNoWindowSmokePassed,activation.dataSourceApplyCoordinatorOnly]",
            "releaseBlockers=[requiresNetworkWork]",
            "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=true,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false,dataSourceApplyFromRoot=false,extraNostrStore=false)",
            "startupNetworkClean=false",
            "readMarkerChanged=false",
            "requiresNetworkWork=false",
            "requiresDBWrite=false",
            "dataSourceApplyFromRoot=false",
            "extraNostrHomeTimelineStoreConstructed=false",
            "diagnostics(route={\(expectedBlockedArtifactSummary)},construction={\(expectedBlockedArtifactSummary)},offscreen={\(expectedBlockedArtifactSummary)},flagged={\(expectedBlockedFlaggedConstructionSummary)},activation={\(expectedBlockedActivationArtifactSummary)})"
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
            "event_id"
        ]
    }

    private var missingFlagActivationIssues: [TimelineHomeCollectionViewRouteActivationGate] {
        [
            .explicitCollectionViewLaunchFlag,
            .flaggedConstructionResultClean,
            .dataSourceApplyCoordinatorOnly
        ]
    }

    private func allFixtureConsumers() throws -> [TimelineHomeActivationArtifactChainConsumer] {
        try [
            cleanActivationChain(),
            blockedConstructionActivationChain(),
            blockedActivationReadinessChain()
        ].map(makeConsumer(for:))
    }

    private func makeConsumer(
        for chain: TimelineHomeActivationArtifactChain
    ) throws -> TimelineHomeActivationArtifactChainConsumer {
        try TimelineHomeActivationArtifactChainConsumer.decodeFixtureJSON(
            encodedData(chain)
        )
    }

    private func cleanActivationChain() -> TimelineHomeActivationArtifactChain {
        let chain = cleanConstructionChain()
        return TimelineHomeActivationArtifactChain(
            constructionArtifactChain: chain,
            activationReadinessResult: evaluate(chain: chain)
        )
    }

    private func blockedConstructionActivationChain() -> TimelineHomeActivationArtifactChain {
        let chain = blockedConstructionChain()
        return TimelineHomeActivationArtifactChain(
            constructionArtifactChain: chain,
            activationReadinessResult: evaluate(chain: chain, constructionResult: construct(chain: chain))
        )
    }

    private func blockedActivationReadinessChain() -> TimelineHomeActivationArtifactChain {
        let chain = cleanConstructionChain()
        return TimelineHomeActivationArtifactChain(
            constructionArtifactChain: chain,
            activationReadinessResult: evaluate(
                arguments: ["Astrenza"],
                chain: chain,
                constructionResult: construct(arguments: ["Astrenza"], chain: chain)
            )
        )
    }

    private func staleActivationPairChain() -> TimelineHomeActivationArtifactChain {
        TimelineHomeActivationArtifactChain(
            constructionArtifactChain: blockedConstructionChain(),
            activationReadinessResult: evaluate(chain: cleanConstructionChain())
        )
    }

    private func dirtyActivationSideEffectChain() -> TimelineHomeActivationArtifactChain {
        let chain = cleanConstructionChain()
        var constructionResult = construct(chain: chain)
        constructionResult.dbWriteAttempted = true
        constructionResult.readMarkerAdvanced = true
        constructionResult.dataSourceApplyFromRootCalled = true
        return TimelineHomeActivationArtifactChain(
            constructionArtifactChain: chain,
            activationReadinessResult: evaluate(
                chain: chain,
                constructionResult: constructionResult,
                requiresDBWrite: true,
                noExtraNostrHomeTimelineStore: false
            )
        )
    }

    private func evaluate(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        chain: TimelineHomeConstructionArtifactChain,
        constructionResult: TimelineHomeCollectionViewRouteConstructionResult? = nil,
        requiresDBWrite: Bool = false,
        noExtraNostrHomeTimelineStore: Bool = true
    ) -> TimelineHomeCollectionViewRouteActivationResult {
        TimelineHomeCollectionViewRouteActivationReadiness(
            launchArguments: arguments,
            debugOverride: nil,
            constructionResult: constructionResult ?? construct(arguments: arguments, chain: chain),
            artifactChain: chain,
            offscreenNoWindowSmokePassed: true,
            initialRestoreSnapshotCoordinatorHarnessPassed: true,
            startupNetworkPatternClean: true,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWrite: requiresDBWrite,
            dataSourceApplyCoordinatorOnly: true,
            noExtraNostrHomeTimelineStore: noExtraNostrHomeTimelineStore,
            rootBodyDecisionSnapshotPermitsActivationScope: true,
            createdAtMS: 1_735_000_007_000
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
                createdAtMS: 1_735_000_006_900
            )
        )
    }

    private func cleanConstructionChain() -> TimelineHomeConstructionArtifactChain {
        let snapshot = makeSnapshot()
        let readiness = makeReadiness(
            rootDecisionSnapshot: snapshot,
            preferredConstructionKind: .offscreenOnly
        ).evaluate()
        return TimelineHomeConstructionArtifactChain(
            routeDecisionSnapshot: snapshot,
            constructionReadinessResult: readiness,
            offscreenHarnessResult: allowedHarnessResult(
                constructionKind: .offscreenOnly,
                artifactSummary: snapshot.artifactSummary
            )
        )
    }

    private func blockedConstructionChain() -> TimelineHomeConstructionArtifactChain {
        var snapshot = makeSnapshot()
        snapshot.renderedRoute = .collectionViewPlaceholder
        snapshot.collectionViewRouteConstructed = true
        snapshot.sideEffectSentinel.networkStarted = true
        snapshot.artifactSummary = artifactSummary(releaseBlockerFlags: [.requiresNetworkWork])
        let readiness = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
        return TimelineHomeConstructionArtifactChain(
            routeDecisionSnapshot: snapshot,
            constructionReadinessResult: readiness,
            offscreenHarnessResult: blockedReadinessHarnessResult(artifactSummary: snapshot.artifactSummary)
        )
    }

    private func makeSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: 1_735_000_006_500
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: 1_735_000_006_600
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

    private func allowedHarnessResult(
        constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
        artifactSummary: TimelineHomeRootRouteArtifactSnapshot
    ) -> TimelineHomeOffscreenConstructionHarnessResult {
        TimelineHomeOffscreenConstructionHarnessResult(
            offscreenConstructionAllowed: true,
            rejectionReasons: [],
            constructionKind: constructionKind,
            renderedRouteAfterConstruction: .legacy,
            routeActivationAllowed: false,
            collectionViewRouteConstructedFromRoot: false,
            timelineSurfaceConstructedFromRoot: false,
            timelineCollectionViewControllerConstructedFromRoot: false,
            controllerLoadedOffscreen: true,
            isAttachedToWindow: false,
            networkStarted: false,
            dbWriteAttempted: false,
            readMarkerAdvanced: false,
            coordinatorOwnedDataSourceApplyAllowed: true,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
            controllerItemIDs: ["note:visible"],
            diagnosticsArtifactSummary: artifactSummary
        )
    }

    private func blockedReadinessHarnessResult(
        artifactSummary: TimelineHomeRootRouteArtifactSnapshot
    ) -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = allowedHarnessResult(
            constructionKind: .productionClosed,
            artifactSummary: artifactSummary
        )
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.readinessBlocked, .unsupportedConstructionKind, .constructionPlanClosed]
        result.controllerLoadedOffscreen = false
        result.controllerItemIDs = []
        result.coordinatorOwnedDataSourceApplyAllowed = false
        return result
    }

    private func artifactSummary(
        releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    ) -> TimelineHomeRootRouteArtifactSnapshot {
        var artifact = makeSnapshot().artifactSummary
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

    private func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try encodedData(value)
        return try #require(String(data: data, encoding: .utf8))
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
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
