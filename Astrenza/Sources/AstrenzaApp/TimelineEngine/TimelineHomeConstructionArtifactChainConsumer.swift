import Foundation

struct TimelineHomeConstructionArtifactChain: Codable, Equatable, Sendable {
    var routeDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot
    var constructionReadinessResult: TimelineHomeRouteConstructionReadinessResult
    var offscreenHarnessResult: TimelineHomeOffscreenConstructionHarnessResult
}

struct TimelineHomeConstructionArtifactChainReader: Codable, Equatable, Sendable {
    var chain: TimelineHomeConstructionArtifactChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeConstructionArtifactChainReader {
        TimelineHomeConstructionArtifactChainReader(
            chain: try decoder.decode(
                TimelineHomeConstructionArtifactChain.self,
                from: data
            )
        )
    }

    var consumer: TimelineHomeConstructionArtifactChainConsumer {
        TimelineHomeConstructionArtifactChainConsumer(chain: chain)
    }
}

struct TimelineHomeConstructionArtifactChainConsumer: Codable, Equatable, Sendable {
    var chain: TimelineHomeConstructionArtifactChain

    static func decodeFixtureJSON(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TimelineHomeConstructionArtifactChainConsumer {
        try TimelineHomeConstructionArtifactChainReader
            .decodeFixtureJSON(data, decoder: decoder)
            .consumer
    }

    var routeDecisionConsumer: TimelineHomeRootRouteDecisionSnapshotConsumer {
        TimelineHomeRootRouteDecisionSnapshotConsumer(snapshot: chain.routeDecisionSnapshot)
    }

    var constructionReadinessConsumer: TimelineHomeRouteConstructionReadinessConsumer {
        TimelineHomeRouteConstructionReadinessConsumer(result: chain.constructionReadinessResult)
    }

    var offscreenHarnessConsumer: TimelineHomeOffscreenConstructionHarnessResultConsumer {
        TimelineHomeOffscreenConstructionHarnessResultConsumer(result: chain.offscreenHarnessResult)
    }

    var didRenderLegacy: Bool {
        routeDecisionConsumer.didRenderLegacy
            && constructionReadinessConsumer.renderedRouteAfterConstruction == .legacy
            && offscreenHarnessConsumer.renderedRouteAfterConstruction == .legacy
    }

    var didObserveCollectionView: Bool {
        routeDecisionConsumer.didObserveCollectionView
    }

    var constructionReady: Bool {
        constructionReadinessConsumer.isReady
    }

    var constructionAllowed: Bool {
        constructionReadinessConsumer.constructionAllowed
    }

    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind {
        constructionReadinessConsumer.constructionKind
    }

    var offscreenHarnessAllowed: Bool {
        offscreenHarnessConsumer.isAllowed
    }

    var noWindowAttached: Bool {
        offscreenHarnessConsumer.noWindowAttached
    }

    var routeActivationAllowed: Bool {
        constructionReadinessConsumer.routeActivationAllowed
            || offscreenHarnessConsumer.routeActivationAllowed
    }

    var collectionViewRouteConstructedFromRoot: Bool {
        routeDecisionConsumer.didConstructCollectionView
            || constructionReadinessConsumer.collectionViewRouteConstructed
            || offscreenHarnessConsumer.collectionViewRouteConstructedFromRoot
    }

    var timelineSurfaceConstructedFromRoot: Bool {
        constructionReadinessConsumer.timelineSurfaceConstructed
            || offscreenHarnessConsumer.timelineSurfaceConstructedFromRoot
    }

    var timelineCollectionViewControllerConstructedFromRoot: Bool {
        constructionReadinessConsumer.timelineCollectionViewControllerConstructedFromRoot
            || offscreenHarnessConsumer.timelineCollectionViewControllerConstructedFromRoot
    }

    var coordinatorOwnedDataSourceApplyAllowed: Bool {
        offscreenHarnessConsumer.coordinatorOwnedDataSourceApplyAllowed
    }

    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool {
        offscreenHarnessConsumer.forbiddenDataSourceApplyOutsideCoordinatorCalled
    }

    var combinedBlockedIssueKinds: [String] {
        routeDecisionConsumer.fallbackIssueKinds.map { "routeDecision.\($0.rawValue)" }
            + constructionReadinessConsumer.blockedIssueKinds.map { "readiness.\($0.rawValue)" }
            + offscreenHarnessConsumer.rejectionIssueKinds.map { "offscreen.\($0.rawValue)" }
    }

    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag] {
        var flags: [TimelineHomeRouteReleaseBlockerFlag] = []
        appendUnique(routeDecisionConsumer.releaseBlockerFlags, to: &flags)
        appendUnique(constructionReadinessConsumer.releaseBlockerFlags, to: &flags)
        appendUnique(
            offscreenHarnessConsumer.diagnosticsArtifactSummary.releaseBlockerFlags,
            to: &flags
        )
        return flags
    }

    var sideEffectFlags: TimelineHomeConstructionArtifactChainSideEffectFlags {
        TimelineHomeConstructionArtifactChainSideEffectFlags.make(from: self)
    }

    var diagnosticsSummaries: TimelineHomeConstructionArtifactChainDiagnosticsSummaries {
        TimelineHomeConstructionArtifactChainDiagnosticsSummaries(
            routeDecision: routeDecisionConsumer.artifactSummary.deterministicSummary,
            constructionReadiness: constructionReadinessConsumer.artifactDeterministicSummary,
            offscreenHarness: offscreenHarnessConsumer.artifactDeterministicSummary
        )
    }

    var debugSummary: TimelineHomeConstructionArtifactChainDebugSummary {
        TimelineHomeConstructionArtifactChainDebugSummary.make(from: self)
    }

    var deterministicDebugSummary: String {
        debugSummary.deterministicText
    }

    private func appendUnique(
        _ source: [TimelineHomeRouteReleaseBlockerFlag],
        to destination: inout [TimelineHomeRouteReleaseBlockerFlag]
    ) {
        for flag in source where !destination.contains(flag) {
            destination.append(flag)
        }
    }
}

struct TimelineHomeConstructionArtifactChainDiagnosticsSummaries: Codable, Equatable, Sendable {
    var routeDecision: String
    var constructionReadiness: String
    var offscreenHarness: String
}

struct TimelineHomeConstructionArtifactChainSideEffectFlags: Codable, Equatable, Sendable {
    var rootViewConstructed: Bool
    var homeTimelineViewConstructed: Bool
    var nostrHomeTimelineStoreConstructed: Bool
    var timelineCollectionViewControllerConstructed: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyCalled: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool

    static func make(
        from consumer: TimelineHomeConstructionArtifactChainConsumer
    ) -> TimelineHomeConstructionArtifactChainSideEffectFlags {
        let routeSideEffects = consumer.routeDecisionConsumer.sideEffectFlags
        let constructionSideEffects = consumer.constructionReadinessConsumer.sideEffectFlags
        return TimelineHomeConstructionArtifactChainSideEffectFlags(
            rootViewConstructed: routeSideEffects.rootViewConstructed
                || constructionSideEffects.rootViewConstructed,
            homeTimelineViewConstructed: routeSideEffects.homeTimelineViewConstructed
                || constructionSideEffects.homeTimelineViewConstructed,
            nostrHomeTimelineStoreConstructed: routeSideEffects.nostrHomeTimelineStoreConstructed
                || constructionSideEffects.nostrHomeTimelineStoreConstructed,
            timelineCollectionViewControllerConstructed: routeSideEffects.timelineCollectionViewControllerConstructed
                || constructionSideEffects.timelineCollectionViewControllerConstructed,
            networkStarted: routeSideEffects.networkStarted
                || constructionSideEffects.networkStarted
                || consumer.offscreenHarnessConsumer.networkStarted,
            dbWriteAttempted: routeSideEffects.dbWriteAttempted
                || constructionSideEffects.dbWriteAttempted
                || consumer.offscreenHarnessConsumer.dbWriteAttempted,
            readMarkerAdvanced: routeSideEffects.readMarkerAdvanced
                || constructionSideEffects.readMarkerAdvanced
                || consumer.offscreenHarnessConsumer.readMarkerAdvanced,
            dataSourceApplyCalled: routeSideEffects.dataSourceApplyCalled
                || constructionSideEffects.dataSourceApplyCalled
                || consumer.chain.routeDecisionSnapshot.dataSourceApplyCalled
                || consumer.chain.constructionReadinessResult.plan.dataSourceApplyCalled,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: consumer
                .forbiddenDataSourceApplyOutsideCoordinatorCalled,
            requiresNetworkWork: consumer.chain.routeDecisionSnapshot.requiresNetworkWork
                || consumer.chain.constructionReadinessResult.plan.requiresNetworkWork,
            requiresDBWrite: consumer.chain.routeDecisionSnapshot.requiresDBWrite
                || consumer.chain.constructionReadinessResult.plan.requiresDBWrite
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
            "readMarker=\(readMarkerAdvanced)",
            "dataSourceApply=\(dataSourceApplyCalled)",
            "forbiddenDataSourceApply=\(forbiddenDataSourceApplyOutsideCoordinatorCalled)",
            "requiresNetworkWork=\(requiresNetworkWork)",
            "requiresDBWrite=\(requiresDBWrite)"
        ].joined(separator: ",")
    }
}

struct TimelineHomeConstructionArtifactChainDebugSummary: Codable, Equatable, Sendable {
    var didRenderLegacy: Bool
    var didObserveCollectionView: Bool
    var constructionReady: Bool
    var constructionAllowed: Bool
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var offscreenHarnessAllowed: Bool
    var noWindowAttached: Bool
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructedFromRoot: Bool
    var timelineSurfaceConstructedFromRoot: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var combinedBlockedIssueKinds: [String]
    var releaseBlockerFlags: [TimelineHomeRouteReleaseBlockerFlag]
    var sideEffectFlags: TimelineHomeConstructionArtifactChainSideEffectFlags
    var diagnosticsSummaries: TimelineHomeConstructionArtifactChainDiagnosticsSummaries

    static func make(
        from consumer: TimelineHomeConstructionArtifactChainConsumer
    ) -> TimelineHomeConstructionArtifactChainDebugSummary {
        TimelineHomeConstructionArtifactChainDebugSummary(
            didRenderLegacy: consumer.didRenderLegacy,
            didObserveCollectionView: consumer.didObserveCollectionView,
            constructionReady: consumer.constructionReady,
            constructionAllowed: consumer.constructionAllowed,
            constructionKind: consumer.constructionKind,
            offscreenHarnessAllowed: consumer.offscreenHarnessAllowed,
            noWindowAttached: consumer.noWindowAttached,
            routeActivationAllowed: consumer.routeActivationAllowed,
            collectionViewRouteConstructedFromRoot: consumer.collectionViewRouteConstructedFromRoot,
            timelineSurfaceConstructedFromRoot: consumer.timelineSurfaceConstructedFromRoot,
            timelineCollectionViewControllerConstructedFromRoot: consumer
                .timelineCollectionViewControllerConstructedFromRoot,
            coordinatorOwnedDataSourceApplyAllowed: consumer.coordinatorOwnedDataSourceApplyAllowed,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: consumer
                .forbiddenDataSourceApplyOutsideCoordinatorCalled,
            combinedBlockedIssueKinds: consumer.combinedBlockedIssueKinds,
            releaseBlockerFlags: consumer.releaseBlockerFlags,
            sideEffectFlags: consumer.sideEffectFlags,
            diagnosticsSummaries: consumer.diagnosticsSummaries
        )
    }

    var deterministicText: String {
        [
            "didRenderLegacy=\(didRenderLegacy)",
            "didObserveCollectionView=\(didObserveCollectionView)",
            "constructionReady=\(constructionReady)",
            "constructionAllowed=\(constructionAllowed)",
            "constructionKind=\(constructionKind.rawValue)",
            "offscreenHarnessAllowed=\(offscreenHarnessAllowed)",
            "noWindowAttached=\(noWindowAttached)",
            "routeActivationAllowed=\(routeActivationAllowed)",
            "rootConstructed(route=\(collectionViewRouteConstructedFromRoot),surface=\(timelineSurfaceConstructedFromRoot),controller=\(timelineCollectionViewControllerConstructedFromRoot))",
            "coordinatorApplyAllowed=\(coordinatorOwnedDataSourceApplyAllowed)",
            "forbiddenDataSourceApplyOutsideCoordinatorCalled=\(forbiddenDataSourceApplyOutsideCoordinatorCalled)",
            "blockedIssues=\(combinedBlockedIssueKinds.debugList)",
            "releaseBlockers=\(releaseBlockerFlags.map(\.rawValue).debugList)",
            "sideEffects(\(sideEffectFlags.deterministicText))",
            "diagnostics(route={\(diagnosticsSummaries.routeDecision)},construction={\(diagnosticsSummaries.constructionReadiness)},offscreen={\(diagnosticsSummaries.offscreenHarness)})"
        ].joined(separator: " ")
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
