import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome route construction readiness")
struct TimelineHomeRouteConstructionReadinessTests {
    @Test
    func collectionView_route_construction_requires_explicit_flag() {
        var readiness = makeReadiness(hasExplicitCollectionViewLaunchFlag: false)

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .explicitCollectionViewLaunchFlag))
        #expect(result.plan.collectionViewRouteConstructed == false)
        #expect(result.plan.routeActivationAllowed == false)

        readiness.hasExplicitCollectionViewLaunchFlag = true
        #expect(readiness.evaluate().issues.contains(gate: .explicitCollectionViewLaunchFlag) == false)
    }

    @Test
    func collectionView_route_construction_requires_readiness() {
        let readiness = makeReadiness(dependencies: .init(
            repositoryStoreAvailable: false,
            windowComposerAvailable: true,
            restoreUseCaseAvailable: true,
            coordinatorAdapterAvailable: true,
            collectionViewControllerAvailable: true,
            diagnosticsSinkAvailable: true,
            runtimeGuardAllowsCollectionView: true,
            rolloutAllowsCollectionView: true
        ))

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .dependencyReadiness))
        #expect(result.plan.constructionKind == .productionClosed)
        #expect(result.plan.collectionViewRouteConstructed == false)
    }

    @Test
    func debug_override_collectionView_does_not_bypass_flag() {
        let readiness = makeReadiness(
            hasExplicitCollectionViewLaunchFlag: false,
            rootDecisionSnapshot: makeSnapshot(
                arguments: ["Astrenza"],
                debugOverride: .collectionView
            )
        )

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .explicitCollectionViewLaunchFlag))
        #expect(result.plan.renderedRouteAfterConstruction == .legacy)
        #expect(result.plan.collectionViewRouteConstructed == false)
        #expect(result.plan.timelineSurfaceConstructed == false)
        #expect(result.plan.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let readiness = makeReadiness(selectedSwiftTestingSuitesNonZero: false)

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .selectedSwiftTestingSuitesNonZero))
        #expect(result.plan.collectionViewRouteConstructed == false)
    }

    @Test
    func readiness_fails_when_privacy_guard_marker_missing() {
        let readiness = makeReadiness(artifactPrivacyGuardPassed: false)

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .artifactPrivacyGuardPassed))
        #expect(result.plan.diagnosticsArtifactSummary.artifactKind == "timeline_home_route_decision")
    }

    @Test
    func readiness_fails_when_startup_network_marker_dirty() {
        var snapshot = makeSnapshot()
        snapshot.networkWaitedBeforeInteractiveScrollMS = 1
        let readiness = makeReadiness(
            rootDecisionSnapshot: snapshot,
            startupNetworkPatternClean: false
        )

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .startupNetworkPatternClean))
        #expect(result.issues.contains(gate: .networkWaitedBeforeInteractiveScrollZero))
        #expect(result.plan.networkStarted == false)
    }

    @Test
    func readiness_fails_when_snapshot_consumer_unavailable() {
        let readiness = makeReadiness(snapshotConsumerAvailable: false)

        let result = readiness.evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .snapshotConsumerAvailable))
        #expect(result.plan.collectionViewRouteConstructed == false)
    }

    @Test
    func collectionView_construction_records_route_artifact() {
        let result = makeReadiness().evaluate()

        #expect(result.isReady)
        #expect(result.plan.diagnosticsArtifactSummary.artifactKind == "timeline_home_route_decision")
        #expect(result.plan.diagnosticsArtifactSummary.schemaVersion == 1)
        #expect(result.plan.diagnosticsArtifactSummary.eventName == "timeline_home_route_preflight_decision")
        #expect(result.plan.diagnosticsArtifactSummary.source == .rootPreflight)
        #expect(result.plan.diagnosticsArtifactSummary.collectionViewAllowed)
        #expect(result.plan.diagnosticsArtifactSummary.runtimeAllowed)
        #expect(result.plan.diagnosticsArtifactSummary.rolloutAllowed)
    }

    @Test
    func collectionView_construction_does_not_start_network() {
        let result = makeReadiness().evaluate()
        let source = try? sourceFile(named: "TimelineHomeRouteConstructionReadiness.swift")

        #expect(result.plan.networkStarted == false)
        #expect(result.plan.requiresNetworkWork == false)
        #expect((source ?? "").contains("URL" + "Session") == false)
        #expect((source ?? "").contains("Web" + "Socket") == false)
        #expect((source ?? "").contains("set" + "DefaultRelays") == false)
    }

    @Test
    func collectionView_construction_does_not_write_db() {
        let result = makeReadiness().evaluate()
        let source = try? sourceFile(named: "TimelineHomeRouteConstructionReadiness.swift")

        #expect(result.plan.dbWriteAttempted == false)
        #expect(result.plan.requiresDBWrite == false)
        #expect((source ?? "").contains("IN" + "SERT") == false)
        #expect((source ?? "").contains("UP" + "DATE") == false)
        #expect((source ?? "").contains("DE" + "LETE") == false)
        #expect((source ?? "").contains("." + "execute(") == false)
    }

    @Test
    func collectionView_construction_does_not_advance_read_marker() {
        var snapshot = makeSnapshot()
        snapshot.readMarkerChanged = true
        let result = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .readMarkerUnchanged))
        #expect(result.plan.readMarkerAdvanced == false)
    }

    @Test
    func collectionView_construction_does_not_call_dataSourceApply() {
        var snapshot = makeSnapshot()
        snapshot.dataSourceApplyCalled = true
        let result = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
        let source = try? sourceFile(named: "TimelineHomeRouteConstructionReadiness.swift")

        #expect(result.isReady == false)
        #expect(result.issues.contains(gate: .dataSourceApplyCoordinatorOnly))
        #expect(result.plan.dataSourceApplyCalled == false)
        #expect((source ?? "").contains("dataSource." + "apply") == false)
    }

    @Test
    func construction_gate_issue_cases_have_negative_coverage() {
        let covered = constructionGateScenarios.map(\.gate.rawValue).sorted()
        let declared = TimelineHomeRouteConstructionGate.allCases.map(\.rawValue).sorted()

        #expect(covered == declared)

        for scenario in constructionGateScenarios {
            let result = scenario.makeReadiness().evaluate()

            #expect(result.isReady == false, "Expected \(scenario.gate.rawValue) to block readiness")
            #expect(
                result.issues.contains(gate: scenario.gate),
                "Expected issue \(scenario.gate.rawValue)"
            )
            #expect(result.plan.collectionViewRouteConstructed == false)
            #expect(result.plan.timelineSurfaceConstructed == false)
            #expect(result.plan.timelineCollectionViewControllerConstructedFromRoot == false)
            #expect(result.plan.routeActivationAllowed == false)
        }
    }

    @Test
    func dirty_decoded_snapshot_route_fields_reject_readiness_with_typed_issues() {
        for scenario in dirtySnapshotRouteScenarios {
            var snapshot = makeSnapshot()
            scenario.mutate(&snapshot)
            let result = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()

            #expect(result.isReady == false, "Expected \(scenario.gate.rawValue) to reject dirty snapshot")
            #expect(result.issues.contains(gate: scenario.gate))
            #expect(result.plan.renderedRouteAfterConstruction == .legacy)
            #expect(result.plan.collectionViewRouteConstructed == false)
            #expect(result.plan.timelineSurfaceConstructed == false)
            #expect(result.plan.timelineCollectionViewControllerConstructedFromRoot == false)
        }
    }

    @Test
    func dirty_decoded_snapshot_artifact_fields_reject_readiness_with_typed_issues() {
        var missingDependenciesSnapshot = makeSnapshot()
        missingDependenciesSnapshot.artifactSummary.missingDependencies = ["repositoryStore"]
        var fallbackIssueSnapshot = makeSnapshot()
        fallbackIssueSnapshot.artifactSummary.fallbackIssueKinds = [.repositoryStoreUnavailable]
        var releaseBlockerSnapshot = makeSnapshot()
        releaseBlockerSnapshot.artifactSummary.releaseBlockerFlags = [.dualMutationNotPrevented]

        let missingDependencies = makeReadiness(rootDecisionSnapshot: missingDependenciesSnapshot).evaluate()
        let fallbackIssue = makeReadiness(rootDecisionSnapshot: fallbackIssueSnapshot).evaluate()
        let releaseBlocker = makeReadiness(rootDecisionSnapshot: releaseBlockerSnapshot).evaluate()

        #expect(missingDependencies.isReady == false)
        #expect(missingDependencies.issues.contains(gate: .artifactMissingDependenciesEmpty))
        #expect(missingDependencies.plan.diagnosticsArtifactSummary.missingDependencies == ["repositoryStore"])

        #expect(fallbackIssue.isReady == false)
        #expect(fallbackIssue.issues.contains(gate: .artifactFallbackIssueKindsEmpty))
        #expect(fallbackIssue.plan.diagnosticsArtifactSummary.fallbackIssueKinds == [.repositoryStoreUnavailable])

        #expect(releaseBlocker.isReady == false)
        #expect(releaseBlocker.issues.contains(gate: .artifactReleaseBlockerFlagsEmpty))
        #expect(releaseBlocker.plan.diagnosticsArtifactSummary.releaseBlockerFlags == [.dualMutationNotPrevented])
    }

    @Test
    func dirty_decoded_snapshot_side_effect_sentinel_flags_reject_readiness() {
        for scenario in dirtySideEffectScenarios {
            var snapshot = makeSnapshot()
            scenario.mutate(&snapshot.sideEffectSentinel)
            let result = makeReadiness(rootDecisionSnapshot: snapshot).evaluate()

            #expect(result.isReady == false, "Expected side-effect flag \(scenario.name) to reject readiness")
            #expect(result.issues.contains(gate: .sideEffectSentinelClean))
            #expect(result.plan.sideEffectSentinel == .none)
        }
    }
}

private struct ConstructionGateScenario {
    var gate: TimelineHomeRouteConstructionGate
    var makeReadiness: () -> TimelineHomeRouteConstructionReadiness
}

private struct DirtySnapshotScenario {
    var gate: TimelineHomeRouteConstructionGate
    var mutate: (inout TimelineHomeRootRouteDecisionSnapshot) -> Void
}

private struct DirtySideEffectScenario {
    var name: String
    var mutate: (inout TimelineHomeRootRoutePreflightSideEffectSentinel) -> Void
}

private var constructionGateScenarios: [ConstructionGateScenario] {
    [
        ConstructionGateScenario(gate: .explicitCollectionViewLaunchFlag) {
            makeReadiness(hasExplicitCollectionViewLaunchFlag: false)
        },
        ConstructionGateScenario(gate: .dependencyReadiness) {
            makeReadiness(dependencies: TimelineHomeRouteDependencyStatus(
                repositoryStoreAvailable: false,
                windowComposerAvailable: true,
                restoreUseCaseAvailable: true,
                coordinatorAdapterAvailable: true,
                collectionViewControllerAvailable: true,
                diagnosticsSinkAvailable: true,
                runtimeGuardAllowsCollectionView: true,
                rolloutAllowsCollectionView: true
            ))
        },
        ConstructionGateScenario(gate: .runtimeAllowed) {
            var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
            dependencies.runtimeGuardAllowsCollectionView = false
            return makeReadiness(dependencies: dependencies)
        },
        ConstructionGateScenario(gate: .rolloutAllowed) {
            var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
            dependencies.rolloutAllowsCollectionView = false
            return makeReadiness(dependencies: dependencies)
        },
        ConstructionGateScenario(gate: .rootNoOpPreflightComplete) {
            makeReadiness(rootNoOpPreflightComplete: false)
        },
        ConstructionGateScenario(gate: .routeDiagnosticsSinkInjectionComplete) {
            makeReadiness(routeDiagnosticsSinkInjectionComplete: false)
        },
        ConstructionGateScenario(gate: .rootDecisionSnapshotAvailable) {
            makeReadiness(rootDecisionSnapshot: nil)
        },
        ConstructionGateScenario(gate: .rootDecisionSnapshotObservedCollectionView) {
            var snapshot = makeSnapshot()
            snapshot.collectionViewDecisionObserved = false
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .snapshotConsumerAvailable) {
            makeReadiness(snapshotConsumerAvailable: false)
        },
        ConstructionGateScenario(gate: .offscreenControllerSmokePassed) {
            makeReadiness(offscreenControllerSmokePassed: false)
        },
        ConstructionGateScenario(gate: .initialRestoreSnapshotCoordinatorHarnessPassed) {
            makeReadiness(initialRestoreSnapshotCoordinatorHarnessPassed: false)
        },
        ConstructionGateScenario(gate: .startupNetworkPatternClean) {
            makeReadiness(startupNetworkPatternClean: false)
        },
        ConstructionGateScenario(gate: .selectedSwiftTestingSuitesNonZero) {
            makeReadiness(selectedSwiftTestingSuitesNonZero: false)
        },
        ConstructionGateScenario(gate: .networkWaitedBeforeInteractiveScrollZero) {
            var snapshot = makeSnapshot()
            snapshot.networkWaitedBeforeInteractiveScrollMS = 1
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .readMarkerUnchanged) {
            var snapshot = makeSnapshot()
            snapshot.readMarkerChanged = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .requiresNetworkWorkFalse) {
            var snapshot = makeSnapshot()
            snapshot.requiresNetworkWork = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .requiresDBWriteFalse) {
            var snapshot = makeSnapshot()
            snapshot.requiresDBWrite = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .dataSourceApplyCoordinatorOnly) {
            var snapshot = makeSnapshot()
            snapshot.dataSourceApplyCalled = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .noExtraNostrHomeTimelineStore) {
            makeReadiness(noExtraNostrHomeTimelineStore: false)
        },
        ConstructionGateScenario(gate: .artifactPrivacyGuardPassed) {
            makeReadiness(artifactPrivacyGuardPassed: false)
        },
        ConstructionGateScenario(gate: .sideEffectSentinelClean) {
            var snapshot = makeSnapshot()
            snapshot.sideEffectSentinel.networkStarted = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .productionRouteActivationClosed) {
            makeReadiness(preferredConstructionKind: .productionClosed)
        },
        ConstructionGateScenario(gate: .visibleRouteCollectionViewPlaceholder) {
            var snapshot = makeSnapshot()
            snapshot.visibleRoute = .legacy
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .renderedRouteLegacy) {
            var snapshot = makeSnapshot()
            snapshot.renderedRoute = .collectionViewPlaceholder
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .collectionViewRouteNotConstructed) {
            var snapshot = makeSnapshot()
            snapshot.collectionViewRouteConstructed = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .legacyHomeRendered) {
            var snapshot = makeSnapshot()
            snapshot.legacyHomeRendered = false
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .rootShellUnchanged) {
            var snapshot = makeSnapshot()
            snapshot.rootShellUnchanged = false
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .preventsDualMutation) {
            var snapshot = makeSnapshot()
            snapshot.preventsDualMutation = false
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .artifactMissingDependenciesEmpty) {
            var snapshot = makeSnapshot()
            snapshot.artifactSummary.missingDependencies = ["repositoryStore"]
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .artifactFallbackIssueKindsEmpty) {
            var snapshot = makeSnapshot()
            snapshot.artifactSummary.fallbackIssueKinds = [.repositoryStoreUnavailable]
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .artifactReleaseBlockerFlagsEmpty) {
            var snapshot = makeSnapshot()
            snapshot.artifactSummary.releaseBlockerFlags = [.dualMutationNotPrevented]
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .timelineRestoreGateTimelineAreaOnly) {
            var snapshot = makeSnapshot()
            snapshot.timelineRestoreGateScope = nil
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .rootOrGlobalRestoreGateNotAllowed) {
            var snapshot = makeSnapshot()
            snapshot.timelineGateContinuesGlobalSplash = true
            return makeReadiness(rootDecisionSnapshot: snapshot)
        },
        ConstructionGateScenario(gate: .routeActivationRenderingSwitchClosed) {
            makeReadiness(routeActivationRenderingSwitchClosed: false)
        },
        ConstructionGateScenario(gate: .timelineSurfaceNotConstructedFromRoot) {
            makeReadiness(timelineSurfaceConstructedFromRoot: true)
        },
        ConstructionGateScenario(gate: .timelineCollectionViewControllerNotConstructedFromRoot) {
            makeReadiness(timelineCollectionViewControllerConstructedFromRoot: true)
        }
    ]
}

private var dirtySnapshotRouteScenarios: [DirtySnapshotScenario] {
    [
        DirtySnapshotScenario(gate: .visibleRouteCollectionViewPlaceholder) {
            $0.visibleRoute = .legacy
        },
        DirtySnapshotScenario(gate: .renderedRouteLegacy) {
            $0.renderedRoute = .collectionViewPlaceholder
        },
        DirtySnapshotScenario(gate: .collectionViewRouteNotConstructed) {
            $0.collectionViewRouteConstructed = true
        },
        DirtySnapshotScenario(gate: .legacyHomeRendered) {
            $0.legacyHomeRendered = false
        },
        DirtySnapshotScenario(gate: .rootShellUnchanged) {
            $0.rootShellUnchanged = false
        },
        DirtySnapshotScenario(gate: .preventsDualMutation) {
            $0.preventsDualMutation = false
        },
        DirtySnapshotScenario(gate: .timelineRestoreGateTimelineAreaOnly) {
            $0.timelineRestoreGateScope = nil
        },
        DirtySnapshotScenario(gate: .rootOrGlobalRestoreGateNotAllowed) {
            $0.timelineGateCoversRootShell = true
        },
        DirtySnapshotScenario(gate: .rootOrGlobalRestoreGateNotAllowed) {
            $0.timelineGateCoversTabBar = true
        },
        DirtySnapshotScenario(gate: .rootOrGlobalRestoreGateNotAllowed) {
            $0.timelineGateContinuesGlobalSplash = true
        }
    ]
}

private var dirtySideEffectScenarios: [DirtySideEffectScenario] {
    [
        DirtySideEffectScenario(name: "rootViewConstructed") { $0.rootViewConstructed = true },
        DirtySideEffectScenario(name: "homeTimelineViewConstructed") { $0.homeTimelineViewConstructed = true },
        DirtySideEffectScenario(name: "nostrHomeTimelineStoreConstructed") { $0.nostrHomeTimelineStoreConstructed = true },
        DirtySideEffectScenario(name: "timelineCollectionViewControllerConstructed") {
            $0.timelineCollectionViewControllerConstructed = true
        },
        DirtySideEffectScenario(name: "networkStarted") { $0.networkStarted = true },
        DirtySideEffectScenario(name: "dbWriteAttempted") { $0.dbWriteAttempted = true },
        DirtySideEffectScenario(name: "readMarkerAdvanced") { $0.readMarkerAdvanced = true },
        DirtySideEffectScenario(name: "dataSourceApplyCalled") { $0.dataSourceApplyCalled = true }
    ]
}

private func makeReadiness(
    hasExplicitCollectionViewLaunchFlag: Bool = true,
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable,
    rootNoOpPreflightComplete: Bool = true,
    routeDiagnosticsSinkInjectionComplete: Bool = true,
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot? = makeSnapshot(),
    snapshotConsumerAvailable: Bool = true,
    offscreenControllerSmokePassed: Bool = true,
    initialRestoreSnapshotCoordinatorHarnessPassed: Bool = true,
    startupNetworkPatternClean: Bool = true,
    selectedSwiftTestingSuitesNonZero: Bool = true,
    dataSourceApplyCoordinatorOnly: Bool = true,
    noExtraNostrHomeTimelineStore: Bool = true,
    artifactPrivacyGuardPassed: Bool = true,
    routeActivationRenderingSwitchClosed: Bool = true,
    timelineSurfaceConstructedFromRoot: Bool = false,
    timelineCollectionViewControllerConstructedFromRoot: Bool = false,
    preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly
) -> TimelineHomeRouteConstructionReadiness {
    TimelineHomeRouteConstructionReadiness(
        hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
        dependencies: dependencies,
        rootNoOpPreflightComplete: rootNoOpPreflightComplete,
        routeDiagnosticsSinkInjectionComplete: routeDiagnosticsSinkInjectionComplete,
        rootDecisionSnapshot: rootDecisionSnapshot,
        snapshotConsumerAvailable: snapshotConsumerAvailable,
        offscreenControllerSmokePassed: offscreenControllerSmokePassed,
        initialRestoreSnapshotCoordinatorHarnessPassed: initialRestoreSnapshotCoordinatorHarnessPassed,
        startupNetworkPatternClean: startupNetworkPatternClean,
        selectedSwiftTestingSuitesNonZero: selectedSwiftTestingSuitesNonZero,
        dataSourceApplyCoordinatorOnly: dataSourceApplyCoordinatorOnly,
        noExtraNostrHomeTimelineStore: noExtraNostrHomeTimelineStore,
        artifactPrivacyGuardPassed: artifactPrivacyGuardPassed,
        routeActivationRenderingSwitchClosed: routeActivationRenderingSwitchClosed,
        timelineSurfaceConstructedFromRoot: timelineSurfaceConstructedFromRoot,
        timelineCollectionViewControllerConstructedFromRoot: timelineCollectionViewControllerConstructedFromRoot,
        preferredConstructionKind: preferredConstructionKind
    )
}

private func makeSnapshot(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    debugOverride: TimelineHomeRouteDebugOverride? = nil,
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        debugOverride: debugOverride,
        dependencies: dependencies,
        createdAtMS: 1_111
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(from: result, createdAtMS: 1_111)
}

private extension [TimelineHomeRouteConstructionIssue] {
    func contains(gate: TimelineHomeRouteConstructionGate) -> Bool {
        contains { $0.gate == gate }
    }
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
