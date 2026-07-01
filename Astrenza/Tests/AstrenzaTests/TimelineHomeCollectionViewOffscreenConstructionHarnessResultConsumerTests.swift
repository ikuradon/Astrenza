import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView offscreen construction harness result consumer")
struct TimelineHomeCollectionViewOffscreenConstructionHarnessResultConsumerTests {
    @Test("decodes allowed offscreen/no-window result fixture")
    func decodes_allowed_offscreen_no_window_result_fixture() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.isAllowed)
        #expect(consumer.rejectionIssueKinds.isEmpty)
        #expect(consumer.constructionKind == .offscreenOnly)
        #expect(consumer.noWindowAttached)
        #expect(consumer.controllerItemIDs == ["note:visible"])
    }

    @Test("decodes blocked missing flag result fixture")
    func decodes_blocked_missing_flag_result_fixture() throws {
        let consumer = try makeConsumer(for: blockedMissingFlagResult())

        #expect(consumer.isAllowed == false)
        #expect(consumer.rejectionIssueKinds == [
            .readinessBlocked,
            .unsupportedConstructionKind,
            .constructionPlanClosed
        ])
        #expect(consumer.constructionKind == .productionClosed)
    }

    @Test("decodes blocked dirty snapshot result fixture")
    func decodes_blocked_dirty_snapshot_result_fixture() throws {
        let consumer = try makeConsumer(for: blockedDirtySnapshotResult())

        #expect(consumer.isAllowed == false)
        #expect(consumer.rejectionIssueKinds == [
            .readinessBlocked,
            .unsupportedConstructionKind,
            .constructionPlanClosed
        ])
        #expect(consumer.diagnosticsArtifactSummary.releaseBlockerFlags == [.requiresNetworkWork])
    }

    @Test("decodes activation-open rejected result fixture")
    func decodes_activation_open_rejected_result_fixture() throws {
        let consumer = try makeConsumer(for: activationOpenResult())

        #expect(consumer.isAllowed == false)
        #expect(consumer.rejectionIssueKinds == [.routeActivationOpen, .constructionPlanClosed])
        #expect(consumer.routeActivationAllowed)
    }

    @Test("deterministic debug summary for allowed result")
    func deterministic_debug_summary_for_allowed_result() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.debugSummary.deterministicText == expectedAllowedDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedAllowedDebugSummary)
    }

    @Test("deterministic debug summary for blocked result")
    func deterministic_debug_summary_for_blocked_result() throws {
        let consumer = try makeConsumer(for: blockedDirtySnapshotResult())

        #expect(consumer.debugSummary.deterministicText == expectedBlockedDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedBlockedDebugSummary)
    }

    @Test("query allowed and rejected state")
    func query_allowed_and_rejected_state() throws {
        let allowed = try makeConsumer(for: allowedResult())
        let blocked = try makeConsumer(for: blockedMissingFlagResult())

        #expect(allowed.isAllowed)
        #expect(allowed.rejectionIssueKinds.isEmpty)
        #expect(blocked.isAllowed == false)
        #expect(blocked.rejectionIssueKinds.contains(.readinessBlocked))
    }

    @Test("query noWindowAttached")
    func query_no_window_attached() throws {
        let allowed = try makeConsumer(for: allowedResult())
        let blocked = try makeConsumer(for: blockedMissingFlagResult())

        #expect(allowed.noWindowAttached)
        #expect(blocked.noWindowAttached == false)
    }

    @Test("query renderedRouteAfterConstruction equals legacy")
    func query_rendered_route_after_construction_equals_legacy() throws {
        let consumers = try [
            makeConsumer(for: allowedResult()),
            makeConsumer(for: blockedMissingFlagResult()),
            makeConsumer(for: blockedDirtySnapshotResult()),
            makeConsumer(for: activationOpenResult())
        ]

        #expect(consumers.allSatisfy { $0.renderedRouteAfterConstruction == .legacy })
    }

    @Test("query routeActivationAllowed equals false")
    func query_route_activation_allowed_equals_false() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.routeActivationAllowed == false)
    }

    @Test("query Root construction flags all false")
    func query_root_construction_flags_all_false() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.collectionViewRouteConstructedFromRoot == false)
        #expect(consumer.timelineSurfaceConstructedFromRoot == false)
        #expect(consumer.timelineCollectionViewControllerConstructedFromRoot == false)
        #expect(consumer.debugSummary.collectionViewRouteConstructedFromRoot == false)
        #expect(consumer.debugSummary.timelineSurfaceConstructedFromRoot == false)
        #expect(consumer.debugSummary.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test("query coordinator-owned apply vs forbidden direct apply")
    func query_coordinator_owned_apply_vs_forbidden_direct_apply() throws {
        let consumer = try makeConsumer(for: allowedResult())
        let directApply = try makeConsumer(for: forbiddenDirectApplyResult())

        #expect(consumer.coordinatorOwnedDataSourceApplyAllowed)
        #expect(consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
        #expect(directApply.coordinatorOwnedDataSourceApplyAllowed == false)
        #expect(directApply.forbiddenDataSourceApplyOutsideCoordinatorCalled)
    }

    @Test("query network db read-marker side effects all false")
    func query_network_db_read_marker_side_effects_all_false() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.networkStarted == false)
        #expect(consumer.dbWriteAttempted == false)
        #expect(consumer.readMarkerAdvanced == false)
    }

    @Test("query diagnostics artifact summary")
    func query_diagnostics_artifact_summary() throws {
        let consumer = try makeConsumer(for: allowedResult())

        #expect(consumer.diagnosticsArtifactSummary.artifactKind == "timeline_home_route_decision")
        #expect(consumer.diagnosticsArtifactSummary.artifactVersion == 1)
        #expect(consumer.diagnosticsArtifactSummary.eventName == "timeline_home_route_preflight_decision")
        #expect(consumer.diagnosticsArtifactSummary.source == .rootPreflight)
        #expect(consumer.diagnosticsArtifactSummary.collectionViewAllowed)
        #expect(consumer.artifactDeterministicSummary == expectedAllowedArtifactSummary)
    }

    @Test("privacy forbidden fragments absent from encoded result and summary")
    func privacy_forbidden_fragments_absent_from_encoded_result_and_summary() throws {
        let resultJSON = try encodedJSONString(allowedResult()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: allowedResult())).debugSummary).lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!resultJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: allowedResult())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeOffscreenConstructionHarnessResultConsumer.self,
            from: encoded
        )
        let source = try sourceFile(
            named: "TimelineHomeOffscreenConstructionHarnessResultConsumer.swift"
        )

        assertSendable(TimelineHomeOffscreenConstructionHarnessResult.self)
        assertSendable(TimelineHomeOffscreenConstructionRejection.self)
        assertSendable(TimelineHomeCollectionViewOffscreenHarnessResultReader.self)
        assertSendable(TimelineHomeOffscreenConstructionHarnessResultConsumer.self)
        assertSendable(TimelineHomeOffscreenConstructionDebugSummary.self)
        #expect(decoded == consumer)
        #expect(!source.contains("AstrenzaRootView("))
        #expect(!source.contains("HomeTimelineView("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
        #expect(!source.contains("Timeline" + "Surface("))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("TimelineSurfaceDependencyContainer"))
        #expect(!source.contains("repositoryStore"))
        #expect(!source.contains("fetchInitialWindow"))
        #expect(!source.contains("loadViewIfNeeded"))
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

    private var expectedAllowedArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[]"
    }

    private var expectedBlockedArtifactSummary: String {
        "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=collectionView requested=collectionView effective=collectionView fallback=false collectionViewAllowed=true missing=[] issues=[] runtimeAllowed=true rolloutAllowed=true blockers=[requiresNetworkWork]"
    }

    private var expectedAllowedDebugSummary: String {
        "allowed=true kind=offscreenOnly noWindow=true rendered=legacy activation=false rootFlags(route=false,surface=false,controller=false) sideEffects(network=false,dbWrite=false,readMarker=false,forbiddenDataSourceApply=false) coordinatorApplyAllowed=true offscreen(viewLoaded=true,attachedToWindow=false,itemIDs=[note:visible]) rejections=[] artifactSummary={\(expectedAllowedArtifactSummary)}"
    }

    private var expectedBlockedDebugSummary: String {
        "allowed=false kind=productionClosed noWindow=false rendered=legacy activation=false rootFlags(route=false,surface=false,controller=false) sideEffects(network=false,dbWrite=false,readMarker=false,forbiddenDataSourceApply=false) coordinatorApplyAllowed=false offscreen(viewLoaded=false,attachedToWindow=false,itemIDs=[]) rejections=[readinessBlocked,unsupportedConstructionKind,constructionPlanClosed] artifactSummary={\(expectedBlockedArtifactSummary)}"
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
            "event id",
            "eventid",
            "event_id"
        ]
    }

    private func allowedResult() -> TimelineHomeOffscreenConstructionHarnessResult {
        TimelineHomeOffscreenConstructionHarnessResult(
            offscreenConstructionAllowed: true,
            rejectionReasons: [],
            constructionKind: .offscreenOnly,
            renderedRouteAfterConstruction: .legacy,
            routeActivationAllowed: false,
            collectionViewRouteConstructedFromRoot: false,
            timelineSurfaceConstructedFromRoot: false,
            timelineCollectionViewControllerConstructedFromRoot: false,
            controllerLoadedOffscreen: true,
            isAttachedToWindow: false,
            networkStarted: false,
            dbWriteAttempted: false,
            readMarkerAdvanced: false,
            coordinatorOwnedDataSourceApplyAllowed: true,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
            controllerItemIDs: ["note:visible"],
            diagnosticsArtifactSummary: makeArtifactSummary()
        )
    }

    private func blockedMissingFlagResult() -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = allowedResult()
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.readinessBlocked, .unsupportedConstructionKind, .constructionPlanClosed]
        result.constructionKind = .productionClosed
        result.controllerLoadedOffscreen = false
        result.controllerItemIDs = []
        result.coordinatorOwnedDataSourceApplyAllowed = false
        return result
    }

    private func blockedDirtySnapshotResult() -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = blockedMissingFlagResult()
        result.diagnosticsArtifactSummary = makeArtifactSummary(releaseBlockerFlags: [.requiresNetworkWork])
        return result
    }

    private func activationOpenResult() -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = allowedResult()
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.routeActivationOpen, .constructionPlanClosed]
        result.routeActivationAllowed = true
        result.controllerLoadedOffscreen = false
        result.controllerItemIDs = []
        result.coordinatorOwnedDataSourceApplyAllowed = false
        return result
    }

    private func forbiddenDirectApplyResult() -> TimelineHomeOffscreenConstructionHarnessResult {
        var result = allowedResult()
        result.offscreenConstructionAllowed = false
        result.rejectionReasons = [.sideEffectFlagsDirty, .constructionPlanClosed]
        result.coordinatorOwnedDataSourceApplyAllowed = false
        result.forbiddenDataSourceApplyOutsideCoordinatorCalled = true
        return result
    }

    private func makeArtifactSummary(
        releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] = []
    ) -> TimelineHomeRootRouteArtifactSnapshot {
        var artifact = makeSnapshot().artifactSummary
        artifact.releaseBlockerFlags = releaseBlockerFlags
        artifact.deterministicSummary = [
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
            "blockers=\(releaseBlockerFlags.map(\.rawValue).debugList)"
        ].joined(separator: " ")
        return artifact
    }

    private func makeSnapshot() -> TimelineHomeRootRouteDecisionSnapshot {
        let result = TimelineHomeRootRouteCallSite.invoke(
            launchArguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: .allAvailable,
            createdAtMS: 1_735_000_004_100
        )
        return TimelineHomeRootRouteDecisionSnapshot.make(
            from: result,
            createdAtMS: 1_735_000_004_200
        )
    }

    private func makeConsumer(
        for result: TimelineHomeOffscreenConstructionHarnessResult
    ) throws -> TimelineHomeOffscreenConstructionHarnessResultConsumer {
        try TimelineHomeOffscreenConstructionHarnessResultConsumer.decodeFixtureJSON(
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

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
