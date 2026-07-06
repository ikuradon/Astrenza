import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRouteCallSite")
struct TimelineHomeRootRouteCallSiteTests {
    @Test("default_root_route_preflight_keeps_legacy_home")
    func default_root_route_preflight_keeps_legacy_home() {
        let result = rootCallSite(arguments: ["Astrenza"])

        #expect(result.didInvokePreflight)
        #expect(result.preflight.decision.selectedRoute == .legacy)
        #expect(result.visibleRoute == .legacy)
        #expect(result.legacyHomeRemainsDefault)
        #expect(result.collectionViewRouteConstructed == false)
    }

    @Test("root_route_preflight_does_not_construct_collection_view")
    func root_route_preflight_does_not_construct_collection_view() throws {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let rootSource = try appSourceFile(named: "AstrenzaRootView.swift")

        #expect(result.preflight.decision.selectedRoute == .collectionView)
        #expect(result.visibleRoute == .legacy)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.preflight.sideEffects.timelineCollectionViewControllerConstructed == false)
        #expect(!callSiteSource.contains("Timeline" + "CollectionViewController("))
        #expect(!callSiteSource.contains("TimelineSurface("))
        #expect(!rootSource.contains("Timeline" + "CollectionViewController("))
        #expect(rootSource.contains("TimelineHomeRootBodyRenderSwitch.decide"))
        #expect(rootSource.contains("rootBodyRenderDecision.selectedRoute == .collectionView"))
        #expect(rootSource.contains("TimelineSurface("))
    }

    @Test("root_route_preflight_does_not_construct_nostr_store")
    func root_route_preflight_does_not_construct_nostr_store() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let rootSource = try appSourceFile(named: "AstrenzaRootView.swift")

        #expect(result.nostrHomeTimelineStoreConstructedByCallSite == false)
        #expect(result.preflight.sideEffects.nostrHomeTimelineStoreConstructed == false)
        #expect(!callSiteSource.contains("Nostr" + "HomeTimelineStore("))
        #expect(rootSource.countOccurrences(of: "Nostr" + "HomeTimelineStore(") == 2)
    }

    @Test("root_route_preflight_records_local_diagnostics")
    func root_route_preflight_records_local_diagnostics() throws {
        var exports: [TimelineHomeRouteDiagnosticsExport] = []
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            diagnosticsSink: { exports.append($0) }
        )

        #expect(result.localDiagnosticsArtifactRecorded)
        #expect(exports == [result.preflight.diagnosticsExport])
        #expect(result.preflight.diagnosticsExport.artifacts == [result.preflight.artifact])
        #expect(result.preflight.diagnosticsExport.summary == result.preflight.artifact.summary)
        #expect(result.preflight.artifact.source == .rootPreflight)
        #expect(result.preflight.artifact.createdAtMS == createdAtMS)

        let data = try JSONEncoder().encode(result.preflight.diagnosticsExport)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: data)
        #expect(decoded == result.preflight.diagnosticsExport)
    }

    @Test("collection_view_flag_records_decision_but_does_not_enable_by_default")
    func collection_view_flag_records_decision_but_does_not_enable_by_default() {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )

        #expect(result.preflight.decision.selectedRoute == .collectionView)
        #expect(result.preflight.artifact.summary.collectionViewAllowed)
        #expect(result.visibleRoute == .legacy)
        #expect(result.legacyHomeRemainsDefault)
        #expect(result.collectionViewRouteConstructed == false)
    }

    @Test("unknown_flag_falls_back_to_legacy")
    func unknown_flag_falls_back_to_legacy() throws {
        let result = rootCallSite(arguments: ["Astrenza", "--timeline-engine=nsec-secret-grid"])
        let data = try JSONEncoder().encode(result.preflight.artifact)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(result.preflight.decision.selectedRoute == .legacy)
        #expect(result.preflight.decision.requestedMode == .unknown)
        #expect(result.preflight.artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(result.preflight.artifact.record.launchArgumentValue == nil)
        #expect(result.visibleRoute == .legacy)
        #expect(!json.localizedCaseInsensitiveContains("nsec"))
        #expect(!json.localizedCaseInsensitiveContains("secret"))
    }

    @Test("read_marker_not_advanced_by_root_preflight")
    func read_marker_not_advanced_by_root_preflight() {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )

        #expect(result.readMarkerAdvancedByCallSite == false)
        #expect(result.preflight.diagnostics.readMarkerChanged == false)
        #expect(result.preflight.decision.readMarkerChanged == false)
        #expect(result.preflight.artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("no_network_started_by_root_preflight")
    func no_network_started_by_root_preflight() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")

        #expect(result.networkStartedByCallSite == false)
        #expect(result.preflight.diagnostics.requiresNetworkWork == false)
        #expect(!callSiteSource.contains("URL" + "Session"))
        #expect(!callSiteSource.contains("Web" + "Socket"))
        #expect(!callSiteSource.contains("set" + "Default" + "Relays"))
    }

    @Test("no_db_write_by_root_preflight")
    func no_db_write_by_root_preflight() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")

        #expect(result.dbWriteAttemptedByCallSite == false)
        #expect(result.preflight.diagnostics.requiresDBWrite == false)
        #expect(!callSiteSource.contains("GR" + "DB"))
        #expect(!callSiteSource.contains("exec" + "ute("))
        #expect(!callSiteSource.contains("wri" + "te("))
    }

    @Test("dataSourceApply_coordinator_only")
    func dataSourceApply_coordinator_only() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let coordinatorSource = try sourceFile(named: "TimelineSnapshotCoordinator.swift")

        #expect(result.dataSourceApplyCalledByCallSite == false)
        #expect(result.preflight.sideEffects.dataSourceApplyCalled == false)
        #expect(!callSiteSource.contains("dataSource." + "apply"))
        #expect(coordinatorSource.contains("dataSource." + "apply"))
    }

    @Test("selected route artifact is decodable")
    func selected_route_artifact_is_decodable() throws {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        let data = try JSONEncoder().encode(result.preflight.artifact)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDecisionArtifact.self, from: data)
        let exportData = try JSONEncoder().encode(result.preflight.diagnosticsExport)
        let consumer = try TimelineHomeRouteDiagnosticsConsumer.decodeFixtureJSON(exportData)

        #expect(decoded == result.preflight.artifact)
        #expect(consumer.collectionViewAllowed)
        #expect(consumer.releaseBlockerFlags.isEmpty)
    }

    @Test("side-effect sentinel all false")
    func side_effect_sentinel_all_false() {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )

        assertAllSideEffectsFalse(result.preflight.sideEffects)
        assertAllSideEffectsFalse(result.preflight.diagnostics.sideEffects)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.nostrHomeTimelineStoreConstructedByCallSite == false)
        #expect(result.networkStartedByCallSite == false)
        #expect(result.dbWriteAttemptedByCallSite == false)
        #expect(result.readMarkerAdvancedByCallSite == false)
        #expect(result.dataSourceApplyCalledByCallSite == false)
    }

    @Test("root shell behavior unchanged")
    func root_shell_behavior_unchanged() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let rootSource = try appSourceFile(named: "AstrenzaRootView.swift")

        #expect(result.rootShellBehaviorUnchanged)
        #expect(result.preflight.diagnostics.rootShellBehavior == .unchangedImmediate)
        #expect(result.preflight.diagnostics.rootShellBehaviorUnchanged)
        #expect(rootSource.contains("Astrenza" + "StartupSplashView(startDate: startupSplashStartDate)"))
        #expect(rootSource.contains(".task(id: account.pubkey)"))
        #expect(rootSource.contains("homeTimelineStore.start(account: account)"))
        #expect(!rootSource.contains("TimelineHomeRouteHost.decide"))
        #expect(!rootSource.contains("TimelineHomeRouteAdapter.decide"))
        #expect(!rootSource.contains("TimelineHomeRouteIntegrationSkeleton.select"))
    }

    private var createdAtMS: Int64 {
        1_735_000_000_480
    }

    private func rootCallSite(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy,
        diagnosticsSink: ((TimelineHomeRouteDiagnosticsExport) -> Void)? = nil
    ) -> TimelineHomeRootRouteCallSiteResult {
        TimelineHomeRootRouteCallSite.invoke(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS,
            diagnosticsSink: diagnosticsSink
        )
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

    private func appSourceFile(named fileName: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/\(fileName)"),
            encoding: .utf8
        )
    }
}

private extension String {
    func countOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
