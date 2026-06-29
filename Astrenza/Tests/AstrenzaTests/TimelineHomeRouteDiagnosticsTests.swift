import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRouteDiagnostics")
struct TimelineHomeRouteDiagnosticsTests {
    @Test("collectionView allowed decision exports collectionView without fallback issue")
    func collectionViewAllowedDecisionExportsCollectionViewWithoutFallbackIssue() {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"]
        )

        #expect(artifact.record.selectedRoute == .collectionView)
        #expect(artifact.record.requestedMode == .collectionView)
        #expect(artifact.record.effectiveMode == .collectionView)
        #expect(artifact.record.launchArgumentValue == "collectionView")
        #expect(artifact.record.launchArgumentSource == .recognized)
        #expect(artifact.record.isFallback == false)
        #expect(artifact.record.fallbackIssueKinds.isEmpty)
        #expect(artifact.record.timelineRestoreGateScope == .timelineArea)
        #expect(artifact.summary.collectionViewAllowed)
    }

    @Test("default legacy decision exports legacy without fallback")
    func defaultLegacyDecisionExportsLegacyWithoutFallback() {
        let artifact = routeArtifact(arguments: ["Astrenza"])

        #expect(artifact.record.selectedRoute == .legacy)
        #expect(artifact.record.requestedMode == .legacy)
        #expect(artifact.record.effectiveMode == .legacy)
        #expect(artifact.record.launchArgumentValue == nil)
        #expect(artifact.record.launchArgumentSource == .absent)
        #expect(artifact.record.isFallback == false)
        #expect(artifact.summary.legacyFallback == false)
    }

    @Test("unknown flag fallback exports parser issue without raw launch value")
    func unknownFlagFallbackExportsParserIssueWithoutRawLaunchValue() throws {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=nsec-secret-raw_json-privateKey"]
        )
        let json = try encodedJSONString(artifact)

        #expect(artifact.record.selectedRoute == .legacy)
        #expect(artifact.record.requestedMode == .unknown)
        #expect(artifact.record.isFallback)
        #expect(artifact.record.launchArgumentSource == .unknownRedacted)
        #expect(artifact.record.launchArgumentValue == nil)
        #expect(artifact.record.fallbackIssueKinds == [.unknownTimelineEngineMode])
        #expect(!json.localizedCaseInsensitiveContains("nsec"))
        #expect(!json.localizedCaseInsensitiveContains("secret"))
        #expect(!json.localizedCaseInsensitiveContains("raw_json"))
        #expect(!json.localizedCaseInsensitiveContains("privateKey"))
    }

    @Test("missing dependency fallback exports dependency names")
    func missingDependencyFallbackExportsDependencyNames() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        dependencies.diagnosticsSinkAvailable = false

        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(artifact.record.selectedRoute == .legacy)
        #expect(artifact.record.isFallback)
        #expect(artifact.record.fallbackIssueKinds == [
            .repositoryStoreUnavailable,
            .diagnosticsSinkUnavailable
        ])
        #expect(artifact.record.dependencyReadiness.missingDependencies == [
            "repositoryStore",
            "diagnosticsSink"
        ])
        #expect(artifact.summary.missingDependencies == [
            "repositoryStore",
            "diagnosticsSink"
        ])
    }

    @Test("runtime disabled fallback exports runtime issue")
    func runtimeDisabledFallbackExportsRuntimeIssue() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(artifact.record.selectedRoute == .legacy)
        #expect(artifact.record.runtimeAllowed == false)
        #expect(artifact.record.fallbackIssueKinds == [.runtimeGuardDisabled])
        #expect(artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("rollout blocked fallback exports rollout issue")
    func rolloutBlockedFallbackExportsRolloutIssue() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(artifact.record.selectedRoute == .legacy)
        #expect(artifact.record.rolloutAllowed == false)
        #expect(artifact.record.fallbackIssueKinds == [.rolloutBlocked])
        #expect(artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("debug override source is represented")
    func debugOverrideSourceIsRepresented() {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=legacy"],
            debugOverride: .collectionView
        )

        #expect(artifact.record.selectedRoute == .collectionView)
        #expect(artifact.record.debugOverride == .collectionView)
        #expect(artifact.record.decisionSource == .debugOverride)
        #expect(artifact.record.launchArgumentValue == "legacy")
    }

    @Test("route decision side effect flags stay closed")
    func routeDecisionSideEffectFlagsStayClosed() {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"]
        )

        #expect(artifact.record.preventsDualMutation)
        #expect(artifact.record.readMarkerChanged == false)
        #expect(artifact.record.requiresNetworkWork == false)
        #expect(artifact.record.requiresDBWrite == false)
        #expect(artifact.record.rootShellBehavior == .unchangedImmediate)
        #expect(artifact.record.rootShellBehaviorUnchanged)
        #expect(artifact.record.hostSideEffects.instantiatesRoot == false)
        #expect(artifact.record.hostSideEffects.instantiatesLegacyHomeStore == false)
        #expect(artifact.record.hostSideEffects.instantiatesCollectionViewController == false)
        #expect(artifact.record.hostSideEffects.startsNetworkWork == false)
        #expect(artifact.record.hostSideEffects.performsDatabaseMutation == false)
        #expect(artifact.record.hostSideEffects.advancesReadMarker == false)
        #expect(artifact.record.hostSideEffects.callsDataSourceApply == false)
        #expect(artifact.summary.releaseBlockerFlags.isEmpty)
    }

    @Test("consumer decodes fixture JSON and answers route questions")
    func consumerDecodesFixtureJSONAndAnswersRouteQuestions() throws {
        let export = TimelineHomeRouteDiagnosticsExport.make(
            from: hostDecision(
                arguments: ["Astrenza", "--timeline-engine=collectionView"]
            ),
            createdAtMS: 1_735_000_000_180
        )
        let data = try JSONEncoder().encode(export)
        let consumer = try TimelineHomeRouteDiagnosticsConsumer.decodeFixtureJSON(data)

        #expect(consumer.collectionViewAllowed)
        #expect(consumer.legacyFallback == false)
        #expect(consumer.missingDependencies.isEmpty)
        #expect(consumer.releaseBlockerFlags.isEmpty)
    }

    @Test("consumer debug summary is deterministic")
    func consumerDebugSummaryIsDeterministic() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        dependencies.runtimeGuardAllowsCollectionView = false

        let export = TimelineHomeRouteDiagnosticsExport.make(
            from: hostDecision(
                arguments: ["Astrenza", "--timeline-engine=collectionView"],
                dependencies: dependencies
            ),
            createdAtMS: 1_735_000_000_180
        )
        let consumer = TimelineHomeRouteDiagnosticsConsumer(export: export)

        #expect(consumer.debugSummary() == """
        route=legacy requested=collectionView effective=legacy fallback=true missing=[repositoryStore] issues=[repositoryStoreUnavailable,runtimeGuardDisabled] runtimeAllowed=false rolloutAllowed=true sideEffects(network=false,dbWrite=false,readMarker=false,dualMutationPrevented=true) root=unchangedImmediate restoreGate=none blockers=[]
        """)
    }

    @Test("privacy forbidden fragments are absent from encoded artifact JSON")
    func privacyForbiddenFragmentsAreAbsentFromEncodedArtifactJSON() throws {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"]
        )
        let json = try encodedJSONString(artifact).lowercased()
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
            "nostr secret",
            "raw event content phrase",
            "private message content phrase"
        ]

        for fragment in forbiddenFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test("consumer detects release blocker flags when side effect flags are unsafe")
    func consumerDetectsReleaseBlockerFlagsWhenSideEffectFlagsAreUnsafe() {
        var artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"]
        )
        artifact.record.preventsDualMutation = false
        artifact.record.readMarkerChanged = true
        artifact.record.requiresNetworkWork = true
        artifact.record.requiresDBWrite = true
        artifact.summary = .make(from: artifact.record)
        let export = TimelineHomeRouteDiagnosticsExport(
            artifacts: [artifact],
            summary: artifact.summary
        )
        let consumer = TimelineHomeRouteDiagnosticsConsumer(export: export)

        #expect(consumer.releaseBlockerFlags == [
            .dualMutationNotPrevented,
            .readMarkerChanged,
            .requiresNetworkWork,
            .requiresDBWrite
        ])
    }

    @Test("diagnostics models are Codable Equatable and Sendable")
    func diagnosticsModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRouteDiagnosticRecord.self)
        assertSendable(TimelineHomeRouteDiagnosticsExport.self)
        assertSendable(TimelineHomeRouteDecisionArtifact.self)
        assertSendable(TimelineHomeRouteDiagnosticsConsumer.self)
        assertSendable(TimelineHomeRouteDecisionSummary.self)

        let export = TimelineHomeRouteDiagnosticsExport.make(
            from: hostDecision(
                arguments: ["Astrenza", "--timeline-engine=collectionView"]
            ),
            createdAtMS: 1_735_000_000_180
        )
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: data)

        #expect(decoded == export)
    }

    @Test("route diagnostics source has no network upload or controller instantiation path")
    func routeDiagnosticsSourceHasNoNetworkUploadOrControllerInstantiationPath() throws {
        let source = try sourceFile(named: "TimelineHomeRouteDiagnostics.swift")

        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("Local" + "Data" + "Task"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("upload"))
        #expect(!source.contains("remote" + "Logging"))
        #expect(!source.contains("analytics"))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
    }

    private func routeArtifact(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRouteDecisionArtifact {
        TimelineHomeRouteDecisionArtifact.make(
            from: hostDecision(
                arguments: arguments,
                debugOverride: debugOverride,
                dependencies: dependencies
            ),
            createdAtMS: 1_735_000_000_180
        )
    }

    private func hostDecision(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRouteHostDecision {
        TimelineHomeRouteHost.decide(TimelineHomeRouteHostInput(
            launchArguments: arguments,
            debugOverride: debugOverride,
            dependencies: dependencies
        ))
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

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
