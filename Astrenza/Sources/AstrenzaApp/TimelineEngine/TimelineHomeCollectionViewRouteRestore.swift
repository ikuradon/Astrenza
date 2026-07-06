import AstrenzaCore
import Foundation

struct TimelineHomeCollectionViewRouteRestoreComposerInput: Sendable {
    var launchArguments: [String]
    var rootBodyRenderDecision: TimelineHomeRootBodyRenderDecision
    var container: TimelineSurfaceDependencyContainer
    var readRequest: TimelineRepositoryReadRequest
    var accountID: AccountID
    var timelineKey: TimelineKey
    var repositoryPolicy: TimelineRepositoryVisiblePolicy
    var visibleWindowPolicy: TimelineVisibleWindowPolicy
    var requestedAnchorItemKey: String?
    var createdAtMS: Int64
}

enum TimelineHomeCollectionViewRouteRestoreIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case cleanRootBodyWiringGate
    case rootBodyRenderSwitchAllows
    case containerModeCollectionView
    case timelineAreaRestoreGateOnly
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case dbWriteNotAttempted
    case dataSourceApplyFromRootNotCalled
    case networkNotStarted
    case legacyRollback
    case manualFallbackLegacy
    case noExtraNostrHomeTimelineStore
    case sameSessionDoubleMutationPrevented
}

struct TimelineHomeCollectionViewRouteRestorePlan: Codable, Equatable, Sendable {
    var snapshotItemKeys: [String]
    var restoreGateIntent: TimelineInitialRestoreGateIntent
    var restoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var requestedAnchorItemKey: String?
    var restoreCandidateItemKey: String?
    var fallbackReason: TimelineRepositoryBoundaryFallbackReason
    var localDBReadWork: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var dbWriteAttempted: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var networkStarted: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var pendingNewExcludedCount: Int
    var hiddenExcludedCount: Int
    var issueCount: Int
}

struct TimelineHomeCollectionViewRouteRestoreArtifactSummary: Codable, Equatable, Sendable {
    var localOnly: Bool
    var restoreDecisionSummary: String
    var initialRestoreSummary: String
    var sideEffectSummary: String
    var deterministicSummary: String

    static func make(
        selectedRoute: TimelineHomeRootBodyRouteSelection,
        restorePlanBuilt: Bool,
        legacyFallback: Bool,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?,
        issueKinds: [TimelineHomeCollectionViewRouteRestoreIssueKind]
    ) -> TimelineHomeCollectionViewRouteRestoreArtifactSummary {
        let restoreDecisionSummary = [
            "selectedRoute=\(selectedRoute.rawValue)",
            "restorePlanBuilt=\(restorePlanBuilt)",
            "legacyFallback=\(legacyFallback)",
            "issues=\(issueKinds.map(\.rawValue).debugList)"
        ].joined(separator: " ")
        let initialRestoreSummary: String
        if let restorePlan {
            initialRestoreSummary = [
                "items=\(restorePlan.snapshotItemKeys.count)",
                "gate=\(restorePlan.restoreGateIntent.rawValue)",
                "scope=\(restorePlan.restoreGateScope?.rawValue ?? "none")",
                "pending=\(restorePlan.pendingNewExcludedCount)",
                "hidden=\(restorePlan.hiddenExcludedCount)",
                "fallback=\(restorePlan.fallbackReason.rawValue)"
            ].joined(separator: " ")
        } else {
            initialRestoreSummary = "none"
        }
        let sideEffectSummary = [
            "network=\(restorePlan?.networkStarted ?? false)",
            "networkWaitMS=\(restorePlan?.networkWaitedBeforeInteractiveScrollMS ?? 0)",
            "requiresNetworkWork=\(restorePlan?.requiresNetworkWork ?? false)",
            "dbWrite=\(restorePlan?.dbWriteAttempted ?? false)",
            "requiresDBWrite=\(restorePlan?.requiresDBWrite ?? false)",
            "readMarkerChanged=\(restorePlan?.readMarkerChanged ?? false)",
            "readMarkerAdvanced=\(restorePlan?.readMarkerAdvanced ?? false)",
            "dataSourceApplyFromRoot=\(restorePlan?.dataSourceApplyFromRootCalled ?? false)"
        ].joined(separator: ",")
        let deterministicSummary = [
            "localOnly=true",
            restoreDecisionSummary,
            "initialRestore={\(initialRestoreSummary)}",
            "sideEffects={\(sideEffectSummary)}"
        ].joined(separator: " ")

        return TimelineHomeCollectionViewRouteRestoreArtifactSummary(
            localOnly: true,
            restoreDecisionSummary: restoreDecisionSummary,
            initialRestoreSummary: initialRestoreSummary,
            sideEffectSummary: sideEffectSummary,
            deterministicSummary: deterministicSummary
        )
    }
}

struct TimelineHomeCollectionViewRouteRestoreDecision: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    var collectionViewRestorePlanBuilt: Bool
    var legacyRestorePathPreserved: Bool
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var networkStarted: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var readMarkerAdvanced: Bool
    var dbWriteAttempted: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var dataSourceApplyFromRootCalled: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var artifactSummary: TimelineHomeCollectionViewRouteRestoreArtifactSummary
    var issueKinds: [TimelineHomeCollectionViewRouteRestoreIssueKind]
    var createdAtMS: Int64
}

enum TimelineHomeCollectionViewRouteRestoreComposer {
    static func compose(
        _ input: TimelineHomeCollectionViewRouteRestoreComposerInput
    ) async throws -> TimelineHomeCollectionViewRouteRestoreDecision {
        let gateIssues = issueKinds(input: input, restorePlan: nil)
        guard gateIssues.isEmpty else {
            return decision(
                selectedRoute: .legacy,
                restorePlan: nil,
                issueKinds: gateIssues,
                input: input
            )
        }

        let window = try await input.container.repositoryStore.fetchInitialWindow(
            input.readRequest,
            policy: input.repositoryPolicy
        )
        let composition = try input.container.windowComposer.compose(
            window,
            input.accountID,
            input.timelineKey,
            input.visibleWindowPolicy
        )
        let initialRestorePlan = input.container.makeInitialRestorePlan(
            from: composition,
            requestedAnchorItemKey: input.requestedAnchorItemKey
        )
        let expectation = input.container.initialRestore.coordinatorExpectation(
            for: initialRestorePlan,
            timestampMS: input.createdAtMS
        )
        let restorePlan = makeRestorePlan(
            initialRestorePlan: initialRestorePlan,
            expectation: expectation,
            rootBodyDecision: input.rootBodyRenderDecision
        )
        let issues = issueKinds(input: input, restorePlan: restorePlan)
        return decision(
            selectedRoute: issues.isEmpty ? .collectionView : .legacy,
            restorePlan: issues.isEmpty ? restorePlan : nil,
            issueKinds: issues,
            input: input
        )
    }

    private static func makeRestorePlan(
        initialRestorePlan: TimelineInitialRestorePlan,
        expectation: TimelineInitialRestoreCoordinatorExpectation,
        rootBodyDecision: TimelineHomeRootBodyRenderDecision
    ) -> TimelineHomeCollectionViewRouteRestorePlan {
        TimelineHomeCollectionViewRouteRestorePlan(
            snapshotItemKeys: initialRestorePlan.snapshotPlan.itemIDs.map(\.rawValue),
            restoreGateIntent: initialRestorePlan.restoreGateIntent,
            restoreGateScope: rootBodyDecision.timelineRestoreGateScope,
            timelineGateCoversRootShell: rootBodyDecision.timelineGateCoversRootShell,
            timelineGateCoversTabBar: rootBodyDecision.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: rootBodyDecision.timelineGateContinuesGlobalSplash,
            requestedAnchorItemKey: expectation.anchor.requestedAnchorItemKey,
            restoreCandidateItemKey: expectation.anchor.restoreCandidateItemKey,
            fallbackReason: expectation.anchor.fallbackReason,
            localDBReadWork: expectation.diagnostics.localDBReadWork,
            networkWaitedBeforeInteractiveScrollMS: expectation.diagnostics.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: expectation.diagnostics.readMarkerChanged,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: expectation.diagnostics.requiresNetworkWork,
            requiresDBWrite: expectation.diagnostics.requiresDBWork,
            networkStarted: rootBodyDecision.networkStartedBeforeInteractiveScroll,
            dataSourceApplyFromRootCalled: rootBodyDecision.dataSourceApplyFromRootCalled,
            coordinatorOwnedDataSourceApplyAllowed: !expectation.expectsDataSourceApply
                && !expectation.expectsInsertOrDeleteMutation,
            pendingNewExcludedCount: expectation.diagnostics.pendingNewExcludedCount,
            hiddenExcludedCount: expectation.diagnostics.hiddenExcludedCount,
            issueCount: expectation.diagnostics.issueCount
        )
    }

    private static func decision(
        selectedRoute: TimelineHomeRootBodyRouteSelection,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?,
        issueKinds: [TimelineHomeCollectionViewRouteRestoreIssueKind],
        input: TimelineHomeCollectionViewRouteRestoreComposerInput
    ) -> TimelineHomeCollectionViewRouteRestoreDecision {
        let restorePlanBuilt = restorePlan != nil && selectedRoute == .collectionView
        let legacyFallback = selectedRoute == .legacy
        let artifactSummary = TimelineHomeCollectionViewRouteRestoreArtifactSummary.make(
            selectedRoute: selectedRoute,
            restorePlanBuilt: restorePlanBuilt,
            legacyFallback: legacyFallback,
            restorePlan: restorePlan,
            issueKinds: issueKinds
        )

        return TimelineHomeCollectionViewRouteRestoreDecision(
            selectedRoute: selectedRoute,
            restorePlan: restorePlanBuilt ? restorePlan : nil,
            collectionViewRestorePlanBuilt: restorePlanBuilt,
            legacyRestorePathPreserved: legacyFallback,
            rollbackRoute: input.rootBodyRenderDecision.rollbackRoute,
            manualFallbackRoute: input.rootBodyRenderDecision.manualFallbackRoute,
            networkStarted: restorePlan?.networkStarted ?? input.rootBodyRenderDecision.networkStartedBeforeInteractiveScroll,
            networkWaitedBeforeInteractiveScrollMS: restorePlan?.networkWaitedBeforeInteractiveScrollMS
                ?? input.rootBodyRenderDecision.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: restorePlan?.readMarkerChanged ?? false,
            readMarkerAdvanced: restorePlan?.readMarkerAdvanced ?? input.rootBodyRenderDecision.readMarkerAdvanced,
            dbWriteAttempted: restorePlan?.dbWriteAttempted ?? input.rootBodyRenderDecision.dbWriteAttempted,
            requiresNetworkWork: restorePlan?.requiresNetworkWork ?? false,
            requiresDBWrite: restorePlan?.requiresDBWrite ?? false,
            dataSourceApplyFromRootCalled: restorePlan?.dataSourceApplyFromRootCalled
                ?? input.rootBodyRenderDecision.dataSourceApplyFromRootCalled,
            noExtraNostrHomeTimelineStore: !input.rootBodyRenderDecision.extraNostrHomeTimelineStoreConstructed,
            artifactSummary: artifactSummary,
            issueKinds: issueKinds,
            createdAtMS: input.createdAtMS
        )
    }

    private static func issueKinds(
        input: TimelineHomeCollectionViewRouteRestoreComposerInput,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    ) -> [TimelineHomeCollectionViewRouteRestoreIssueKind] {
        let decision = input.rootBodyRenderDecision
        let restoreGateScopeDirty = restorePlan.map { $0.restoreGateScope != .timelineArea } ?? false
        let restoreNetworkWaited = restorePlan.map { $0.networkWaitedBeforeInteractiveScrollMS != 0 } ?? false
        var issues: [TimelineHomeCollectionViewRouteRestoreIssueKind] = []

        append(
            .explicitCollectionViewLaunchFlag,
            when: !decision.explicitCollectionViewFlagPresent || !hasExplicitCollectionViewLaunchFlag(input.launchArguments),
            to: &issues
        )
        append(
            .cleanRootBodyWiringGate,
            when: !decision.wiringGateEvaluated || !decision.wiringAllowed || decision.issueKinds.contains(.cleanWiringGate),
            to: &issues
        )
        append(.rootBodyRenderSwitchAllows, when: decision.selectedRoute != .collectionView, to: &issues)
        append(.containerModeCollectionView, when: input.container.mode != .collectionView, to: &issues)
        append(
            .timelineAreaRestoreGateOnly,
            when: decision.timelineRestoreGateScope != .timelineArea
                || decision.timelineGateCoversRootShell
                || decision.timelineGateCoversTabBar
                || decision.timelineGateContinuesGlobalSplash
                || restoreGateScopeDirty,
            to: &issues
        )
        append(
            .networkWaitedBeforeInteractiveScrollZero,
            when: decision.networkWaitedBeforeInteractiveScrollMS != 0
                || restoreNetworkWaited,
            to: &issues
        )
        append(
            .readMarkerUnchanged,
            when: decision.readMarkerAdvanced
                || restorePlan?.readMarkerChanged == true
                || restorePlan?.readMarkerAdvanced == true,
            to: &issues
        )
        append(
            .dbWriteNotAttempted,
            when: decision.dbWriteAttempted
                || restorePlan?.dbWriteAttempted == true
                || restorePlan?.requiresDBWrite == true,
            to: &issues
        )
        append(
            .dataSourceApplyFromRootNotCalled,
            when: decision.dataSourceApplyFromRootCalled
                || restorePlan?.dataSourceApplyFromRootCalled == true,
            to: &issues
        )
        append(
            .networkNotStarted,
            when: decision.networkStartedBeforeInteractiveScroll
                || restorePlan?.networkStarted == true
                || restorePlan?.requiresNetworkWork == true,
            to: &issues
        )
        append(.legacyRollback, when: decision.rollbackRoute != .legacy, to: &issues)
        append(.manualFallbackLegacy, when: decision.manualFallbackRoute != .legacy, to: &issues)
        append(.noExtraNostrHomeTimelineStore, when: decision.extraNostrHomeTimelineStoreConstructed, to: &issues)
        append(
            .sameSessionDoubleMutationPrevented,
            when: !decision.sameSessionDoubleMutationPrevented
                || decision.issueKinds.contains(.sameSessionDoubleMutationPrevented),
            to: &issues
        )

        return issues
    }

    private static func hasExplicitCollectionViewLaunchFlag(_ arguments: [String]) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func append(
        _ issue: TimelineHomeCollectionViewRouteRestoreIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeCollectionViewRouteRestoreIssueKind]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
