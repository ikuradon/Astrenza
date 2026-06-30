import Foundation

struct TimelineHomeRouteConstructionPlanConsumer: Codable, Equatable, Sendable {
    var plan: TimelineHomeCollectionViewRouteConstructionPlan

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRouteConstructionPlanConsumer {
        TimelineHomeRouteConstructionPlanConsumer(
            plan: try decoder.decode(
                TimelineHomeCollectionViewRouteConstructionPlan.self,
                from: data
            )
        )
    }

    var constructionAllowed: Bool {
        switch constructionKind {
        case .describedOnly, .offscreenOnly:
            break
        case .productionClosed:
            return false
        }

        return renderedRouteAfterConstruction == .legacy
            && routeActivationAllowed == false
            && collectionViewRouteConstructed == false
            && timelineSurfaceConstructed == false
            && timelineCollectionViewControllerConstructedFromRoot == false
            && networkStarted == false
            && dbWriteAttempted == false
            && readMarkerAdvanced == false
            && dataSourceApplyCalled == false
            && requiresNetworkWork == false
            && requiresDBWrite == false
            && sideEffectFlags == .none
    }

    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind {
        plan.constructionKind
    }

    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision {
        plan.renderedRouteAfterConstruction
    }

    var routeActivationAllowed: Bool {
        plan.routeActivationAllowed
    }

    var collectionViewRouteConstructed: Bool {
        plan.collectionViewRouteConstructed
    }

    var timelineSurfaceConstructed: Bool {
        plan.timelineSurfaceConstructed
    }

    var timelineCollectionViewControllerConstructedFromRoot: Bool {
        plan.timelineCollectionViewControllerConstructedFromRoot
    }

    var sideEffectFlags: TimelineHomeRootRoutePreflightSideEffectSentinel {
        plan.sideEffectSentinel
    }

    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot {
        plan.diagnosticsArtifactSummary
    }

    var artifactDeterministicSummary: String {
        diagnosticsArtifactSummary.deterministicSummary
    }

    private var networkStarted: Bool {
        plan.networkStarted
    }

    private var dbWriteAttempted: Bool {
        plan.dbWriteAttempted
    }

    private var readMarkerAdvanced: Bool {
        plan.readMarkerAdvanced
    }

    private var dataSourceApplyCalled: Bool {
        plan.dataSourceApplyCalled
    }

    private var requiresNetworkWork: Bool {
        plan.requiresNetworkWork
    }

    private var requiresDBWrite: Bool {
        plan.requiresDBWrite
    }
}

struct TimelineHomeRouteConstructionReadinessConsumer: Codable, Equatable, Sendable {
    var result: TimelineHomeRouteConstructionReadinessResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRouteConstructionReadinessConsumer {
        TimelineHomeRouteConstructionReadinessConsumer(
            result: try decoder.decode(
                TimelineHomeRouteConstructionReadinessResult.self,
                from: data
            )
        )
    }

    var planConsumer: TimelineHomeRouteConstructionPlanConsumer {
        TimelineHomeRouteConstructionPlanConsumer(plan: result.plan)
    }

    var isReady: Bool {
        result.isReady
    }

    var constructionAllowed: Bool {
        isReady && planConsumer.constructionAllowed
    }

    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind {
        planConsumer.constructionKind
    }

    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision {
        planConsumer.renderedRouteAfterConstruction
    }

    var routeActivationAllowed: Bool {
        planConsumer.routeActivationAllowed
    }

    var collectionViewRouteConstructed: Bool {
        planConsumer.collectionViewRouteConstructed
    }

    var timelineSurfaceConstructed: Bool {
        planConsumer.timelineSurfaceConstructed
    }

    var timelineCollectionViewControllerConstructedFromRoot: Bool {
        planConsumer.timelineCollectionViewControllerConstructedFromRoot
    }

    var blockedIssueKinds: [TimelineHomeRouteConstructionGate] {
        result.issues.map(\.gate)
    }

    var missingGateKinds: [TimelineHomeRouteConstructionGate] {
        blockedIssueKinds
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        diagnosticsArtifactSummary.releaseBlockerFlags
    }

    var sideEffectFlags: TimelineHomeRootRoutePreflightSideEffectSentinel {
        planConsumer.sideEffectFlags
    }

    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot {
        planConsumer.diagnosticsArtifactSummary
    }

    var artifactDeterministicSummary: String {
        planConsumer.artifactDeterministicSummary
    }

    var debugSummary: TimelineHomeConstructionDebugSummary {
        TimelineHomeConstructionDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeConstructionDebugSummary: Codable, Equatable, Sendable {
    var isReady: Bool
    var constructionAllowed: Bool
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructed: Bool
    var timelineSurfaceConstructed: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var blockedIssueKinds: [TimelineHomeRouteConstructionGate]
    var missingGateKinds: [TimelineHomeRouteConstructionGate]
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    var sideEffectFlags: TimelineHomeRootRoutePreflightSideEffectSentinel
    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot

    static func make(
        from consumer: TimelineHomeRouteConstructionReadinessConsumer
    ) -> TimelineHomeConstructionDebugSummary {
        TimelineHomeConstructionDebugSummary(
            isReady: consumer.isReady,
            constructionAllowed: consumer.constructionAllowed,
            constructionKind: consumer.constructionKind,
            renderedRouteAfterConstruction: consumer.renderedRouteAfterConstruction,
            routeActivationAllowed: consumer.routeActivationAllowed,
            collectionViewRouteConstructed: consumer.collectionViewRouteConstructed,
            timelineSurfaceConstructed: consumer.timelineSurfaceConstructed,
            timelineCollectionViewControllerConstructedFromRoot: consumer.timelineCollectionViewControllerConstructedFromRoot,
            blockedIssueKinds: consumer.blockedIssueKinds,
            missingGateKinds: consumer.missingGateKinds,
            releaseBlockerFlags: consumer.releaseBlockerFlags,
            sideEffectFlags: consumer.sideEffectFlags,
            diagnosticsArtifactSummary: consumer.diagnosticsArtifactSummary
        )
    }

    var deterministicText: String {
        [
            "isReady=\(isReady)",
            "constructionAllowed=\(constructionAllowed)",
            "constructionKind=\(constructionKind.rawValue)",
            "renderedRouteAfterConstruction=\(renderedRouteAfterConstruction.rawValue)",
            "routeActivationAllowed=\(routeActivationAllowed)",
            "collectionViewRouteConstructed=\(collectionViewRouteConstructed)",
            "timelineSurfaceConstructed=\(timelineSurfaceConstructed)",
            "timelineCollectionViewControllerConstructedFromRoot=\(timelineCollectionViewControllerConstructedFromRoot)",
            "blockedIssues=\(blockedIssueKinds.map(\.rawValue).debugList)",
            "missingGates=\(missingGateKinds.map(\.rawValue).debugList)",
            "releaseBlockers=\(releaseBlockerFlags.map(\.rawValue).debugList)",
            "sideEffects(\(sideEffectFlags.debugSummary))",
            "artifactSummary={\(diagnosticsArtifactSummary.deterministicSummary)}"
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
