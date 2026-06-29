import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRouteGuard")
struct TimelineHomeRootRouteGuardTests {
    @Test("root guard default decision is legacy")
    func rootGuardDefaultDecisionIsLegacy() {
        let result = guardResult(arguments: ["Astrenza"])

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.effectiveMode == .legacy)
        #expect(result.decision.fallbackIssues.isEmpty)
        #expect(result.artifact.record.selectedRoute == .legacy)
    }

    @Test("root guard explicit legacy is legacy")
    func rootGuardExplicitLegacyIsLegacy() {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=legacy"])

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.effectiveMode == .legacy)
        #expect(result.artifact.record.launchArgumentValue == "legacy")
    }

    @Test("root guard collectionView flag can produce collectionView only when all readiness gates pass")
    func rootGuardCollectionViewFlagCanProduceCollectionViewOnlyWhenAllReadinessGatesPass() {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(result.decision.selectedRoute == .collectionView)
        #expect(result.decision.requestedMode == .collectionView)
        #expect(result.decision.dependencyReadiness.allReady)
        #expect(result.artifact.summary.collectionViewAllowed)
        #expect(result.diagnosticsExport.summary.collectionViewAllowed)
    }

    @Test("root guard collectionView flag with missing dependency falls back legacy")
    func rootGuardCollectionViewFlagWithMissingDependencyFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false

        let result = guardResult(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .collectionView)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.repositoryStoreUnavailable])
        #expect(result.artifact.summary.legacyFallback)
        #expect(result.artifact.summary.missingDependencies == ["repositoryStore"])
    }

    @Test("root guard unknown flag falls back legacy")
    func rootGuardUnknownFlagFallsBackLegacy() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=grid"])
        let issue = try #require(result.decision.fallbackIssues.first)

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .unknown)
        #expect(issue.kind == .unknownTimelineEngineMode)
        #expect(result.artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(result.artifact.record.launchArgumentValue == nil)
    }

    @Test("root guard debug override legacy forces legacy")
    func rootGuardDebugOverrideLegacyForcesLegacy() {
        let result = guardResult(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            debugOverride: .legacy
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.fallbackIssues.isEmpty)
        #expect(result.artifact.record.debugOverride == .legacy)
        #expect(result.artifact.record.decisionSource == .debugOverride)
    }

    @Test("root guard collectionView debug override cannot bypass launch flag")
    func rootGuardCollectionViewDebugOverrideCannotBypassLaunchFlag() {
        let result = guardResult(
            arguments: ["Astrenza"],
            debugOverride: .collectionView
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.requestedMode == .legacy)
        #expect(result.decision.debugOverrideSource.override == nil)
        #expect(result.artifact.record.selectedRoute == .legacy)
        #expect(result.artifact.record.debugOverride == nil)
        #expect(result.artifact.record.decisionSource == .defaultLegacy)
    }

    @Test("root guard runtime disabled falls back legacy")
    func rootGuardRuntimeDisabledFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let result = guardResult(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.runtimeGuardDisabled])
        #expect(result.artifact.record.runtimeAllowed == false)
    }

    @Test("root guard rollout blocked falls back legacy")
    func rootGuardRolloutBlockedFallsBackLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let result = guardResult(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(result.decision.selectedRoute == .legacy)
        #expect(result.decision.fallbackIssues.map(\.kind) == [.rolloutBlocked])
        #expect(result.artifact.record.rolloutAllowed == false)
    }

    @Test("root guard produces route diagnostics artifact")
    func rootGuardProducesRouteDiagnosticsArtifact() {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let consumer = TimelineHomeRouteDiagnosticsConsumer(export: result.diagnosticsExport)

        #expect(result.artifact.schemaVersion == 1)
        #expect(result.artifact.createdAtMS == 1_735_000_000_240)
        #expect(result.diagnosticsExport.artifacts == [result.artifact])
        #expect(consumer.collectionViewAllowed)
        #expect(consumer.debugSummary().contains("route=collectionView"))
    }

    @Test("root guard does not instantiate AstrenzaRootView")
    func rootGuardDoesNotInstantiateAstrenzaRootView() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.diagnostics.instantiatesRoot == false)
        #expect(!source.contains("Astrenza" + "RootView"))
    }

    @Test("root guard does not instantiate NostrHomeTimelineStore")
    func rootGuardDoesNotInstantiateNostrHomeTimelineStore() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.diagnostics.instantiatesLegacyHomeStore == false)
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
    }

    @Test("root guard does not instantiate TimelineCollectionViewController")
    func rootGuardDoesNotInstantiateTimelineCollectionViewController() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.diagnostics.instantiatesCollectionViewController == false)
        #expect(!source.contains("Timeline" + "CollectionViewController("))
    }

    @Test("root guard does not start network")
    func rootGuardDoesNotStartNetwork() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.requiresNetworkWork == false)
        #expect(result.decision.diagnostics.startsNetworkWork == false)
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
    }

    @Test("root guard does not perform database mutation or advance read marker")
    func rootGuardDoesNotPerformDatabaseMutationOrAdvanceReadMarker() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.requiresDBWrite == false)
        #expect(result.decision.readMarkerChanged == false)
        #expect(result.decision.diagnostics.performsDatabaseMutation == false)
        #expect(result.decision.diagnostics.advancesReadMarker == false)
        #expect(!source.contains("GR" + "DB"))
        #expect(!source.contains("exec" + "ute("))
        #expect(!source.contains("wri" + "te("))
    }

    @Test("root guard does not call dataSource apply")
    func rootGuardDoesNotCallDataSourceApply() throws {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let source = try sourceFile(named: "TimelineHomeRootRouteGuard.swift")

        #expect(result.decision.diagnostics.callsDataSourceApply == false)
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
    }

    @Test("root guard preserves root shell behavior unchanged")
    func rootGuardPreservesRootShellBehaviorUnchanged() {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(result.decision.rootShellBehavior == .unchangedImmediate)
        #expect(result.decision.rootShellBehaviorUnchanged)
        #expect(result.artifact.record.rootShellBehavior == .unchangedImmediate)
        #expect(result.artifact.record.rootShellBehaviorUnchanged)
    }

    @Test("root guard prevents dual mutation")
    func rootGuardPreventsDualMutation() {
        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])

        #expect(result.decision.preventsDualMutation)
        #expect(result.artifact.record.preventsDualMutation)
        #expect(result.artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("root guard keeps raw decision in memory and exports Codable diagnostics")
    func rootGuardKeepsRawDecisionInMemoryAndExportsCodableDiagnostics() throws {
        assertSendable(TimelineHomeRootRouteGuard.self)
        assertSendable(TimelineHomeRootRouteGuardInput.self)
        assertSendable(TimelineHomeRootRouteGuardResult.self)

        let result = guardResult(arguments: ["Astrenza", "--timeline-engine=collectionView"])
        let data = try JSONEncoder().encode(result.diagnosticsExport)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: data)

        #expect(decoded == result.diagnosticsExport)
        #expect(decoded.artifacts == [result.artifact])
    }

    private func guardResult(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRootRouteGuardResult {
        TimelineHomeRootRouteGuard.evaluate(TimelineHomeRootRouteGuardInput(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: 1_735_000_000_240
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
