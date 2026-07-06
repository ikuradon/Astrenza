import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRouteDiagnosticsSinkInjection")
struct TimelineHomeRootRouteDiagnosticsSinkInjectionTests {
    @Test("root_preflight_records_one_local_route_decision")
    func root_preflight_records_one_local_route_decision() throws {
        let defaultResult = TimelineHomeRootRouteCallSite.invokeDefaultProductionPreflight()
        let explicitLegacy = rootCallSite(arguments: ["Astrenza", "--timeline-engine=legacy"])

        try assertOneLocalArtifact(defaultResult)
        try assertOneLocalArtifact(explicitLegacy)
        #expect(defaultResult.preflight.artifact.source == .rootPreflight)
        #expect(explicitLegacy.preflight.artifact.record.selectedRoute == .legacy)
        #expect(explicitLegacy.preflight.artifact.record.launchArgumentValue == "legacy")
    }

    @Test("root_preflight_default_legacy_rendering_unchanged")
    func root_preflight_default_legacy_rendering_unchanged() throws {
        let result = TimelineHomeRootRouteCallSite.invokeDefaultProductionPreflight()
        let rootSource = try appSourceFile(named: "AstrenzaRootView.swift")

        #expect(result.didInvokePreflight)
        #expect(result.visibleRoute == .legacy)
        #expect(result.legacyHomeRemainsDefault)
        #expect(result.collectionViewRouteConstructed == false)
        #expect(result.rootShellBehaviorUnchanged)
        #expect(rootSource.contains("Home" + "TimelineView("))
        #expect(rootSource.contains("Nostr" + "HomeTimelineStore("))
        #expect(rootSource.contains("TimelineHomeRootRouteCallSite.invokeDefaultProductionPreflight()"))
    }

    @Test("root_preflight_sink_is_in_memory_only")
    func root_preflight_sink_is_in_memory_only() throws {
        var sink = TimelineHomeRouteDiagnosticsSink(retentionLimit: 2)
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            localDiagnosticsSink: &sink
        )
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let sinkSource = try sourceFile(named: "TimelineHomeRouteDiagnosticsSink.swift")

        #expect(sink.records == [result.preflight.artifact])
        #expect(result.localDiagnosticsRecordCount == 1)
        #expect(result.localDiagnosticsExport == sink.export())
        #expect(!callSiteSource.contains("File" + "Manager"))
        #expect(!callSiteSource.contains("write" + "(to:"))
        #expect(!sinkSource.contains("File" + "Manager"))
        #expect(!sinkSource.contains("write" + "(to:"))
        #expect(!sinkSource.contains("upload"))
        #expect(!sinkSource.contains("telemetry"))
        #expect(!sinkSource.contains("analytics"))
    }

    @Test("root_preflight_sink_does_not_construct_collection_view")
    func root_preflight_sink_does_not_construct_collection_view() throws {
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

    @Test("root_preflight_sink_does_not_construct_nostr_store")
    func root_preflight_sink_does_not_construct_nostr_store() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let rootSource = try appSourceFile(named: "AstrenzaRootView.swift")

        #expect(result.nostrHomeTimelineStoreConstructedByCallSite == false)
        #expect(result.preflight.sideEffects.nostrHomeTimelineStoreConstructed == false)
        #expect(!callSiteSource.contains("Nostr" + "HomeTimelineStore("))
        #expect(rootSource.countOccurrences(of: "Nostr" + "HomeTimelineStore(") == 2)
    }

    @Test("root_preflight_sink_does_not_start_network")
    func root_preflight_sink_does_not_start_network() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")

        #expect(result.networkStartedByCallSite == false)
        #expect(result.preflight.diagnostics.requiresNetworkWork == false)
        #expect(result.preflight.artifact.record.requiresNetworkWork == false)
        #expect(!callSiteSource.contains("URL" + "Session"))
        #expect(!callSiteSource.contains("Web" + "Socket"))
        #expect(!callSiteSource.contains("set" + "Default" + "Relays"))
    }

    @Test("root_preflight_sink_does_not_write_db")
    func root_preflight_sink_does_not_write_db() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")

        #expect(result.dbWriteAttemptedByCallSite == false)
        #expect(result.preflight.diagnostics.requiresDBWrite == false)
        #expect(result.preflight.artifact.record.requiresDBWrite == false)
        #expect(!callSiteSource.contains("GR" + "DB"))
        #expect(!callSiteSource.contains("exec" + "ute("))
        #expect(!callSiteSource.contains("wri" + "te("))
        #expect(!callSiteSource.contains("INSERT"))
        #expect(!callSiteSource.contains("UPDATE"))
        #expect(!callSiteSource.contains("DELETE"))
    }

    @Test("root_preflight_sink_does_not_advance_read_marker")
    func root_preflight_sink_does_not_advance_read_marker() {
        let result = rootCallSite(arguments: ["Astrenza"])

        #expect(result.readMarkerAdvancedByCallSite == false)
        #expect(result.preflight.diagnostics.readMarkerChanged == false)
        #expect(result.preflight.decision.readMarkerChanged == false)
        #expect(result.preflight.artifact.record.readMarkerChanged == false)
        #expect(result.preflight.artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("root_preflight_sink_does_not_call_dataSourceApply")
    func root_preflight_sink_does_not_call_dataSourceApply() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let callSiteSource = try sourceFile(named: "TimelineHomeRootRouteCallSite.swift")
        let coordinatorSource = try sourceFile(named: "TimelineSnapshotCoordinator.swift")

        #expect(result.dataSourceApplyCalledByCallSite == false)
        #expect(result.preflight.sideEffects.dataSourceApplyCalled == false)
        #expect(result.preflight.artifact.record.hostSideEffects.callsDataSourceApply == false)
        #expect(!callSiteSource.contains("dataSource." + "apply"))
        #expect(coordinatorSource.contains("dataSource." + "apply"))
    }

    @Test("root_preflight_sink_artifact_passes_privacy_guard")
    func root_preflight_sink_artifact_passes_privacy_guard() throws {
        let result = rootCallSite(arguments: ["Astrenza", "--timeline-engine=nsec-secret-grid"])
        let export = try #require(result.localDiagnosticsExport)
        let json = try encodedJSONString(export).lowercased()
        let forbiddenFragments = [
            "nsec",
            "secret",
            "privatekey",
            "private_key",
            "raw_json",
            "rawevent",
            "raw_event",
            "mnemonic",
            "keychain",
            "bearer",
            "wss://"
        ]

        #expect(result.preflight.artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(result.preflight.artifact.record.launchArgumentValue == nil)
        for fragment in forbiddenFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test("root_preflight_collectionView_flag_records_decision_but_does_not_construct_route")
    func root_preflight_collectionView_flag_records_decision_but_does_not_construct_route() throws {
        let selected = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        var missingDependencies = TimelineHomeRouteDependencyStatus.allAvailable
        missingDependencies.repositoryStoreAvailable = false
        let fallback = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: missingDependencies
        )

        try assertOneLocalArtifact(selected)
        #expect(selected.preflight.decision.selectedRoute == .collectionView)
        #expect(selected.preflight.artifact.summary.collectionViewAllowed)
        #expect(selected.visibleRoute == .legacy)
        #expect(selected.collectionViewRouteConstructed == false)
        #expect(fallback.preflight.decision.selectedRoute == .legacy)
        #expect(fallback.preflight.artifact.summary.legacyFallback)
        #expect(fallback.preflight.artifact.summary.missingDependencies == ["repositoryStore"])
        #expect(fallback.collectionViewRouteConstructed == false)
    }

    @Test("root_preflight_unknown_flag_records_legacy_fallback")
    func root_preflight_unknown_flag_records_legacy_fallback() throws {
        let result = rootCallSite(arguments: ["Astrenza", "--timeline-engine=nsec-secret-grid"])
        let summary = try #require(result.localDiagnosticsDebugSummary)

        try assertOneLocalArtifact(result)
        #expect(result.preflight.decision.selectedRoute == .legacy)
        #expect(result.preflight.decision.requestedMode == .unknown)
        #expect(result.preflight.artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(result.preflight.artifact.record.launchArgumentValue == nil)
        #expect(summary.selectedRoute == .legacy)
        #expect(summary.legacyFallback)
        #expect(summary.fallbackIssueKinds == [.unknownTimelineEngineMode])
    }

    @Test("selected route artifact is decodable")
    func selected_route_artifact_is_decodable() throws {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        let export = try #require(result.localDiagnosticsExport)
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: data)
        let consumer = try TimelineHomeRouteDiagnosticsConsumer.decodeFixtureJSON(data)

        #expect(decoded == export)
        #expect(decoded.artifacts == [result.preflight.artifact])
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
        #expect(result.preflight.artifact.summary.releaseBlockerFlags.isEmpty)
    }

    private var createdAtMS: Int64 {
        1_735_000_001_400
    }

    private func rootCallSite(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy
    ) -> TimelineHomeRootRouteCallSiteResult {
        TimelineHomeRootRouteCallSite.invoke(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS
        )
    }

    private func rootCallSite(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy,
        localDiagnosticsSink: inout TimelineHomeRouteDiagnosticsSink
    ) -> TimelineHomeRootRouteCallSiteResult {
        TimelineHomeRootRouteCallSite.invoke(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS,
            localDiagnosticsSink: &localDiagnosticsSink
        )
    }

    private func assertOneLocalArtifact(
        _ result: TimelineHomeRootRouteCallSiteResult
    ) throws {
        let export = try #require(result.localDiagnosticsExport)
        let summary = try #require(result.localDiagnosticsDebugSummary)

        #expect(result.localDiagnosticsArtifactRecorded)
        #expect(result.localDiagnosticsRecordCount == 1)
        #expect(export.artifacts == [result.preflight.artifact])
        #expect(export.summary == result.preflight.artifact.summary)
        #expect(summary.recordCount == 1)
        #expect(summary.source == .rootPreflight)
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

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
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
