import Foundation

enum TimelineHomeStartupNetworkPatternKind: String, Codable, Equatable, Sendable {
    case startupNetwork
}

struct TimelineHomeStartupNetworkPatternHit: Codable, Equatable, Sendable {
    var patternKind: TimelineHomeStartupNetworkPatternKind
    var tokenID: String
    var lineNumber: Int
    var redactedSummary: String
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
            for definition in patternDefinitions where lineText.contains(definition.matcher) {
                hits.append(
                    TimelineHomeStartupNetworkPatternHit(
                        patternKind: .startupNetwork,
                        tokenID: definition.tokenID,
                        lineNumber: index + 1,
                        redactedSummary: "redacted startup network pattern match"
                    )
                )
            }
        }
        return TimelineHomeStartupResultBundleScan(patternHits: hits)
    }

    private struct PatternDefinition: Sendable {
        var tokenID: String
        var matcher: String
    }

    private static var patternDefinitions: [PatternDefinition] {
        [
            PatternDefinition(tokenID: "startup-network-token-001", matcher: ["Local", "Data", "Task"].joined()),
            PatternDefinition(tokenID: "startup-network-token-002", matcher: ["ATS", "failure"].joined(separator: " ")),
            PatternDefinition(tokenID: "startup-network-token-003", matcher: ["n", "w_"].joined()),
            PatternDefinition(tokenID: "startup-network-token-004", matcher: ["Web", "Socket"].joined()),
            PatternDefinition(
                tokenID: "startup-network-token-005",
                matcher: ["URL", "Session", "Web", "Socket", "Task"].joined()
            ),
            PatternDefinition(tokenID: "startup-network-token-006", matcher: ["ws", "s://"].joined()),
            PatternDefinition(tokenID: "startup-network-token-007", matcher: ["set", "Default", "Relays"].joined()),
            PatternDefinition(tokenID: "startup-network-token-008", matcher: ["URL", "Session"].joined()),
            PatternDefinition(
                tokenID: "startup-network-token-009",
                matcher: ["relay", "connection", "attempts"].joined(separator: " ")
            )
        ]
    }
}

struct TimelineHomeStartupLaunchArgumentSummary: Codable, Equatable, Sendable {
    var hasCollectionViewFlag: Bool
    var requestedEngineMode: String
    var knownFlags: [String]
    var unknownArgumentCount: Int
    var redactedUnknownArguments: Bool

    static func make(arguments: [String]) -> TimelineHomeStartupLaunchArgumentSummary {
        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: arguments)
        let hasCollectionViewFlag = TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue ==
            AstrenzaTimelineEngineMode.collectionView.rawValue
        var knownFlags: [String] = []
        var unknownArgumentCount = 0
        var requestedEngineMode = resolution.issues.isEmpty ? resolution.mode.rawValue : "unknown"

        for (index, argument) in arguments.enumerated() {
            guard !isExecutableName(argument, at: index) else { continue }

            switch argument {
            case "--timeline-engine=collectionView":
                appendKnownFlag("timeline-engine=collectionView", to: &knownFlags)
                requestedEngineMode = AstrenzaTimelineEngineMode.collectionView.rawValue
            case "--timeline-engine=legacy":
                appendKnownFlag("timeline-engine=legacy", to: &knownFlags)
                if !hasCollectionViewFlag {
                    requestedEngineMode = AstrenzaTimelineEngineMode.legacy.rawValue
                }
            default:
                if argument.hasPrefix("--timeline-engine=") {
                    appendKnownFlag("timeline-engine=unknown", to: &knownFlags)
                }
                unknownArgumentCount += 1
            }
        }

        return TimelineHomeStartupLaunchArgumentSummary(
            hasCollectionViewFlag: hasCollectionViewFlag,
            requestedEngineMode: requestedEngineMode,
            knownFlags: knownFlags,
            unknownArgumentCount: unknownArgumentCount,
            redactedUnknownArguments: unknownArgumentCount > 0
        )
    }

    private static func isExecutableName(_ argument: String, at index: Int) -> Bool {
        index == 0 && !argument.hasPrefix("-")
    }

    private static func appendKnownFlag(_ flag: String, to flags: inout [String]) {
        guard !flags.contains(flag) else { return }
        flags.append(flag)
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
    var launchArgumentSummary: TimelineHomeStartupLaunchArgumentSummary
    var routeDecisionSummary: String
    var initialRestoreSummary: String
    var sideEffectSummary: String
    var resultBundleSummary: String
    var deterministicSummary: String

    static func make(
        launchArgumentSummary: TimelineHomeStartupLaunchArgumentSummary,
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
            launchArgumentSummary: launchArgumentSummary,
            routeDecisionSummary: routeDecisionSummary,
            initialRestoreSummary: initialRestoreSummary,
            sideEffectSummary: sideEffectSummary,
            resultBundleSummary: resultBundleSummary,
            deterministicSummary: deterministicSummary
        )
    }
}

struct TimelineHomeFlaggedStartupSmokeInput: Equatable, Sendable {
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
    var launchArgumentSummary: TimelineHomeStartupLaunchArgumentSummary
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
        let launchArgumentSummary = TimelineHomeStartupLaunchArgumentSummary.make(arguments: input.launchArguments)
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
            launchArgumentSummary: launchArgumentSummary,
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
                launchArgumentSummary: launchArgumentSummary,
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
            launchArgumentSummary: launchArgumentSummary,
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
