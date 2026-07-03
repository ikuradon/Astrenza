import Foundation

struct TimelineHomeCollectionViewRouteActivationSwitchInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var mode: AstrenzaTimelineEngineMode
    var activationPreflightResult: TimelineHomeRootActivationPreflightResult?
    var rootActivationDecisionSnapshotResult: TimelineHomeRootActivationDecisionSnapshotResult?
    var activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer?
    var createdAtMS: Int64
}

enum TimelineHomeCollectionViewRouteActivationSwitchIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case activationPreflightPresent
    case activationPreflightAllows
    case rootActivationDecisionSnapshotPresent
    case rootActivationDecisionSnapshotAllows
    case activationArtifactChainPresent
    case activationReadinessPresent
    case activationArtifactChainClean
    case constructionGatesClean
    case flaggedConstructionResultClean
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

struct TimelineHomeCollectionViewRouteActivationSwitchDiagnostics: Codable, Equatable, Sendable {
    var rootActivationDecisionSummary: String
    var activationArtifactChainSummary: String
    var activationReadinessSummary: String
    var flaggedConstructionSummary: String
    var constructionReadinessSummary: String
    var offscreenHarnessSummary: String
    var sideEffectSummary: String
}

struct TimelineHomeRootRenderRouteDecision: Codable, Equatable, Sendable {
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
}

struct TimelineHomeActivatedRouteDecision: Codable, Equatable, Sendable {
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var routeDecision: TimelineHomeRootRenderRouteDecision
    var issueKinds: [TimelineHomeCollectionViewRouteActivationSwitchIssueKind]
    var diagnostics: TimelineHomeCollectionViewRouteActivationSwitchDiagnostics
    var routeDiagnosticsRecorded: Bool
    var activationArtifactChainRecorded: Bool
    var constructionArtifactChainRecorded: Bool
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var dbWriteAttempted: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var preventsDualMutation: Bool
    var createdAtMS: Int64
}

enum TimelineHomeCollectionViewRouteActivator {
    static func activate(
        _ input: TimelineHomeCollectionViewRouteActivationSwitchInput
    ) -> TimelineHomeActivatedRouteDecision {
        TimelineHomeCollectionViewRouteActivation.decide(input)
    }
}

enum TimelineHomeCollectionViewRouteActivation: Sendable {
    static func decide(
        _ input: TimelineHomeCollectionViewRouteActivationSwitchInput
    ) -> TimelineHomeActivatedRouteDecision {
        let consumer = input.activationArtifactChainConsumer
        let activationResult = consumer?.activationConsumer.result
        let sideEffects = consumer?.sideEffectFlags
        var issues: [TimelineHomeCollectionViewRouteActivationSwitchIssueKind] = []

        append(.explicitCollectionViewLaunchFlag, when: !hasExplicitCollectionViewLaunchFlag(input), to: &issues)
        append(.activationPreflightPresent, when: input.activationPreflightResult == nil, to: &issues)
        append(
            .activationPreflightAllows,
            when: input.activationPreflightResult?.activationWouldBeAllowed != true,
            to: &issues
        )
        append(.rootActivationDecisionSnapshotPresent, when: input.rootActivationDecisionSnapshotResult == nil, to: &issues)
        append(
            .rootActivationDecisionSnapshotAllows,
            when: input.rootActivationDecisionSnapshotResult?.activationWouldBeAllowed != true,
            to: &issues
        )
        append(.activationArtifactChainPresent, when: consumer == nil, to: &issues)
        append(.activationReadinessPresent, when: activationResult == nil, to: &issues)

        if let consumer, let activationResult {
            append(.activationArtifactChainClean, when: !isArtifactChainClean(consumer), to: &issues)
            append(.constructionGatesClean, when: !constructionGatesClean(consumer), to: &issues)
            append(.flaggedConstructionResultClean, when: !flaggedConstructionResultClean(consumer), to: &issues)
            append(.offscreenNoWindowSmokePassed, when: !offscreenNoWindowSmokePassed(consumer), to: &issues)
            append(
                .initialRestoreSnapshotCoordinatorHarnessPassed,
                when: activationResult.issues.contains(gate: .initialRestoreSnapshotCoordinatorHarnessPassed),
                to: &issues
            )
            append(
                .startupNetworkPatternClean,
                when: !consumer.startupNetworkClean
                    || activationResult.issues.contains(gate: .startupNetworkPatternClean)
                    || activationResult.networkStarted,
                to: &issues
            )
            append(
                .networkWaitedBeforeInteractiveScrollZero,
                when: activationResult.networkWaitedBeforeInteractiveScrollMS != 0,
                to: &issues
            )
            append(
                .readMarkerUnchanged,
                when: consumer.readMarkerChanged
                    || activationResult.readMarkerChanged
                    || activationResult.readMarkerAdvanced,
                to: &issues
            )
            append(
                .requiresNetworkWorkFalse,
                when: consumer.requiresNetworkWork || activationResult.requiresNetworkWork,
                to: &issues
            )
            append(
                .requiresDBWriteFalse,
                when: consumer.requiresDBWrite || activationResult.requiresDBWrite,
                to: &issues
            )
            append(
                .dataSourceApplyCoordinatorOnly,
                when: !activationResult.coordinatorOwnedDataSourceApplyAllowed
                    || consumer.dataSourceApplyFromRootCalled
                    || activationResult.dataSourceApplyFromRootCalled
                    || consumer.sideEffectFlags.forbiddenDataSourceApplyOutsideCoordinatorCalled,
                to: &issues
            )
            append(
                .noExtraNostrHomeTimelineStore,
                when: consumer.extraNostrHomeTimelineStoreConstructed
                    || !activationResult.noExtraNostrHomeTimelineStore,
                to: &issues
            )
            append(
                .rootBodyDecisionSnapshotPermitsActivationScope,
                when: activationResult.issues.contains(gate: .rootBodyDecisionSnapshotPermitsActivationScope),
                to: &issues
            )
            append(
                .timelineAreaRestoreGateOnly,
                when: activationResult.timelineRestoreGateScope != .timelineArea
                    || activationResult.timelineGateCoversRootShell
                    || activationResult.timelineGateCoversTabBar
                    || activationResult.timelineGateContinuesGlobalSplash,
                to: &issues
            )
            append(
                .rootShellFirstPaintPreserved,
                when: activationResult.rootShellPresentation != .immediate
                    || !activationResult.rootShellMustRenderBeforeTimelineRestore
                    || input.activationPreflightResult?.issues.contains(.rootShellFirstPaintMarker) == true,
                to: &issues
            )
        }

        let activationAllowed = issues.isEmpty
        let renderedRoute: TimelineHomeRootVisibleRouteDecision = activationAllowed ? .collectionView : .legacy
        let routeDecision = TimelineHomeRootRenderRouteDecision(
            renderedRoute: renderedRoute,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy
        )

        return TimelineHomeActivatedRouteDecision(
            activationWouldBeAllowed: activationAllowed,
            activationPerformed: activationAllowed,
            productionRenderSwitchPerformed: activationAllowed,
            renderedRoute: renderedRoute,
            rollbackRoute: routeDecision.rollbackRoute,
            manualFallbackRoute: routeDecision.manualFallbackRoute,
            routeDecision: routeDecision,
            issueKinds: issues,
            diagnostics: diagnostics(
                rootActivationDecisionSnapshotResult: input.rootActivationDecisionSnapshotResult,
                consumer: consumer
            ),
            routeDiagnosticsRecorded: input.rootActivationDecisionSnapshotResult != nil,
            activationArtifactChainRecorded: consumer != nil,
            constructionArtifactChainRecorded: consumer != nil,
            rootShellPresentation: activationResult?.rootShellPresentation ?? .immediate,
            rootShellMustRenderBeforeTimelineRestore: activationResult?.rootShellMustRenderBeforeTimelineRestore ?? true,
            timelineRestoreGateScope: activationResult?.timelineRestoreGateScope,
            timelineGateCoversRootShell: activationResult?.timelineGateCoversRootShell ?? false,
            timelineGateCoversTabBar: activationResult?.timelineGateCoversTabBar ?? false,
            timelineGateContinuesGlobalSplash: activationResult?.timelineGateContinuesGlobalSplash ?? false,
            networkStarted: sideEffects?.networkStarted ?? activationResult?.networkStarted ?? false,
            networkWaitedBeforeInteractiveScrollMS: activationResult?.networkWaitedBeforeInteractiveScrollMS ?? 0,
            readMarkerChanged: sideEffects?.readMarkerChanged ?? activationResult?.readMarkerChanged ?? false,
            readMarkerAdvanced: activationResult?.readMarkerAdvanced ?? false,
            dbWriteAttempted: sideEffects?.dbWriteAttempted ?? activationResult?.dbWriteAttempted ?? false,
            requiresNetworkWork: sideEffects?.requiresNetworkWork ?? activationResult?.requiresNetworkWork ?? false,
            requiresDBWrite: sideEffects?.requiresDBWrite ?? activationResult?.requiresDBWrite ?? false,
            dataSourceApplyFromRootCalled: consumer?.dataSourceApplyFromRootCalled
                ?? activationResult?.dataSourceApplyFromRootCalled
                ?? false,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: sideEffects?
                .forbiddenDataSourceApplyOutsideCoordinatorCalled ?? false,
            coordinatorOwnedDataSourceApplyAllowed: activationResult?.coordinatorOwnedDataSourceApplyAllowed ?? false,
            noExtraNostrHomeTimelineStore: !(consumer?.extraNostrHomeTimelineStoreConstructed ?? true)
                && (activationResult?.noExtraNostrHomeTimelineStore ?? false),
            preventsDualMutation: consumer?.chain.constructionArtifactChain.routeDecisionSnapshot.preventsDualMutation ?? false,
            createdAtMS: input.createdAtMS
        )
    }

    private static func hasExplicitCollectionViewLaunchFlag(
        _ input: TimelineHomeCollectionViewRouteActivationSwitchInput
    ) -> Bool {
        input.mode == .collectionView
            && TimelineHomeRouteLaunchArgumentSource(arguments: input.launchArguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func isArtifactChainClean(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.combinedBlockedIssueKinds.isEmpty
            && consumer.activationArtifactPairIssueKinds.isEmpty
            && consumer.releaseBlockerFlags.isEmpty
            && consumer.activationBlockedIssueKinds.isEmpty
            && consumer.activationWouldBeAllowed
    }

    private static func constructionGatesClean(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.constructionReady
            && consumer.constructionAllowed
            && consumer.offscreenHarnessAllowed
            && consumer.constructionConsumer.noWindowAttached
    }

    private static func flaggedConstructionResultClean(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        let result = consumer.activationConsumer.result.constructionResult
        return result.requestedRoute == .collectionView
            && result.constructionAttempted
            && result.constructionAllowed
            && result.constructionKind.isFlaggedActivationConstructionKind
            && result.issueKinds.isEmpty
            && result.collectionViewRouteConstructed
            && !result.collectionViewRouteConstructedFromRoot
            && !result.timelineSurfaceConstructed
            && !result.timelineSurfaceConstructedFromRoot
            && !result.timelineCollectionViewControllerConstructedFromRoot
            && result.renderedRouteAfterConstruction == .legacy
            && result.routeActivationAllowed == false
            && result.rootHomeRenderingChanged == false
            && result.legacyHomeRenderingPreserved
            && result.noExtraNostrHomeTimelineStore
            && !result.networkStarted
            && !result.dbWriteAttempted
            && !result.readMarkerAdvanced
            && !result.dataSourceApplyFromRootCalled
            && result.coordinatorOwnedDataSourceApplyAllowed
            && consumer.activationArtifactPairIssueKinds.isEmpty
    }

    private static func offscreenNoWindowSmokePassed(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.offscreenHarnessAllowed
            && consumer.constructionConsumer.noWindowAttached
            && !consumer.activationConsumer.result.issues.contains(gate: .offscreenNoWindowSmokePassed)
    }

    private static func diagnostics(
        rootActivationDecisionSnapshotResult: TimelineHomeRootActivationDecisionSnapshotResult?,
        consumer: TimelineHomeActivationArtifactChainConsumer?
    ) -> TimelineHomeCollectionViewRouteActivationSwitchDiagnostics {
        let chainSummary = consumer?.diagnosticsSummary
        return TimelineHomeCollectionViewRouteActivationSwitchDiagnostics(
            rootActivationDecisionSummary: rootActivationDecisionSnapshotResult?
                .deterministicRouteActivationText ?? "none",
            activationArtifactChainSummary: consumer?.deterministicDebugSummary ?? "none",
            activationReadinessSummary: chainSummary?.activation ?? "none",
            flaggedConstructionSummary: chainSummary?.flaggedConstruction ?? "none",
            constructionReadinessSummary: chainSummary?.constructionReadiness ?? "none",
            offscreenHarnessSummary: chainSummary?.offscreenHarness ?? "none",
            sideEffectSummary: consumer?.sideEffectFlags.deterministicText ?? "none"
        )
    }

    private static func append(
        _ issue: TimelineHomeCollectionViewRouteActivationSwitchIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeCollectionViewRouteActivationSwitchIssueKind]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

private extension TimelineHomeRootActivationDecisionSnapshotResult {
    var deterministicRouteActivationText: String {
        [
            "preflightEvaluated=\(preflightEvaluated)",
            "activationWouldBeAllowed=\(activationWouldBeAllowed)",
            "activationPerformed=\(activationPerformed)",
            "productionRenderSwitchPerformed=\(productionRenderSwitchPerformed)",
            "renderedRoute=\(renderedRoute.rawValue)",
            "rollbackRoute=\(rollbackRoute.rawValue)",
            "manualFallbackRoute=\(manualFallbackRoute.rawValue)",
            "artifactIssues=\(combinedArtifactChainIssueKinds.debugList)"
        ].joined(separator: " ")
    }
}

private extension TimelineHomeCollectionViewRouteConstructionKind {
    var isFlaggedActivationConstructionKind: Bool {
        switch self {
        case .describedOnly, .offscreenOnly:
            return true
        case .productionClosed:
            return false
        }
    }
}

private extension [TimelineHomeCollectionViewRouteActivationIssue] {
    func contains(gate: TimelineHomeCollectionViewRouteActivationGate) -> Bool {
        contains { $0.gate == gate }
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
