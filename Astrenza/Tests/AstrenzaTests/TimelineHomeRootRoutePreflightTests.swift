import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRoutePreflight")
struct TimelineHomeRootRoutePreflightTests {
    @Test("default no args preflight returns legacy without side effects")
    func defaultNoArgsPreflightReturnsLegacyWithoutSideEffects() {
        let result = preflight(arguments: ["Astrenza"])

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.effectiveMode == .legacy)
        #expect(result.decision.fallbackIssues.isEmpty)
        assertAllSideEffectsFalse(result.sideEffects)
    }

    @Test("explicit legacy preflight returns legacy")
    func explicitLegacyPreflightReturnsLegacy() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=legacy"])

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.effectiveMode == .legacy)
        #expect(result.artifact.record.launchArgumentValue == "legacy")
        assertAllSideEffectsFalse(result.sideEffects)
    }

    @Test("collectionView flag with ready dependencies returns collectionView decision")
    func collectionViewFlagWithReadyDependenciesReturnsCollectionViewDecision() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(result.decision.selectedRoute == .collectionView)
        #expect(result.decision.requestedMode == .collectionView)
        #expect(result.decision.dependencyReadiness.allReady)
        #expect(result.artifact.summary.collectionViewAllowed)
        #expect(result.diagnostics.timelineRestoreGateScope == .timelineArea)
        assertAllSideEffectsFalse(result.sideEffects)
    }

    @Test("collectionView flag with missing dependencies returns legacy")
    func collectionViewFlagWithMissingDependenciesReturnsLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false

        let result = preflight(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .collectionView)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.repositoryStoreUnavailable])
        #expect(result.artifact.summary.legacyFallback)
        #expect(result.artifact.summary.missingDependencies == ["repositoryStore"])
        #expect(result.diagnostics.timelineRestoreGateScope == nil)
    }

    @Test("unknown flag returns legacy with redacted diagnostics")
    func unknownFlagReturnsLegacyWithRedactedDiagnostics() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=grid"])

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .unknown)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.unknownTimelineEngineMode])
        #expect(result.artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(result.artifact.record.launchArgumentValue == nil)
    }

    @Test("runtime disabled preflight returns legacy")
    func runtimeDisabledPreflightReturnsLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let result = preflight(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.runtimeGuardDisabled])
        #expect(result.artifact.record.runtimeAllowed == false)
    }

    @Test("rollout blocked preflight returns legacy")
    func rolloutBlockedPreflightReturnsLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let result = preflight(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.rolloutBlocked])
        #expect(result.artifact.record.rolloutAllowed == false)
    }

    @Test("debug override legacy forces legacy")
    func debugOverrideLegacyForcesLegacy() {
        let result = preflight(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            debugOverride: .legacy
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.fallbackIssues.isEmpty)
        #expect(result.artifact.record.debugOverride == .legacy)
        #expect(result.artifact.record.decisionSource == .debugOverride)
    }

    @Test("debug override collectionView cannot bypass launch flag")
    func debugOverrideCollectionViewCannotBypassLaunchFlag() {
        let result = preflight(
            arguments: ["Astrenza"],
            debugOverride: .collectionView
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.debugOverrideSource.override == nil)
        #expect(result.artifact.record.debugOverride == nil)
        #expect(result.artifact.record.decisionSource == .defaultLegacy)
    }

    @Test("debug override collectionView does not replace launch argument source")
    func debugOverrideCollectionViewDoesNotReplaceLaunchArgumentSource() {
        let result = preflight(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            debugOverride: .collectionView
        )

        #expect(result.decision.selectedRoute == .collectionView)
        #expect(result.decision.requestedMode == .collectionView)
        #expect(result.decision.debugOverrideSource.override == nil)
        #expect(result.artifact.record.debugOverride == nil)
        #expect(result.artifact.record.decisionSource == .launchArgument)
    }

    @Test("diagnostics artifact is produced and decodable")
    func diagnosticsArtifactIsProducedAndDecodable() throws {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let data = try JSONEncoder().encode(result.diagnosticsExport)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: data)
        let consumer = try TimelineHomeRouteDiagnosticsConsumer.decodeFixtureJSON(data)

        #expect(result.artifact.schemaVersion == 1)
        #expect(result.artifact.source == .rootPreflight)
        #expect(result.artifact.createdAtMS == 1_735_000_000_360)
        #expect(result.diagnosticsExport.summary == result.artifact.summary)
        #expect(decoded == result.diagnosticsExport)
        #expect(decoded.artifacts == [result.artifact])
        #expect(decoded.artifacts.count == 1)
        #expect(decoded.artifacts.last?.summary == decoded.summary)
        #expect(consumer.collectionViewAllowed)
        #expect(consumer.releaseBlockerFlags.isEmpty)
    }

    @Test("side effect sentinel remains all false")
    func sideEffectSentinelRemainsAllFalse() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        assertAllSideEffectsFalse(result.sideEffects)
        assertAllSideEffectsFalse(result.diagnostics.sideEffects)
    }

    @Test("old new dual mutation and launch side effect flags stay safe")
    func oldNewDualMutationAndLaunchSideEffectFlagsStaySafe() {
        let result = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(result.decision.preventsDualMutation)
        #expect(result.diagnostics.preventsDualMutation)
        #expect(result.diagnostics.readMarkerChanged == false)
        #expect(result.diagnostics.requiresNetworkWork == false)
        #expect(result.diagnostics.requiresDBWrite == false)
        #expect(result.artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("root shell behavior is unchanged")
    func rootShellBehaviorIsUnchanged() {
        let result = preflight(arguments: ["Astrenza"])

        #expect(result.decision.rootShellBehavior == .unchangedImmediate)
        #expect(result.decision.rootShellBehaviorUnchanged)
        #expect(result.diagnostics.rootShellBehavior == .unchangedImmediate)
        #expect(result.diagnostics.rootShellBehaviorUnchanged)
    }

    @Test("timeline restore gate is timeline area only when collectionView route is selected")
    func timelineRestoreGateIsTimelineAreaOnlyWhenCollectionViewRouteIsSelected() {
        let legacy = preflight(arguments: ["Astrenza"])
        let collectionView = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(legacy.decision.timelineRestoreGateScope == nil)
        #expect(legacy.diagnostics.timelineRestoreGateScope == nil)
        #expect(collectionView.decision.timelineRestoreGateScope == .timelineArea)
        #expect(collectionView.diagnostics.timelineRestoreGateScope == .timelineArea)
    }

    @Test("preflight source stays pure and injected")
    func preflightSourceStaysPureAndInjected() throws {
        let source = try sourceFile(named: "TimelineHomeRootRoutePreflight.swift")

        #expect(!source.contains("User" + "Defaults.standard"))
        #expect(!source.contains("Process" + "Info.process" + "Info"))
        #expect(!source.contains("Astrenza" + "RootView("))
        #expect(!source.contains("Home" + "TimelineView("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("actor " + "Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
        #expect(!source.contains("GR" + "DB"))
        #expect(!source.contains("exec" + "ute("))
        #expect(!source.contains("wri" + "te("))
    }

    @Test("integration skeleton source keeps launch arguments injected")
    func integrationSkeletonSourceKeepsLaunchArgumentsInjected() throws {
        let source = try sourceFile(named: "TimelineHomeRouteIntegrationSkeleton.swift")

        #expect(!source.contains("User" + "Defaults.standard"))
        #expect(!source.contains("User" + "Defaults("))
        #expect(!source.contains("Process" + "Info.process" + "Info"))
    }

    @Test("preflight models are Codable Equatable and Sendable")
    func preflightModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRootRoutePreflight.self)
        assertSendable(TimelineHomeRootRoutePreflightInput.self)
        assertSendable(TimelineHomeRootRoutePreflightInvocation.self)
        assertSendable(TimelineHomeRootRoutePreflightResult.self)
        assertSendable(TimelineHomeRootRoutePreflightDiagnostics.self)
        assertSendable(TimelineHomeRootRoutePreflightSideEffectSentinel.self)

        let result = preflight(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(TimelineHomeRootRoutePreflightResult.self, from: data)

        #expect(decoded == result)
    }

    private func preflight(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRootRoutePreflightResult {
        TimelineHomeRootRoutePreflight.invoke(TimelineHomeRootRoutePreflightInput(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: 1_735_000_000_360
        ))
    }

    private func assertAllSideEffectsFalse(
        _ sideEffects: TimelineHomeRootRoutePreflightSideEffectSentinel
    ) {
        #expect(sideEffects.rootViewConstructed == false)
        #expect(sideEffects.homeTimelineViewConstructed == false)
        #expect(sideEffects.nostrHomeTimelineStoreConstructed == false)
        #expect(sideEffects.timelineCollectionViewControllerConstructed == false)
        #expect(sideEffects.networkStarted == false)
        #expect(sideEffects.dbWriteAttempted == false)
        #expect(sideEffects.readMarkerAdvanced == false)
        #expect(sideEffects.dataSourceApplyCalled == false)
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
