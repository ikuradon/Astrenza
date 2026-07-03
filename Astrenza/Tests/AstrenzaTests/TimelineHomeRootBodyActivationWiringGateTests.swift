import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome Root body activation wiring gate")
struct TimelineHomeRootBodyActivationWiringGateTests {
    @Test
    func root_body_wiring_requires_explicit_flag() {
        let result = evaluate(arguments: ["Astrenza"], activationSwitchResult: cleanActivationSwitchResult())

        #expect(result.wiringGateEvaluated)
        #expect(result.wiringAllowed == false)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(result.collectionViewRenderingActivated == false)
        #expect(result.issueKinds.contains(.explicitCollectionViewLaunchFlag))
    }

    @Test
    func root_body_wiring_requires_clean_activation_switch() {
        var activation = cleanActivationSwitchResult()
        activation.networkStarted = true
        activation.issueKinds = [.startupNetworkPatternClean]

        let result = evaluate(activationSwitchResult: activation)

        #expect(result.wiringAllowed == false)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(result.issueKinds.contains(.activationSwitchClean))
        #expect(result.collectionViewRenderingActivated == false)
    }

    @Test
    func default_without_flag_keeps_legacy() {
        let result = evaluate(arguments: ["Astrenza"], activationSwitchResult: cleanActivationSwitchResult())

        #expect(result.wiringAllowed == false)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(result.legacyHomeRenderingPreserved)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
    }

    @Test
    func dirty_activation_result_keeps_legacy() {
        var activation = cleanActivationSwitchResult()
        activation.dbWriteAttempted = true

        let result = evaluate(activationSwitchResult: activation)

        #expect(result.wiringAllowed == false)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(result.issueKinds.contains(.dbWriteNotAttempted))
        #expect(result.collectionViewRenderingActivated == false)
    }

    @Test
    func root_body_wiring_does_not_change_AstrenzaRootView_body_by_default() throws {
        let result = evaluate()
        let rootSource = try sourceFile(named: "AstrenzaRootView.swift")

        #expect(result.productionRootBodyChanged == false)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(rootSource.contains("var body: some View"))
        #expect(rootSource.contains("HomeTimelineView"))
        #expect(rootSource.contains("NostrHomeTimelineStore"))
        #expect(!rootSource.contains("TimelineHomeRootBodyActivationWiringGate.evaluate"))
        #expect(!rootSource.contains("renderedRouteDecision == .collectionView"))
        #expect(!rootSource.contains("Timeline" + "Surface("))
        #expect(!rootSource.contains("Timeline" + "CollectionViewController("))
    }

    @Test
    func root_body_wiring_does_not_start_network() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeRootBodyActivationWiringGate.swift")

        #expect(result.networkStarted == false)
        for token in forbiddenStartupNetworkTokens {
            #expect(!source.contains(token))
        }
    }

    @Test
    func root_body_wiring_does_not_write_db() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeRootBodyActivationWiringGate.swift")

        #expect(result.dbWriteAttempted == false)
        #expect(!source.contains("feed" + "_read" + "_state"))
        #expect(!source.contains("pending" + "_new"))
        #expect(!source.contains("resolve" + "_jobs"))
    }

    @Test
    func root_body_wiring_does_not_advance_read_marker() {
        let result = evaluate()

        #expect(result.readMarkerAdvanced == false)
        #expect(!result.issueKinds.contains(.readMarkerUnchanged))
    }

    @Test
    func root_body_wiring_does_not_call_dataSourceApply_from_Root() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeRootBodyActivationWiringGate.swift")

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test
    func root_body_wiring_does_not_construct_extra_NostrHomeTimelineStore() throws {
        let result = evaluate()
        let source = try sourceFile(named: "TimelineHomeRootBodyActivationWiringGate.swift")

        #expect(result.extraNostrHomeTimelineStoreConstructed == false)
        #expect(!source.contains("Nostr" + "HomeTimelineStore("))
    }

    @Test
    func root_body_wiring_prevents_same_session_double_mutation() {
        let result = evaluate()
        let dirty = evaluate(context: .defaultClean(mutatingLegacyAndCollectionViewInSameSession: true))

        #expect(result.sameSessionDoubleMutationPrevented)
        #expect(dirty.wiringAllowed == false)
        #expect(dirty.sameSessionDoubleMutationPrevented == false)
        #expect(dirty.issueKinds.contains(.sameSessionDoubleMutationPrevented))
    }

    @Test
    func rollback_and_manualFallback_are_legacy() {
        let result = evaluate()

        #expect(result.rollbackRoute == .legacy)
        #expect(result.manualFallbackRoute == .legacy)
        #expect(!result.issueKinds.contains(.rollbackRouteLegacy))
        #expect(!result.issueKinds.contains(.manualFallbackRouteLegacy))
    }

    @Test
    func clean_flagged_activation_marks_wiring_allowed_without_defaulting_collectionView() {
        let result = evaluate()

        #expect(result.wiringAllowed)
        #expect(result.renderedRouteDecision == .legacy)
        #expect(result.productionRootBodyChanged == false)
        #expect(result.legacyHomeRenderingPreserved)
        #expect(result.collectionViewRenderingActivated == false)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
    }

    @Test
    func wiring_result_records_activation_artifact_summary() {
        let result = evaluate()

        #expect(result.artifactSummary.activationSwitchSummary.contains("activationSwitchRenderedRoute=collectionView"))
        #expect(result.artifactSummary.activationSwitchSummary.contains("activationSwitchPerformed=true"))
        #expect(result.artifactSummary.rootBodySummary.contains("rootBodyRenderedRoute=legacy"))
        #expect(result.artifactSummary.deterministicSummary.contains("wiringAllowed=true"))
    }

    @Test
    func wiring_result_is_codable_privacy_safe() throws {
        let result = evaluate()
        let data = try encodedData(result)
        let decoded = try JSONDecoder().decode(TimelineHomeRootBodyActivationWiringResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        assertSendable(TimelineHomeRootBodyActivationWiringInput.self)
        assertSendable(TimelineHomeRootBodyActivationWiringContext.self)
        assertSendable(TimelineHomeRootBodyActivationWiringResult.self)
        assertSendable(TimelineHomeRootBodyActivationDecision.self)
        assertSendable(TimelineHomeRootBodyRenderSwitchGate.self)
        assertSendable(TimelineHomeRootBodyActivationWiringGate.self)
        #expect(decoded == result)
        #expect(Set(payload.keys) == requiredResultKeys)
        #expect(result.wiringGateEvaluated)
        #expect(result.activationPerformed == false)
        #expect(result.productionRenderSwitchPerformed == false)
        #expect(result.collectionViewRenderingActivated == false)

        for fragment in forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let uniqueSuites = Set(selectedSwiftTestingSuites)

        #expect(!selectedSwiftTestingSuites.isEmpty)
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootBodyActivationWiringGateTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeCollectionViewRouteActivationSwitchTests"))
        #expect(selectedSwiftTestingSuites.contains("TimelineHomeRootActivationDecisionSnapshotChainTests"))
        #expect(uniqueSuites.count == selectedSwiftTestingSuites.count)
        #expect(selectedSwiftTestingSuites.allSatisfy { !$0.isEmpty })
    }
}

private func evaluate(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
    activationSwitchResult: TimelineHomeActivatedRouteDecision? = cleanActivationSwitchResult(),
    context: TimelineHomeRootBodyActivationWiringContext = .defaultClean()
) -> TimelineHomeRootBodyActivationWiringResult {
    TimelineHomeRootBodyActivationWiringGate.evaluate(
        TimelineHomeRootBodyActivationWiringInput(
            launchArguments: arguments,
            activationSwitchResult: activationSwitchResult,
            context: context,
            createdAtMS: 1_735_000_020_000
        )
    )
}

private func cleanActivationSwitchResult() -> TimelineHomeActivatedRouteDecision {
    let routeDecision = TimelineHomeRootRenderRouteDecision(
        renderedRoute: .collectionView,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy
    )
    return TimelineHomeActivatedRouteDecision(
        activationWouldBeAllowed: true,
        activationPerformed: true,
        productionRenderSwitchPerformed: true,
        renderedRoute: .collectionView,
        rollbackRoute: .legacy,
        manualFallbackRoute: .legacy,
        routeDecision: routeDecision,
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
        createdAtMS: 1_735_000_020_000
    )
}

private let requiredResultKeys: Set<String> = [
    "wiringGateEvaluated",
    "wiringAllowed",
    "renderedRouteDecision",
    "productionRootBodyChanged",
    "legacyHomeRenderingPreserved",
    "collectionViewRenderingActivated",
    "sameSessionDoubleMutationPrevented",
    "rollbackRoute",
    "manualFallbackRoute",
    "activationPerformed",
    "productionRenderSwitchPerformed",
    "dataSourceApplyFromRootCalled",
    "networkStarted",
    "dbWriteAttempted",
    "readMarkerAdvanced",
    "extraNostrHomeTimelineStoreConstructed",
    "issueKinds",
    "artifactSummary",
    "createdAtMS"
]

private var selectedSwiftTestingSuites: [String] {
    [
        "TimelineHomeRootBodyActivationWiringGateTests",
        "TimelineHomeCollectionViewRouteActivationSwitchTests",
        "TimelineHomeRootActivationDecisionSnapshotChainConsumerTests",
        "TimelineHomeRootActivationDecisionSnapshotChainTests",
        "TimelineHomeRootActivationPreflightTests",
        "TimelineHomeActivationArtifactChainConsumerTests",
        "TimelineHomeCollectionViewRouteActivationReadinessConsumerTests",
        "TimelineHomeCollectionViewRouteActivationTests",
        "TimelineHomeCollectionViewRouteBehindFlagConstructionTests",
        "TimelineHomeConstructionArtifactChainConsumerTests",
        "TimelineHomeCollectionViewOffscreenConstructionHarnessResultConsumerTests",
        "TimelineHomeCollectionViewOffscreenConstructionHarnessTests",
        "TimelineHomeRouteConstructionPlanConsumerTests",
        "TimelineHomeRouteConstructionReadinessTests",
        "TimelineHomeCollectionViewRouteConstructionTests",
        "TimelineHomeRootRouteDecisionSnapshotConsumerTests",
        "TimelineHomeRootRouteDecisionSnapshotTests",
        "TimelineHomeRootRouteDiagnosticsSinkInjectionTests",
        "TimelineHomeRouteDiagnosticsSinkTests",
        "TimelineHomeRootRouteCallSiteTests",
        "TimelineHomeRootRoutePreflightTests",
        "TimelineHomeRootRouteGuardTests",
        "TimelineHomeRouteDiagnosticsTests",
        "TimelineHomeRouteHostTests",
        "TimelineHomeRouteIntegrationSkeletonTests",
        "TimelineHomeRouteAdapterTests",
        "TimelineHomeLaunchRestoreContractTests",
        "TimelineHomeEngineModeTests",
        "TimelineSurfaceDependencyContainerTests",
        "TimelineCollectionViewControllerSmokeTests",
        "TimelineInitialRestoreSnapshotCoordinatorHarnessTests",
        "TimelineEngineScaffoldTests"
    ]
}

private var forbiddenStartupNetworkTokens: [String] {
    [
        "Local" + "Data" + "Task",
        "ATS " + "failure",
        "n" + "w_",
        "Web" + "Socket",
        "URL" + "Session" + "Web" + "Socket" + "Task",
        "ws" + "s://",
        "set" + "Default" + "Relays",
        "URL" + "Session",
        "relay " + "connection " + "attempts"
    ]
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

private func sourceFile(named fileName: String) throws -> String {
    try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AstrenzaApp")
            .appendingPathComponent(fileName == "AstrenzaRootView.swift" ? fileName : "TimelineEngine/\(fileName)"),
        encoding: .utf8
    )
}

private func assertSendable<T: Sendable>(_: T.Type) {}
