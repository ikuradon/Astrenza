import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route activation readiness consumer")
struct TimelineHomeCollectionViewRouteActivationReadinessConsumerTests {
    @Test("decodes allowed activation readiness fixture JSON")
    func decodes_allowed_activation_readiness_fixture_json() throws {
        let consumer = try makeConsumer(for: allowedActivationResult())

        #expect(consumer.activationWouldBeAllowed)
        #expect(consumer.activationPerformed == false)
        #expect(consumer.productionRenderSwitchPerformed == false)
        #expect(consumer.renderedRoute == .legacy)
    }

    @Test("decodes blocked missing flag fixture JSON")
    func decodes_blocked_missing_flag_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedMissingFlagResult())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.blockedIssueKinds == missingFlagBlockedIssues)
        #expect(consumer.renderedRoute == .legacy)
    }

    @Test("decodes blocked dirty construction result fixture JSON")
    func decodes_blocked_dirty_construction_result_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedDirtyConstructionResult())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.blockedIssueKinds.contains(.flaggedConstructionResultClean))
        #expect(consumer.constructionResultClean == false)
        #expect(consumer.requiresDBWrite)
        #expect(consumer.readMarkerChanged)
    }

    @Test("decodes blocked stale artifact identity fixture JSON")
    func decodes_blocked_stale_artifact_identity_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedStaleArtifactIdentityResult())

        #expect(consumer.activationWouldBeAllowed == false)
        #expect(consumer.blockedIssueKinds == [.flaggedConstructionResultClean])
        #expect(consumer.constructionResultClean == false)
        #expect(consumer.artifactChainClean)
    }

    @Test("deterministic debug summary for allowed result")
    func deterministic_debug_summary_for_allowed_result() throws {
        let consumer = try makeConsumer(for: allowedActivationResult())

        #expect(consumer.debugSummary.deterministicText == expectedAllowedDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedAllowedDebugSummary)
    }

    @Test("deterministic debug summary for blocked result")
    func deterministic_debug_summary_for_blocked_result() throws {
        let consumer = try makeConsumer(for: blockedMissingFlagResult())

        #expect(consumer.debugSummary.deterministicText == expectedBlockedMissingFlagDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedBlockedMissingFlagDebugSummary)
    }

    @Test("query activationWouldBeAllowed")
    func query_activation_would_be_allowed() throws {
        let allowed = try makeConsumer(for: allowedActivationResult())
        let blocked = try makeConsumer(for: blockedMissingFlagResult())

        #expect(allowed.activationWouldBeAllowed)
        #expect(blocked.activationWouldBeAllowed == false)
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

    @Test("query blocked issue kinds")
    func query_blocked_issue_kinds() throws {
        let missingFlag = try makeConsumer(for: blockedMissingFlagResult())
        let dirtyConstruction = try makeConsumer(for: blockedDirtyConstructionResult())

        #expect(missingFlag.blockedIssueKinds == missingFlagBlockedIssues)
        #expect(dirtyConstruction.blockedIssueKinds.contains(.flaggedConstructionResultClean))
        #expect(dirtyConstruction.blockedIssueKinds.contains(.readMarkerUnchanged))
        #expect(dirtyConstruction.blockedIssueKinds.contains(.requiresDBWriteFalse))
        #expect(dirtyConstruction.blockedIssueKinds.contains(.dataSourceApplyCoordinatorOnly))
    }

    @Test("query construction artifact and root snapshot gates")
    func query_construction_artifact_and_root_snapshot_gates() throws {
        let allowed = try makeConsumer(for: allowedActivationResult())
        let dirtyConstruction = try makeConsumer(for: blockedDirtyConstructionResult())
        let staleIdentity = try makeConsumer(for: blockedStaleArtifactIdentityResult())
        let blockedRootSnapshot = try makeConsumer(for: blockedRootSnapshotScopeResult())

        #expect(allowed.constructionResultClean)
        #expect(allowed.artifactChainClean)
        #expect(allowed.rootBodySnapshotPermitsActivation)
        #expect(dirtyConstruction.constructionResultClean == false)
        #expect(staleIdentity.artifactChainClean)
        #expect(blockedRootSnapshot.rootBodySnapshotPermitsActivation == false)
    }

    @Test("query startup readMarker network DB dataSource and NostrStore flags")
    func query_startup_read_marker_network_db_data_source_and_nostr_store_flags() throws {
        let allowed = try makeConsumer(for: allowedActivationResult())
        let dirty = try makeConsumer(for: blockedDirtyConstructionResult())

        #expect(allowed.startupNetworkClean)
        #expect(allowed.readMarkerChanged == false)
        #expect(allowed.requiresNetworkWork == false)
        #expect(allowed.requiresDBWrite == false)
        #expect(allowed.dataSourceApplyFromRootCalled == false)
        #expect(allowed.extraNostrHomeTimelineStoreConstructed == false)
        #expect(dirty.startupNetworkClean)
        #expect(dirty.readMarkerChanged)
        #expect(dirty.requiresNetworkWork == false)
        #expect(dirty.requiresDBWrite)
        #expect(dirty.dataSourceApplyFromRootCalled)
        #expect(dirty.extraNostrHomeTimelineStoreConstructed == false)
    }

    @Test("query diagnostics artifact summary")
    func query_diagnostics_artifact_summary() throws {
        let consumer = try makeConsumer(for: allowedActivationResult())

        #expect(consumer.diagnosticsSummary.routeDecision.contains("route=collectionView"))
        #expect(consumer.diagnosticsSummary.constructionReadiness.contains("collectionViewAllowed=true"))
        #expect(consumer.diagnosticsSummary.offscreenHarness.contains("collectionViewAllowed=true"))
        #expect(consumer.diagnosticsSummary.flaggedConstruction.contains("constructionAllowed=true"))
    }

    @Test("privacy forbidden fragments absent from encoded result and summary")
    func privacy_forbidden_fragments_absent_from_encoded_result_and_summary() throws {
        let resultJSON = try encodedJSONString(allowedActivationResult()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: allowedActivationResult())).debugSummary)
            .lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!resultJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: allowedActivationResult())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeCollectionViewRouteActivationReadinessConsumer.self,
            from: encoded
        )
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteActivationReadinessConsumer.swift")

        assertSendable(TimelineHomeCollectionViewRouteActivationResultReader.self)
        assertSendable(TimelineHomeCollectionViewRouteActivationReadinessConsumer.self)
        assertSendable(TimelineHomeCollectionViewActivationDebugSummary.self)
        assertSendable(TimelineHomeCollectionViewActivationDiagnosticsSummary.self)
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

    private var expectedAllowedDebugSummary: String {
        [
            "activationWouldBeAllowed=true",
            "activationPerformed=false",
            "productionRenderSwitchPerformed=false",
            "renderedRoute=legacy",
            "rollbackRoute=legacy",
            "manualFallbackRoute=legacy",
            "blockedIssues=[]",
            "chainIssues=[]",
            "constructionResultClean=true",
            "artifactChainClean=true",
            "rootBodySnapshotPermitsActivation=true",
            "startupNetworkClean=true",
            "sideEffects(network=false,dbWrite=false,readMarker=false,requiresNetworkWork=false,requiresDBWrite=false,dataSourceApplyFromRoot=false,extraNostrStore=false)",
            "diagnostics(route={\(expectedReadyArtifactSummary)},construction={\(expectedReadyArtifactSummary)},offscreen={\(expectedReadyArtifactSummary)},flagged={\(expectedAllowedFlaggedConstructionSummary)})"
        ].joined(separator: " ")
    }

    private var expectedBlockedMissingFlagDebugSummary: String {
        [
            "activationWouldBeAllowed=false",
            "activationPerformed=false",
            "productionRenderSwitchPerformed=false",
            "renderedRoute=legacy",
            "rollbackRoute=legacy",
            "manualFallbackRoute=legacy",
            "blockedIssues=[explicitCollectionViewLaunchFlag,flaggedConstructionResultClean,dataSourceApplyCoordinatorOnly]",
            "chainIssues=[]",
            "constructionResultClean=false",
            "artifactChainClean=true",
            "rootBodySnapshotPermitsActivation=true",
            "startupNetworkClean=true",
            "sideEffects(network=false,dbWrite=false,readMarker=false,requiresNetworkWork=false,requiresDBWrite=false,dataSourceApplyFromRoot=false,extraNostrStore=false)",
            "diagnostics(route={\(expectedReadyArtifactSummary)},construction={\(expectedReadyArtifactSummary)},offscreen={\(expectedReadyArtifactSummary)},flagged={\(expectedBlockedMissingFlagConstructionSummary)})"
        ].joined(separator: " ")
    }

    private var expectedReadyArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
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

    private var expectedBlockedMissingFlagConstructionSummary: String {
        [
            "requestedRoute=legacy",
            "constructionAllowed=false",
            "constructionKind=productionClosed",
            "renderedRouteAfterConstruction=legacy",
            "routeActivationAllowed=false",
            "issues=[missingExplicitCollectionViewFlag,requestedRouteNotCollectionView]",
            "chainIssues=[]",
            "sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false)",
            "routeDecision={\(expectedReadyArtifactSummary)}",
            "constructionReadiness={\(expectedReadyArtifactSummary)}",
            "offscreenHarness={\(expectedReadyArtifactSummary)}"
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

    private var missingFlagBlockedIssues: [TimelineHomeCollectionViewRouteActivationGate] {
        [
            .explicitCollectionViewLaunchFlag,
            .flaggedConstructionResultClean,
            .dataSourceApplyCoordinatorOnly
        ]
    }

    private func allFixtureConsumers() throws -> [TimelineHomeCollectionViewRouteActivationReadinessConsumer] {
        try [
            allowedActivationResult(),
            blockedMissingFlagResult(),
            blockedDirtyConstructionResult(),
            blockedStaleArtifactIdentityResult()
        ].map(makeConsumer(for:))
    }

    private func makeConsumer(
        for result: TimelineHomeCollectionViewRouteActivationResult
    ) throws -> TimelineHomeCollectionViewRouteActivationReadinessConsumer {
        try TimelineHomeCollectionViewRouteActivationReadinessConsumer.decodeFixtureJSON(
            encodedData(result)
        )
    }

    private func allowedActivationResult() -> TimelineHomeCollectionViewRouteActivationResult {
        evaluate()
    }

    private func blockedMissingFlagResult() -> TimelineHomeCollectionViewRouteActivationResult {
        evaluate(arguments: ["Astrenza"])
    }

    private func blockedDirtyConstructionResult() -> TimelineHomeCollectionViewRouteActivationResult {
        var constructionResult = construct()
        constructionResult.dbWriteAttempted = true
        constructionResult.readMarkerAdvanced = true
        constructionResult.dataSourceApplyFromRootCalled = true
        return evaluate(constructionResult: constructionResult, requiresDBWrite: true)
    }

    private func blockedStaleArtifactIdentityResult() -> TimelineHomeCollectionViewRouteActivationResult {
        var constructionResult = construct()
        constructionResult.artifactSummary.routeDecisionSummary = "stale-route-decision"
        return evaluate(constructionResult: constructionResult)
    }

    private func blockedRootSnapshotScopeResult() -> TimelineHomeCollectionViewRouteActivationResult {
        return evaluate(rootBodyDecisionSnapshotPermitsActivationScope: false)
    }

    private func evaluate(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        chain: TimelineHomeConstructionArtifactChain? = nil,
        constructionResult: TimelineHomeCollectionViewRouteConstructionResult? = nil,
        startupNetworkPatternClean: Bool = true,
        networkWaitedBeforeInteractiveScrollMS: Double = 0,
        readMarkerChanged: Bool = false,
        requiresNetworkWork: Bool = false,
        requiresDBWrite: Bool = false,
        rootBodyDecisionSnapshotPermitsActivationScope: Bool = true
    ) -> TimelineHomeCollectionViewRouteActivationResult {
        let resolvedChain = chain ?? cleanChain()
        return TimelineHomeCollectionViewRouteActivationReadiness(
            launchArguments: arguments,
            debugOverride: nil,
            constructionResult: constructionResult ?? construct(arguments: arguments, chain: resolvedChain),
            artifactChain: resolvedChain,
            offscreenNoWindowSmokePassed: true,
            initialRestoreSnapshotCoordinatorHarnessPassed: true,
            startupNetworkPatternClean: startupNetworkPatternClean,
            networkWaitedBeforeInteractiveScrollMS: networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: readMarkerChanged,
            requiresNetworkWork: requiresNetworkWork,
            requiresDBWrite: requiresDBWrite,
            dataSourceApplyCoordinatorOnly: true,
            noExtraNostrHomeTimelineStore: true,
            rootBodyDecisionSnapshotPermitsActivationScope: rootBodyDecisionSnapshotPermitsActivationScope,
            createdAtMS: 1_735_000_006_400
        ).evaluate()
    }

    private func construct(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        chain: TimelineHomeConstructionArtifactChain? = nil
    ) -> TimelineHomeCollectionViewRouteConstructionResult {
        let resolvedChain = chain ?? cleanChain()
        return TimelineHomeFlaggedCollectionViewRouteConstruction.evaluate(
            TimelineHomeCollectionViewRouteConstructionInput(
                launchArguments: arguments,
                artifactChain: resolvedChain,
                createdAtMS: 1_735_000_006_300
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
            offscreenHarnessResult: allowedHarnessResult(
                constructionKind: kind,
                artifactSummary: snapshot.artifactSummary
            )
        )
    }

    private func makeSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: 1_735_000_006_100
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: 1_735_000_006_200
        )
    }

    private func makeReadiness(
        rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
        preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind
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
