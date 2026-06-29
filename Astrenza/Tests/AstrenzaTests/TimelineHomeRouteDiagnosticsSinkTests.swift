import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRouteDiagnosticsSink")
struct TimelineHomeRouteDiagnosticsSinkTests {
    @Test("sink starts empty")
    func sinkStartsEmpty() {
        let sink = TimelineHomeRouteDiagnosticsSink()

        #expect(sink.retentionLimit == 10)
        #expect(sink.records.isEmpty)
        #expect(sink.latestDebugSummary == nil)
        #expect(sink.export() == nil)
        #expect(sink.collectionViewAllowed == false)
        #expect(sink.legacyFallback == false)
        #expect(sink.missingDependencies.isEmpty)
        #expect(sink.releaseBlockerFlags.isEmpty)
    }

    @Test("record appends local route artifact and exports newest summary")
    func recordAppendsLocalRouteArtifactAndExportsNewestSummary() throws {
        var sink = TimelineHomeRouteDiagnosticsSink()
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_000_500,
            source: .rootPreflight
        )

        sink.record(artifact)
        let export = try #require(sink.export())
        let summary = try #require(sink.latestDebugSummary)

        #expect(sink.records == [artifact])
        #expect(export.artifacts == [artifact])
        #expect(export.summary == artifact.summary)
        #expect(summary.artifactKind == "timeline_home_route_decision")
        #expect(summary.artifactVersion == 1)
        #expect(summary.eventName == "timeline_home_route_preflight_decision")
        #expect(summary.source == .rootPreflight)
        #expect(summary.createdAtMS == 1_735_000_000_500)
        #expect(summary.collectionViewAllowed)
        #expect(summary.recordCount == 1)
        #expect(summary.retentionLimit == 10)
    }

    @Test("bounded retention keeps deterministic newest-last ordering")
    func boundedRetentionKeepsDeterministicNewestLastOrdering() {
        var sink = TimelineHomeRouteDiagnosticsSink(retentionLimit: 3)

        for index in 0..<5 {
            sink.record(routeArtifact(
                arguments: ["Astrenza", "--timeline-engine=legacy"],
                createdAtMS: Int64(1_735_000_000_600 + index),
                source: .testFixture
            ))
        }

        #expect(sink.records.map(\.createdAtMS) == [
            1_735_000_000_602,
            1_735_000_000_603,
            1_735_000_000_604
        ])
        #expect(sink.latestDebugSummary?.createdAtMS == 1_735_000_000_604)
        #expect(sink.latestDebugSummary?.recordCount == 3)
    }

    @Test("latest debug summary is deterministic")
    func latestDebugSummaryIsDeterministic() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        dependencies.runtimeGuardAllowsCollectionView = false

        var sink = TimelineHomeRouteDiagnosticsSink(retentionLimit: 2)
        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies,
            createdAtMS: 1_735_000_000_700,
            source: .rootPreflight
        ))

        let summary = try #require(sink.latestDebugSummary)

        #expect(summary == TimelineHomeRouteDiagnosticsDebugSummary(
            artifactKind: "timeline_home_route_decision",
            artifactVersion: 1,
            eventName: "timeline_home_route_preflight_decision",
            source: .rootPreflight,
            createdAtMS: 1_735_000_000_700,
            selectedRoute: .legacy,
            requestedMode: .collectionView,
            effectiveMode: .legacy,
            collectionViewAllowed: false,
            legacyFallback: true,
            missingDependencies: ["repositoryStore"],
            fallbackIssueKinds: [.repositoryStoreUnavailable, .runtimeGuardDisabled],
            runtimeAllowed: false,
            rolloutAllowed: true,
            releaseBlockerFlags: [],
            recordCount: 1,
            retentionLimit: 2
        ))
        #expect(sink.debugSummary() == "kind=timeline_home_route_decision version=1 event=timeline_home_route_preflight_decision source=rootPreflight route=legacy requested=collectionView effective=legacy fallback=true missing=[repositoryStore] issues=[repositoryStoreUnavailable,runtimeGuardDisabled] runtimeAllowed=false rolloutAllowed=true blockers=[] records=1 retention=2")
    }

    @Test("sink export models are Codable Equatable and Sendable")
    func sinkExportModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRouteDiagnosticsSink.self)
        assertSendable(TimelineHomeRouteDiagnosticsDebugSummary.self)
        assertSendable(TimelineHomeRouteDecisionArtifactSource.self)

        var sink = TimelineHomeRouteDiagnosticsSink()
        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_000_800,
            source: .testFixture
        ))

        let sinkData = try JSONEncoder().encode(sink)
        let decodedSink = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsSink.self, from: sinkData)
        let export = try #require(sink.export())
        let exportData = try JSONEncoder().encode(export)
        let decodedExport = try JSONDecoder().decode(TimelineHomeRouteDiagnosticsExport.self, from: exportData)

        #expect(decodedSink == sink)
        #expect(decodedExport == export)
    }

    @Test("legacy route artifact JSON decodes with metadata defaults")
    func legacyRouteArtifactJSONDecodesWithMetadataDefaults() throws {
        let artifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_000_850,
            source: .testFixture
        )
        let data = try JSONEncoder().encode(artifact)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "artifactKind")
        object.removeValue(forKey: "artifactVersion")
        object.removeValue(forKey: "eventName")
        object.removeValue(forKey: "source")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let decoded = try JSONDecoder().decode(
            TimelineHomeRouteDecisionArtifact.self,
            from: legacyData
        )

        #expect(decoded.artifactKind == TimelineHomeRouteDecisionArtifact.artifactKind)
        #expect(decoded.artifactVersion == TimelineHomeRouteDecisionArtifact.artifactVersion)
        #expect(decoded.eventName == TimelineHomeRouteDecisionArtifact.eventName)
        #expect(decoded.source == .routeHost)
        #expect(decoded.schemaVersion == artifact.schemaVersion)
        #expect(decoded.createdAtMS == artifact.createdAtMS)
        #expect(decoded.record == artifact.record)
        #expect(decoded.summary == artifact.summary)
    }

    @Test("route decision metadata naming semantics are fixed")
    func routeDecisionMetadataNamingSemanticsAreFixed() {
        let artifact = routeArtifact(
            arguments: ["Astrenza"],
            createdAtMS: 1_735_000_000_900,
            source: .rootPreflight
        )

        #expect(TimelineHomeRouteDecisionArtifact.artifactKind == "timeline_home_route_decision")
        #expect(TimelineHomeRouteDecisionArtifact.artifactVersion == 1)
        #expect(TimelineHomeRouteDecisionArtifact.eventName == "timeline_home_route_preflight_decision")
        #expect(artifact.artifactKind == TimelineHomeRouteDecisionArtifact.artifactKind)
        #expect(artifact.artifactVersion == TimelineHomeRouteDecisionArtifact.artifactVersion)
        #expect(artifact.eventName == TimelineHomeRouteDecisionArtifact.eventName)
        #expect(artifact.source == .rootPreflight)
    }

    @Test("consumer queries expose allowed fallback missing dependencies and blockers")
    func consumerQueriesExposeAllowedFallbackMissingDependenciesAndBlockers() {
        var sink = TimelineHomeRouteDiagnosticsSink()

        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_001_000,
            source: .testFixture
        ))
        #expect(sink.collectionViewAllowed)
        #expect(sink.legacyFallback == false)

        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false
        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies,
            createdAtMS: 1_735_000_001_001,
            source: .testFixture
        ))
        #expect(sink.collectionViewAllowed == false)
        #expect(sink.legacyFallback)
        #expect(sink.missingDependencies == ["repositoryStore"])

        var blockerArtifact = routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_001_002,
            source: .testFixture
        )
        blockerArtifact.record.preventsDualMutation = false
        blockerArtifact.record.readMarkerChanged = true
        blockerArtifact.record.requiresNetworkWork = true
        blockerArtifact.record.requiresDBWrite = true
        blockerArtifact.summary = .make(from: blockerArtifact.record)
        sink.record(blockerArtifact)

        #expect(sink.releaseBlockerFlags == [
            .dualMutationNotPrevented,
            .readMarkerChanged,
            .requiresNetworkWork,
            .requiresDBWrite
        ])
    }

    @Test("clear removes records")
    func clearRemovesRecords() {
        var sink = TimelineHomeRouteDiagnosticsSink()
        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_001_100,
            source: .testFixture
        ))

        sink.clear()

        #expect(sink.records.isEmpty)
        #expect(sink.latestDebugSummary == nil)
        #expect(sink.export() == nil)
    }

    @Test("safe encoded sink export omits privacy forbidden fragments")
    func safeEncodedSinkExportOmitsPrivacyForbiddenFragments() throws {
        var sink = TimelineHomeRouteDiagnosticsSink()
        sink.record(routeArtifact(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            createdAtMS: 1_735_000_001_200,
            source: .rootPreflight
        ))
        let export = try #require(sink.export())
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
            "nostr secret",
            "raw event content phrase",
            "private message content phrase"
        ]

        for fragment in forbiddenFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test("sink source has no file network upload db write read marker or apply path")
    func sinkSourceHasNoFileNetworkUploadDBWriteReadMarkerOrApplyPath() throws {
        let source = try sourceFile(named: "TimelineHomeRouteDiagnosticsSink.swift")

        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("Local" + "Data" + "Task"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("File" + "Manager"))
        #expect(!source.contains("write" + "(to:"))
        #expect(!source.contains("upload"))
        #expect(!source.contains("remote" + "Logging"))
        #expect(!source.contains("analytics"))
        #expect(!source.contains("GR" + "DB"))
        #expect(!source.contains("INSERT"))
        #expect(!source.contains("UPDATE"))
        #expect(!source.contains("DELETE"))
        #expect(!source.contains("CREATE"))
        #expect(!source.contains("DROP"))
        #expect(!source.contains("ALTER"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
        #expect(!source.contains("read" + "Marker"))
    }

    private func routeArtifact(
        arguments: [String],
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable,
        createdAtMS: Int64,
        source: TimelineHomeRouteDecisionArtifactSource
    ) -> TimelineHomeRouteDecisionArtifact {
        TimelineHomeRouteDecisionArtifact.make(
            from: TimelineHomeRouteHost.decide(TimelineHomeRouteHostInput(
                launchArguments: arguments,
                debugOverride: nil,
                dependencies: dependencies
            )),
            createdAtMS: createdAtMS,
            source: source
        )
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
