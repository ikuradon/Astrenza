import Foundation

enum TimelineHomeCollectionViewRouteActivationGate: String, CaseIterable, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case constructionGatesClean
    case flaggedConstructionResultClean
    case artifactChainClean
    case offscreenNoWindowSmokePassed
    case initialRestoreSnapshotCoordinatorHarnessPassed
    case startupNetworkPatternClean
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case requiresNetworkWorkFalse
    case requiresDBWriteFalse
    case dataSourceApplyCoordinatorOnly
    case noExtraNostrHomeTimelineStore
    case rootBodyDecisionSnapshotPermitsActivationScope
    case timelineAreaRestoreGateOnly
    case rootShellFirstPaintPreserved
}

struct TimelineHomeCollectionViewRouteActivationIssue: Codable, Equatable, Sendable {
    var gate: TimelineHomeCollectionViewRouteActivationGate
}

struct TimelineHomeCollectionViewRouteActivationArtifactSummary: Codable, Equatable, Sendable {
    var routeDecisionSummary: String
    var constructionReadinessSummary: String
    var offscreenHarnessSummary: String
    var flaggedConstructionSummary: String
    var sideEffectSummary: String
    var activationIssueKinds: [TimelineHomeCollectionViewRouteActivationGate]
    var chainIssueKinds: [String]
    var deterministicSummary: String

    static func make(
        consumer: TimelineHomeConstructionArtifactChainConsumer?,
        constructionResult: TimelineHomeCollectionViewRouteConstructionResult,
        issues: [TimelineHomeCollectionViewRouteActivationIssue],
        chainIssueKinds: [String]
    ) -> TimelineHomeCollectionViewRouteActivationArtifactSummary {
        let routeDecisionSummary = consumer?.diagnosticsSummaries.routeDecision ?? "none"
        let constructionReadinessSummary = consumer?.diagnosticsSummaries.constructionReadiness ?? "none"
        let offscreenHarnessSummary = consumer?.diagnosticsSummaries.offscreenHarness ?? "none"
        let flaggedConstructionSummary = constructionResult.artifactSummary.deterministicSummary
        let sideEffectSummary = Self.sideEffectSummary(
            consumer: consumer,
            constructionResult: constructionResult
        )
        let activationIssueKinds = issues.map(\.gate)
        let deterministicSummary = [
            "activationWouldBeAllowed=\(issues.isEmpty)",
            "activationPerformed=false",
            "productionRenderSwitchPerformed=false",
            "renderedRoute=legacy",
            "rollbackRoute=legacy",
            "manualFallbackRoute=legacy",
            "issues=\(activationIssueKinds.map(\.rawValue).debugList)",
            "chainIssues=\(chainIssueKinds.debugList)",
            "sideEffects(\(sideEffectSummary))",
            "routeDecision={\(routeDecisionSummary)}",
            "constructionReadiness={\(constructionReadinessSummary)}",
            "offscreenHarness={\(offscreenHarnessSummary)}",
            "flaggedConstruction={\(flaggedConstructionSummary)}"
        ].joined(separator: " ")

        return TimelineHomeCollectionViewRouteActivationArtifactSummary(
            routeDecisionSummary: routeDecisionSummary,
            constructionReadinessSummary: constructionReadinessSummary,
            offscreenHarnessSummary: offscreenHarnessSummary,
            flaggedConstructionSummary: flaggedConstructionSummary,
            sideEffectSummary: sideEffectSummary,
            activationIssueKinds: activationIssueKinds,
            chainIssueKinds: chainIssueKinds,
            deterministicSummary: deterministicSummary
        )
    }

    private static var cleanSideEffectSummary: String {
        [
            "root=false",
            "home=false",
            "nostrStore=false",
            "collectionView=false",
            "network=false",
            "dbWrite=false",
            "readMarker=false",
            "dataSourceApply=false",
            "forbiddenDataSourceApply=false",
            "requiresNetworkWork=false",
            "requiresDBWrite=false"
        ].joined(separator: ",")
    }

    private static func sideEffectSummary(
        consumer: TimelineHomeConstructionArtifactChainConsumer?,
        constructionResult: TimelineHomeCollectionViewRouteConstructionResult
    ) -> String {
        guard let consumer else {
            return cleanSideEffectSummary
        }
        let sideEffects = consumer.sideEffectFlags
        return [
            "root=\(sideEffects.rootViewConstructed)",
            "home=\(sideEffects.homeTimelineViewConstructed)",
            "nostrStore=\(sideEffects.nostrHomeTimelineStoreConstructed)",
            "collectionView=\(sideEffects.timelineCollectionViewControllerConstructed)",
            "network=\(sideEffects.networkStarted || constructionResult.networkStarted)",
            "dbWrite=\(sideEffects.dbWriteAttempted || constructionResult.dbWriteAttempted)",
            "readMarker=\(sideEffects.readMarkerAdvanced || constructionResult.readMarkerAdvanced)",
            "dataSourceApply=\(sideEffects.dataSourceApplyCalled || constructionResult.dataSourceApplyFromRootCalled)",
            "forbiddenDataSourceApply=\(sideEffects.forbiddenDataSourceApplyOutsideCoordinatorCalled || constructionResult.dataSourceApplyFromRootCalled)",
            "requiresNetworkWork=\(sideEffects.requiresNetworkWork)",
            "requiresDBWrite=\(sideEffects.requiresDBWrite)"
        ].joined(separator: ",")
    }
}

struct TimelineHomeCollectionViewRouteActivationResult: Codable, Equatable, Sendable {
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var constructionResult: TimelineHomeCollectionViewRouteConstructionResult
    var artifactSummary: TimelineHomeCollectionViewRouteActivationArtifactSummary
    var issues: [TimelineHomeCollectionViewRouteActivationIssue]
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var dbWriteAttempted: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var createdAtMS: Int64
}

struct TimelineHomeCollectionViewRouteActivationReadiness: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var debugOverride: TimelineHomeRouteDebugOverride?
    var constructionResult: TimelineHomeCollectionViewRouteConstructionResult
    var artifactChain: TimelineHomeConstructionArtifactChain
    var offscreenNoWindowSmokePassed: Bool
    var initialRestoreSnapshotCoordinatorHarnessPassed: Bool
    var startupNetworkPatternClean: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyCoordinatorOnly: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var rootBodyDecisionSnapshotPermitsActivationScope: Bool
    var createdAtMS: Int64

    func evaluate() -> TimelineHomeCollectionViewRouteActivationResult {
        let consumer = TimelineHomeConstructionArtifactChainConsumer(chain: artifactChain)
        let snapshot = artifactChain.routeDecisionSnapshot
        let chainIssueKinds = Self.chainIssueKinds(for: consumer)
        let coordinatorOwnedDataSourceApplyAllowed = dataSourceApplyCoordinatorOnly
            && consumer.coordinatorOwnedDataSourceApplyAllowed
            && !consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled
            && constructionResult.coordinatorOwnedDataSourceApplyAllowed
            && !constructionResult.dataSourceApplyFromRootCalled
        let storeMarkerClean = noExtraNostrHomeTimelineStore
            && constructionResult.noExtraNostrHomeTimelineStore
            && !consumer.sideEffectFlags.nostrHomeTimelineStoreConstructed
        let observedNetworkStarted = constructionResult.networkStarted
            || consumer.sideEffectFlags.networkStarted
        let observedDBWriteAttempted = constructionResult.dbWriteAttempted
            || consumer.sideEffectFlags.dbWriteAttempted
        let observedReadMarkerAdvanced = constructionResult.readMarkerAdvanced
            || consumer.sideEffectFlags.readMarkerAdvanced
        let observedDataSourceApplyFromRootCalled = constructionResult.dataSourceApplyFromRootCalled
        let observedReadMarkerChanged = readMarkerChanged
            || snapshot.readMarkerChanged
            || observedReadMarkerAdvanced
        let observedRequiresNetworkWork = requiresNetworkWork
            || snapshot.requiresNetworkWork
            || consumer.sideEffectFlags.requiresNetworkWork
        let observedRequiresDBWrite = requiresDBWrite
            || snapshot.requiresDBWrite
            || consumer.sideEffectFlags.requiresDBWrite
        let observedNetworkWaitedBeforeInteractiveScrollMS = max(
            networkWaitedBeforeInteractiveScrollMS,
            snapshot.networkWaitedBeforeInteractiveScrollMS
        )
        var issues: [TimelineHomeCollectionViewRouteActivationIssue] = []

        append(.explicitCollectionViewLaunchFlag, when: !hasExplicitCollectionViewLaunchFlag, to: &issues)
        append(
            .constructionGatesClean,
            when: !consumer.constructionReady
                || !consumer.constructionAllowed
                || !consumer.didRenderLegacy,
            to: &issues
        )
        append(.flaggedConstructionResultClean, when: !constructionResult.isActivationClean, to: &issues)
        append(.artifactChainClean, when: !chainIssueKinds.isEmpty, to: &issues)
        append(
            .offscreenNoWindowSmokePassed,
            when: !offscreenNoWindowSmokePassed
                || !consumer.offscreenHarnessAllowed
                || !consumer.noWindowAttached,
            to: &issues
        )
        append(
            .initialRestoreSnapshotCoordinatorHarnessPassed,
            when: !initialRestoreSnapshotCoordinatorHarnessPassed,
            to: &issues
        )
        append(.startupNetworkPatternClean, when: !startupNetworkPatternClean, to: &issues)
        append(
            .networkWaitedBeforeInteractiveScrollZero,
            when: observedNetworkWaitedBeforeInteractiveScrollMS != 0,
            to: &issues
        )
        append(.readMarkerUnchanged, when: observedReadMarkerChanged, to: &issues)
        append(.requiresNetworkWorkFalse, when: observedRequiresNetworkWork, to: &issues)
        append(.requiresDBWriteFalse, when: observedRequiresDBWrite, to: &issues)
        append(.dataSourceApplyCoordinatorOnly, when: !coordinatorOwnedDataSourceApplyAllowed, to: &issues)
        append(.noExtraNostrHomeTimelineStore, when: !storeMarkerClean, to: &issues)
        append(
            .rootBodyDecisionSnapshotPermitsActivationScope,
            when: !rootBodyDecisionSnapshotPermitsActivationScope,
            to: &issues
        )
        append(
            .timelineAreaRestoreGateOnly,
            when: snapshot.timelineRestoreGateScope != .timelineArea
                || snapshot.timelineGateCoversRootShell
                || snapshot.timelineGateCoversTabBar
                || snapshot.timelineGateContinuesGlobalSplash,
            to: &issues
        )
        append(
            .rootShellFirstPaintPreserved,
            when: snapshot.rootShellPresentation != .immediate
                || !snapshot.rootShellMustRenderBeforeTimelineRestore
                || !snapshot.rootShellUnchanged,
            to: &issues
        )

        let artifactSummary = TimelineHomeCollectionViewRouteActivationArtifactSummary.make(
            consumer: consumer,
            constructionResult: constructionResult,
            issues: issues,
            chainIssueKinds: chainIssueKinds
        )

        return TimelineHomeCollectionViewRouteActivationResult(
            activationWouldBeAllowed: issues.isEmpty,
            activationPerformed: false,
            productionRenderSwitchPerformed: false,
            renderedRoute: .legacy,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            constructionResult: constructionResult,
            artifactSummary: artifactSummary,
            issues: issues,
            networkStarted: observedNetworkStarted,
            networkWaitedBeforeInteractiveScrollMS: observedNetworkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: observedReadMarkerChanged,
            readMarkerAdvanced: observedReadMarkerAdvanced,
            dbWriteAttempted: observedDBWriteAttempted,
            requiresNetworkWork: observedRequiresNetworkWork,
            requiresDBWrite: observedRequiresDBWrite,
            dataSourceApplyFromRootCalled: observedDataSourceApplyFromRootCalled,
            coordinatorOwnedDataSourceApplyAllowed: coordinatorOwnedDataSourceApplyAllowed,
            noExtraNostrHomeTimelineStore: storeMarkerClean,
            rootShellPresentation: snapshot.rootShellPresentation,
            rootShellMustRenderBeforeTimelineRestore: snapshot.rootShellMustRenderBeforeTimelineRestore,
            timelineRestoreGateScope: snapshot.timelineRestoreGateScope,
            timelineGateCoversRootShell: snapshot.timelineGateCoversRootShell,
            timelineGateCoversTabBar: snapshot.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: snapshot.timelineGateContinuesGlobalSplash,
            createdAtMS: createdAtMS
        )
    }

    private var hasExplicitCollectionViewLaunchFlag: Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: launchArguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func chainIssueKinds(
        for consumer: TimelineHomeConstructionArtifactChainConsumer
    ) -> [String] {
        var issues = consumer.combinedBlockedIssueKinds
        append("artifact.renderedRouteNotLegacy", when: !consumer.didRenderLegacy, to: &issues)
        append("artifact.activationOpen", when: consumer.routeActivationAllowed, to: &issues)
        append(
            "artifact.collectionViewRouteConstructedFromRoot",
            when: consumer.collectionViewRouteConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.timelineSurfaceConstructedFromRoot",
            when: consumer.timelineSurfaceConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.timelineCollectionViewControllerConstructedFromRoot",
            when: consumer.timelineCollectionViewControllerConstructedFromRoot,
            to: &issues
        )
        append(
            "artifact.forbiddenDataSourceApply",
            when: consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled,
            to: &issues
        )
        append("artifact.releaseBlockersPresent", when: !consumer.releaseBlockerFlags.isEmpty, to: &issues)
        append("artifact.sideEffectsDirty", when: consumer.sideEffectFlags.hasActivationSideEffects, to: &issues)
        return issues
    }

    private func append(
        _ gate: TimelineHomeCollectionViewRouteActivationGate,
        when condition: Bool,
        to issues: inout [TimelineHomeCollectionViewRouteActivationIssue]
    ) {
        guard condition, !issues.contains(where: { $0.gate == gate }) else {
            return
        }
        issues.append(TimelineHomeCollectionViewRouteActivationIssue(gate: gate))
    }

    private static func append(
        _ issue: String,
        when condition: Bool,
        to issues: inout [String]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

private extension TimelineHomeCollectionViewRouteConstructionResult {
    var isActivationClean: Bool {
        constructionAllowed
            && issueKinds.isEmpty
            && collectionViewRouteConstructed
            && !collectionViewRouteConstructedFromRoot
            && !timelineSurfaceConstructed
            && !timelineSurfaceConstructedFromRoot
            && !timelineCollectionViewControllerConstructedFromRoot
            && renderedRouteAfterConstruction == .legacy
            && routeActivationAllowed == false
            && rootHomeRenderingChanged == false
            && legacyHomeRenderingPreserved
            && noExtraNostrHomeTimelineStore
            && !networkStarted
            && !dbWriteAttempted
            && !readMarkerAdvanced
            && !dataSourceApplyFromRootCalled
            && coordinatorOwnedDataSourceApplyAllowed
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

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
