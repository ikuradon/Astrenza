import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route behind flag construction")
struct TimelineHomeCollectionViewRouteBehindFlagConstructionTests {
    @Test
    func collectionView_route_requires_explicit_flag() {
        let result = construct(arguments: ["Astrenza"])

        #expect(result.requestedRoute == .legacy)
        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.issueKinds.contains(.missingExplicitCollectionViewFlag))
        #expect(result.artifactSummary.rejectionIssueKinds.contains(.missingExplicitCollectionViewFlag))
    }

    @Test
    func collectionView_route_requires_all_readiness_gates() {
        let result = construct(chain: readinessDirtyChain())

        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.issueKinds.contains(.readinessDirty))
        #expect(result.artifactSummary.chainIssueKinds.contains("readiness.dependencyReadiness"))
    }

    @Test
    func default_legacy_route_does_not_construct_collectionView() {
        let result = construct(arguments: ["Astrenza", "--timeline-engine=legacy"])

        #expect(result.requestedRoute == .legacy)
        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.renderedRouteAfterConstruction == .legacy)
        #expect(result.legacyHomeRenderingPreserved)
    }

    @Test
    func debug_override_collectionView_does_not_bypass_flag() {
        let result = construct(
            arguments: ["Astrenza"],
            debugOverride: .collectionView
        )

        #expect(result.requestedRoute == .collectionView)
        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.issueKinds.contains(.missingExplicitCollectionViewFlag))
    }

    @Test
    func debug_override_legacy_keeps_collectionView_construction_closed() {
        let result = construct(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            debugOverride: .legacy
        )

        #expect(result.requestedRoute == .legacy)
        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.renderedRouteAfterConstruction == .legacy)
        #expect(result.issueKinds.contains(.requestedRouteNotCollectionView))
    }

    @Test
    func flagged_collectionView_route_constructs_only_non_rendered_or_offscreen_path() throws {
        let result = construct()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteConstruction.swift")

        #expect(result.requestedRoute == .collectionView)
        #expect(result.constructionAttempted)
        #expect(result.constructionAllowed)
        #expect(result.constructionKind == .offscreenOnly)
        #expect(result.collectionViewRouteConstructed)
        #expect(result.collectionViewRouteConstructedFromRoot == false)
        #expect(result.timelineSurfaceConstructed == false)
        #expect(result.timelineSurfaceConstructedFromRoot == false)
        #expect(result.timelineCollectionViewControllerConstructedFromRoot == false)
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("Timeline" + "Surface("))
        #expect(!source.contains("loadViewIfNeeded"))
        #expect(!source.contains("AstrenzaRootView("))
    }

    @Test
    func flagged_collectionView_route_keeps_renderedRoute_legacy() {
        let result = construct()

        #expect(result.renderedRouteAfterConstruction == .legacy)
        #expect(result.rootHomeRenderingChanged == false)
        #expect(result.legacyHomeRenderingPreserved)
    }

    @Test
    func flagged_collectionView_route_keeps_activation_false() {
        let result = construct()

        #expect(result.routeActivationAllowed == false)
        #expect(result.artifactSummary.routeActivationAllowed == false)
    }

    @Test
    func flagged_collectionView_route_records_artifact_chain() {
        let result = construct()

        #expect(result.artifactSummary.routeDecisionSummary.contains("route=collectionView"))
        #expect(result.artifactSummary.constructionReadinessSummary.contains("collectionViewAllowed=true"))
        #expect(result.artifactSummary.offscreenHarnessSummary.contains("collectionViewAllowed=true"))
        #expect(result.artifactSummary.rejectionIssueKinds.isEmpty)
        #expect(result.artifactSummary.chainIssueKinds.isEmpty)
    }

    @Test
    func flagged_collectionView_route_does_not_start_network() {
        let result = construct()

        #expect(result.networkStarted == false)
        #expect(result.artifactSummary.sideEffectSummary.contains("network=false"))
    }

    @Test
    func flagged_collectionView_route_does_not_write_db() {
        let result = construct()

        #expect(result.dbWriteAttempted == false)
        #expect(result.artifactSummary.sideEffectSummary.contains("dbWrite=false"))
    }

    @Test
    func flagged_collectionView_route_does_not_advance_read_marker() {
        let result = construct()

        #expect(result.readMarkerAdvanced == false)
        #expect(result.artifactSummary.sideEffectSummary.contains("readMarker=false"))
    }

    @Test
    func flagged_collectionView_route_does_not_call_dataSourceApply_from_Root() {
        let result = construct()

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(result.artifactSummary.sideEffectSummary.contains("dataSourceApply=false"))
        #expect(result.artifactSummary.sideEffectSummary.contains("forbiddenDataSourceApply=false"))
    }

    @Test
    func flagged_collectionView_route_does_not_construct_extra_NostrHomeTimelineStore() throws {
        let result = construct()
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteConstruction.swift")

        #expect(result.noExtraNostrHomeTimelineStore)
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func startup_network_grep_no_matches() throws {
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteConstruction.swift")
        let forbidden = [
            "LocalDataTask",
            "ATS failure",
            "nw_",
            "WebSocket",
            "wss://",
            "setDefaultRelays",
            "URLSession"
        ]

        for token in forbidden {
            #expect(!source.contains(token))
        }
    }

    @Test
    func construction_source_has_no_resolver_db_or_root_apply_paths() throws {
        let source = try sourceFile(named: "TimelineHomeCollectionViewRouteConstruction.swift")
        let forbidden = [
            "ResolveCoordinator",
            "dataSource.apply",
            "feed_read_state",
            "pending_new",
            "readMarkerAdvanced = true",
            "dbWriteAttempted = true",
            "networkStarted = true",
            "FileManager",
            "write(to:",
            "upload",
            "telemetry"
        ]

        for token in forbidden {
            #expect(!source.contains(token))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteBehindFlagConstructionTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }

    @Test
    func blocked_when_artifact_chain_dirty() {
        let result = construct(chain: dirtyArtifactChain())

        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.issueKinds.contains(.artifactChainDirty))
        #expect(result.artifactSummary.chainIssueKinds.contains("artifact.sideEffectsDirty"))
    }

    @Test
    func blocked_when_artifact_chain_has_non_artifact_prefixed_dirty_issue() {
        let result = construct(chain: nonArtifactDirtyChain())

        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.issueKinds.contains(.artifactChainDirty))
        #expect(result.artifactSummary.chainIssueKinds.contains("offscreen.sideEffectFlagsDirty"))
    }

    @Test
    func blocked_when_readiness_dirty() {
        let result = construct(chain: readinessDirtyChain())

        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.issueKinds.contains(.readinessDirty))
        #expect(result.renderedRouteAfterConstruction == .legacy)
    }

    @Test
    func blocked_when_offscreen_harness_rejects() {
        let result = construct(chain: offscreenRejectedChain())

        #expect(result.constructionAttempted == false)
        #expect(result.constructionAllowed == false)
        #expect(result.issueKinds.contains(.offscreenHarnessRejected))
        #expect(result.artifactSummary.chainIssueKinds.contains("offscreen.sideEffectFlagsDirty"))
    }

    @Test
    func constructed_result_decodes_and_is_privacy_safe() throws {
        let result = construct()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(
            TimelineHomeCollectionViewRouteConstructionResult.self,
            from: data
        )
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }
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
            createdAtMS: 1_735_000_005_000
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

private func dirtyArtifactChain() -> TimelineHomeConstructionArtifactChain {
    var chain = cleanChain()
    chain.routeDecisionSnapshot.sideEffectSentinel.networkStarted = true
    return chain
}

private func offscreenRejectedChain() -> TimelineHomeConstructionArtifactChain {
    var chain = cleanChain()
    chain.offscreenHarnessResult = harnessResult(
        allowed: false,
        rejectionReasons: [.sideEffectFlagsDirty],
        constructionKind: .offscreenOnly,
        coordinatorOwnedDataSourceApplyAllowed: false,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: true,
        artifactSummary: chain.routeDecisionSnapshot.artifactSummary
    )
    return chain
}

private func nonArtifactDirtyChain() -> TimelineHomeConstructionArtifactChain {
    var chain = cleanChain()
    chain.offscreenHarnessResult.rejectionReasons = [.sideEffectFlagsDirty]
    chain.offscreenHarnessResult.offscreenConstructionAllowed = true
    chain.offscreenHarnessResult.controllerLoadedOffscreen = true
    chain.offscreenHarnessResult.isAttachedToWindow = false
    return chain
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
        createdAtMS: 1_735_000_005_000
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_005_000
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
        "artifactSummary",
        "collectionViewRouteConstructed",
        "collectionViewRouteConstructedFromRoot",
        "constructionAllowed",
        "constructionAttempted",
        "constructionKind",
        "coordinatorOwnedDataSourceApplyAllowed",
        "createdAtMS",
        "dataSourceApplyFromRootCalled",
        "dbWriteAttempted",
        "issueKinds",
        "legacyHomeRenderingPreserved",
        "networkStarted",
        "noExtraNostrHomeTimelineStore",
        "readMarkerAdvanced",
        "renderedRouteAfterConstruction",
        "requestedRoute",
        "rootHomeRenderingChanged",
        "routeActivationAllowed",
        "timelineCollectionViewControllerConstructedFromRoot",
        "timelineSurfaceConstructed",
        "timelineSurfaceConstructedFromRoot"
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
    let candidate = appRoot.appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)")
    return try String(contentsOf: candidate, encoding: .utf8)
}
