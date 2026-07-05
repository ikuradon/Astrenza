import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome Root body activation wiring gate consumer")
struct TimelineHomeRootBodyActivationWiringGateConsumerTests {
    @Test("decodes clean wiring gate fixture JSON")
    func decodes_clean_wiring_gate_fixture_json() throws {
        let consumer = try makeConsumer(for: cleanWiringGateResult())

        #expect(consumer.wiringGateEvaluated)
        #expect(consumer.wiringAllowed)
        #expect(consumer.renderedRouteDecision == .legacy)
    }

    @Test("decodes blocked missing flag fixture JSON")
    func decodes_blocked_missing_flag_fixture_json() throws {
        let consumer = try makeConsumer(for: blockedMissingFlagResult())

        #expect(consumer.wiringAllowed == false)
        #expect(consumer.renderedRouteDecision == .legacy)
        #expect(consumer.issueKinds == [.explicitCollectionViewLaunchFlag])
    }

    @Test("decodes dirty activation fixture JSON")
    func decodes_dirty_activation_fixture_json() throws {
        let consumer = try makeConsumer(for: dirtyActivationResult())

        #expect(consumer.wiringAllowed == false)
        #expect(consumer.renderedRouteDecision == .legacy)
        #expect(consumer.issueKinds.contains(.activationSwitchClean))
        #expect(consumer.issueKinds.contains(.networkNotStarted))
        #expect(consumer.networkStarted)
    }

    @Test("deterministic debug summary for clean fixture")
    func deterministic_debug_summary_for_clean_fixture() throws {
        let consumer = try makeConsumer(for: cleanWiringGateResult())

        #expect(consumer.debugSummary.deterministicText == expectedCleanDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedCleanDebugSummary)
    }

    @Test("deterministic debug summary for blocked fixture")
    func deterministic_debug_summary_for_blocked_fixture() throws {
        let consumer = try makeConsumer(for: blockedMissingFlagResult())

        #expect(consumer.debugSummary.deterministicText == expectedBlockedMissingFlagDebugSummary)
        #expect(consumer.deterministicDebugSummary == expectedBlockedMissingFlagDebugSummary)
    }

    @Test("query wiringAllowed")
    func query_wiring_allowed() throws {
        let clean = try makeConsumer(for: cleanWiringGateResult())
        let blocked = try makeConsumer(for: blockedMissingFlagResult())

        #expect(clean.wiringAllowed)
        #expect(blocked.wiringAllowed == false)
    }

    @Test("query renderedRouteDecision equals legacy")
    func query_rendered_route_decision_equals_legacy() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.renderedRouteDecision == .legacy })
    }

    @Test("query productionRootBodyChanged remains false")
    func query_production_root_body_changed_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.productionRootBodyChanged == false })
    }

    @Test("query collectionViewRenderingActivated remains false")
    func query_collection_view_rendering_activated_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.collectionViewRenderingActivated == false })
    }

    @Test("query legacyHomeRenderingPreserved remains true")
    func query_legacy_home_rendering_preserved_remains_true() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.legacyHomeRenderingPreserved })
    }

    @Test("query sameSessionDoubleMutationPrevented remains true")
    func query_same_session_double_mutation_prevented_remains_true() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.sameSessionDoubleMutationPrevented })
    }

    @Test("query rollback and manualFallback remain legacy")
    func query_rollback_and_manual_fallback_remain_legacy() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.rollbackRoute == .legacy })
        #expect(consumers.allSatisfy { $0.manualFallbackRoute == .legacy })
    }

    @Test("query activationPerformed remains false")
    func query_activation_performed_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.activationPerformed == false })
    }

    @Test("query productionRenderSwitchPerformed remains false")
    func query_production_render_switch_performed_remains_false() throws {
        let consumers = try allFixtureConsumers()

        #expect(consumers.allSatisfy { $0.productionRenderSwitchPerformed == false })
    }

    @Test("query no network DB read-marker dataSource or store side effects")
    func query_no_network_db_read_marker_data_source_or_store_side_effects() throws {
        let consumer = try makeConsumer(for: cleanWiringGateResult())

        #expect(consumer.dataSourceApplyFromRootCalled == false)
        #expect(consumer.networkStarted == false)
        #expect(consumer.dbWriteAttempted == false)
        #expect(consumer.readMarkerAdvanced == false)
        #expect(consumer.extraNostrHomeTimelineStoreConstructed == false)
    }

    @Test("query issueKinds and artifactSummary")
    func query_issue_kinds_and_artifact_summary() throws {
        let clean = try makeConsumer(for: cleanWiringGateResult())
        let blocked = try makeConsumer(for: blockedMissingFlagResult())

        #expect(clean.issueKinds.isEmpty)
        #expect(clean.artifactSummary.deterministicSummary == expectedCleanArtifactSummary)
        #expect(blocked.issueKinds == [.explicitCollectionViewLaunchFlag])
        #expect(blocked.artifactSummary.deterministicSummary == expectedBlockedMissingFlagArtifactSummary)
    }

    @Test("privacy forbidden fragments absent from encoded result and summary")
    func privacy_forbidden_fragments_absent_from_encoded_result_and_summary() throws {
        let resultJSON = try encodedJSONString(cleanWiringGateResult()).lowercased()
        let summaryJSON = try encodedJSONString((try makeConsumer(for: cleanWiringGateResult())).debugSummary)
            .lowercased()

        for fragment in forbiddenPrivacyFragments {
            #expect(!resultJSON.contains(fragment))
            #expect(!summaryJSON.contains(fragment))
        }
    }

    @Test("no Root Home controller store or surface construction")
    func no_root_home_controller_store_or_surface_construction() throws {
        let consumer = try makeConsumer(for: cleanWiringGateResult())
        let encoded = try JSONEncoder().encode(consumer)
        let decoded = try JSONDecoder().decode(
            TimelineHomeRootBodyActivationWiringGateConsumer.self,
            from: encoded
        )
        let source = try sourceFile(named: "TimelineHomeRootBodyActivationWiringGateConsumer.swift")

        assertSendable(TimelineHomeRootBodyActivationWiringGateReader.self)
        assertSendable(TimelineHomeRootBodyActivationWiringGateConsumer.self)
        assertSendable(TimelineHomeRootBodyActivationWiringDebugSummary.self)
        #expect(decoded == consumer)
        #expect(!source.contains("AstrenzaRootView("))
        #expect(!source.contains("HomeTimelineView("))
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
        #expect(!source.contains("Timeline" + "Surface("))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("TimelineSurfaceDependencyContainer"))
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
}

private func makeConsumer(
    for result: TimelineHomeRootBodyActivationWiringResult
) throws -> TimelineHomeRootBodyActivationWiringGateConsumer {
    try TimelineHomeRootBodyActivationWiringGateConsumer.decodeFixtureJSON(
        encodedData(result)
    )
}

private func allFixtureConsumers() throws -> [TimelineHomeRootBodyActivationWiringGateConsumer] {
    try [
        makeConsumer(for: cleanWiringGateResult()),
        makeConsumer(for: blockedMissingFlagResult()),
        makeConsumer(for: dirtyActivationResult())
    ]
}

private func cleanWiringGateResult() -> TimelineHomeRootBodyActivationWiringResult {
    wiringGateResult(activationSwitchResult: cleanActivationSwitchResult())
}

private func blockedMissingFlagResult() -> TimelineHomeRootBodyActivationWiringResult {
    wiringGateResult(
        arguments: ["Astrenza"],
        activationSwitchResult: cleanActivationSwitchResult()
    )
}

private func dirtyActivationResult() -> TimelineHomeRootBodyActivationWiringResult {
    var activation = cleanActivationSwitchResult()
    activation.networkStarted = true
    activation.issueKinds = [.startupNetworkPatternClean]
    return wiringGateResult(activationSwitchResult: activation)
}

private func wiringGateResult(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    activationSwitchResult: TimelineHomeActivatedRouteDecision?,
    context: TimelineHomeRootBodyActivationWiringContext = .defaultClean()
) -> TimelineHomeRootBodyActivationWiringResult {
    TimelineHomeRootBodyActivationWiringGate.evaluate(
        TimelineHomeRootBodyActivationWiringInput(
            launchArguments: arguments,
            activationSwitchResult: activationSwitchResult,
            context: context,
            createdAtMS: 1_735_000_030_000
        )
    )
}

private func cleanActivationSwitchResult() -> TimelineHomeActivatedRouteDecision {
    TimelineHomeActivatedRouteDecision(
        activationWouldBeAllowed: true,
        activationPerformed: true,
        productionRenderSwitchPerformed: true,
        renderedRoute: .collectionView,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy,
        routeDecision: TimelineHomeRootRenderRouteDecision(
            renderedRoute: .collectionView,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy
        ),
        issueKinds: [],
        diagnostics: TimelineHomeCollectionViewRouteActivationSwitchDiagnostics(
            rootActivationDecisionSummary: "renderedRoute=legacy activationWouldBeAllowed=true",
            activationArtifactChainSummary: "activationWouldBeAllowed=true",
            activationReadinessSummary: "activationWouldBeAllowed=true",
            flaggedConstructionSummary: "constructionAllowed=true",
            constructionReadinessSummary: "collectionViewAllowed=true",
            offscreenHarnessSummary: "collectionViewAllowed=true",
            sideEffectSummary: "network=false,dbWrite=false,readMarker=false"
        ),
        routeDiagnosticsRecorded: true,
        activationArtifactChainRecorded: true,
        constructionArtifactChainRecorded: true,
        rootShellPresentation: .immediate,
        rootShellMustRenderBeforeTimelineRestore: true,
        timelineRestoreGateScope: .timelineArea,
        timelineGateCoversRootShell: false,
        timelineGateCoversTabBar: false,
        timelineGateContinuesGlobalSplash: false,
        networkStarted: false,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: false,
        readMarkerAdvanced: false,
        dbWriteAttempted: false,
        requiresNetworkWork: false,
        requiresDBWrite: false,
        dataSourceApplyFromRootCalled: false,
        forbiddenDataSourceApplyOutsideCoordinatorCalled: false,
        coordinatorOwnedDataSourceApplyAllowed: true,
        noExtraNostrHomeTimelineStore: true,
        preventsDualMutation: true,
        createdAtMS: 1_735_000_030_000
    )
}

private var expectedCleanDebugSummary: String {
    [
        "wiringGateEvaluated=true",
        "wiringAllowed=true",
        "renderedRouteDecision=legacy",
        "productionRootBodyChanged=false",
        "legacyHomeRenderingPreserved=true",
        "collectionViewRenderingActivated=false",
        "sameSessionDoubleMutationPrevented=true",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "sideEffects(dataSourceApplyFromRoot=false,network=false,dbWrite=false,readMarker=false,extraNostrStore=false)",
        "issueKinds=[]",
        "artifactSummary={\(expectedCleanArtifactSummary)}"
    ].joined(separator: " ")
}

private var expectedBlockedMissingFlagDebugSummary: String {
    [
        "wiringGateEvaluated=true",
        "wiringAllowed=false",
        "renderedRouteDecision=legacy",
        "productionRootBodyChanged=false",
        "legacyHomeRenderingPreserved=true",
        "collectionViewRenderingActivated=false",
        "sameSessionDoubleMutationPrevented=true",
        "rollbackRoute=legacy",
        "manualFallbackRoute=legacy",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "sideEffects(dataSourceApplyFromRoot=false,network=false,dbWrite=false,readMarker=false,extraNostrStore=false)",
        "issueKinds=[explicitCollectionViewLaunchFlag]",
        "artifactSummary={\(expectedBlockedMissingFlagArtifactSummary)}"
    ].joined(separator: " ")
}

private var expectedCleanArtifactSummary: String {
    [
        "wiringGateEvaluated=true",
        "wiringAllowed=true",
        "renderedRouteDecision=legacy",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "issues=[]",
        "activationSwitch={activationSwitchPresent=true activationSwitchAllowed=true activationSwitchRenderedRoute=collectionView activationSwitchPerformed=true activationSwitchRenderSwitch=true}",
        "rootBody={rootBodyRenderedRoute=legacy productionRootBodyChanged=false legacyHomeRenderingPreserved=true collectionViewRenderingActivated=false sameSessionDoubleMutationPrevented=true}"
    ].joined(separator: " ")
}

private var expectedBlockedMissingFlagArtifactSummary: String {
    [
        "wiringGateEvaluated=true",
        "wiringAllowed=false",
        "renderedRouteDecision=legacy",
        "activationPerformed=false",
        "productionRenderSwitchPerformed=false",
        "issues=[explicitCollectionViewLaunchFlag]",
        "activationSwitch={activationSwitchPresent=true activationSwitchAllowed=true activationSwitchRenderedRoute=collectionView activationSwitchPerformed=true activationSwitchRenderSwitch=true}",
        "rootBody={rootBodyRenderedRoute=legacy productionRootBodyChanged=false legacyHomeRenderingPreserved=true collectionViewRenderingActivated=false sameSessionDoubleMutationPrevented=true}"
    ].joined(separator: " ")
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
        "event_id",
        "bearer"
    ]
}

private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    try #require(String(data: encodedData(value), encoding: .utf8))
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
