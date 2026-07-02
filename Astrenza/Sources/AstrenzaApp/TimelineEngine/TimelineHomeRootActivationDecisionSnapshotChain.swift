import Foundation

enum TimelineHomeRootActivationDecisionSnapshotBridge {
    static func make(
        preflightResult: TimelineHomeRootActivationPreflightResult,
        rootRouteDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
        activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer
    ) -> TimelineHomeRootActivationDecisionSnapshotResult {
        let combinedArtifactChainIssueKinds = activationArtifactChainConsumer
            .combinedBlockedIssueKinds
        return TimelineHomeRootActivationDecisionSnapshotResult(
            preflightEvaluated: preflightResult.activationPreflightEvaluated,
            activationWouldBeAllowed: preflightResult.activationWouldBeAllowed
                && activationArtifactChainConsumer.activationWouldBeAllowed
                && combinedArtifactChainIssueKinds.isEmpty,
            activationPerformed: false,
            productionRenderSwitchPerformed: false,
            renderedRoute: .legacy,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            rootBodyDecisionRenderedRoute: rootRouteDecisionSnapshot.renderedRoute,
            rootBodyDecisionVisibleRoute: rootRouteDecisionSnapshot.visibleRoute,
            activationBlockedIssueKinds: preflightResult.issues,
            combinedArtifactChainIssueKinds: combinedArtifactChainIssueKinds,
            sideEffectFlags: TimelineHomeRootActivationDecisionSnapshotSideEffectFlags.make(
                rootRouteDecisionSnapshot: rootRouteDecisionSnapshot,
                activationArtifactChainConsumer: activationArtifactChainConsumer
            ),
            diagnostics: TimelineHomeRootActivationDecisionSnapshotDiagnostics.make(
                rootRouteDecisionSnapshot: rootRouteDecisionSnapshot,
                activationArtifactChainConsumer: activationArtifactChainConsumer
            )
        )
    }
}

struct TimelineHomeRootActivationPreflightSnapshotChain: Codable, Equatable, Sendable {
    var preflightResult: TimelineHomeRootActivationPreflightResult
    var rootRouteDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot
    var activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeRootActivationPreflightSnapshotChain {
        try decoder.decode(TimelineHomeRootActivationPreflightSnapshotChain.self, from: data)
    }

    var result: TimelineHomeRootActivationDecisionSnapshotResult {
        TimelineHomeRootActivationDecisionSnapshotBridge.make(
            preflightResult: preflightResult,
            rootRouteDecisionSnapshot: rootRouteDecisionSnapshot,
            activationArtifactChainConsumer: activationArtifactChainConsumer
        )
    }
}

struct TimelineHomeRootActivationDecisionSnapshotResult: Codable, Equatable, Sendable {
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
}

struct TimelineHomeRootActivationDecisionSnapshotDiagnostics: Codable, Equatable, Sendable {
    var rootBodyDecisionDebugSummary: String
    var rootBodyDecisionArtifactSummary: String
    var activationArtifactChainSummary: String
    var activationReadinessSummary: String
    var flaggedConstructionSummary: String
    var constructionReadinessSummary: String
    var offscreenHarnessSummary: String
    var sideEffectSummary: String

    static func make(
        rootRouteDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
        activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer
    ) -> TimelineHomeRootActivationDecisionSnapshotDiagnostics {
        let rootDecisionConsumer = TimelineHomeRootRouteDecisionSnapshotConsumer(
            snapshot: rootRouteDecisionSnapshot
        )
        let diagnosticsSummary = activationArtifactChainConsumer.diagnosticsSummary
        return TimelineHomeRootActivationDecisionSnapshotDiagnostics(
            rootBodyDecisionDebugSummary: rootDecisionConsumer.deterministicDebugSummary,
            rootBodyDecisionArtifactSummary: rootDecisionConsumer
                .artifactSummary
                .deterministicSummary,
            activationArtifactChainSummary: activationArtifactChainConsumer
                .deterministicDebugSummary,
            activationReadinessSummary: diagnosticsSummary.activation,
            flaggedConstructionSummary: diagnosticsSummary.flaggedConstruction,
            constructionReadinessSummary: diagnosticsSummary.constructionReadiness,
            offscreenHarnessSummary: diagnosticsSummary.offscreenHarness,
            sideEffectSummary: activationArtifactChainConsumer
                .sideEffectFlags
                .deterministicText
        )
    }
}

struct TimelineHomeRootActivationDecisionSnapshotSideEffectFlags: Codable, Equatable, Sendable {
    var rootViewConstructed: Bool
    var homeTimelineViewConstructed: Bool
    var nostrHomeTimelineStoreConstructed: Bool
    var timelineCollectionViewControllerConstructed: Bool
    var timelineSurfaceConstructed: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerChanged: Bool
    var dataSourceApplyCalled: Bool
    var dataSourceApplyFromRootCalled: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var fileWriteAttempted: Bool
    var externalTelemetryUploadAttempted: Bool

    static func make(
        rootRouteDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot,
        activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer
    ) -> TimelineHomeRootActivationDecisionSnapshotSideEffectFlags {
        let rootSideEffects = rootRouteDecisionSnapshot.sideEffectSentinel
        let activationSideEffects = activationArtifactChainConsumer.sideEffectFlags
        return TimelineHomeRootActivationDecisionSnapshotSideEffectFlags(
            rootViewConstructed: rootSideEffects.rootViewConstructed
                || activationSideEffects.rootViewConstructed,
            homeTimelineViewConstructed: rootSideEffects.homeTimelineViewConstructed
                || activationSideEffects.homeTimelineViewConstructed,
            nostrHomeTimelineStoreConstructed: rootSideEffects.nostrHomeTimelineStoreConstructed
                || activationSideEffects.nostrHomeTimelineStoreConstructed
                || activationSideEffects.extraNostrHomeTimelineStoreConstructed,
            timelineCollectionViewControllerConstructed: rootSideEffects
                .timelineCollectionViewControllerConstructed
                || activationSideEffects.timelineCollectionViewControllerConstructed,
            timelineSurfaceConstructed: false,
            networkStarted: rootSideEffects.networkStarted
                || activationSideEffects.networkStarted,
            dbWriteAttempted: rootSideEffects.dbWriteAttempted
                || activationSideEffects.dbWriteAttempted,
            readMarkerChanged: rootSideEffects.readMarkerAdvanced
                || rootRouteDecisionSnapshot.readMarkerChanged
                || activationSideEffects.readMarkerChanged,
            dataSourceApplyCalled: rootSideEffects.dataSourceApplyCalled
                || rootRouteDecisionSnapshot.dataSourceApplyCalled
                || activationSideEffects.dataSourceApplyCalled,
            dataSourceApplyFromRootCalled: activationSideEffects.dataSourceApplyFromRootCalled,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: activationSideEffects
                .forbiddenDataSourceApplyOutsideCoordinatorCalled,
            requiresNetworkWork: rootRouteDecisionSnapshot.requiresNetworkWork
                || activationSideEffects.requiresNetworkWork,
            requiresDBWrite: rootRouteDecisionSnapshot.requiresDBWrite
                || activationSideEffects.requiresDBWrite,
            fileWriteAttempted: false,
            externalTelemetryUploadAttempted: false
        )
    }
}
