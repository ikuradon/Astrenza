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
}

private func makeReadiness(
    hasExplicitCollectionViewLaunchFlag: Bool = true,
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable,
    rootNoOpPreflightComplete: Bool = true,
    routeDiagnosticsSinkInjectionComplete: Bool = true,
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot? = nil,
    snapshotConsumerAvailable: Bool = true,
    offscreenControllerSmokePassed: Bool = true,
    initialRestoreSnapshotCoordinatorHarnessPassed: Bool = true,
    startupNetworkPatternClean: Bool = true,
    selectedSwiftTestingSuitesNonZero: Bool = true,
    dataSourceApplyCoordinatorOnly: Bool = true,
    noExtraNostrHomeTimelineStore: Bool = true,
    artifactPrivacyGuardPassed: Bool = true,
    preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly
) -> TimelineHomeRouteConstructionReadiness {
    TimelineHomeRouteConstructionReadiness(
        hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
        dependencies: dependencies,
        rootNoOpPreflightComplete: rootNoOpPreflightComplete,
        routeDiagnosticsSinkInjectionComplete: routeDiagnosticsSinkInjectionComplete,
        rootDecisionSnapshot: rootDecisionSnapshot ?? makeSnapshot(),
        snapshotConsumerAvailable: snapshotConsumerAvailable,
        offscreenControllerSmokePassed: offscreenControllerSmokePassed,
        initialRestoreSnapshotCoordinatorHarnessPassed: initialRestoreSnapshotCoordinatorHarnessPassed,
        startupNetworkPatternClean: startupNetworkPatternClean,
        selectedSwiftTestingSuitesNonZero: selectedSwiftTestingSuitesNonZero,
        dataSourceApplyCoordinatorOnly: dataSourceApplyCoordinatorOnly,
        noExtraNostrHomeTimelineStore: noExtraNostrHomeTimelineStore,
        artifactPrivacyGuardPassed: artifactPrivacyGuardPassed,
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
