import Foundation

enum TimelineHomeRootVisibleRouteDecision: String, Codable, Equatable, Sendable {
    case legacy
    case collectionViewPlaceholder
    case unavailable
}

struct TimelineHomeRootRouteArtifactSnapshot: Codable, Equatable, Sendable {
    var artifactKind: String
    var artifactVersion: Int
    var eventName: String
    var source: TimelineHomeRouteDecisionArtifactSource?
    var schemaVersion: Int
    var createdAtMS: Int64?
    var selectedRoute: TimelineHomeRouteMode?
    var requestedMode: TimelineHomeRouteMode
    var effectiveMode: TimelineHomeRouteMode
    var decisionSource: TimelineHomeRouteDiagnosticDecisionSource?
    var launchArgumentSource: TimelineHomeRouteLaunchArgumentDiagnosticSource?
    var launchArgumentValue: String?
    var collectionViewAllowed: Bool
    var legacyFallback: Bool
    var missingDependencies: [String]
    var fallbackIssueKinds: [TimelineHomeRouteDecisionIssue.Kind]
    var runtimeAllowed: Bool
    var rolloutAllowed: Bool
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    var rootShellBehavior: TimelineHomeRouteRootShellBehavior?
    var rootShellBehaviorUnchanged: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var deterministicSummary: String

    static let unavailable = TimelineHomeRootRouteArtifactSnapshot(
        artifactKind: "none",
        artifactVersion: 0,
        eventName: "none",
        source: nil,
        schemaVersion: 0,
        createdAtMS: nil,
        selectedRoute: nil,
        requestedMode: .unknown,
        effectiveMode: .unknown,
        decisionSource: nil,
        launchArgumentSource: nil,
        launchArgumentValue: nil,
        collectionViewAllowed: false,
        legacyFallback: false,
        missingDependencies: [],
        fallbackIssueKinds: [],
        runtimeAllowed: false,
        rolloutAllowed: false,
        releaseBlockerFlags: [],
        rootShellBehavior: nil,
        rootShellBehaviorUnchanged: true,
        timelineRestoreGateScope: nil,
        deterministicSummary: [
            "kind=none",
            "version=0",
            "event=none",
            "source=none",
            "route=none",
            "requested=unknown",
            "effective=unknown",
            "fallback=false",
            "collectionViewAllowed=false",
            "missing=[]",
            "issues=[]",
            "runtimeAllowed=false",
            "rolloutAllowed=false",
            "blockers=[]"
        ].joined(separator: " ")
    )

    static func make(
        from artifact: TimelineHomeRouteDecisionArtifact
    ) -> TimelineHomeRootRouteArtifactSnapshot {
        let summary = TimelineHomeRouteDecisionSummary.make(from: artifact.record)
        return TimelineHomeRootRouteArtifactSnapshot(
            artifactKind: artifact.artifactKind,
            artifactVersion: artifact.artifactVersion,
            eventName: artifact.eventName,
            source: artifact.source,
            schemaVersion: artifact.schemaVersion,
            createdAtMS: artifact.createdAtMS,
            selectedRoute: artifact.record.selectedRoute,
            requestedMode: artifact.record.requestedMode,
            effectiveMode: artifact.record.effectiveMode,
            decisionSource: artifact.record.decisionSource,
            launchArgumentSource: artifact.record.launchArgumentSource,
            launchArgumentValue: artifact.record.launchArgumentValue,
            collectionViewAllowed: summary.collectionViewAllowed,
            legacyFallback: summary.legacyFallback,
            missingDependencies: summary.missingDependencies,
            fallbackIssueKinds: summary.fallbackIssueKinds,
            runtimeAllowed: summary.runtimeAllowed,
            rolloutAllowed: summary.rolloutAllowed,
            releaseBlockerFlags: summary.releaseBlockerFlags,
            rootShellBehavior: artifact.record.rootShellBehavior,
            rootShellBehaviorUnchanged: artifact.record.rootShellBehaviorUnchanged,
            timelineRestoreGateScope: artifact.record.timelineRestoreGateScope,
            deterministicSummary: deterministicSummary(from: artifact, summary: summary)
        )
    }

    private static func deterministicSummary(
        from artifact: TimelineHomeRouteDecisionArtifact,
        summary: TimelineHomeRouteDecisionSummary
    ) -> String {
        [
            "kind=\(artifact.artifactKind)",
            "version=\(artifact.artifactVersion)",
            "event=\(artifact.eventName)",
            "source=\(artifact.source.rawValue)",
            "route=\(artifact.record.selectedRoute.rawValue)",
            "requested=\(artifact.record.requestedMode.rawValue)",
            "effective=\(artifact.record.effectiveMode.rawValue)",
            "fallback=\(summary.legacyFallback)",
            "collectionViewAllowed=\(summary.collectionViewAllowed)",
            "missing=\(summary.missingDependencies.debugList)",
            "issues=\(summary.fallbackIssueKinds.map(\.rawValue).debugList)",
            "runtimeAllowed=\(summary.runtimeAllowed)",
            "rolloutAllowed=\(summary.rolloutAllowed)",
            "blockers=\(summary.releaseBlockerFlags.map(\.rawValue).debugList)"
        ].joined(separator: " ")
    }
}

struct TimelineHomeRootRouteDecisionSnapshot: Codable, Equatable, Sendable {
    var visibleRoute: TimelineHomeRootVisibleRouteDecision
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var requestedRouteDecision: TimelineHomeRouteMode
    var artifactSummary: TimelineHomeRootRouteArtifactSnapshot
    var diagnosticsRecordCount: Int
    var collectionViewDecisionObserved: Bool
    var collectionViewRouteConstructed: Bool
    var legacyHomeRendered: Bool
    var rootShellUnchanged: Bool
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var firstInteractiveScrollPolicy: TimelineFirstInteractiveScrollPolicy
    var networkWaitedBeforeInteractiveScrollMS: Double
    var requiresRemoteSyncBeforeInteractiveScroll: Bool
    var requiresOGPResolveBeforeInteractiveScroll: Bool
    var requiresMediaResolveBeforeInteractiveScroll: Bool
    var requiresProfileResolveBeforeInteractiveScroll: Bool
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyCalled: Bool
    var sideEffectSentinel: TimelineHomeRootRoutePreflightSideEffectSentinel
    var createdAtMS: Int64

    static func make(
        from result: TimelineHomeRootRouteCallSiteResult,
        createdAtMS: Int64
    ) -> TimelineHomeRootRouteDecisionSnapshot {
        make(
            artifact: result.localDiagnosticsExport?.artifacts.last ?? result.preflight.artifact,
            diagnosticsRecordCount: result.localDiagnosticsRecordCount,
            collectionViewRouteConstructed: result.collectionViewRouteConstructed,
            legacyHomeRendered: result.legacyHomeRemainsDefault,
            rootShellUnchanged: result.rootShellBehaviorUnchanged,
            dataSourceApplyCalled: result.dataSourceApplyCalledByCallSite,
            sideEffectSentinel: result.preflight.sideEffects,
            createdAtMS: createdAtMS
        )
    }

    static func make(
        from sink: TimelineHomeRouteDiagnosticsSink,
        createdAtMS: Int64
    ) -> TimelineHomeRootRouteDecisionSnapshot {
        guard let artifact = sink.records.last else {
            return unavailable(createdAtMS: createdAtMS)
        }

        return make(
            artifact: artifact,
            diagnosticsRecordCount: sink.records.count,
            collectionViewRouteConstructed: false,
            legacyHomeRendered: true,
            rootShellUnchanged: artifact.record.rootShellBehaviorUnchanged,
            dataSourceApplyCalled: artifact.record.hostSideEffects.callsDataSourceApply,
            sideEffectSentinel: .none,
            createdAtMS: createdAtMS
        )
    }

    private static func make(
        artifact: TimelineHomeRouteDecisionArtifact,
        diagnosticsRecordCount: Int,
        collectionViewRouteConstructed: Bool,
        legacyHomeRendered: Bool,
        rootShellUnchanged: Bool,
        dataSourceApplyCalled: Bool,
        sideEffectSentinel: TimelineHomeRootRoutePreflightSideEffectSentinel,
        createdAtMS: Int64
    ) -> TimelineHomeRootRouteDecisionSnapshot {
        let artifactSummary = TimelineHomeRootRouteArtifactSnapshot.make(from: artifact)
        return TimelineHomeRootRouteDecisionSnapshot(
            visibleRoute: visibleRoute(from: artifact),
            renderedRoute: .legacy,
            requestedRouteDecision: artifact.record.requestedMode,
            artifactSummary: artifactSummary,
            diagnosticsRecordCount: diagnosticsRecordCount,
            collectionViewDecisionObserved: collectionViewDecisionObserved(from: artifact),
            collectionViewRouteConstructed: collectionViewRouteConstructed,
            legacyHomeRendered: legacyHomeRendered,
            rootShellUnchanged: rootShellUnchanged,
            rootShellPresentation: .immediate,
            rootShellMustRenderBeforeTimelineRestore: true,
            timelineRestoreGateScope: artifact.record.timelineRestoreGateScope,
            timelineGateCoversRootShell: false,
            timelineGateCoversTabBar: false,
            timelineGateContinuesGlobalSplash: false,
            firstInteractiveScrollPolicy: .allowedAfterLocalRestoreWithoutNetwork,
            networkWaitedBeforeInteractiveScrollMS: 0,
            requiresRemoteSyncBeforeInteractiveScroll: false,
            requiresOGPResolveBeforeInteractiveScroll: false,
            requiresMediaResolveBeforeInteractiveScroll: false,
            requiresProfileResolveBeforeInteractiveScroll: false,
            preventsDualMutation: artifact.record.preventsDualMutation,
            readMarkerChanged: artifact.record.readMarkerChanged,
            requiresNetworkWork: artifact.record.requiresNetworkWork,
            requiresDBWrite: artifact.record.requiresDBWrite,
            dataSourceApplyCalled: dataSourceApplyCalled || artifact.record.hostSideEffects.callsDataSourceApply,
            sideEffectSentinel: sideEffectSentinel,
            createdAtMS: createdAtMS
        )
    }

    private static func unavailable(
        createdAtMS: Int64
    ) -> TimelineHomeRootRouteDecisionSnapshot {
        TimelineHomeRootRouteDecisionSnapshot(
            visibleRoute: .unavailable,
            renderedRoute: .legacy,
            requestedRouteDecision: .unknown,
            artifactSummary: .unavailable,
            diagnosticsRecordCount: 0,
            collectionViewDecisionObserved: false,
            collectionViewRouteConstructed: false,
            legacyHomeRendered: true,
            rootShellUnchanged: true,
            rootShellPresentation: .immediate,
            rootShellMustRenderBeforeTimelineRestore: true,
            timelineRestoreGateScope: nil,
            timelineGateCoversRootShell: false,
            timelineGateCoversTabBar: false,
            timelineGateContinuesGlobalSplash: false,
            firstInteractiveScrollPolicy: .allowedAfterLocalRestoreWithoutNetwork,
            networkWaitedBeforeInteractiveScrollMS: 0,
            requiresRemoteSyncBeforeInteractiveScroll: false,
            requiresOGPResolveBeforeInteractiveScroll: false,
            requiresMediaResolveBeforeInteractiveScroll: false,
            requiresProfileResolveBeforeInteractiveScroll: false,
            preventsDualMutation: true,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            dataSourceApplyCalled: false,
            sideEffectSentinel: .none,
            createdAtMS: createdAtMS
        )
    }

    private static func visibleRoute(
        from artifact: TimelineHomeRouteDecisionArtifact
    ) -> TimelineHomeRootVisibleRouteDecision {
        let summary = TimelineHomeRouteDecisionSummary.make(from: artifact.record)
        if summary.collectionViewAllowed {
            return .collectionViewPlaceholder
        }
        if artifact.record.selectedRoute == .legacy {
            return .legacy
        }
        return .unavailable
    }

    private static func collectionViewDecisionObserved(
        from artifact: TimelineHomeRouteDecisionArtifact
    ) -> Bool {
        let summary = TimelineHomeRouteDecisionSummary.make(from: artifact.record)
        return artifact.record.requestedMode == .collectionView
            || artifact.record.selectedRoute == .collectionView
            || summary.collectionViewAllowed
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
