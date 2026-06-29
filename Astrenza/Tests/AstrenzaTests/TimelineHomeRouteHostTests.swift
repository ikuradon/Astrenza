import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRouteHost")
struct TimelineHomeRouteHostTests {
    @Test("default no args chooses legacy")
    func defaultNoArgsChoosesLegacy() {
        let decision = hostDecision(arguments: ["Astrenza"])

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.fallbackIssues.isEmpty)
        #expect(decision.launchArgumentSource.argument == nil)
        #expect(decision.debugOverrideSource.override == nil)
        #expect(decision.rootShellBehavior == .unchangedImmediate)
    }

    @Test("launch arg legacy chooses legacy")
    func launchArgLegacyChoosesLegacy() {
        let decision = hostDecision(arguments: ["Astrenza", "--timeline-engine=legacy"])

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.launchArgumentSource.argument == "--timeline-engine=legacy")
    }

    @Test("launch arg collectionView with ready dependencies chooses collectionView")
    func launchArgCollectionViewWithReadyDependenciesChoosesCollectionView() {
        let decision = hostDecision(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(decision.selectedRoute == .collectionView)
        #expect(decision.requestedMode == .collectionView)
        #expect(decision.effectiveMode == .collectionView)
        #expect(decision.timelineRestoreGateScope == .timelineArea)
        #expect(decision.dependencyReadiness.allReady)
    }

    @Test("launch arg collectionView with missing dependencies falls back legacy")
    func launchArgCollectionViewWithMissingDependenciesFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        dependencies.diagnosticsSinkAvailable = false

        let decision = hostDecision(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .collectionView)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.fallbackIssues.map(\.kind) == [
            .repositoryStoreUnavailable,
            .diagnosticsSinkUnavailable
        ])
        #expect(decision.dependencyReadiness.allReady == false)
        #expect(decision.dependencyReadiness.issueKinds == [
            .repositoryStoreUnavailable,
            .diagnosticsSinkUnavailable
        ])
    }

    @Test("unknown launch arg falls back legacy and preserves parser issue")
    func unknownLaunchArgFallsBackLegacyAndPreservesParserIssue() throws {
        let decision = hostDecision(arguments: ["Astrenza", "--timeline-engine=grid"])
        let issue = try #require(decision.fallbackIssues.first)

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .unknown)
        #expect(decision.effectiveMode == .legacy)
        #expect(issue.kind == .unknownTimelineEngineMode)
        #expect(issue.argument == "--timeline-engine=grid")
        #expect(issue.rawValue == "grid")
        #expect(decision.launchArgumentSource.argument == "--timeline-engine=grid")
        #expect(decision.launchArgumentSource.rawValue == "grid")
    }

    @Test("debug override legacy forces legacy")
    func debugOverrideLegacyForcesLegacy() {
        let decision = hostDecision(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            debugOverride: .legacy
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.requestedMode == .legacy)
        #expect(decision.effectiveMode == .legacy)
        #expect(decision.debugOverrideSource.override == .legacy)
        #expect(decision.fallbackIssues.isEmpty)
        #expect(decision.timelineRestoreGateScope == nil)
    }

    @Test("debug override collectionView requires ready dependencies")
    func debugOverrideCollectionViewRequiresReadyDependencies() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.windowComposerAvailable = false

        let fallback = hostDecision(
            arguments: ["Astrenza"],
            debugOverride: .collectionView,
            dependencies: dependencies
        )
        let ready = hostDecision(
            arguments: ["Astrenza"],
            debugOverride: .collectionView
        )

        #expect(fallback.selectedRoute == .legacy)
        #expect(fallback.requestedMode == .collectionView)
        #expect(fallback.fallbackIssues.map(\.kind) == [.windowComposerUnavailable])
        #expect(ready.selectedRoute == .collectionView)
        #expect(ready.requestedMode == .collectionView)
        #expect(ready.debugOverrideSource.override == .collectionView)
    }

    @Test("debug override collectionView requires runtime and rollout readiness")
    func debugOverrideCollectionViewRequiresRuntimeAndRolloutReadiness() {
        var runtimeDisabled = TimelineHomeRouteDependencyStatus.allAvailable
        runtimeDisabled.runtimeGuardAllowsCollectionView = false
        var rolloutBlocked = TimelineHomeRouteDependencyStatus.allAvailable
        rolloutBlocked.rolloutAllowsCollectionView = false

        let runtimeDecision = hostDecision(
            arguments: ["Astrenza"],
            debugOverride: .collectionView,
            dependencies: runtimeDisabled
        )
        let rolloutDecision = hostDecision(
            arguments: ["Astrenza"],
            debugOverride: .collectionView,
            dependencies: rolloutBlocked
        )

        #expect(runtimeDecision.selectedRoute == .legacy)
        #expect(runtimeDecision.requestedMode == .collectionView)
        #expect(runtimeDecision.fallbackIssues.map(\.kind) == [.runtimeGuardDisabled])
        #expect(rolloutDecision.selectedRoute == .legacy)
        #expect(rolloutDecision.requestedMode == .collectionView)
        #expect(rolloutDecision.fallbackIssues.map(\.kind) == [.rolloutBlocked])
    }

    @Test("runtime disabled falls back legacy")
    func runtimeDisabledFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let decision = hostDecision(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.fallbackIssues.map(\.kind) == [.runtimeGuardDisabled])
        #expect(decision.dependencyReadiness.runtimeGuardAllowsCollectionView == false)
    }

    @Test("rollout blocked falls back legacy")
    func rolloutBlockedFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let decision = hostDecision(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(decision.selectedRoute == .legacy)
        #expect(decision.fallbackIssues.map(\.kind) == [.rolloutBlocked])
        #expect(decision.dependencyReadiness.rolloutAllowsCollectionView == false)
    }

    @Test("diagnostics include dependency readiness summary")
    func diagnosticsIncludeDependencyReadinessSummary() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.collectionViewControllerAvailable = false

        let decision = hostDecision(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(decision.diagnostics.dependencyReadiness == decision.dependencyReadiness)
        #expect(decision.diagnostics.dependencyReadiness.issueKinds == [.collectionViewControllerUnavailable])
    }

    @Test("route host keeps side effect flags closed")
    func routeHostKeepsSideEffectFlagsClosed() {
        let decision = hostDecision(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(decision.preventsDualMutation)
        #expect(decision.readMarkerChanged == false)
        #expect(decision.requiresNetworkWork == false)
        #expect(decision.requiresDBWrite == false)
        #expect(decision.rootShellBehavior == .unchangedImmediate)
        #expect(decision.rootShellBehaviorUnchanged)
        #expect(decision.diagnostics.instantiatesRoot == false)
        #expect(decision.diagnostics.instantiatesLegacyHomeStore == false)
        #expect(decision.diagnostics.instantiatesCollectionViewController == false)
        #expect(decision.diagnostics.startsNetworkWork == false)
        #expect(decision.diagnostics.performsDatabaseMutation == false)
        #expect(decision.diagnostics.advancesReadMarker == false)
        #expect(decision.diagnostics.callsDataSourceApply == false)
    }

    @Test("route host source stays pure")
    func routeHostSourceStaysPure() throws {
        let source = try sourceFile(named: "TimelineHomeRouteHost.swift")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("actor " + "Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
    }

    @Test("route host models are Codable Equatable and Sendable")
    func routeHostModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRouteHost.self)
        assertSendable(TimelineHomeRouteHostInput.self)
        assertSendable(TimelineHomeRouteHostDecision.self)
        assertSendable(TimelineHomeRouteDebugFlagSource.self)
        assertSendable(TimelineHomeRouteHostDiagnostics.self)
        assertSendable(TimelineHomeRouteDebugOverride.self)

        let decision = hostDecision(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let data = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteHostDecision.self, from: data)

        #expect(decoded == decision)
    }

    private func hostDecision(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRouteHostDecision {
        TimelineHomeRouteHost.decide(TimelineHomeRouteHostInput(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies
        ))
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
