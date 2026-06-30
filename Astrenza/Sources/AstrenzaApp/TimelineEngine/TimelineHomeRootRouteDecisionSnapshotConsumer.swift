import Foundation

struct TimelineHomeRootRouteDecisionSnapshotReader: Codable, Equatable, Sendable {
    var snapshot: TimelineHomeRootRouteDecisionSnapshot

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootRouteDecisionSnapshotReader {
        TimelineHomeRootRouteDecisionSnapshotReader(
            snapshot: try decoder.decode(
                TimelineHomeRootRouteDecisionSnapshot.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeRootRouteDecisionSnapshotConsumer {
        TimelineHomeRootRouteDecisionSnapshotConsumer(snapshot: snapshot)
    }
}

struct TimelineHomeRootRouteDecisionSnapshotConsumer: Codable, Equatable, Sendable {
    var snapshot: TimelineHomeRootRouteDecisionSnapshot

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootRouteDecisionSnapshotConsumer {
        try TimelineHomeRootRouteDecisionSnapshotReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var didRenderLegacy: Bool {
        snapshot.renderedRoute == .legacy && snapshot.legacyHomeRendered
    }

    var didObserveCollectionView: Bool {
        snapshot.collectionViewDecisionObserved
    }

    var didConstructCollectionView: Bool {
        snapshot.collectionViewRouteConstructed
    }

    var isFallback: Bool {
        snapshot.artifactSummary.legacyFallback
    }

    var fallbackIssueKinds: [TimelineHomeRouteDecisionIssue.Kind] {
        snapshot.artifactSummary.fallbackIssueKinds
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        snapshot.artifactSummary.releaseBlockerFlags
    }

    var sideEffectFlags: TimelineHomeRootRoutePreflightSideEffectSentinel {
        snapshot.sideEffectSentinel
    }

    var diagnosticsRecordCount: Int {
        snapshot.diagnosticsRecordCount
    }

    var artifactSummary: TimelineHomeRootRouteArtifactSnapshot {
        snapshot.artifactSummary
    }

    var debugSummary: TimelineHomeRootDecisionDebugSummary {
        TimelineHomeRootDecisionDebugSummary.make(from: snapshot)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeRootDecisionDebugSummary: Codable, Equatable, Sendable {
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var visibleRoute: TimelineHomeRootVisibleRouteDecision
    var observedCollectionView: Bool
    var constructedCollectionView: Bool
    var fallbackIssueKinds: [TimelineHomeRouteDecisionIssue.Kind]
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyCalled: Bool
    var diagnosticsRecordCount: Int
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    var sideEffectFlags: TimelineHomeRootRoutePreflightSideEffectSentinel
    var artifactSummary: String

    static func make(
        from snapshot: TimelineHomeRootRouteDecisionSnapshot
    ) -> TimelineHomeRootDecisionDebugSummary {
        TimelineHomeRootDecisionDebugSummary(
            renderedRoute: snapshot.renderedRoute,
            visibleRoute: snapshot.visibleRoute,
            observedCollectionView: snapshot.collectionViewDecisionObserved,
            constructedCollectionView: snapshot.collectionViewRouteConstructed,
            fallbackIssueKinds: snapshot.artifactSummary.fallbackIssueKinds,
            readMarkerChanged: snapshot.readMarkerChanged,
            requiresNetworkWork: snapshot.requiresNetworkWork,
            requiresDBWrite: snapshot.requiresDBWrite,
            dataSourceApplyCalled: snapshot.dataSourceApplyCalled,
            diagnosticsRecordCount: snapshot.diagnosticsRecordCount,
            releaseBlockerFlags: snapshot.artifactSummary.releaseBlockerFlags,
            sideEffectFlags: snapshot.sideEffectSentinel,
            artifactSummary: snapshot.artifactSummary.deterministicSummary
        )
    }

    var deterministicText: String {
        [
            "renderedRoute=\(renderedRoute.rawValue)",
            "visibleRoute=\(visibleRoute.rawValue)",
            "observedCollectionView=\(observedCollectionView)",
            "constructedCollectionView=\(constructedCollectionView)",
            "fallbackIssues=\(fallbackIssueKinds.map(\.rawValue).debugList)",
            "readMarkerChanged=\(readMarkerChanged)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)",
            "dataSourceApplyCalled=\(dataSourceApplyCalled)",
            "diagnosticsRecordCount=\(diagnosticsRecordCount)",
            "releaseBlockers=\(releaseBlockerFlags.map(\.rawValue).debugList)",
            "sideEffects(\(sideEffectFlags.debugSummary))",
            "artifactSummary={\(artifactSummary)}"
        ].joined(separator: " ")
    }
}

private extension TimelineHomeRootRoutePreflightSideEffectSentinel {
    var debugSummary: String {
        [
            "root=\(rootViewConstructed)",
            "home=\(homeTimelineViewConstructed)",
            "nostrStore=\(nostrHomeTimelineStoreConstructed)",
            "collectionView=\(timelineCollectionViewControllerConstructed)",
            "network=\(networkStarted)",
            "dbWrite=\(dbWriteAttempted)",
            "readMarker=\(readMarkerAdvanced)",
            "dataSourceApply=\(dataSourceApplyCalled)"
        ].joined(separator: ",")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
