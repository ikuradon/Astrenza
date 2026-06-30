import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRootRouteDecisionSnapshotConsumer")
struct TimelineHomeRootRouteDecisionSnapshotConsumerTests {
    @Test("consumer decodes default legacy fixture JSON")
    func consumer_decodes_default_legacy_fixture_json() throws {
        let consumer = try consumer(for: defaultLegacySnapshot())

        #expect(consumer.snapshot.visibleRoute == .legacy)
        #expect(consumer.snapshot.renderedRoute == .legacy)
        #expect(consumer.didRenderLegacy)
        #expect(consumer.didObserveCollectionView == false)
        #expect(consumer.didConstructCollectionView == false)
        #expect(consumer.diagnosticsRecordCount == 1)
        #expect(consumer.artifactSummary.deterministicSummary == expectedDefaultArtifactSummary)
    }

    @Test("consumer decodes collectionView observed placeholder fixture JSON")
    func consumer_decodes_collection_view_observed_placeholder_fixture_json() throws {
        let consumer = try consumer(for: collectionViewObservedSnapshot())

        #expect(consumer.snapshot.visibleRoute == .collectionViewPlaceholder)
        #expect(consumer.snapshot.renderedRoute == .legacy)
        #expect(consumer.didRenderLegacy)
        #expect(consumer.didObserveCollectionView)
        #expect(consumer.didConstructCollectionView == false)
        #expect(consumer.isFallback == false)
        #expect(consumer.diagnosticsRecordCount == 1)
        #expect(consumer.artifactSummary.deterministicSummary == expectedCollectionViewArtifactSummary)
    }

    @Test("consumer decodes fallback fixture JSON")
    func consumer_decodes_fallback_fixture_json() throws {
        let consumer = try consumer(for: missingRepositoryFallbackSnapshot())

        #expect(consumer.snapshot.visibleRoute == .legacy)
        #expect(consumer.didRenderLegacy)
        #expect(consumer.didObserveCollectionView)
        #expect(consumer.didConstructCollectionView == false)
        #expect(consumer.isFallback)
        #expect(consumer.fallbackIssueKinds == [.repositoryStoreUnavailable])
        #expect(consumer.artifactSummary.missingDependencies == ["repositoryStore"])
    }

    @Test("default legacy deterministic debug summary is stable")
    func default_legacy_deterministic_debug_summary_is_stable() throws {
        let consumer = try consumer(for: defaultLegacySnapshot())

        #expect(consumer.debugSummary.deterministicText == expectedDefaultDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedDefaultDebugSummary)
    }

    @Test("collectionView observed placeholder deterministic debug summary is stable")
    func collection_view_observed_placeholder_deterministic_debug_summary_is_stable() throws {
        let consumer = try consumer(for: collectionViewObservedSnapshot())

        #expect(consumer.debugSummary.deterministicText == expectedCollectionViewDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedCollectionViewDebugSummary)
    }

    @Test("query reports legacy render for every local fixture")
    func query_reports_legacy_render_for_every_local_fixture() throws {
        let consumers = try [
            consumer(for: defaultLegacySnapshot()),
            consumer(for: collectionViewObservedSnapshot()),
            consumer(for: missingRepositoryFallbackSnapshot()),
            consumer(for: unknownFlagFallbackSnapshot())
        ]

        #expect(consumers.allSatisfy { $0.didRenderLegacy })
        #expect(consumers.allSatisfy { $0.snapshot.renderedRoute == .legacy })
    }

    @Test("query reports collectionView observation without construction")
    func query_reports_collection_view_observation_without_construction() throws {
        let observed = try consumer(for: collectionViewObservedSnapshot())
        let fallback = try consumer(for: missingRepositoryFallbackSnapshot())

        #expect(observed.didObserveCollectionView)
        #expect(fallback.didObserveCollectionView)
        #expect(observed.didConstructCollectionView == false)
        #expect(fallback.didConstructCollectionView == false)
    }

    @Test("query exposes fallback issue kinds")
    func query_exposes_fallback_issue_kinds() throws {
        let missingRepository = try consumer(for: missingRepositoryFallbackSnapshot())
        let unknownFlag = try consumer(for: unknownFlagFallbackSnapshot())

        #expect(missingRepository.fallbackIssueKinds == [.repositoryStoreUnavailable])
        #expect(unknownFlag.fallbackIssueKinds == [.unknownTimelineEngineMode])
    }

    @Test("query exposes release blocker flags as empty for safe fixtures")
    func query_exposes_release_blocker_flags_as_empty_for_safe_fixtures() throws {
        let consumers = try [
            consumer(for: defaultLegacySnapshot()),
            consumer(for: collectionViewObservedSnapshot()),
            consumer(for: missingRepositoryFallbackSnapshot())
        ]

        #expect(consumers.allSatisfy { $0.releaseBlockerFlags.isEmpty })
    }

    @Test("query exposes side effect flags as false")
    func query_exposes_side_effect_flags_as_false() throws {
        let consumer = try consumer(for: collectionViewObservedSnapshot())

        assertAllSideEffectsFalse(consumer.sideEffectFlags)
        assertAllSideEffectsFalse(consumer.debugSummary.sideEffectFlags)
    }

    @Test("query exposes diagnostics record count")
    func query_exposes_diagnostics_record_count() throws {
        let oneRecord = try consumer(for: defaultLegacySnapshot())
        let twoRecords = try consumer(for: latestSinkSnapshot(recordCount: 2))

        #expect(oneRecord.diagnosticsRecordCount == 1)
        #expect(twoRecords.diagnosticsRecordCount == 2)
        #expect(twoRecords.snapshot.visibleRoute == .collectionViewPlaceholder)
    }

    @Test("reader decodes fixture JSON and returns consumer")
    func reader_decodes_fixture_json_and_returns_consumer() throws {
        let data = try encodedData(collectionViewObservedSnapshot())
        let reader = try TimelineHomeRootRouteDecisionSnapshotReader.decodeFixtureJSON(data)
        let consumer = reader.consumer

        #expect(reader.snapshot == collectionViewObservedSnapshot())
        #expect(consumer.didObserveCollectionView)
        #expect(consumer.didConstructCollectionView == false)
    }

    @Test("encoded fixture JSON omits privacy forbidden fragments")
    func encoded_fixture_json_omits_privacy_forbidden_fragments() throws {
        let json = try encodedJSONString(unknownFlagFallbackSnapshot())
        let normalized = json.lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!normalized.contains(fragment.lowercased()))
        }
    }

    @Test("consumer is codable equatable sendable and pure source")
    func consumer_is_codable_equatable_sendable_and_pure_source() throws {
        let consumer = try consumer(for: collectionViewObservedSnapshot())
        let data = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeRootRouteDecisionSnapshotConsumer.self,
            from: data
        )
        let consumerSource = try sourceFile(
            named: "TimelineHomeRootRouteDecisionSnapshotConsumer.swift"
        )

        assertSendable(TimelineHomeRootRouteDecisionSnapshotConsumer.self)
        assertSendable(TimelineHomeRootRouteDecisionSnapshotReader.self)
        assertSendable(TimelineHomeRootDecisionDebugSummary.self)
        #expect(decoded == consumer)
        #expect(!consumerSource.contains("AstrenzaRootView("))
        #expect(!consumerSource.contains("HomeTimelineView("))
        #expect(!consumerSource.contains("Nostr" + "HomeTimelineStore("))
        #expect(!consumerSource.contains("Timeline" + "CollectionViewController("))
        #expect(!consumerSource.contains("TimelineSurface("))
        #expect(!consumerSource.contains("URL" + "Session"))
        #expect(!consumerSource.contains("Web" + "Socket"))
        #expect(!consumerSource.contains("set" + "Default" + "Relays"))
        #expect(!consumerSource.contains("dataSource." + "apply"))
        #expect(!consumerSource.contains("deleteItems"))
        #expect(!consumerSource.contains("insertItems"))
        #expect(!consumerSource.contains("advance" + "Read" + "Marker"))
        #expect(!consumerSource.contains("File" + "Manager"))
        #expect(!consumerSource.contains("write(to:"))
        #expect(!consumerSource.contains("upload"))
        #expect(!consumerSource.contains("telemetry"))
        #expect(!consumerSource.contains("analytics"))
    }

    private var createdAtMS: Int64 {
        1_735_000_002_100
    }

    private var snapshotCreatedAtMS: Int64 {
        1_735_000_002_200
    }

    private var expectedDefaultArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=legacy requested=legacy effective=legacy fallback=false collectionViewAllowed=false missing=[repositoryStore,windowComposer,restoreUseCase,coordinatorAdapter,collectionViewController] issues=[] runtimeAllowed=false rolloutAllowed=false blockers=[]"
    }

    private var expectedCollectionViewArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedDefaultDebugSummary: String {
        "renderedRoute=legacy visibleRoute=legacy observedCollectionView=false constructedCollectionView=false fallbackIssues=[] readMarkerChanged=false requiresNetworkWork=false requiresDBWrite=false dataSourceApplyCalled=false diagnosticsRecordCount=1 releaseBlockers=[] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false) artifactSummary={\(expectedDefaultArtifactSummary)}"
    }

    private var expectedCollectionViewDebugSummary: String {
        "renderedRoute=legacy visibleRoute=collectionViewPlaceholder observedCollectionView=true constructedCollectionView=false fallbackIssues=[] readMarkerChanged=false requiresNetworkWork=false requiresDBWrite=false dataSourceApplyCalled=false diagnosticsRecordCount=1 releaseBlockers=[] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false) artifactSummary={\(expectedCollectionViewArtifactSummary)}"
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
            "event id"
        ]
    }

    private func defaultLegacySnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        snapshot(arguments: ["Astrenza"])
    }

    private func collectionViewObservedSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        snapshot(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable
        )
    }

    private func missingRepositoryFallbackSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        return snapshot(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )
    }

    private func unknownFlagFallbackSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        snapshot(arguments: ["Astrenza", "--timeline-engine=nsec-secret-grid"])
    }

    private func latestSinkSnapshot(recordCount: Int) -> TimelineHomeRootRouteDecisionSnapshot {
        var sink = TimelineHomeRouteDiagnosticsSink(retentionLimit: recordCount)
        _ = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=legacy"],
            dependencies: .rootCallSiteDefaultLegacy,
            createdAtMS: createdAtMS,
            localDiagnosticsSink: &sink
        )
        _ = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: createdAtMS,
            localDiagnosticsSink: &sink
        )

        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: sink,
            createdAtMS: snapshotCreatedAtMS
        )
    }

    private func snapshot(
        arguments: [String],
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy
    ) -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: arguments,
            dependencies: dependencies,
            createdAtMS: createdAtMS
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: snapshotCreatedAtMS
        )
    }

    private func consumer(
        for snapshot: TimelineHomeRootRouteDecisionSnapshot
    ) throws -> TimelineHomeRootRouteDecisionSnapshotConsumer {
        try TimelineHomeRootRouteDecisionSnapshotConsumer.decodeFixtureJSON(
            encodedData(snapshot)
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

    private func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try encodedData(value)
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

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
