import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView route construction")
struct TimelineHomeCollectionViewRouteConstructionTests {
    @Test
    func default_legacy_does_not_construct_collectionView() {
        let result = makeConstructionReadiness(
            hasExplicitCollectionViewLaunchFlag: false,
            rootDecisionSnapshot: makeConstructionSnapshot(arguments: ["Astrenza"])
        ).evaluate()

        #expect(result.isReady == false)
        #expect(result.plan.renderedRouteAfterConstruction == .legacy)
        #expect(result.plan.collectionViewRouteConstructed == false)
        #expect(result.plan.timelineSurfaceConstructed == false)
        #expect(result.plan.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test
    func collectionView_construction_is_offscreen_or_no_window() {
        let result = makeConstructionReadiness(
            preferredConstructionKind: .offscreenOnly
        ).evaluate()

        #expect(result.isReady)
        #expect(result.plan.constructionKind == .offscreenOnly)
        #expect(result.plan.collectionViewRouteConstructed == false)
        #expect(result.plan.timelineSurfaceConstructed == false)
        #expect(result.plan.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test
    func legacy_rendering_remains_default() throws {
        let result = makeConstructionReadiness().evaluate()
        let rootSource = try sourceFileForConstruction(named: "AstrenzaRootView.swift")

        #expect(result.plan.renderedRouteAfterConstruction == .legacy)
        #expect(result.plan.routeActivationAllowed == false)
        #expect(rootSource.contains("NostrHomeTimelineStore"))
        #expect(rootSource.contains("HomeTimelineView"))
        #expect(rootSource.contains("Timeline" + "CollectionViewController(") == false)
        #expect(rootSource.contains("TimelineHomeRootBodyRenderSwitch.decide"))
        #expect(rootSource.contains("Timeline" + "Surface("))
    }

    @Test
    func readiness_passes_only_as_described_or_offscreen_plan_not_production_route_activation() {
        let described = makeConstructionReadiness(
            preferredConstructionKind: .describedOnly
        ).evaluate()
        let offscreen = makeConstructionReadiness(
            preferredConstructionKind: .offscreenOnly
        ).evaluate()
        let closed = makeConstructionReadiness(
            preferredConstructionKind: .productionClosed
        ).evaluate()

        #expect(described.isReady)
        #expect(described.plan.constructionKind == .describedOnly)
        #expect(offscreen.isReady)
        #expect(offscreen.plan.constructionKind == .offscreenOnly)
        #expect(closed.isReady == false)
        #expect(closed.plan.constructionKind == .productionClosed)
        #expect(described.plan.routeActivationAllowed == false)
        #expect(offscreen.plan.routeActivationAllowed == false)
        #expect(closed.plan.routeActivationAllowed == false)
    }

    @Test
    func route_activation_rendering_switch_remains_later() throws {
        let result = makeConstructionReadiness().evaluate()
        let rootSource = try sourceFileForConstruction(named: "AstrenzaRootView.swift")

        #expect(result.plan.renderedRouteAfterConstruction == .legacy)
        #expect(result.plan.routeActivationAllowed == false)
        #expect(result.plan.collectionViewRouteConstructed == false)
        #expect(rootSource.contains("renderedRoute == .collectionView") == false)
        #expect(rootSource.contains("TimelineSurfaceDependencyContainer.") == false)
        #expect(rootSource.contains("make" + "Controller(") == false)
        #expect(rootSource.contains("rootBodyRenderDecision.selectedRoute == .collectionView"))
    }

    @Test
    func readiness_models_are_codable_equatable_and_sendable() throws {
        let result = makeConstructionReadiness().evaluate()

        assertSendable(TimelineHomeRouteConstructionReadiness.self)
        assertSendable(TimelineHomeRouteConstructionReadinessResult.self)
        assertSendable(TimelineHomeCollectionViewRouteConstructionPlan.self)
        assertSendable(TimelineHomeRouteConstructionGate.self)
        assertSendable(TimelineHomeRouteConstructionIssue.self)

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteConstructionReadinessResult.self, from: encoded)

        #expect(decoded == result)
        #expect(decoded.plan.collectionViewRouteConstructed == false)
        #expect(decoded.plan.timelineSurfaceConstructed == false)
        #expect(decoded.plan.timelineCollectionViewControllerConstructedFromRoot == false)
    }
}

private func makeConstructionReadiness(
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
        rootDecisionSnapshot: rootDecisionSnapshot ?? makeConstructionSnapshot(),
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

private func makeConstructionSnapshot(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    debugOverride: TimelineHomeRouteDebugOverride? = nil,
    dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        debugOverride: debugOverride,
        dependencies: dependencies,
        createdAtMS: 2_222
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(from: result, createdAtMS: 2_222)
}

private func assertSendable<T: Sendable>(_ type: T.Type) {}

private func sourceFileForConstruction(named fileName: String) throws -> String {
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
