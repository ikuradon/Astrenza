import Foundation

struct TimelineHomeRootActivationPreflightInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var activationArtifactChainConsumer: TimelineHomeActivationArtifactChainConsumer
    var rootShellFirstPaintObserved: Bool
    var timelineAreaRestoreGateObserved: Bool
    var startupNetworkMarkerObserved: Bool
}

enum TimelineHomeRootActivationPreflightIssue: String, CaseIterable, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case activationArtifactChainClean
    case activationReadinessClean
    case rootShellFirstPaintMarker
    case timelineAreaRestoreGateMarker
    case startupNetworkMarkerClean
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case requiresNetworkWorkFalse
    case dbWriteNotAttempted
    case requiresDBWriteFalse
    case dataSourceApplyCoordinatorOnly
    case noExtraNostrHomeTimelineStore
}

struct TimelineHomeRootActivationPreflightResult: Codable, Equatable, Sendable {
    var activationPreflightEvaluated: Bool
    var activationWouldBeAllowed: Bool
    var activationPerformed: Bool
    var productionRenderSwitchPerformed: Bool
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var issues: [TimelineHomeRootActivationPreflightIssue]
    var activationArtifactChainSummary: String
}

enum TimelineHomeRootActivationPreflight {
    static func evaluate(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> TimelineHomeRootActivationPreflightResult {
        let consumer = input.activationArtifactChainConsumer
        var issues: [TimelineHomeRootActivationPreflightIssue] = []

        append(.explicitCollectionViewLaunchFlag, when: !hasExplicitCollectionViewLaunchFlag(input), to: &issues)
        append(.activationArtifactChainClean, when: !activationArtifactChainClean(consumer), to: &issues)
        append(.activationReadinessClean, when: !activationReadinessClean(consumer), to: &issues)
        append(.rootShellFirstPaintMarker, when: !rootShellFirstPaintPreserved(input), to: &issues)
        append(.timelineAreaRestoreGateMarker, when: !timelineAreaRestoreGateOnly(input), to: &issues)
        append(.startupNetworkMarkerClean, when: !startupNetworkClean(input), to: &issues)
        append(
            .networkWaitedBeforeInteractiveScrollZero,
            when: consumer.activationConsumer.result.networkWaitedBeforeInteractiveScrollMS != 0,
            to: &issues
        )
        append(.readMarkerUnchanged, when: consumer.readMarkerChanged, to: &issues)
        append(.requiresNetworkWorkFalse, when: consumer.requiresNetworkWork, to: &issues)
        append(.dbWriteNotAttempted, when: dbWriteAttempted(consumer), to: &issues)
        append(.requiresDBWriteFalse, when: consumer.requiresDBWrite, to: &issues)
        append(.dataSourceApplyCoordinatorOnly, when: dataSourceApplyFromRootCalled(consumer), to: &issues)
        append(
            .noExtraNostrHomeTimelineStore,
            when: consumer.extraNostrHomeTimelineStoreConstructed,
            to: &issues
        )

        return TimelineHomeRootActivationPreflightResult(
            activationPreflightEvaluated: true,
            activationWouldBeAllowed: issues.isEmpty,
            activationPerformed: false,
            productionRenderSwitchPerformed: false,
            renderedRoute: .legacy,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            issues: issues,
            activationArtifactChainSummary: consumer.deterministicDebugSummary
        )
    }

    private static func hasExplicitCollectionViewLaunchFlag(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: input.launchArguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func activationArtifactChainClean(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.constructionBlockedIssueKinds.isEmpty
            && consumer.activationArtifactPairIssueKinds.isEmpty
            && consumer.releaseBlockerFlags.isEmpty
    }

    private static func activationReadinessClean(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.activationConsumer.activationWouldBeAllowed
            && consumer.activationConsumer.blockedIssueKinds.isEmpty
    }

    private static func rootShellFirstPaintPreserved(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> Bool {
        let result = input.activationArtifactChainConsumer.activationConsumer.result
        return input.rootShellFirstPaintObserved
            && result.rootShellPresentation == .immediate
            && result.rootShellMustRenderBeforeTimelineRestore
    }

    private static func timelineAreaRestoreGateOnly(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> Bool {
        let result = input.activationArtifactChainConsumer.activationConsumer.result
        return input.timelineAreaRestoreGateObserved
            && result.timelineRestoreGateScope == .timelineArea
            && result.timelineGateCoversRootShell == false
            && result.timelineGateCoversTabBar == false
            && result.timelineGateContinuesGlobalSplash == false
    }

    private static func startupNetworkClean(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> Bool {
        !input.startupNetworkMarkerObserved
            && input.activationArtifactChainConsumer.startupNetworkClean
    }

    private static func dbWriteAttempted(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.sideEffectFlags.dbWriteAttempted
            || consumer.activationConsumer.result.dbWriteAttempted
    }

    private static func dataSourceApplyFromRootCalled(
        _ consumer: TimelineHomeActivationArtifactChainConsumer
    ) -> Bool {
        consumer.dataSourceApplyFromRootCalled
            || consumer.sideEffectFlags.forbiddenDataSourceApplyOutsideCoordinatorCalled
    }

    private static func append(
        _ issue: TimelineHomeRootActivationPreflightIssue,
        when condition: Bool,
        to issues: inout [TimelineHomeRootActivationPreflightIssue]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

enum TimelineHomeRootCollectionViewActivationPreflight {
    static func evaluate(
        _ input: TimelineHomeRootActivationPreflightInput
    ) -> TimelineHomeRootActivationPreflightResult {
        TimelineHomeRootActivationPreflight.evaluate(input)
    }
}
