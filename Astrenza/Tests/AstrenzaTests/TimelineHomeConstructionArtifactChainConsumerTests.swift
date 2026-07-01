import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome construction artifact chain consumer")
struct TimelineHomeConstructionArtifactChainConsumerTests {
    @Test("decodes all-clean chain fixture")
    func decodes_all_clean_chain_fixture() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.didRenderLegacy)
        #expect(consumer.didObserveCollectionView)
        #expect(consumer.constructionReady)
        #expect(consumer.constructionAllowed)
        #expect(consumer.constructionKind == .offscreenOnly)
        #expect(consumer.offscreenHarnessAllowed)
    }

    @Test("decodes blocked readiness chain fixture")
    func decodes_blocked_readiness_chain_fixture() throws {
        let consumer = try makeConsumer(for: blockedReadinessChain())

        #expect(consumer.constructionReady == false)
        #expect(consumer.constructionAllowed == false)
        #expect(consumer.constructionKind == .productionClosed)
        #expect(consumer.combinedBlockedIssueKinds == [
            "readiness.renderedRouteLegacy",
            "readiness.collectionViewRouteNotConstructed",
            "readiness.sideEffectSentinelClean",
            "readiness.artifactReleaseBlockerFlagsEmpty",
            "offscreen.readinessBlocked",
            "offscreen.unsupportedConstructionKind",
            "offscreen.constructionPlanClosed"
        ])
    }

    @Test("decodes blocked offscreen harness chain fixture")
    func decodes_blocked_offscreen_harness_chain_fixture() throws {
        let consumer = try makeConsumer(for: blockedOffscreenHarnessChain())

        #expect(consumer.constructionReady)
        #expect(consumer.constructionAllowed)
        #expect(consumer.offscreenHarnessAllowed == false)
        #expect(consumer.coordinatorOwnedDataSourceApplyAllowed == false)
        #expect(consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled)
        #expect(consumer.combinedBlockedIssueKinds == [
            "offscreen.sideEffectFlagsDirty",
            "offscreen.constructionPlanClosed"
        ])
    }

    @Test("deterministic debug summary for clean chain")
    func deterministic_debug_summary_for_clean_chain() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.debugSummary.deterministicText == expectedCleanDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedCleanDebugSummary)
    }

    @Test("deterministic debug summary for blocked chain")
    func deterministic_debug_summary_for_blocked_chain() throws {
        let consumer = try makeConsumer(for: blockedReadinessChain())

        #expect(consumer.debugSummary.deterministicText == expectedBlockedReadinessDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedBlockedReadinessDebugSummary)
    }

    @Test("query legacy render and observed collectionView")
    func query_legacy_render_and_observed_collection_view() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.didRenderLegacy)
        #expect(consumer.didObserveCollectionView)
        #expect(consumer.routeDecisionConsumer.didRenderLegacy)
        #expect(consumer.routeDecisionConsumer.didObserveCollectionView)
    }

    @Test("query construction readiness and construction allowed")
    func query_construction_readiness_and_construction_allowed() throws {
        let clean = try makeConsumer(for: cleanChain())
        let blocked = try makeConsumer(for: blockedReadinessChain())

        #expect(clean.constructionReady)
        #expect(clean.constructionAllowed)
        #expect(blocked.constructionReady == false)
        #expect(blocked.constructionAllowed == false)
    }

    @Test("query offscreen harness allowed and no-window")
    func query_offscreen_harness_allowed_and_no_window() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.offscreenHarnessAllowed)
        #expect(consumer.noWindowAttached)
        #expect(consumer.offscreenHarnessConsumer.noWindowAttached)
    }

    @Test("query activation closed and constructed flags all false")
    func query_activation_closed_and_constructed_flags_all_false() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.routeActivationAllowed == false)
        #expect(consumer.collectionViewRouteConstructedFromRoot == false)
        #expect(consumer.timelineSurfaceConstructedFromRoot == false)
        #expect(consumer.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test("query coordinator-owned apply vs forbidden direct apply")
    func query_coordinator_owned_apply_vs_forbidden_direct_apply() throws {
        let clean = try makeConsumer(for: cleanChain())
        let blocked = try makeConsumer(for: blockedOffscreenHarnessChain())

        #expect(clean.coordinatorOwnedDataSourceApplyAllowed)
        #expect(clean.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
        #expect(blocked.coordinatorOwnedDataSourceApplyAllowed == false)
        #expect(blocked.forbiddenDataSourceApplyOutsideCoordinatorCalled)
    }

    @Test("query network db read-marker side effects all false")
    func query_network_db_read_marker_side_effects_all_false() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.sideEffectFlags.networkStarted == false)
        #expect(consumer.sideEffectFlags.dbWriteAttempted == false)
        #expect(consumer.sideEffectFlags.readMarkerAdvanced == false)
        #expect(consumer.sideEffectFlags.requiresNetworkWork == false)
        #expect(consumer.sideEffectFlags.requiresDBWrite == false)
    }

    @Test("query combined blocked issue kinds")
    func query_combined_blocked_issue_kinds() throws {
        let readiness = try makeConsumer(for: blockedReadinessChain())
        let offscreen = try makeConsumer(for: blockedOffscreenHarnessChain())

        #expect(readiness.combinedBlockedIssueKinds.contains("readiness.renderedRouteLegacy"))
        #expect(readiness.combinedBlockedIssueKinds.contains("offscreen.readinessBlocked"))
        #expect(offscreen.combinedBlockedIssueKinds == [
            "offscreen.sideEffectFlagsDirty",
            "offscreen.constructionPlanClosed"
        ])
    }

    @Test("query diagnostics summaries from snapshot readiness and harness")
    func query_diagnostics_summaries_from_snapshot_readiness_and_harness() throws {
        let consumer = try makeConsumer(for: cleanChain())

        #expect(consumer.diagnosticsSummaries.routeDecision == expectedReadyArtifactSummary)
        #expect(consumer.diagnosticsSummaries.constructionReadiness == expectedReadyArtifactSummary)
        #expect(consumer.diagnosticsSummaries.offscreenHarness == expectedReadyArtifactSummary)
    }

    @Test("privacy forbidden fragments absent from encoded chain and summary")
    func privacy_forbidden_fragments_absent_from_encoded_chain_and_summary() throws {
        let chainJSON = try encodedJSONString(cleanChain()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: cleanChain())).debugSummary).lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!chainJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: cleanChain())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeConstructionArtifactChainConsumer.self,
            from: encoded
        )
        let source = try sourceFile(named: "TimelineHomeConstructionArtifactChainConsumer.swift")

        assertSendable(TimelineHomeConstructionArtifactChain.self)
        assertSendable(TimelineHomeConstructionArtifactChainReader.self)
        assertSendable(TimelineHomeConstructionArtifactChainConsumer.self)
        assertSendable(TimelineHomeConstructionArtifactChainDebugSummary.self)
        assertSendable(TimelineHomeConstructionArtifactChainDiagnosticsSummaries.self)
        assertSendable(TimelineHomeConstructionArtifactChainSideEffectFlags.self)
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

    private var expectedCleanDebugSummary: String {
        "didRenderLegacy=true didObserveCollectionView=true constructionReady=true constructionAllowed=true constructionKind=offscreenOnly offscreenHarnessAllowed=true noWindowAttached=true routeActivationAllowed=false rootConstructed(route=false,surface=false,controller=false) coordinatorApplyAllowed=true forbiddenDataSourceApplyOutsideCoordinatorCalled=false blockedIssues=[] releaseBlockers=[] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false) diagnostics(route={\(expectedReadyArtifactSummary)},construction={\(expectedReadyArtifactSummary)},offscreen={\(expectedReadyArtifactSummary)})"
    }

    private var expectedBlockedReadinessDebugSummary: String {
        "didRenderLegacy=false didObserveCollectionView=true constructionReady=false constructionAllowed=false constructionKind=productionClosed offscreenHarnessAllowed=false noWindowAttached=false routeActivationAllowed=false rootConstructed(route=true,surface=false,controller=false) coordinatorApplyAllowed=false forbiddenDataSourceApplyOutsideCoordinatorCalled=false blockedIssues=[readiness.renderedRouteLegacy,readiness.collectionViewRouteNotConstructed,readiness.sideEffectSentinelClean,readiness.artifactReleaseBlockerFlagsEmpty,offscreen.readinessBlocked,offscreen.unsupportedConstructionKind,offscreen.constructionPlanClosed] releaseBlockers=[requiresNetworkWork] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=true,dbWrite=false,readMarker=false,dataSourceApply=false,forbiddenDataSourceApply=false,requiresNetworkWork=false,requiresDBWrite=false) diagnostics(route={\(expectedBlockedArtifactSummary)},construction={\(expectedBlockedArtifactSummary)},offscreen={\(expectedBlockedArtifactSummary)})"
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

    private func cleanChain() -> TimelineHomeConstructionArtifactChain {
        let snapshot = makeSnapshot()
        let readiness = makeReadiness(
            rootDecisionSnapshot: snapshot,
            preferredConstructionKind: .offscreenOnly
        ).evaluate()
        return TimelineHomeConstructionArtifactChain(
            routeDecisionSnapshot: snapshot,
            constructionReadinessResult: readiness,
            offscreenHarnessResult: allowedHarnessResult(artifactSummary: snapshot.artifactSummary)
        )
    }

    private func blockedReadinessChain() -> TimelineHomeConstructionArtifactChain {
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

    private func blockedOffscreenHarnessChain() -> TimelineHomeConstructionArtifactChain {
        let snapshot = makeSnapshot()
        let readiness = makeReadiness(
            rootDecisionSnapshot: snapshot,
            preferredConstructionKind: .offscreenOnly
        ).evaluate()
        return TimelineHomeConstructionArtifactChain(
            routeDecisionSnapshot: snapshot,
            constructionReadinessResult: readiness,
            offscreenHarnessResult: forbiddenDirectApplyHarnessResult(artifactSummary: snapshot.artifactSummary)
        )
    }

    private func makeSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: 1_735_000_005_100
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: 1_735_000_005_200
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
        artifactSummary: TimelineHomeRootRouteArtifactSnapshot
    ) -> TimelineHomeOffscreenConstructionHarnessResult {
        TimelineHomeOffscreenConstructionHarnessResult(
            offscreenConstructionAllowed: true,
            rejectionReasons: [],
            constructionKind: .offscreenOnly,
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
        var result = allowedHarnessResult(artifactSummary: artifactSummary)
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.readinessBlocked, .unsupportedConstructionKind, .constructionPlanClosed]
        result.constructionKind = .productionClosed
        result.controllerLoadedOffscreen = false
        result.controllerItemIDs = []
        result.coordinatorOwnedDataSourceApplyAllowed = false
        return result
    }

    private func forbiddenDirectApplyHarnessResult(
        artifactSummary: TimelineHomeRootRouteArtifactSnapshot
    ) -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = allowedHarnessResult(artifactSummary: artifactSummary)
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.sideEffectFlagsDirty, .constructionPlanClosed]
        result.coordinatorOwnedDataSourceApplyAllowed = false
        result.forbiddenDataSourceApplyOutsideCoordinatorCalled = true
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

    private func makeConsumer(
        for chain: TimelineHomeConstructionArtifactChain
    ) throws -> TimelineHomeConstructionArtifactChainConsumer {
        try TimelineHomeConstructionArtifactChainConsumer.decodeFixtureJSON(
            encodedData(chain)
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
