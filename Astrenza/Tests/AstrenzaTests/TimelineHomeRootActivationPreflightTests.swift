import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome Root activation preflight")
struct TimelineHomeRootActivationPreflightTests {
    @Test
    func preflight_requires_explicit_flag() {
        let result = preflight(arguments: ["Astrenza"])

        #expect(result.activationPreflightEvaluated)
        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.explicitCollectionViewLaunchFlag))
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_requires_clean_activation_artifact_chain() {
        let result = preflight(chain: dirtyActivationArtifactPairChain())

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.activationArtifactChainClean))
        #expect(result.activationPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_requires_activation_readiness_clean() {
        let result = preflight(chain: dirtyActivationReadinessChain())

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.activationReadinessClean))
        #expect(result.activationPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_default_legacy_remains_legacy() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=legacy"])

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.renderedRoute == .legacy)
        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
    }

    @Test
    func preflight_does_not_activate_collectionView() {
        let result = preflight()

        #expect(result.activationWouldBeAllowed)
        #expect(result.activationPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_does_not_render_switch() {
        let result = preflight()

        #expect(result.activationWouldBeAllowed)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_does_not_modify_Root_body() throws {
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")

        #expect(rootSource.contains("HomeTimelineView"))
        #expect(rootSource.contains("NostrHomeTimelineStore"))
        #expect(!rootSource.contains("TimelineHomeRootActivationPreflight.evaluate"))
        #expect(!rootSource.contains("TimelineHomeRootCollectionViewActivationPreflight.evaluate"))
        #expect(!rootSource.contains("renderedRoute == .collectionView"))
        #expect(!rootSource.contains("Timeline" + "CollectionViewController("))
        #expect(rootSource.contains("TimelineHomeRootBodyRenderSwitch.decide"))
        #expect(rootSource.contains("Timeline" + "Surface("))
    }

    @Test
    func preflight_does_not_start_network() throws {
        let result = preflight(startupNetworkMarkerObserved: true)
        let source = try sourceFile(named: "TimelineHomeRootActivationPreflight.swift")

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.startupNetworkMarkerClean))
        #expect(result.activationPerformed == false)
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func preflight_does_not_write_db() {
        let result = preflight(chain: dirtyActivationSideEffectChain { activation in
            activation.dbWriteAttempted = true
            activation.requiresDBWrite = true
        })

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.dbWriteNotAttempted))
        #expect(result.issues.contains(.requiresDBWriteFalse))
        #expect(result.activationPerformed == false)
    }

    @Test
    func preflight_does_not_advance_read_marker() {
        let result = preflight(chain: dirtyActivationSideEffectChain { activation in
            activation.readMarkerChanged = true
            activation.readMarkerAdvanced = true
        })

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.readMarkerUnchanged))
        #expect(result.activationPerformed == false)
    }

    @Test
    func preflight_does_not_call_dataSourceApply_from_Root() {
        let result = preflight(chain: dirtyActivationSideEffectChain { activation in
            activation.dataSourceApplyFromRootCalled = true
        })

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.dataSourceApplyCoordinatorOnly))
        #expect(result.activationPerformed == false)
    }

    @Test
    func preflight_does_not_construct_extra_NostrHomeTimelineStore() {
        let result = preflight(chain: dirtyActivationSideEffectChain { activation in
            activation.noExtraNostrHomeTimelineStore = false
        })

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.noExtraNostrHomeTimelineStore))
        #expect(result.activationPerformed == false)
    }

    @Test
    func preflight_requires_timeline_area_restore_gate() {
        let result = preflight(timelineAreaRestoreGateObserved: false)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.timelineAreaRestoreGateMarker))
        #expect(result.activationPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_requires_root_shell_first_paint() {
        let result = preflight(rootShellFirstPaintObserved: false)

        #expect(result.activationWouldBeAllowed == false)
        #expect(result.issues.contains(.rootShellFirstPaintMarker))
        #expect(result.activationPerformed == false)
        #expect(result.renderedRoute == .legacy)
    }

    @Test
    func preflight_rollback_and_manualFallback_are_legacy() {
        let result = preflight()

        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(result.activationPerformed == false)
    }

    @Test
    func preflight_result_is_codable_privacy_safe() throws {
        let result = preflight()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(TimelineHomeRootActivationPreflightResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeRootActivationPreflightInput.self)
        assertSendable(TimelineHomeRootActivationPreflightIssue.self)
        assertSendable(TimelineHomeRootActivationPreflightResult.self)
        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)
        #expect(result.activationPreflightEvaluated)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.renderedRoute == .legacy)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootActivationPreflightTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeActivationArtifactChainConsumerTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteActivationTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }
}

private func preflight(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    chain: TimelineHomeActivationArtifactChain = cleanActivationChain(),
    rootShellFirstPaintObserved: Bool = true,
    timelineAreaRestoreGateObserved: Bool = true,
    startupNetworkMarkerObserved: Bool = false
) -> TimelineHomeRootActivationPreflightResult {
    TimelineHomeRootCollectionViewActivationPreflight.evaluate(
        TimelineHomeRootActivationPreflightInput(
            launchArguments: arguments,
            activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer(chain: chain),
            rootShellFirstPaintObserved: rootShellFirstPaintObserved,
            timelineAreaRestoreGateObserved: timelineAreaRestoreGateObserved,
            startupNetworkMarkerObserved: startupNetworkMarkerObserved
        )
    )
}

private func cleanActivationChain() -> TimelineHomeActivationArtifactChain {
    let chain = cleanConstructionChain()
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: chain,
        activationReadinessResult: evaluateActivation(chain: chain)
    )
}

private func dirtyActivationArtifactPairChain() -> TimelineHomeActivationArtifactChain {
    var chain = cleanActivationChain()
    chain.activationReadinessResult.artifactSummary.chainIssueKinds = ["stale"]
    chain.activationReadinessResult.artifactSummary.deterministicSummary = "stale"
    return chain
}

private func dirtyActivationReadinessChain() -> TimelineHomeActivationArtifactChain {
    let chain = cleanConstructionChain()
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: chain,
        activationReadinessResult: evaluateActivation(
            arguments: ["Astrenza"],
            chain: chain,
            constructionResult: construct(arguments: ["Astrenza"], chain: chain)
        )
    )
}

private func dirtyActivationSideEffectChain(
    _ mutate: (inout TimelineHomeCollectionViewRouteActivationResult) -> Void
) -> TimelineHomeActivationArtifactChain {
    let chain = cleanConstructionChain()
    var activation = evaluateActivation(chain: chain)
    mutate(&activation)
    return TimelineHomeActivationArtifactChain(
        constructionArtifactChain: chain,
        activationReadinessResult: activation
    )
}

private func evaluateActivation(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    chain: TimelineHomeConstructionArtifactChain,
    constructionResult: TimelineHomeCollectionViewRouteConstructionResult? = nil
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
        requiresDBWrite: false,
        dataSourceApplyCoordinatorOnly: true,
        noExtraNostrHomeTimelineStore: true,
        rootBodyDecisionSnapshotPermitsActivationScope: true,
        createdAtMS: 1_735_000_008_000
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
            createdAtMS: 1_735_000_007_900
        )
    )
}

private func cleanConstructionChain(
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

private func makeSnapshot(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"]
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        dependencies: .allAvailable,
        createdAtMS: 1_735_000_007_800
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_007_800
    )
}

private func harnessResult(
    allowed: Bool,
    constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
    artifactSummary: TimelineHomeRootRouteArtifactSnapshot
) -> TimelineHomeOffscreenConstructionHarnessResult {
    TimelineHomeOffscreenConstructionHarnessResult(
        offscreenConstructionAllowed: allowed,
        rejectionReasons: [],
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
        coordinatorOwnedDataSourceApplyAllowed: true,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
        controllerItemIDs: allowed ? ["note:visible"] : [],
        diagnosticsArtifactSummary: artifactSummary
    )
}

private var selectedSwiftTestingSuites: [String] {
    [
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

private var requiredResultKeys: Set<String> {
    [
        "activationArtifactChainSummary",
        "activationPerformed",
        "activationPreflightEvaluated",
        "activationWouldBeAllowed",
        "issues",
        "manualFallbackRoute",
        "productionRenderSwitchPerformed",
        "renderedRoute",
        "rollbackRoute"
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
        "relay " + "connection " + "attempts",
        "Process" + "Info"
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
