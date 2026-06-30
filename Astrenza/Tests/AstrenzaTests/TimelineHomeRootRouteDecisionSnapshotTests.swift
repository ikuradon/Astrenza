import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRouteDecisionSnapshot")
struct TimelineHomeRootRouteDecisionSnapshotTests {
    @Test("default snapshot renders legacy route")
    func default_snapshot_renders_legacy_route() throws {
        let result = rootCallSite(arguments: ["Astrenza"])
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(snapshot.visibleRoute == .legacy)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .legacy)
        #expect(snapshot.diagnosticsRecordCount == 1)
        #expect(snapshot.collectionViewDecisionObserved == false)
        #expect(snapshot.collectionViewRouteConstructed == false)
        #expect(snapshot.legacyHomeRendered)
        #expect(snapshot.rootShellUnchanged)
        #expect(snapshot.rootShellPresentation == .immediate)
        #expect(snapshot.rootShellMustRenderBeforeTimelineRestore)
        #expect(snapshot.timelineRestoreGateScope == nil)
        #expect(snapshot.timelineGateCoversRootShell == false)
        #expect(snapshot.timelineGateCoversTabBar == false)
        #expect(snapshot.timelineGateContinuesGlobalSplash == false)
        #expect(snapshot.firstInteractiveScrollPolicy == .allowedAfterLocalRestoreWithoutNetwork)
        #expect(snapshot.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(snapshot.requiresRemoteSyncBeforeInteractiveScroll == false)
        #expect(snapshot.requiresOGPResolveBeforeInteractiveScroll == false)
        #expect(snapshot.requiresMediaResolveBeforeInteractiveScroll == false)
        #expect(snapshot.requiresProfileResolveBeforeInteractiveScroll == false)
        #expect(snapshot.preventsDualMutation)
        #expect(snapshot.readMarkerChanged == false)
        #expect(snapshot.requiresNetworkWork == false)
        #expect(snapshot.requiresDBWrite == false)
        #expect(snapshot.dataSourceApplyCalled == false)
        #expect(snapshot.createdAtMS == snapshotCreatedAtMS)
        assertAllSideEffectsFalse(snapshot.sideEffectSentinel)
    }

    @Test("collectionView decision is observed but not constructed or rendered")
    func collectionView_decision_is_observed_but_not_constructed_or_rendered() {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(result.preflight.decision.selectedRoute == .collectionView)
        #expect(snapshot.visibleRoute == .collectionViewPlaceholder)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .collectionView)
        #expect(snapshot.collectionViewDecisionObserved)
        #expect(snapshot.collectionViewRouteConstructed == false)
        #expect(snapshot.legacyHomeRendered)
        #expect(snapshot.rootShellUnchanged)
        #expect(snapshot.rootShellPresentation == .immediate)
        #expect(snapshot.rootShellMustRenderBeforeTimelineRestore)
        #expect(snapshot.timelineRestoreGateScope == .timelineArea)
        #expect(snapshot.timelineGateCoversRootShell == false)
        #expect(snapshot.timelineGateCoversTabBar == false)
        #expect(snapshot.timelineGateContinuesGlobalSplash == false)
        #expect(snapshot.firstInteractiveScrollPolicy == .allowedAfterLocalRestoreWithoutNetwork)
        #expect(snapshot.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(snapshot.artifactSummary.collectionViewAllowed)
        #expect(snapshot.artifactSummary.rootShellBehavior == .unchangedImmediate)
        #expect(snapshot.artifactSummary.rootShellBehaviorUnchanged)
        #expect(snapshot.artifactSummary.timelineRestoreGateScope == .timelineArea)
        #expect(snapshot.artifactSummary.deterministicSummary == expectedCollectionViewSummary)
        #expect(snapshot.readMarkerChanged == false)
        #expect(snapshot.requiresNetworkWork == false)
        #expect(snapshot.requiresDBWrite == false)
        #expect(snapshot.dataSourceApplyCalled == false)
        assertAllSideEffectsFalse(snapshot.sideEffectSentinel)
    }

    @Test("missing dependency snapshot renders legacy fallback")
    func missing_dependency_snapshot_renders_legacy_fallback() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(snapshot.visibleRoute == .legacy)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .collectionView)
        #expect(snapshot.collectionViewDecisionObserved)
        #expect(snapshot.collectionViewRouteConstructed == false)
        #expect(snapshot.artifactSummary.legacyFallback)
        #expect(snapshot.artifactSummary.missingDependencies == ["repositoryStore"])
        #expect(snapshot.artifactSummary.fallbackIssueKinds == [.repositoryStoreUnavailable])
        #expect(snapshot.artifactSummary.decisionSource == .launchArgument)
        #expect(snapshot.artifactSummary.launchArgumentSource == .recognized)
        #expect(snapshot.artifactSummary.launchArgumentValue == "collectionView")
        #expect(snapshot.artifactSummary.deterministicSummary == expectedMissingRepositorySummary)
        #expect(snapshot.legacyHomeRendered)
        #expect(snapshot.rootShellUnchanged)
    }

    @Test("unknown flag snapshot renders legacy fallback without raw flag")
    func unknown_flag_snapshot_renders_legacy_fallback_without_raw_flag() throws {
        let result = rootCallSite(arguments: ["Astrenza", "--timeline-engine=nsec-secret-grid"])
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )
        let encodedJSON = try encodedJSONString(snapshot)
        let encoded = encodedJSON.lowercased()

        #expect(snapshot.visibleRoute == .legacy)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .unknown)
        #expect(snapshot.artifactSummary.legacyFallback)
        #expect(snapshot.artifactSummary.fallbackIssueKinds == [.unknownTimelineEngineMode])
        #expect(snapshot.artifactSummary.launchArgumentSource == .unknownRedacted)
        #expect(snapshot.artifactSummary.launchArgumentValue == nil)
        #expect(snapshot.collectionViewRouteConstructed == false)
        #expect(snapshot.legacyHomeRendered)
        #expect(!encodedJSON.contains("\"launchArguments\""))
        #expect(!encoded.contains("invocation"))
        #expect(!encoded.contains("preflightinput"))
        #expect(!encoded.contains("rootroutepreflightinput"))
        #expect(!encoded.contains("nsec"))
        #expect(!encoded.contains("secret"))
        #expect(!encoded.contains("privatekey"))
        #expect(!encoded.contains("private_key"))
        #expect(!encoded.contains("raw_json"))
        #expect(!encoded.contains("raw_event"))
        #expect(!encoded.contains("mnemonic"))
        #expect(!encoded.contains("keychain"))
        #expect(!encoded.contains("bearer"))
        #expect(!encoded.contains("wss://"))
    }

    @Test("snapshot reads latest local artifact from sink")
    func snapshot_reads_latest_local_artifact_from_sink() {
        var sink = TimelineHomeRouteDiagnosticsSink(retentionLimit: 3)
        _ = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=legacy"],
            localDiagnosticsSink: &sink
        )
        let selected = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            localDiagnosticsSink: &sink
        )

        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: sink,
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(sink.records.count == 2)
        #expect(snapshot.diagnosticsRecordCount == 2)
        #expect(snapshot.artifactSummary.createdAtMS == selected.preflight.artifact.createdAtMS)
        #expect(snapshot.visibleRoute == .collectionViewPlaceholder)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .collectionView)
        #expect(snapshot.artifactSummary.deterministicSummary == expectedCollectionViewSummary)
    }

    @Test("snapshot recomputes stale artifact summary from latest record")
    func snapshot_recomputes_stale_artifact_summary_from_latest_record() {
        let legacy = rootCallSite(arguments: ["Astrenza", "--timeline-engine=legacy"])
        let selected = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        var staleArtifact = selected.preflight.artifact
        staleArtifact.summary = legacy.preflight.artifact.summary
        let sink = TimelineHomeRouteDiagnosticsSink(
            retentionLimit: 1,
            records: [staleArtifact]
        )

        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: sink,
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(snapshot.visibleRoute == .collectionViewPlaceholder)
        #expect(snapshot.collectionViewDecisionObserved)
        #expect(snapshot.artifactSummary.collectionViewAllowed)
        #expect(snapshot.artifactSummary.legacyFallback == false)
        #expect(snapshot.artifactSummary.deterministicSummary == expectedCollectionViewSummary)
    }

    @Test("empty sink snapshot is unavailable but renders legacy safely")
    func empty_sink_snapshot_is_unavailable_but_renders_legacy_safely() {
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: TimelineHomeRouteDiagnosticsSink(retentionLimit: 2),
            createdAtMS: snapshotCreatedAtMS
        )

        #expect(snapshot.visibleRoute == .unavailable)
        #expect(snapshot.renderedRoute == .legacy)
        #expect(snapshot.requestedRouteDecision == .unknown)
        #expect(snapshot.diagnosticsRecordCount == 0)
        #expect(snapshot.collectionViewDecisionObserved == false)
        #expect(snapshot.collectionViewRouteConstructed == false)
        #expect(snapshot.legacyHomeRendered)
        #expect(snapshot.rootShellUnchanged)
        #expect(snapshot.rootShellPresentation == .immediate)
        #expect(snapshot.rootShellMustRenderBeforeTimelineRestore)
        #expect(snapshot.timelineGateCoversRootShell == false)
        #expect(snapshot.timelineGateCoversTabBar == false)
        #expect(snapshot.timelineGateContinuesGlobalSplash == false)
        #expect(snapshot.artifactSummary.deterministicSummary == expectedUnavailableSummary)
        assertAllSideEffectsFalse(snapshot.sideEffectSentinel)
    }

    @Test("snapshot is codable equatable sendable and pure source")
    func snapshot_is_codable_equatable_sendable_and_pure_source() throws {
        let result = rootCallSite(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
        let snapshot = TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TimelineHomeRootRouteDecisionSnapshot.self, from: data)
        let snapshotSource = try sourceFile(named: "TimelineHomeRootRouteDecisionSnapshot.swift")

        assertSendable(TimelineHomeRootRouteDecisionSnapshot.self)
        assertSendable(TimelineHomeRootVisibleRouteDecision.self)
        assertSendable(TimelineHomeRootRouteArtifactSnapshot.self)
        #expect(decoded == snapshot)
        #expect(!snapshotSource.contains("Nostr" + "HomeTimelineStore("))
        #expect(!snapshotSource.contains("Timeline" + "CollectionViewController("))
        #expect(!snapshotSource.contains("TimelineSurface("))
        #expect(!snapshotSource.contains("URL" + "Session"))
        #expect(!snapshotSource.contains("Web" + "Socket"))
        #expect(!snapshotSource.contains("set" + "Default" + "Relays"))
        #expect(!snapshotSource.contains("dataSource." + "apply"))
        #expect(!snapshotSource.contains("deleteItems"))
        #expect(!snapshotSource.contains("insertItems"))
        #expect(!snapshotSource.contains("advance" + "Read" + "Marker"))
        #expect(!snapshotSource.contains("File" + "Manager"))
        #expect(!snapshotSource.contains("upload"))
        #expect(!snapshotSource.contains("telemetry"))
        #expect(!snapshotSource.contains("analytics"))
    }

    private var createdAtMS: Int64 {
        1_735_000_002_100
    }

    private var snapshotCreatedAtMS: Int64 {
        1_735_000_002_200
    }

    private var expectedCollectionViewSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedMissingRepositorySummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=legacy requested=collectionView effective=legacy fallback=true collectionViewAllowed=false missing=[repositoryStore] issues=[repositoryStoreUnavailable] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedUnavailableSummary: String {
        "kind=none version=0 event=none source=none route=none requested=unknown effective=unknown fallback=false collectionViewAllowed=false missing=[] issues=[] runtimeAllowed=false rolloutAllowed=false blockers=[]"
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

    private func assertSendable<T: Sendable>(_ type: T.Type) {}

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
}
