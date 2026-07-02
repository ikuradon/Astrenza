import Foundation

struct TimelineHomeCollectionViewRouteActivationResultReader: Codable, Equatable, Sendable {
    var result: TimelineHomeCollectionViewRouteActivationResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeCollectionViewRouteActivationResultReader {
        TimelineHomeCollectionViewRouteActivationResultReader(
            result: try decoder.decode(
                TimelineHomeCollectionViewRouteActivationResult.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeCollectionViewRouteActivationReadinessConsumer {
        TimelineHomeCollectionViewRouteActivationReadinessConsumer(result: result)
    }
}

struct TimelineHomeCollectionViewRouteActivationReadinessConsumer: Codable, Equatable, Sendable {
    var result: TimelineHomeCollectionViewRouteActivationResult

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeCollectionViewRouteActivationReadinessConsumer {
        try TimelineHomeCollectionViewRouteActivationResultReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var activationWouldBeAllowed: Bool {
        result.activationWouldBeAllowed
    }

    var activationPerformed: Bool {
        result.activationPerformed
    }

    var productionRenderSwitchPerformed: Bool {
        result.productionRenderSwitchPerformed
    }

    var renderedRoute: TimelineHomeRootVisibleRouteDecision {
        result.renderedRoute
    }

    var rollbackRoute: TimelineHomeRootVisibleRouteDecision {
        result.rollbackRoute
    }

    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision {
        result.manualFallbackRoute
    }

    var blockedIssueKinds: [TimelineHomeCollectionViewRouteActivationGate] {
        result.issues.map(\.gate)
    }

    var chainIssueKinds: [String] {
        result.artifactSummary.chainIssueKinds
    }

    var constructionResultClean: Bool {
        !blockedIssueKinds.contains(.flaggedConstructionResultClean)
            && result.constructionResult.constructionAllowed
            && result.constructionResult.issueKinds.isEmpty
    }

    var artifactChainClean: Bool {
        !blockedIssueKinds.contains(.artifactChainClean)
            && chainIssueKinds.isEmpty
    }

    var rootBodySnapshotPermitsActivation: Bool {
        !blockedIssueKinds.contains(.rootBodyDecisionSnapshotPermitsActivationScope)
    }

    var startupNetworkClean: Bool {
        !blockedIssueKinds.contains(.startupNetworkPatternClean)
            && !blockedIssueKinds.contains(.networkWaitedBeforeInteractiveScrollZero)
            && !result.networkStarted
            && result.networkWaitedBeforeInteractiveScrollMS == 0
            && !result.requiresNetworkWork
    }

    var readMarkerChanged: Bool {
        result.readMarkerChanged || result.readMarkerAdvanced
    }

    var requiresNetworkWork: Bool {
        result.requiresNetworkWork
    }

    var requiresDBWrite: Bool {
        result.requiresDBWrite
    }

    var dataSourceApplyFromRootCalled: Bool {
        result.dataSourceApplyFromRootCalled
    }

    var extraNostrHomeTimelineStoreConstructed: Bool {
        !result.noExtraNostrHomeTimelineStore
    }

    var diagnosticsSummary: TimelineHomeCollectionViewActivationDiagnosticsSummary {
        TimelineHomeCollectionViewActivationDiagnosticsSummary(
            routeDecision: result.artifactSummary.routeDecisionSummary,
            constructionReadiness: result.artifactSummary.constructionReadinessSummary,
            offscreenHarness: result.artifactSummary.offscreenHarnessSummary,
            flaggedConstruction: result.artifactSummary.flaggedConstructionSummary
        )
    }

    var debugSummary: TimelineHomeCollectionViewActivationDebugSummary {
        TimelineHomeCollectionViewActivationDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeCollectionViewActivationDiagnosticsSummary: Codable, Equatable, Sendable {
    var routeDecision: String
    var constructionReadiness: String
    var offscreenHarness: String
    var flaggedConstruction: String
}

struct TimelineHomeCollectionViewActivationDebugSummary: Codable, Equatable, Sendable {
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var blockedIssueKinds: [TimelineHomeCollectionViewRouteActivationGate]
    var chainIssueKinds: [String]
    var constructionResultClean: Bool
    var artifactChainClean: Bool
    var rootBodySnapshotPermitsActivation: Bool
    var startupNetworkClean: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var diagnosticsSummary: TimelineHomeCollectionViewActivationDiagnosticsSummary

    static func make(
        from consumer: TimelineHomeCollectionViewRouteActivationReadinessConsumer
    ) -> TimelineHomeCollectionViewActivationDebugSummary {
        TimelineHomeCollectionViewActivationDebugSummary(
            activationWouldBeAllowed: consumer.activationWouldBeAllowed,
            activationPerformed: consumer.activationPerformed,
            productionRenderSwitchPerformed: consumer.productionRenderSwitchPerformed,
            renderedRoute: consumer.renderedRoute,
            rollbackRoute: consumer.rollbackRoute,
            manualFallbackRoute: consumer.manualFallbackRoute,
            blockedIssueKinds: consumer.blockedIssueKinds,
            chainIssueKinds: consumer.chainIssueKinds,
            constructionResultClean: consumer.constructionResultClean,
            artifactChainClean: consumer.artifactChainClean,
            rootBodySnapshotPermitsActivation: consumer.rootBodySnapshotPermitsActivation,
            startupNetworkClean: consumer.startupNetworkClean,
            networkStarted: consumer.result.networkStarted,
            dbWriteAttempted: consumer.result.dbWriteAttempted,
            readMarkerChanged: consumer.readMarkerChanged,
            requiresNetworkWork: consumer.requiresNetworkWork,
            requiresDBWrite: consumer.requiresDBWrite,
            dataSourceApplyFromRootCalled: consumer.dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: consumer.extraNostrHomeTimelineStoreConstructed,
            diagnosticsSummary: consumer.diagnosticsSummary
        )
    }

    var deterministicText: String {
        [
            "activationWouldBeAllowed=\(activationWouldBeAllowed)",
            "activationPerformed=\(activationPerformed)",
            "productionRenderSwitchPerformed=\(productionRenderSwitchPerformed)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "rollbackRoute=\(rollbackRoute.rawValue)",
            "manualFallbackRoute=\(manualFallbackRoute.rawValue)",
            "blockedIssues=\(blockedIssueKinds.map(\.rawValue).debugList)",
            "chainIssues=\(chainIssueKinds.debugList)",
            "constructionResultClean=\(constructionResultClean)",
            "artifactChainClean=\(artifactChainClean)",
            "rootBodySnapshotPermitsActivation=\(rootBodySnapshotPermitsActivation)",
            "startupNetworkClean=\(startupNetworkClean)",
            "sideEffects(network=\(networkStarted),dbWrite=\(dbWriteAttempted),readMarker=\(readMarkerChanged),requiresNetworkWork=\(requiresNetworkWork),requiresDBWrite=\(requiresDBWrite),dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled),extraNostrStore=\(extraNostrHomeTimelineStoreConstructed))",
            "diagnostics(route={\(diagnosticsSummary.routeDecision)},construction={\(diagnosticsSummary.constructionReadiness)},offscreen={\(diagnosticsSummary.offscreenHarness)},flagged={\(diagnosticsSummary.flaggedConstruction)})"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
