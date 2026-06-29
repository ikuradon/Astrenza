import Foundation

struct TimelineHomeRouteDiagnosticsDebugSummary: Codable, Equatable, Sendable {
    var artifactKind: String
    var artifactVersion: Int
    var eventName: String
    var source: TimelineHomeRouteDecisionArtifactSource
    var createdAtMS: Int64
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
    var recordCount: Int
    var retentionLimit: Int

    static func make(
        from artifact: TimelineHomeRouteDecisionArtifact,
        recordCount: Int,
        retentionLimit: Int
    ) -> TimelineHomeRouteDiagnosticsDebugSummary {
        TimelineHomeRouteDiagnosticsDebugSummary(
            artifactKind: artifact.artifactKind,
            artifactVersion: artifact.artifactVersion,
            eventName: artifact.eventName,
            source: artifact.source,
            createdAtMS: artifact.createdAtMS,
            selectedRoute: artifact.record.selectedRoute,
            requestedMode: artifact.record.requestedMode,
            effectiveMode: artifact.record.effectiveMode,
            collectionViewAllowed: artifact.summary.collectionViewAllowed,
            legacyFallback: artifact.summary.legacyFallback,
            missingDependencies: artifact.summary.missingDependencies,
            fallbackIssueKinds: artifact.summary.fallbackIssueKinds,
            runtimeAllowed: artifact.summary.runtimeAllowed,
            rolloutAllowed: artifact.summary.rolloutAllowed,
            releaseBlockerFlags: artifact.summary.releaseBlockerFlags,
            recordCount: recordCount,
            retentionLimit: retentionLimit
        )
    }
}

struct TimelineHomeRouteDiagnosticsSink: Codable, Equatable, Sendable {
    private(set) var records: [TimelineHomeRouteDecisionArtifact]
    var retentionLimit: Int

    init(
        retentionLimit: Int = 10,
        records: [TimelineHomeRouteDecisionArtifact] = []
    ) {
        self.retentionLimit = max(1, retentionLimit)
        self.records = Array(records.suffix(self.retentionLimit))
    }

    var latestDebugSummary: TimelineHomeRouteDiagnosticsDebugSummary? {
        guard let latest = records.last else {
            return nil
        }
        return TimelineHomeRouteDiagnosticsDebugSummary.make(
            from: latest,
            recordCount: records.count,
            retentionLimit: retentionLimit
        )
    }

    var collectionViewAllowed: Bool {
        records.last?.summary.collectionViewAllowed ?? false
    }

    var legacyFallback: Bool {
        records.last?.summary.legacyFallback ?? false
    }

    var missingDependencies: [String] {
        records.last?.summary.missingDependencies ?? []
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        records.last?.summary.releaseBlockerFlags ?? []
    }

    mutating func record(_ artifact: TimelineHomeRouteDecisionArtifact) {
        records.append(artifact)
        records = Array(records.suffix(retentionLimit))
    }

    mutating func record(_ export: TimelineHomeRouteDiagnosticsExport) {
        for artifact in export.artifacts {
            record(artifact)
        }
    }

    mutating func clear() {
        records.removeAll()
    }

    func export() -> TimelineHomeRouteDiagnosticsExport? {
        guard let latest = records.last else {
            return nil
        }
        return TimelineHomeRouteDiagnosticsExport(
            artifacts: records,
            summary: latest.summary
        )
    }

    func debugSummary() -> String {
        guard let summary = latestDebugSummary else {
            return "kind=none version=0 event=none source=none route=none requested=none effective=none fallback=false missing=[] issues=[] runtimeAllowed=false rolloutAllowed=false blockers=[] records=0 retention=\(retentionLimit)"
        }

        return [
            "kind=\(summary.artifactKind)",
            "version=\(summary.artifactVersion)",
            "event=\(summary.eventName)",
            "source=\(summary.source.rawValue)",
            "route=\(summary.selectedRoute.rawValue)",
            "requested=\(summary.requestedMode.rawValue)",
            "effective=\(summary.effectiveMode.rawValue)",
            "fallback=\(summary.legacyFallback)",
            "missing=\(summary.missingDependencies.debugList)",
            "issues=\(summary.fallbackIssueKinds.map(\.rawValue).debugList)",
            "runtimeAllowed=\(summary.runtimeAllowed)",
            "rolloutAllowed=\(summary.rolloutAllowed)",
            "blockers=\(summary.releaseBlockerFlags.map(\.rawValue).debugList)",
            "records=\(summary.recordCount)",
            "retention=\(summary.retentionLimit)"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
