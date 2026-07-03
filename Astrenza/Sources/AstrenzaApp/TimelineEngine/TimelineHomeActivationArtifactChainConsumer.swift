import Foundation

struct TimelineHomeActivationArtifactChain: Codable, Equatable, Sendable {
    var constructionArtifactChain: TimelineHomeConstructionArtifactChain
    var activationReadinessResult: TimelineHomeCollectionViewRouteActivationResult
}

struct TimelineHomeCollectionViewActivationArtifactChainReader: Codable, Equatable, Sendable {
    var chain: TimelineHomeActivationArtifactChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeCollectionViewActivationArtifactChainReader {
        TimelineHomeCollectionViewActivationArtifactChainReader(
            chain: try decoder.decode(
                TimelineHomeActivationArtifactChain.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeActivationArtifactChainConsumer {
        TimelineHomeActivationArtifactChainConsumer(chain: chain)
    }
}

struct TimelineHomeActivationArtifactChainConsumer: Codable, Equatable, Sendable {
    var chain: TimelineHomeActivationArtifactChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeActivationArtifactChainConsumer {
        try TimelineHomeCollectionViewActivationArtifactChainReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var constructionConsumer: TimelineHomeConstructionArtifactChainConsumer {
        TimelineHomeConstructionArtifactChainConsumer(chain: chain.constructionArtifactChain)
    }

    var activationConsumer: TimelineHomeCollectionViewRouteActivationReadinessConsumer {
        TimelineHomeCollectionViewRouteActivationReadinessConsumer(
            result: chain.activationReadinessResult
        )
    }

    var constructionReady: Bool {
        constructionConsumer.constructionReady
    }

    var constructionAllowed: Bool {
        constructionConsumer.constructionAllowed
    }

    var offscreenHarnessAllowed: Bool {
        constructionConsumer.offscreenHarnessAllowed
    }

    var activationWouldBeAllowed: Bool {
        activationConsumer.activationWouldBeAllowed
            && activationArtifactPairIssueKinds.isEmpty
    }

    var activationPerformed: Bool {
        activationConsumer.activationPerformed
    }

    var productionRenderSwitchPerformed: Bool {
        activationConsumer.productionRenderSwitchPerformed
    }

    var renderedRoute: TimelineHomeRootVisibleRouteDecision {
        activationConsumer.renderedRoute
    }

    var rollbackRoute: TimelineHomeRootVisibleRouteDecision {
        activationConsumer.rollbackRoute
    }

    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision {
        activationConsumer.manualFallbackRoute
    }

    var constructionBlockedIssueKinds: [String] {
        constructionConsumer.combinedBlockedIssueKinds
    }

    var activationBlockedIssueKinds: [TimelineHomeCollectionViewRouteActivationGate] {
        var issues = activationConsumer.blockedIssueKinds
        appendUnique(
            .artifactChainClean,
            when: !activationArtifactPairIssueKinds.isEmpty,
            to: &issues
        )
        return issues
    }

    var activationArtifactPairIssueKinds: [String] {
        var issues: [String] = []
        let constructionSummaries = constructionConsumer.diagnosticsSummaries
        let constructionResultArtifact = chain.activationReadinessResult
            .constructionResult
            .artifactSummary
        let activationArtifact = chain.activationReadinessResult.artifactSummary
        let expectedActivationArtifact = TimelineHomeCollectionViewRouteActivationArtifactSummary
            .make(
                consumer: constructionConsumer,
                constructionResult: chain.activationReadinessResult.constructionResult,
                issues: chain.activationReadinessResult.issues,
                chainIssueKinds: expectedActivationChainIssueKinds
            )
        append(
            "routeDecisionSummaryMismatch",
            when: constructionResultArtifact.routeDecisionSummary != constructionSummaries.routeDecision
                || activationArtifact.routeDecisionSummary != constructionSummaries.routeDecision,
            to: &issues
        )
        append(
            "constructionReadinessSummaryMismatch",
            when: constructionResultArtifact.constructionReadinessSummary != constructionSummaries
                .constructionReadiness
                || activationArtifact.constructionReadinessSummary != constructionSummaries
                .constructionReadiness,
            to: &issues
        )
        append(
            "offscreenHarnessSummaryMismatch",
            when: constructionResultArtifact.offscreenHarnessSummary != constructionSummaries
                .offscreenHarness
                || activationArtifact.offscreenHarnessSummary != constructionSummaries.offscreenHarness,
            to: &issues
        )
        append(
            "flaggedConstructionSummaryMismatch",
            when: activationArtifact.flaggedConstructionSummary != constructionResultArtifact
                .deterministicSummary,
            to: &issues
        )
        append(
            "activationIssueKindsMismatch",
            when: activationArtifact.activationIssueKinds != chain.activationReadinessResult
                .issues
                .map(\.gate),
            to: &issues
        )
        append(
            "chainIssueKindsMismatch",
            when: activationArtifact.chainIssueKinds != expectedActivationChainIssueKinds,
            to: &issues
        )
        append(
            "deterministicSummaryMismatch",
            when: activationArtifact.deterministicSummary != expectedActivationArtifact
                .deterministicSummary,
            to: &issues
        )
        return issues
    }

    var combinedBlockedIssueKinds: [String] {
        constructionBlockedIssueKinds.map { "construction.\($0)" }
            + activationBlockedIssueKinds.map { "activation.\($0.rawValue)" }
            + activationArtifactPairIssueKinds.map { "activationPair.\($0)" }
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        constructionConsumer.releaseBlockerFlags
    }

    var sideEffectFlags: TimelineHomeActivationArtifactChainSideEffectFlags {
        TimelineHomeActivationArtifactChainSideEffectFlags.make(from: self)
    }

    var startupNetworkClean: Bool {
        activationConsumer.startupNetworkClean
            && !sideEffectFlags.networkStarted
    }

    var readMarkerChanged: Bool {
        activationConsumer.readMarkerChanged
            || sideEffectFlags.readMarkerChanged
    }

    var requiresNetworkWork: Bool {
        activationConsumer.requiresNetworkWork
            || sideEffectFlags.requiresNetworkWork
    }

    var requiresDBWrite: Bool {
        activationConsumer.requiresDBWrite
            || sideEffectFlags.requiresDBWrite
    }

    var dataSourceApplyFromRootCalled: Bool {
        activationConsumer.dataSourceApplyFromRootCalled
    }

    var extraNostrHomeTimelineStoreConstructed: Bool {
        activationConsumer.extraNostrHomeTimelineStoreConstructed
            || sideEffectFlags.extraNostrHomeTimelineStoreConstructed
    }

    var timelineSurfaceConstructedFromRoot: Bool {
        constructionConsumer.timelineSurfaceConstructedFromRoot
    }

    var diagnosticsSummary: TimelineHomeActivationArtifactChainDiagnosticsSummary {
        TimelineHomeActivationArtifactChainDiagnosticsSummary(
            routeDecision: constructionConsumer.diagnosticsSummaries.routeDecision,
            constructionReadiness: constructionConsumer.diagnosticsSummaries.constructionReadiness,
            offscreenHarness: constructionConsumer.diagnosticsSummaries.offscreenHarness,
            flaggedConstruction: activationConsumer.result.artifactSummary.flaggedConstructionSummary,
            activation: activationConsumer.result.artifactSummary.deterministicSummary
        )
    }

    var debugSummary: TimelineHomeActivationArtifactChainDebugSummary {
        TimelineHomeActivationArtifactChainDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }

    var expectedActivationChainIssueKinds: [String] {
        var issues = constructionConsumer.combinedBlockedIssueKinds
        append("artifact.renderedRouteNotLegacy", when: !constructionConsumer.didRenderLegacy, to: &issues)
        append("artifact.activationOpen", when: constructionConsumer.routeActivationAllowed, to: &issues)
        append(
            "artifact.collectionViewRouteConstructedFromRoot",
            when: constructionConsumer.collectionViewRouteConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.timelineSurfaceConstructedFromRoot",
            when: constructionConsumer.timelineSurfaceConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.timelineCollectionViewControllerConstructedFromRoot",
            when: constructionConsumer.timelineCollectionViewControllerConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.forbiddenDataSourceApply",
            when: constructionConsumer.forbiddenDataSourceApplyOutsideCoordinatorCalled,
            to: &issues
        )
        append(
            "artifact.releaseBlockersPresent",
            when: !constructionConsumer.releaseBlockerFlags.isEmpty,
            to: &issues
        )
        append(
            "artifact.sideEffectsDirty",
            when: constructionConsumer.sideEffectFlags.hasActivationSideEffects,
            to: &issues
        )
        return issues
    }

    private func append(
        _ issue: String,
        when condition: Bool,
        to issues: inout [String]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }

    private func appendUnique(
        _ issue: TimelineHomeCollectionViewRouteActivationGate,
        when condition: Bool,
        to issues: inout [TimelineHomeCollectionViewRouteActivationGate]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

struct TimelineHomeActivationArtifactChainDiagnosticsSummary: Codable, Equatable, Sendable {
    var routeDecision: String
    var constructionReadiness: String
    var offscreenHarness: String
    var flaggedConstruction: String
    var activation: String
}

struct TimelineHomeActivationArtifactChainSideEffectFlags: Codable, Equatable, Sendable {
    var rootViewConstructed: Bool
    var homeTimelineViewConstructed: Bool
    var nostrHomeTimelineStoreConstructed: Bool
    var timelineCollectionViewControllerConstructed: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerChanged: Bool
    var dataSourceApplyCalled: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool

    static func make(
        from consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> TimelineHomeActivationArtifactChainSideEffectFlags {
        let construction = consumer.constructionConsumer.sideEffectFlags
        let activation = consumer.activationConsumer.result
        let extraStoreConstructed = !activation.noExtraNostrHomeTimelineStore
            || construction.nostrHomeTimelineStoreConstructed
        return TimelineHomeActivationArtifactChainSideEffectFlags(
            rootViewConstructed: construction.rootViewConstructed,
            homeTimelineViewConstructed: construction.homeTimelineViewConstructed,
            nostrHomeTimelineStoreConstructed: construction.nostrHomeTimelineStoreConstructed,
            timelineCollectionViewControllerConstructed: construction
                .timelineCollectionViewControllerConstructed,
            networkStarted: construction.networkStarted || activation.networkStarted,
            dbWriteAttempted: construction.dbWriteAttempted || activation.dbWriteAttempted,
            readMarkerChanged: construction.readMarkerAdvanced
                || activation.readMarkerChanged
                || activation.readMarkerAdvanced,
            dataSourceApplyCalled: construction.dataSourceApplyCalled
                || activation.dataSourceApplyFromRootCalled,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: construction
                .forbiddenDataSourceApplyOutsideCoordinatorCalled
                || activation.dataSourceApplyFromRootCalled,
            requiresNetworkWork: construction.requiresNetworkWork || activation.requiresNetworkWork,
            requiresDBWrite: construction.requiresDBWrite || activation.requiresDBWrite,
            dataSourceApplyFromRootCalled: activation.dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: extraStoreConstructed
        )
    }

    var deterministicText: String {
        [
            "root=\(rootViewConstructed)",
            "home=\(homeTimelineViewConstructed)",
            "nostrStore=\(nostrHomeTimelineStoreConstructed)",
            "collectionView=\(timelineCollectionViewControllerConstructed)",
            "network=\(networkStarted)",
            "dbWrite=\(dbWriteAttempted)",
            "readMarker=\(readMarkerChanged)",
            "dataSourceApply=\(dataSourceApplyCalled)",
            "forbiddenDataSourceApply=\(forbiddenDataSourceApplyOutsideCoordinatorCalled)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)",
            "dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled)",
            "extraNostrStore=\(extraNostrHomeTimelineStoreConstructed)"
        ].joined(separator: ",")
    }
}

struct TimelineHomeActivationArtifactChainDebugSummary: Codable, Equatable, Sendable {
    var constructionReady: Bool
    var constructionAllowed: Bool
    var offscreenHarnessAllowed: Bool
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var constructionBlockedIssueKinds: [String]
    var activationBlockedIssueKinds: [TimelineHomeCollectionViewRouteActivationGate]
    var activationArtifactPairIssueKinds: [String]
    var combinedBlockedIssueKinds: [String]
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    var sideEffectFlags: TimelineHomeActivationArtifactChainSideEffectFlags
    var startupNetworkClean: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var diagnosticsSummary: TimelineHomeActivationArtifactChainDiagnosticsSummary

    static func make(
        from consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> TimelineHomeActivationArtifactChainDebugSummary {
        TimelineHomeActivationArtifactChainDebugSummary(
            constructionReady: consumer.constructionReady,
            constructionAllowed: consumer.constructionAllowed,
            offscreenHarnessAllowed: consumer.offscreenHarnessAllowed,
            activationWouldBeAllowed: consumer.activationWouldBeAllowed,
            activationPerformed: consumer.activationPerformed,
            productionRenderSwitchPerformed: consumer.productionRenderSwitchPerformed,
            renderedRoute: consumer.renderedRoute,
            rollbackRoute: consumer.rollbackRoute,
            manualFallbackRoute: consumer.manualFallbackRoute,
            constructionBlockedIssueKinds: consumer.constructionBlockedIssueKinds,
            activationBlockedIssueKinds: consumer.activationBlockedIssueKinds,
            activationArtifactPairIssueKinds: consumer.activationArtifactPairIssueKinds,
            combinedBlockedIssueKinds: consumer.combinedBlockedIssueKinds,
            releaseBlockerFlags: consumer.releaseBlockerFlags,
            sideEffectFlags: consumer.sideEffectFlags,
            startupNetworkClean: consumer.startupNetworkClean,
            readMarkerChanged: consumer.readMarkerChanged,
            requiresNetworkWork: consumer.requiresNetworkWork,
            requiresDBWrite: consumer.requiresDBWrite,
            dataSourceApplyFromRootCalled: consumer.dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: consumer
                .extraNostrHomeTimelineStoreConstructed,
            diagnosticsSummary: consumer.diagnosticsSummary
        )
    }

    var deterministicText: String {
        [
            "constructionReady=\(constructionReady)",
            "constructionAllowed=\(constructionAllowed)",
            "offscreenHarnessAllowed=\(offscreenHarnessAllowed)",
            "activationWouldBeAllowed=\(activationWouldBeAllowed)",
            "activationPerformed=\(activationPerformed)",
            "productionRenderSwitchPerformed=\(productionRenderSwitchPerformed)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "rollbackRoute=\(rollbackRoute.rawValue)",
            "manualFallbackRoute=\(manualFallbackRoute.rawValue)",
            "constructionIssues=\(constructionBlockedIssueKinds.debugList)",
            "activationIssues=\(activationBlockedIssueKinds.map(\.rawValue).debugList)",
            "activationPairIssues=\(activationArtifactPairIssueKinds.debugList)",
            "combinedIssues=\(combinedBlockedIssueKinds.debugList)",
            "releaseBlockers=\(releaseBlockerFlags.map(\.rawValue).debugList)",
            "sideEffects(\(sideEffectFlags.deterministicText))",
            "startupNetworkClean=\(startupNetworkClean)",
            "readMarkerChanged=\(readMarkerChanged)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)",
            "dataSourceApplyFromRoot=\(dataSourceApplyFromRootCalled)",
            "extraNostrHomeTimelineStoreConstructed=\(extraNostrHomeTimelineStoreConstructed)",
            "diagnostics(route={\(diagnosticsSummary.routeDecision)},construction={\(diagnosticsSummary.constructionReadiness)},offscreen={\(diagnosticsSummary.offscreenHarness)},flagged={\(diagnosticsSummary.flaggedConstruction)},activation={\(diagnosticsSummary.activation)})"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}

private extension TimelineHomeConstructionArtifactChainSideEffectFlags {
    var hasActivationSideEffects: Bool {
        rootViewConstructed
            || homeTimelineViewConstructed
            || nostrHomeTimelineStoreConstructed
            || timelineCollectionViewControllerConstructed
            || networkStarted
            || dbWriteAttempted
            || readMarkerAdvanced
            || dataSourceApplyCalled
            || forbiddenDataSourceApplyOutsideCoordinatorCalled
            || requiresNetworkWork
            || requiresDBWrite
    }
}
