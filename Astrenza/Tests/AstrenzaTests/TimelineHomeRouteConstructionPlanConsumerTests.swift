import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome route construction plan consumer")
struct TimelineHomeRouteConstructionPlanConsumerTests {
    @Test("decodes ready described/offscreen plan fixture JSON")
    func decodes_ready_described_offscreen_plan_fixture_json() throws {
        let described = try consumer(for: readyResult(kind: .describedOnly))
        let offscreenPlan = readyResult(kind: .offscreenOnly).plan
        let offscreenData = try encodedData(offscreenPlan)
        let offscreen = try TimelineHomeRouteConstructionPlanConsumer.decodeFixtureJSON(offscreenData)

        #expect(described.isReady)
        #expect(described.constructionAllowed)
        #expect(described.constructionKind == .describedOnly)
        #expect(offscreen.constructionAllowed)
        #expect(offscreen.constructionKind == .offscreenOnly)
        #expect(offscreen.renderedRouteAfterConstruction == .legacy)
    }

    @Test("decodes blocked missing flag fixture JSON")
    func decodes_blocked_missing_flag_fixture_json() throws {
        let consumer = try consumer(for: readyResult(hasExplicitCollectionViewLaunchFlag: false))

        #expect(consumer.isReady == false)
        #expect(consumer.constructionAllowed == false)
        #expect(consumer.constructionKind == .productionClosed)
        #expect(consumer.blockedIssueKinds == [.explicitCollectionViewLaunchFlag])
        #expect(consumer.missingGateKinds == [.explicitCollectionViewLaunchFlag])
    }

    @Test("decodes blocked dirty snapshot fixture JSON")
    func decodes_blocked_dirty_snapshot_fixture_json() throws {
        let consumer = try consumer(for: dirtySnapshotResult())

        #expect(consumer.isReady == false)
        #expect(consumer.constructionAllowed == false)
        #expect(consumer.renderedRouteAfterConstruction == .legacy)
        #expect(consumer.routeActivationAllowed == false)
        #expect(consumer.blockedIssueKinds.contains(.renderedRouteLegacy))
        #expect(consumer.blockedIssueKinds.contains(.collectionViewRouteNotConstructed))
        #expect(consumer.blockedIssueKinds.contains(.artifactReleaseBlockerFlagsEmpty))
        #expect(consumer.blockedIssueKinds.contains(.sideEffectSentinelClean))
    }

    @Test("deterministic debug summary for ready plan")
    func deterministic_debug_summary_for_ready_plan() throws {
        let consumer = try consumer(for: readyResult(kind: .describedOnly))

        #expect(consumer.debugSummary.deterministicText == expectedReadyDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedReadyDebugSummary)
    }

    @Test("deterministic debug summary for blocked dirty snapshot")
    func deterministic_debug_summary_for_blocked_dirty_snapshot() throws {
        let consumer = try consumer(for: dirtySnapshotResult())

        #expect(consumer.debugSummary.deterministicText == expectedDirtySnapshotDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedDirtySnapshotDebugSummary)
    }

    @Test("query isReady constructionAllowed and activation flag")
    func query_is_ready_construction_allowed_and_activation_flag() throws {
        let ready = try consumer(for: readyResult())
        let blocked = try consumer(for: readyResult(hasExplicitCollectionViewLaunchFlag: false))

        #expect(ready.isReady)
        #expect(ready.constructionAllowed)
        #expect(ready.routeActivationAllowed == false)
        #expect(blocked.isReady == false)
        #expect(blocked.constructionAllowed == false)
        #expect(blocked.routeActivationAllowed == false)
    }

    @Test("rendered route after construction remains legacy")
    func rendered_route_after_construction_remains_legacy() throws {
        let consumers = try [
            consumer(for: readyResult()),
            consumer(for: readyResult(hasExplicitCollectionViewLaunchFlag: false)),
            consumer(for: dirtySnapshotResult())
        ]

        #expect(consumers.allSatisfy { $0.renderedRouteAfterConstruction == .legacy })
    }

    @Test("constructed flags all remain false")
    func constructed_flags_all_remain_false() throws {
        let consumer = try consumer(for: readyResult())

        #expect(consumer.collectionViewRouteConstructed == false)
        #expect(consumer.timelineSurfaceConstructed == false)
        #expect(consumer.timelineCollectionViewControllerConstructedFromRoot == false)
        #expect(consumer.debugSummary.collectionViewRouteConstructed == false)
        #expect(consumer.debugSummary.timelineSurfaceConstructed == false)
        #expect(consumer.debugSummary.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test("issue release blocker and side effect queries")
    func issue_release_blocker_and_side_effect_queries() throws {
        let consumer = try consumer(for: dirtySnapshotResult())

        #expect(consumer.blockedIssueKinds.contains(.artifactReleaseBlockerFlagsEmpty))
        #expect(consumer.releaseBlockerFlags == [.requiresNetworkWork])
        #expect(consumer.sideEffectFlags == .none)
        #expect(consumer.sideEffectFlags.networkStarted == false)
        #expect(consumer.sideEffectFlags.dbWriteAttempted == false)
        #expect(consumer.sideEffectFlags.readMarkerAdvanced == false)
        #expect(consumer.sideEffectFlags.dataSourceApplyCalled == false)
    }

    @Test("diagnostics artifact summary query")
    func diagnostics_artifact_summary_query() throws {
        let consumer = try consumer(for: readyResult())
        let artifact = consumer.diagnosticsArtifactSummary

        #expect(artifact.artifactKind == "timeline_home_route_decision")
        #expect(artifact.artifactVersion == 1)
        #expect(artifact.eventName == "timeline_home_route_preflight_decision")
        #expect(artifact.source == .rootPreflight)
        #expect(artifact.collectionViewAllowed)
        #expect(artifact.releaseBlockerFlags.isEmpty)
        #expect(consumer.artifactDeterministicSummary == expectedReadyArtifactSummary)
    }

    @Test("privacy forbidden fragments absent from encoded fixtures")
    func privacy_forbidden_fragments_absent_from_encoded_fixtures() throws {
        let resultJSON = try encodedJSONString(readyResult()).lowercased()
        let planJSON = try encodedJSONString(readyResult().plan).lowercased()
        let summaryJSON = try encodedJSONString((try consumer(for: readyResult())).debugSummary).lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!resultJSON.contains(fragment))
            #expect(!planJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("consumer is codable equatable sendable and pure source")
    func consumer_is_codable_equatable_sendable_and_pure_source() throws {
        let consumer = try consumer(for: readyResult())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeRouteConstructionReadinessConsumer.self,
            from: encoded
        )
        let source = try sourceFile(named: "TimelineHomeRouteConstructionPlanConsumer.swift")

        assertSendable(TimelineHomeRouteConstructionPlanConsumer.self)
        assertSendable(TimelineHomeRouteConstructionReadinessConsumer.self)
        assertSendable(TimelineHomeConstructionDebugSummary.self)
        #expect(decoded == consumer)
        #expect(!source.contains("AstrenzaRootView("))
        #expect(!source.contains("HomeTimelineView("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
        #expect(!source.contains("Timeline" + "Surface("))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("deleteItems"))
        #expect(!source.contains("insertItems"))
        #expect(!source.contains("advance" + "Read" + "Marker"))
        #expect(!source.contains("File" + "Manager"))
        #expect(!source.contains("write(to:"))
        #expect(!source.contains("upload"))
        #expect(!source.contains("telemetry"))
        #expect(!source.contains("analytics"))
    }

    private var expectedReadyArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedReadyDebugSummary: String {
        "isReady=true constructionAllowed=true constructionKind=describedOnly renderedRouteAfterConstruction=legacy routeActivationAllowed=false collectionViewRouteConstructed=false timelineSurfaceConstructed=false timelineCollectionViewControllerConstructedFromRoot=false blockedIssues=[] missingGates=[] releaseBlockers=[] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false) artifactSummary={\(expectedReadyArtifactSummary)}"
    }

    private var expectedDirtySnapshotDebugSummary: String {
        "isReady=false constructionAllowed=false constructionKind=productionClosed renderedRouteAfterConstruction=legacy routeActivationAllowed=false collectionViewRouteConstructed=false timelineSurfaceConstructed=false timelineCollectionViewControllerConstructedFromRoot=false blockedIssues=[renderedRouteLegacy,collectionViewRouteNotConstructed,sideEffectSentinelClean,artifactReleaseBlockerFlagsEmpty] missingGates=[renderedRouteLegacy,collectionViewRouteNotConstructed,sideEffectSentinelClean,artifactReleaseBlockerFlagsEmpty] releaseBlockers=[requiresNetworkWork] sideEffects(root=false,home=false,nostrStore=false,collectionView=false,network=false,dbWrite=false,readMarker=false,dataSourceApply=false) artifactSummary={kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[requiresNetworkWork]}"
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

    private func readyResult(
        kind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly,
        hasExplicitCollectionViewLaunchFlag: Bool = true
    ) -> TimelineHomeRouteConstructionReadinessResult {
        makeReadiness(
            hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
            preferredConstructionKind: kind
        ).evaluate()
    }

    private func dirtySnapshotResult() -> TimelineHomeRouteConstructionReadinessResult {
        var snapshot = makeSnapshot()
        snapshot.renderedRoute = .collectionViewPlaceholder
        snapshot.collectionViewRouteConstructed = true
        snapshot.sideEffectSentinel.networkStarted = true
        snapshot.artifactSummary.releaseBlockerFlags = [.requiresNetworkWork]
        snapshot.artifactSummary.deterministicSummary = [
            "kind=timeline_home_route_decision",
            "version=1",
            "event=timeline_home_route_preflight_decision",
            "source=rootPreflight",
            "route=collectionView",
            "requested=collectionView",
            "effective=collectionView",
            "fallback=false",
            "collectionViewAllowed=true",
            "missing=[]",
            "issues=[]",
            "runtimeAllowed=true",
            "rolloutAllowed=true",
            "blockers=[requiresNetworkWork]"
        ].joined(separator: " ")
        return makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
    }

    private func makeReadiness(
        hasExplicitCollectionViewLaunchFlag: Bool = true,
        rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot? = nil,
        preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly
    ) -> TimelineHomeRouteConstructionReadiness {
        TimelineHomeRouteConstructionReadiness(
            hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
            dependencies: .allAvailable,
            rootNoOpPreflightComplete: true,
            routeDiagnosticsSinkInjectionComplete: true,
            rootDecisionSnapshot: rootDecisionSnapshot ?? makeSnapshot(),
            snapshotConsumerAvailable: true,
            offscreenControllerSmokePassed: true,
            initialRestoreSnapshotCoordinatorHarnessPassed: true,
            startupNetworkPatternClean: true,
            selectedSwiftTestingSuitesNonZero: true,
            dataSourceApplyCoordinatorOnly: true,
            noExtraNostrHomeTimelineStore: true,
            artifactPrivacyGuardPassed: true,
            preferredConstructionKind: preferredConstructionKind
        )
    }

    private func makeSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: 1_735_000_003_100
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: 1_735_000_003_200
        )
    }

    private func consumer(
        for result: TimelineHomeRouteConstructionReadinessResult
    ) throws -> TimelineHomeRouteConstructionReadinessConsumer {
        try TimelineHomeRouteConstructionReadinessConsumer.decodeFixtureJSON(
            encodedData(result)
        )
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
