import Foundation

enum TimelineHomeRouteDiagnosticDecisionSource: String, Codable, Equatable, Sendable {
    case defaultLegacy
    case launchArgument
    case debugOverride
}

enum TimelineHomeRouteLaunchArgumentDiagnosticSource: String, Codable, Equatable, Sendable {
    case absent
    case recognized
    case unknownRedacted
}

enum TimelineHomeRouteReleaseBlockerFlag: String, Codable, Equatable, Sendable {
    case dualMutationNotPrevented
    case readMarkerChanged
    case requiresNetworkWork
    case requiresDBWrite
    case rootShellChanged
    case hostInstantiatedRoot
    case hostInstantiatedLegacyHomeStore
    case hostInstantiatedCollectionViewController
    case hostStartedNetworkWork
    case hostPerformedDatabaseMutation
    case hostAdvancedReadMarker
    case hostCalledDataSourceApply
}

struct TimelineHomeRouteHostSideEffectDiagnosticRecord: Codable, Equatable, Sendable {
    var instantiatesRoot: Bool
    var instantiatesLegacyHomeStore: Bool
    var instantiatesCollectionViewController: Bool
    var startsNetworkWork: Bool
    var performsDatabaseMutation: Bool
    var advancesReadMarker: Bool
    var callsDataSourceApply: Bool

    static func make(
        from diagnostics: TimelineHomeRouteHostDiagnostics
    ) -> TimelineHomeRouteHostSideEffectDiagnosticRecord {
        TimelineHomeRouteHostSideEffectDiagnosticRecord(
            instantiatesRoot: diagnostics.instantiatesRoot,
            instantiatesLegacyHomeStore: diagnostics.instantiatesLegacyHomeStore,
            instantiatesCollectionViewController: diagnostics.instantiatesCollectionViewController,
            startsNetworkWork: diagnostics.startsNetworkWork,
            performsDatabaseMutation: diagnostics.performsDatabaseMutation,
            advancesReadMarker: diagnostics.advancesReadMarker,
            callsDataSourceApply: diagnostics.callsDataSourceApply
        )
    }
}

struct TimelineHomeRouteDependencyReadinessDiagnosticRecord: Codable, Equatable, Sendable {
    var allReady: Bool
    var repositoryStoreAvailable: Bool
    var windowComposerAvailable: Bool
    var restoreUseCaseAvailable: Bool
    var coordinatorAdapterAvailable: Bool
    var collectionViewControllerAvailable: Bool
    var diagnosticsSinkAvailable: Bool
    var runtimeGuardAllowsCollectionView: Bool
    var rolloutAllowsCollectionView: Bool
    var issueKinds: [TimelineHomeRouteDecisionIssue.Kind]
    var missingDependencies: [String]

    static func make(
        from readiness: TimelineHomeRouteDependencyReadinessSummary
    ) -> TimelineHomeRouteDependencyReadinessDiagnosticRecord {
        TimelineHomeRouteDependencyReadinessDiagnosticRecord(
            allReady: readiness.allReady,
            repositoryStoreAvailable: readiness.repositoryStoreAvailable,
            windowComposerAvailable: readiness.windowComposerAvailable,
            restoreUseCaseAvailable: readiness.restoreUseCaseAvailable,
            coordinatorAdapterAvailable: readiness.coordinatorAdapterAvailable,
            collectionViewControllerAvailable: readiness.collectionViewControllerAvailable,
            diagnosticsSinkAvailable: readiness.diagnosticsSinkAvailable,
            runtimeGuardAllowsCollectionView: readiness.runtimeGuardAllowsCollectionView,
            rolloutAllowsCollectionView: readiness.rolloutAllowsCollectionView,
            issueKinds: readiness.issueKinds,
            missingDependencies: readiness.issueKinds.compactMap(\.missingDependencyName)
        )
    }
}

struct TimelineHomeRouteDiagnosticRecord: Codable, Equatable, Sendable {
    var createdAtMS: Int64
    var selectedRoute: TimelineHomeRouteMode
    var requestedMode: TimelineHomeRouteMode
    var effectiveMode: TimelineHomeRouteMode
    var decisionSource: TimelineHomeRouteDiagnosticDecisionSource
    var launchArgumentSource: TimelineHomeRouteLaunchArgumentDiagnosticSource
    var launchArgumentValue: String?
    var debugOverride: TimelineHomeRouteDebugOverride?
    var dependencyReadiness: TimelineHomeRouteDependencyReadinessDiagnosticRecord
    var runtimeAllowed: Bool
    var rolloutAllowed: Bool
    var isFallback: Bool
    var fallbackIssueKinds: [TimelineHomeRouteDecisionIssue.Kind]
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var rootShellBehavior: TimelineHomeRouteRootShellBehavior
    var rootShellBehaviorUnchanged: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var hostSideEffects: TimelineHomeRouteHostSideEffectDiagnosticRecord

    static func make(
        from decision: TimelineHomeRouteHostDecision,
        createdAtMS: Int64
    ) -> TimelineHomeRouteDiagnosticRecord {
        let launchArgument = sanitizedLaunchArgument(
            from: decision.launchArgumentSource
        )
        let dependencyReadiness = TimelineHomeRouteDependencyReadinessDiagnosticRecord.make(
            from: decision.dependencyReadiness
        )

        return TimelineHomeRouteDiagnosticRecord(
            createdAtMS: createdAtMS,
            selectedRoute: decision.selectedRoute,
            requestedMode: decision.requestedMode,
            effectiveMode: decision.effectiveMode,
            decisionSource: diagnosticDecisionSource(from: decision),
            launchArgumentSource: launchArgument.source,
            launchArgumentValue: launchArgument.value,
            debugOverride: decision.debugOverrideSource.override,
            dependencyReadiness: dependencyReadiness,
            runtimeAllowed: dependencyReadiness.runtimeGuardAllowsCollectionView,
            rolloutAllowed: dependencyReadiness.rolloutAllowsCollectionView,
            isFallback: isFallback(decision),
            fallbackIssueKinds: decision.fallbackIssues.map(\.kind),
            preventsDualMutation: decision.preventsDualMutation,
            readMarkerChanged: decision.readMarkerChanged,
            requiresNetworkWork: decision.requiresNetworkWork,
            requiresDBWrite: decision.requiresDBWrite,
            rootShellBehavior: decision.rootShellBehavior,
            rootShellBehaviorUnchanged: decision.rootShellBehaviorUnchanged,
            timelineRestoreGateScope: decision.timelineRestoreGateScope,
            hostSideEffects: .make(from: decision.diagnostics)
        )
    }

    private static func diagnosticDecisionSource(
        from decision: TimelineHomeRouteHostDecision
    ) -> TimelineHomeRouteDiagnosticDecisionSource {
        if decision.debugOverrideSource.override != nil {
            return .debugOverride
        }
        if decision.launchArgumentSource.argument != nil {
            return .launchArgument
        }
        return .defaultLegacy
    }

    private static func isFallback(
        _ decision: TimelineHomeRouteHostDecision
    ) -> Bool {
        !decision.fallbackIssues.isEmpty
            || (decision.selectedRoute == .legacy && decision.requestedMode != .legacy)
    }

    private static func sanitizedLaunchArgument(
        from source: TimelineHomeRouteLaunchArgumentSource
    ) -> (
        source: TimelineHomeRouteLaunchArgumentDiagnosticSource,
        value: String?
    ) {
        guard let rawValue = source.rawValue else {
            return (.absent, nil)
        }
        guard AstrenzaTimelineEngineMode(rawValue: rawValue) != nil else {
            return (.unknownRedacted, nil)
        }
        return (.recognized, rawValue)
    }
}

struct TimelineHomeRouteDecisionSummary: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRouteMode
    var requestedMode: TimelineHomeRouteMode
    var effectiveMode: TimelineHomeRouteMode
    var collectionViewAllowed: Bool
    var legacyFallback: Bool
    var missingDependencies: [String]
    var fallbackIssueKinds: [TimelineHomeRouteDecisionIssue.Kind]
    var runtimeAllowed: Bool
    var rolloutAllowed: Bool
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]

    static func make(
        from record: TimelineHomeRouteDiagnosticRecord
    ) -> TimelineHomeRouteDecisionSummary {
        TimelineHomeRouteDecisionSummary(
            selectedRoute: record.selectedRoute,
            requestedMode: record.requestedMode,
            effectiveMode: record.effectiveMode,
            collectionViewAllowed: record.selectedRoute == .collectionView && !record.isFallback,
            legacyFallback: record.selectedRoute == .legacy && record.isFallback,
            missingDependencies: record.dependencyReadiness.missingDependencies,
            fallbackIssueKinds: record.fallbackIssueKinds,
            runtimeAllowed: record.runtimeAllowed,
            rolloutAllowed: record.rolloutAllowed,
            releaseBlockerFlags: releaseBlockerFlags(from: record)
        )
    }

    private static func releaseBlockerFlags(
        from record: TimelineHomeRouteDiagnosticRecord
    ) -> [TimelineHomeRouteReleaseBlockerFlag] {
        var flags: [TimelineHomeRouteReleaseBlockerFlag] = []

        if !record.preventsDualMutation {
            flags.append(.dualMutationNotPrevented)
        }
        if record.readMarkerChanged {
            flags.append(.readMarkerChanged)
        }
        if record.requiresNetworkWork {
            flags.append(.requiresNetworkWork)
        }
        if record.requiresDBWrite {
            flags.append(.requiresDBWrite)
        }
        if !record.rootShellBehaviorUnchanged {
            flags.append(.rootShellChanged)
        }
        if record.hostSideEffects.instantiatesRoot {
            flags.append(.hostInstantiatedRoot)
        }
        if record.hostSideEffects.instantiatesLegacyHomeStore {
            flags.append(.hostInstantiatedLegacyHomeStore)
        }
        if record.hostSideEffects.instantiatesCollectionViewController {
            flags.append(.hostInstantiatedCollectionViewController)
        }
        if record.hostSideEffects.startsNetworkWork {
            flags.append(.hostStartedNetworkWork)
        }
        if record.hostSideEffects.performsDatabaseMutation {
            flags.append(.hostPerformedDatabaseMutation)
        }
        if record.hostSideEffects.advancesReadMarker {
            flags.append(.hostAdvancedReadMarker)
        }
        if record.hostSideEffects.callsDataSourceApply {
            flags.append(.hostCalledDataSourceApply)
        }

        return flags
    }
}

enum TimelineHomeRouteDecisionArtifactSource: String, Codable, Equatable, Sendable {
    case rootPreflight
    case routeHost
    case testFixture
}

struct TimelineHomeRouteDecisionArtifact: Codable, Equatable, Sendable {
    static let artifactKind = "timeline_home_route_decision"
    static let artifactVersion = 1
    static let eventName = "timeline_home_route_preflight_decision"

    var artifactKind: String
    var artifactVersion: Int
    var eventName: String
    var source: TimelineHomeRouteDecisionArtifactSource
    var schemaVersion: Int
    var createdAtMS: Int64
    var record: TimelineHomeRouteDiagnosticRecord
    var summary: TimelineHomeRouteDecisionSummary

    static func make(
        from decision: TimelineHomeRouteHostDecision,
        createdAtMS: Int64,
        source: TimelineHomeRouteDecisionArtifactSource = .routeHost
    ) -> TimelineHomeRouteDecisionArtifact {
        let record = TimelineHomeRouteDiagnosticRecord.make(
            from: decision,
            createdAtMS: createdAtMS
        )
        return TimelineHomeRouteDecisionArtifact(
            artifactKind: artifactKind,
            artifactVersion: artifactVersion,
            eventName: eventName,
            source: source,
            schemaVersion: 1,
            createdAtMS: createdAtMS,
            record: record,
            summary: .make(from: record)
        )
    }
}

extension TimelineHomeRouteDecisionArtifact {
    private enum CodingKeys: String, CodingKey {
        case artifactKind
        case artifactVersion
        case eventName
        case source
        case schemaVersion
        case createdAtMS
        case record
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        artifactKind = try container.decodeIfPresent(
            String.self,
            forKey: .artifactKind
        ) ?? Self.artifactKind
        artifactVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .artifactVersion
        ) ?? Self.artifactVersion
        eventName = try container.decodeIfPresent(
            String.self,
            forKey: .eventName
        ) ?? Self.eventName
        source = try container.decodeIfPresent(
            TimelineHomeRouteDecisionArtifactSource.self,
            forKey: .source
        ) ?? .routeHost
        createdAtMS = try container.decode(Int64.self, forKey: .createdAtMS)
        record = try container.decode(TimelineHomeRouteDiagnosticRecord.self, forKey: .record)
        summary = try container.decode(TimelineHomeRouteDecisionSummary.self, forKey: .summary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(artifactKind, forKey: .artifactKind)
        try container.encode(artifactVersion, forKey: .artifactVersion)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(source, forKey: .source)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(createdAtMS, forKey: .createdAtMS)
        try container.encode(record, forKey: .record)
        try container.encode(summary, forKey: .summary)
    }
}

struct TimelineHomeRouteDiagnosticsExport: Codable, Equatable, Sendable {
    var artifacts: [TimelineHomeRouteDecisionArtifact]
    var summary: TimelineHomeRouteDecisionSummary

    static func make(
        from decision: TimelineHomeRouteHostDecision,
        createdAtMS: Int64,
        source: TimelineHomeRouteDecisionArtifactSource = .routeHost
    ) -> TimelineHomeRouteDiagnosticsExport {
        let artifact = TimelineHomeRouteDecisionArtifact.make(
            from: decision,
            createdAtMS: createdAtMS,
            source: source
        )
        return TimelineHomeRouteDiagnosticsExport(
            artifacts: [artifact],
            summary: artifact.summary
        )
    }
}

struct TimelineHomeRouteDiagnosticsConsumer: Equatable, Sendable {
    var export: TimelineHomeRouteDiagnosticsExport

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRouteDiagnosticsConsumer {
        TimelineHomeRouteDiagnosticsConsumer(
            export: try decoder.decode(TimelineHomeRouteDiagnosticsExport.self, from: data)
        )
    }

    var collectionViewAllowed: Bool {
        latestSummary?.collectionViewAllowed ?? false
    }

    var legacyFallback: Bool {
        latestSummary?.legacyFallback ?? false
    }

    var missingDependencies: [String] {
        latestSummary?.missingDependencies ?? []
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        latestSummary?.releaseBlockerFlags ?? []
    }

    func debugSummary() -> String {
        guard let record = latestRecord, let summary = latestSummary else {
            return "route=none requested=none effective=none fallback=false missing=[] issues=[] runtimeAllowed=false rolloutAllowed=false sideEffects(network=false,dbWrite=false,readMarker=false,dualMutationPrevented=false) root=none restoreGate=none blockers=[]"
        }

        return [
            "route=\(record.selectedRoute.rawValue)",
            "requested=\(record.requestedMode.rawValue)",
            "effective=\(record.effectiveMode.rawValue)",
            "fallback=\(record.isFallback)",
            "missing=\(summary.missingDependencies.debugList)",
            "issues=\(summary.fallbackIssueKinds.map(\.rawValue).debugList)",
            "runtimeAllowed=\(record.runtimeAllowed)",
            "rolloutAllowed=\(record.rolloutAllowed)",
            "sideEffects(network=\(record.requiresNetworkWork),dbWrite=\(record.requiresDBWrite),readMarker=\(record.readMarkerChanged),dualMutationPrevented=\(record.preventsDualMutation))",
            "root=\(record.rootShellBehavior.rawValue)",
            "restoreGate=\(record.timelineRestoreGateScope?.rawValue ?? "none")",
            "blockers=\(summary.releaseBlockerFlags.map(\.rawValue).debugList)"
        ].joined(separator: " ")
    }

    private var latestRecord: TimelineHomeRouteDiagnosticRecord? {
        export.artifacts.last?.record
    }

    private var latestSummary: TimelineHomeRouteDecisionSummary? {
        guard let artifact = export.artifacts.last else {
            return nil
        }
        return TimelineHomeRouteDecisionSummary.make(from: artifact.record)
    }
}

private extension TimelineHomeRouteDecisionIssue.Kind {
    var missingDependencyName: String? {
        switch self {
        case .repositoryStoreUnavailable:
            "repositoryStore"
        case .windowComposerUnavailable:
            "windowComposer"
        case .restoreUseCaseUnavailable:
            "restoreUseCase"
        case .coordinatorAdapterUnavailable:
            "coordinatorAdapter"
        case .collectionViewControllerUnavailable:
            "collectionViewController"
        case .diagnosticsSinkUnavailable:
            "diagnosticsSink"
        case .unknownTimelineEngineMode, .runtimeGuardDisabled, .rolloutBlocked:
            nil
        }
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
