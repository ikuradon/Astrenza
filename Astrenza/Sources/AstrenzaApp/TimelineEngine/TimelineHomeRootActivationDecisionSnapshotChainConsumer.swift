import Foundation

struct TimelineHomeRootActivationDecisionSnapshotChainReader: Codable, Equatable, Sendable {
    var chain: TimelineHomeRootActivationPreflightSnapshotChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootActivationDecisionSnapshotChainReader {
        TimelineHomeRootActivationDecisionSnapshotChainReader(
            chain: try TimelineHomeRootActivationPreflightSnapshotChain
                .decodeFixtureJSON(data, decoder: decoder)
        )
    }

    var consumer: TimelineHomeRootActivationDecisionSnapshotChainConsumer {
        TimelineHomeRootActivationDecisionSnapshotChainConsumer(chain: chain)
    }
}

struct TimelineHomeRootActivationDecisionSnapshotChainConsumer: Codable, Equatable, Sendable {
    var chain: TimelineHomeRootActivationPreflightSnapshotChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootActivationDecisionSnapshotChainConsumer {
        try TimelineHomeRootActivationDecisionSnapshotChainReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var result: TimelineHomeRootActivationDecisionSnapshotResult {
        chain.result
    }

    var preflightEvaluated: Bool {
        result.preflightEvaluated
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

    var rootBodyDecisionRenderedRoute: TimelineHomeRootVisibleRouteDecision {
        result.rootBodyDecisionRenderedRoute
    }

    var rootBodyDecisionVisibleRoute: TimelineHomeRootVisibleRouteDecision {
        result.rootBodyDecisionVisibleRoute
    }

    var activationBlockedIssueKinds: [TimelineHomeRootActivationPreflightIssue] {
        result.activationBlockedIssueKinds
    }

    var combinedArtifactChainIssueKinds: [String] {
        result.combinedArtifactChainIssueKinds
    }

    var sideEffectFlags: TimelineHomeRootActivationDecisionSnapshotSideEffectFlags {
        result.sideEffectFlags
    }

    var timelineSurfaceConstructed: Bool {
        sideEffectFlags.timelineSurfaceConstructed
    }

    var diagnostics: TimelineHomeRootActivationDecisionSnapshotDiagnostics {
        result.diagnostics
    }

    var debugSummary: TimelineHomeRootActivationDecisionSnapshotDebugSummary {
        TimelineHomeRootActivationDecisionSnapshotDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }
}

struct TimelineHomeRootActivationDecisionSnapshotDebugSummary: Codable, Equatable, Sendable {
    var preflightEvaluated: Bool
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var rootBodyDecisionRenderedRoute: TimelineHomeRootVisibleRouteDecision
    var rootBodyDecisionVisibleRoute: TimelineHomeRootVisibleRouteDecision
    var activationBlockedIssueKinds: [TimelineHomeRootActivationPreflightIssue]
    var combinedArtifactChainIssueKinds: [String]
    var sideEffectFlags: TimelineHomeRootActivationDecisionSnapshotSideEffectFlags
    var diagnostics: TimelineHomeRootActivationDecisionSnapshotDiagnostics

    static func make(
        from consumer: TimelineHomeRootActivationDecisionSnapshotChainConsumer
    ) -> TimelineHomeRootActivationDecisionSnapshotDebugSummary {
        TimelineHomeRootActivationDecisionSnapshotDebugSummary(
            preflightEvaluated: consumer.preflightEvaluated,
            activationWouldBeAllowed: consumer.activationWouldBeAllowed,
            activationPerformed: consumer.activationPerformed,
            productionRenderSwitchPerformed: consumer.productionRenderSwitchPerformed,
            renderedRoute: consumer.renderedRoute,
            rollbackRoute: consumer.rollbackRoute,
            manualFallbackRoute: consumer.manualFallbackRoute,
            rootBodyDecisionRenderedRoute: consumer.rootBodyDecisionRenderedRoute,
            rootBodyDecisionVisibleRoute: consumer.rootBodyDecisionVisibleRoute,
            activationBlockedIssueKinds: consumer.activationBlockedIssueKinds,
            combinedArtifactChainIssueKinds: consumer.combinedArtifactChainIssueKinds,
            sideEffectFlags: consumer.sideEffectFlags,
            diagnostics: consumer.diagnostics
        )
    }

    var deterministicText: String {
        var fields = baseFields
        if activationBlockedIssueKinds.isEmpty && combinedArtifactChainIssueKinds.isEmpty {
            fields.append(diagnosticsText)
        }
        return fields.joined(separator: " ")
    }

    private var baseFields: [String] {
        [
            "preflightEvaluated=\(preflightEvaluated)",
            "activationWouldBeAllowed=\(activationWouldBeAllowed)",
            "activationPerformed=\(activationPerformed)",
            "productionRenderSwitchPerformed=\(productionRenderSwitchPerformed)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "rollbackRoute=\(rollbackRoute.rawValue)",
            "manualFallbackRoute=\(manualFallbackRoute.rawValue)",
            "rootBody(rendered=\(rootBodyDecisionRenderedRoute.rawValue),visible=\(rootBodyDecisionVisibleRoute.rawValue))",
            "activationIssues=\(activationBlockedIssueKinds.map(\.rawValue).debugList)",
            "artifactIssues=\(combinedArtifactChainIssueKinds.debugList)",
            "sideEffects(\(sideEffectFlags.deterministicText))"
        ]
    }

    private var diagnosticsText: String {
        [
            "diagnostics(rootDebug={\(diagnostics.rootBodyDecisionDebugSummary)}",
            "rootArtifact={\(diagnostics.rootBodyDecisionArtifactSummary)}",
            "activationChain={\(diagnostics.activationArtifactChainSummary)}",
            "activationReadiness={\(diagnostics.activationReadinessSummary)}",
            "flaggedConstruction={\(diagnostics.flaggedConstructionSummary)}",
            "constructionReadiness={\(diagnostics.constructionReadinessSummary)}",
            "offscreenHarness={\(diagnostics.offscreenHarnessSummary)}",
            "sideEffects={\(diagnostics.sideEffectSummary)})"
        ].joined(separator: ",")
    }
}

private extension TimelineHomeRootActivationDecisionSnapshotSideEffectFlags {
    var deterministicText: String {
        [
            "root=\(rootViewConstructed)",
            "home=\(homeTimelineViewConstructed)",
            "nostrStore=\(nostrHomeTimelineStoreConstructed)",
            "collectionView=\(timelineCollectionViewControllerConstructed)",
            "timelineSurface=\(timelineSurfaceConstructed)",
            "network=\(networkStarted)",
            "dbWrite=\(dbWriteAttempted)",
            "readMarker=\(readMarkerChanged)",
            "dataSourceApply=\(dataSourceApplyCalled)",
            "dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled)",
            "forbiddenDataSourceApply=\(forbiddenDataSourceApplyOutsideCoordinatorCalled)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)",
            "fileWrite=\(fileWriteAttempted)",
            "externalTelemetryUpload=\(externalTelemetryUploadAttempted)"
        ].joined(separator: ",")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
