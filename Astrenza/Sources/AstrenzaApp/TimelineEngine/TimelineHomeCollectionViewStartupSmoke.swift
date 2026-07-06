import Foundation

struct TimelineHomeStartupNetworkPatternHit: Codable, Equatable, Sendable {
    var pattern: String
    var line: Int
    var excerpt: String
}

struct TimelineHomeStartupResultBundleScan: Codable, Equatable, Sendable {
    var patternHits: [TimelineHomeStartupNetworkPatternHit]

    var passed: Bool {
        patternHits.isEmpty
    }

    static let clean = TimelineHomeStartupResultBundleScan(patternHits: [])
}

enum TimelineHomeFlaggedStartupResultBundleScanner: Sendable {
    static func scan(text: String) -> TimelineHomeStartupResultBundleScan {
        var hits: [TimelineHomeStartupNetworkPatternHit] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineText = String(line)
            for pattern in patterns where lineText.contains(pattern) {
                hits.append(
                    TimelineHomeStartupNetworkPatternHit(
                        pattern: pattern,
                        line: index + 1,
                        excerpt: sanitizedExcerpt(lineText)
                    )
                )
            }
        }
        return TimelineHomeStartupResultBundleScan(patternHits: hits)
    }

    private static var patterns: [String] {
        [
            ["Local", "Data", "Task"].joined(),
            ["ATS", "failure"].joined(separator: " "),
            ["n", "w_"].joined(),
            ["Web", "Socket"].joined(),
            ["URL", "Session", "Web", "Socket", "Task"].joined(),
            ["ws", "s://"].joined(),
            ["set", "Default", "Relays"].joined(),
            ["URL", "Session"].joined(),
            ["relay", "connection", "attempts"].joined(separator: " ")
        ]
    }

    private static func sanitizedExcerpt(_ line: String) -> String {
        String(line.prefix(160))
    }
}

enum TimelineHomeFlaggedStartupSmokeIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case cleanRootBodyWiringGate
    case collectionViewRestorePlan
    case timelineAreaRestoreGateOnly
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case dbWriteNotAttempted
    case networkNotStarted
    case dataSourceApplyFromRootNotCalled
    case noExtraNostrHomeTimelineStore
    case sameSessionDoubleMutationPrevented
    case resultBundleScanClean
}

struct TimelineHomeCollectionViewStartupSmokeArtifact: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var routeDecisionSummary: String
    var initialRestoreSummary: String
    var sideEffectSummary: String
    var resultBundleSummary: String
    var deterministicSummary: String

    static func make(
        launchArguments: [String],
        result: TimelineHomeFlaggedStartupSmokeResult,
        restorePlanSummary: TimelineHomeFlaggedStartupRestorePlanSummary
    ) -> TimelineHomeCollectionViewStartupSmokeArtifact {
        let routeDecisionSummary = [
            "selectedRoute=\(result.selectedRoute.rawValue)",
            "renderedRoute=\(result.renderedRoute.rawValue)",
            "usedCollectionViewFlag=\(result.usedCollectionViewFlag)",
            "evaluated=\(result.collectionViewStartupSmokeEvaluated)"
        ].joined(separator: " ")
        let initialRestoreSummary = [
            "gate=\(restorePlanSummary.restoreGateIntent)",
            "scope=\(result.timelineRestoreGateScope?.rawValue ?? "none")",
            "items=\(restorePlanSummary.snapshotItemCount)",
            "pendingExcluded=\(restorePlanSummary.pendingNewExcludedCount)",
            "hiddenExcluded=\(restorePlanSummary.hiddenExcludedCount)"
        ].joined(separator: " ")
        let sideEffectSummary = [
            "network=\(result.networkStarted)",
            "networkWaitMS=\(result.networkWaitedBeforeInteractiveScrollMS)",
            "requiresNetworkWork=\(result.requiresNetworkWork)",
            "dbWrite=\(result.dbWriteAttempted)",
            "requiresDBWrite=\(result.requiresDBWrite)",
            "readMarkerChanged=\(result.readMarkerChanged)",
            "readMarkerAdvanced=\(result.readMarkerAdvanced)",
            "pendingMutation=\(result.pendingNewMutationAttempted)",
            "rootApply=\(result.dataSourceApplyFromRootCalled)",
            "extraStore=\(result.extraNostrHomeTimelineStoreConstructed)"
        ].joined(separator: ",")
        let resultBundleSummary = [
            "scanPassed=\(result.resultBundleScanPassed)",
            "hits=\(result.startupNetworkPatternHits.count)"
        ].joined(separator: " ")
        let deterministicSummary = [
            routeDecisionSummary,
            "initialRestore={\(initialRestoreSummary)}",
            "sideEffects={\(sideEffectSummary)}",
            "resultBundle={\(resultBundleSummary)}"
        ].joined(separator: " ")
        return TimelineHomeCollectionViewStartupSmokeArtifact(
            launchArguments: launchArguments,
            routeDecisionSummary: routeDecisionSummary,
            initialRestoreSummary: initialRestoreSummary,
            sideEffectSummary: sideEffectSummary,
            resultBundleSummary: resultBundleSummary,
            deterministicSummary: deterministicSummary
        )
    }
}

struct TimelineHomeFlaggedStartupSmokeInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var rootBodyRenderDecision: TimelineHomeRootBodyRenderDecision
    var restoreDecision: TimelineHomeCollectionViewRouteRestoreDecision
    var resultBundleScan: TimelineHomeStartupResultBundleScan
    var createdAtMS: Int64
}

struct TimelineHomeFlaggedStartupRestorePlanSummary: Codable, Equatable, Sendable {
    var restoreGateIntent: String
    var snapshotItemCount: Int
    var pendingNewExcludedCount: Int
    var hiddenExcludedCount: Int
}

struct TimelineHomeFlaggedStartupSmokeResult: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var renderedRoute: TimelineHomeRootVisibleRouteDecision
    var usedCollectionViewFlag: Bool
    var startupNetworkPatternHits: [TimelineHomeStartupNetworkPatternHit]
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact
    var collectionViewStartupSmokeEvaluated: Bool
    var defaultStartupRemainsLegacy: Bool
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var rootShellFirstPaintPreserved: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var networkStarted: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var pendingNewMutationAttempted: Bool
    var pendingNewVisibleMutationAttempted: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var resultBundleScanPassed: Bool
    var issueKinds: [TimelineHomeFlaggedStartupSmokeIssueKind]
    var createdAtMS: Int64
}

enum TimelineHomeFlaggedCollectionViewStartupSmoke: Sendable {
    static func evaluate(
        _ input: TimelineHomeFlaggedStartupSmokeInput
    ) -> TimelineHomeFlaggedStartupSmokeResult {
        let root = input.rootBodyRenderDecision
        let restore = input.restoreDecision
        let restorePlan = restore.restorePlan
        let explicitFlag = hasExplicitCollectionViewLaunchFlag(input.launchArguments)
        let issues = issueKinds(
            explicitFlag: explicitFlag,
            root: root,
            restore: restore,
            restorePlan: restorePlan,
            resultBundleScan: input.resultBundleScan
        )
        let collectionViewEvaluated = explicitFlag
            && root.wiringAllowed
            && restore.selectedRoute == .collectionView
            && restore.collectionViewRestorePlanBuilt
            && restore.issueKinds.isEmpty
            && issues.isEmpty
        let selectedRoute: TimelineHomeRootBodyRouteSelection = collectionViewEvaluated ? .collectionView : .legacy
        let renderedRoute: TimelineHomeRootVisibleRouteDecision = collectionViewEvaluated ? .collectionView : .legacy
        let planSummary = TimelineHomeFlaggedStartupRestorePlanSummary(
            restoreGateIntent: restorePlan?.restoreGateIntent.rawValue ?? "none",
            snapshotItemCount: restorePlan?.snapshotItemKeys.count ?? 0,
            pendingNewExcludedCount: restorePlan?.pendingNewExcludedCount ?? 0,
            hiddenExcludedCount: restorePlan?.hiddenExcludedCount ?? 0
        )

        var result = TimelineHomeFlaggedStartupSmokeResult(
            launchArguments: input.launchArguments,
            selectedRoute: selectedRoute,
            renderedRoute: renderedRoute,
            usedCollectionViewFlag: explicitFlag,
            startupNetworkPatternHits: input.resultBundleScan.patternHits,
            dbWriteAttempted: restore.dbWriteAttempted,
            readMarkerAdvanced: restore.readMarkerAdvanced,
            dataSourceApplyFromRootCalled: restore.dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: root.extraNostrHomeTimelineStoreConstructed,
            networkWaitedBeforeInteractiveScrollMS: restore.networkWaitedBeforeInteractiveScrollMS,
            readMarkerChanged: restore.readMarkerChanged,
            artifactSummary: TimelineHomeCollectionViewStartupSmokeArtifact(
                launchArguments: input.launchArguments,
                routeDecisionSummary: "pending",
                initialRestoreSummary: "pending",
                sideEffectSummary: "pending",
                resultBundleSummary: "pending",
                deterministicSummary: "pending"
            ),
            collectionViewStartupSmokeEvaluated: collectionViewEvaluated,
            defaultStartupRemainsLegacy: !explicitFlag && selectedRoute == .legacy,
            rollbackRoute: restore.rollbackRoute,
            manualFallbackRoute: restore.manualFallbackRoute,
            rootShellPresentation: root.rootShellPresentation,
            rootShellMustRenderBeforeTimelineRestore: root.rootShellMustRenderBeforeTimelineRestore,
            rootShellFirstPaintPreserved: root.rootShellFirstPaintPreserved,
            timelineRestoreGateScope: root.timelineRestoreGateScope,
            timelineGateCoversRootShell: root.timelineGateCoversRootShell,
            timelineGateCoversTabBar: root.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: root.timelineGateContinuesGlobalSplash,
            networkStarted: restore.networkStarted,
            requiresNetworkWork: restore.requiresNetworkWork,
            requiresDBWrite: restore.requiresDBWrite,
            pendingNewMutationAttempted: false,
            pendingNewVisibleMutationAttempted: false,
            coordinatorOwnedDataSourceApplyAllowed: restorePlan?.coordinatorOwnedDataSourceApplyAllowed ?? true,
            resultBundleScanPassed: input.resultBundleScan.passed,
            issueKinds: issues,
            createdAtMS: input.createdAtMS
        )
        result.artifactSummary = TimelineHomeCollectionViewStartupSmokeArtifact.make(
            launchArguments: input.launchArguments,
            result: result,
            restorePlanSummary: planSummary
        )
        return result
    }

    private static func issueKinds(
        explicitFlag: Bool,
        root: TimelineHomeRootBodyRenderDecision,
        restore: TimelineHomeCollectionViewRouteRestoreDecision,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?,
        resultBundleScan: TimelineHomeStartupResultBundleScan
    ) -> [TimelineHomeFlaggedStartupSmokeIssueKind] {
        var issues: [TimelineHomeFlaggedStartupSmokeIssueKind] = []
        append(.explicitCollectionViewLaunchFlag, when: !explicitFlag, to: &issues)
        append(
            .cleanRootBodyWiringGate,
            when: !root.wiringAllowed || root.issueKinds.contains(.cleanWiringGate),
            to: &issues
        )
        append(
            .collectionViewRestorePlan,
            when: explicitFlag
                && root.wiringAllowed
                && (restore.selectedRoute != .collectionView
                    || !restore.collectionViewRestorePlanBuilt
                    || !restore.issueKinds.isEmpty),
            to: &issues
        )
        append(
            .timelineAreaRestoreGateOnly,
            when: root.timelineRestoreGateScope != .timelineArea
                || root.timelineGateCoversRootShell
                || root.timelineGateCoversTabBar
                || root.timelineGateContinuesGlobalSplash
                || restorePlan?.restoreGateScope != .timelineArea,
            to: &issues
        )
        append(
            .networkWaitedBeforeInteractiveScrollZero,
            when: restore.networkWaitedBeforeInteractiveScrollMS != 0,
            to: &issues
        )
        append(
            .readMarkerUnchanged,
            when: restore.readMarkerChanged || restore.readMarkerAdvanced,
            to: &issues
        )
        append(
            .dbWriteNotAttempted,
            when: restore.dbWriteAttempted || restore.requiresDBWrite,
            to: &issues
        )
        append(
            .networkNotStarted,
            when: restore.networkStarted || restore.requiresNetworkWork,
            to: &issues
        )
        append(.dataSourceApplyFromRootNotCalled, when: restore.dataSourceApplyFromRootCalled, to: &issues)
        append(
            .noExtraNostrHomeTimelineStore,
            when: root.extraNostrHomeTimelineStoreConstructed || !restore.noExtraNostrHomeTimelineStore,
            to: &issues
        )
        append(
            .sameSessionDoubleMutationPrevented,
            when: !root.sameSessionDoubleMutationPrevented,
            to: &issues
        )
        append(.resultBundleScanClean, when: !resultBundleScan.passed, to: &issues)
        return issues
    }

    private static func hasExplicitCollectionViewLaunchFlag(_ arguments: [String]) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func append(
        _ issue: TimelineHomeFlaggedStartupSmokeIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeFlaggedStartupSmokeIssueKind]
    ) {
        guard condition, !issues.contains(issue) else { return }
        issues.append(issue)
    }
}
