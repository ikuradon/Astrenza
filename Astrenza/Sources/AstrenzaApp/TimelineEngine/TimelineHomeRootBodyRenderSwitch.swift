import Foundation

struct TimelineHomeRootBodyRenderSwitchInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var wiringGateResult: TimelineHomeRootBodyActivationWiringResult?
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var networkStartedBeforeInteractiveScroll: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var createdAtMS: Int64
}

enum TimelineHomeRootBodyRouteSelection: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
}

enum TimelineHomeRootBodyRenderSwitchIssueKind: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case cleanWiringGate
    case rootShellFirstPaintPreserved
    case timelineAreaRestoreGateOnly
    case networkNotStartedBeforeInteractiveScroll
    case dbWriteNotAttempted
    case readMarkerUnchanged
    case dataSourceApplyFromRootNotCalled
    case noExtraNostrHomeTimelineStore
    case sameSessionDoubleMutationPrevented
    case rollbackRouteLegacy
    case manualFallbackRouteLegacy
}

struct TimelineHomeRootBodyRenderDecision: Codable, Equatable, Sendable {
    var renderSwitchEvaluated: Bool
    var selectedRoute: TimelineHomeRootBodyRouteSelection
    var explicitCollectionViewFlagPresent: Bool
    var wiringGateEvaluated: Bool
    var wiringAllowed: Bool
    var legacyRouteRendered: Bool
    var collectionViewRouteRendered: Bool
    var rollbackRoute: TimelineHomeRootVisibleRouteDecision
    var manualFallbackRoute: TimelineHomeRootVisibleRouteDecision
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var rootShellFirstPaintPreserved: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool
    var timelineGateContinuesGlobalSplash: Bool
    var networkStartedBeforeInteractiveScroll: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyFromRootCalled: Bool
    var extraNostrHomeTimelineStoreConstructed: Bool
    var sameSessionDoubleMutationPrevented: Bool
    var wiringArtifactSummary: TimelineHomeRootBodyActivationWiringArtifactSummary?
    var issueKinds: [TimelineHomeRootBodyRenderSwitchIssueKind]
    var createdAtMS: Int64
}

enum TimelineHomeRootBodyRenderSwitch: Sendable {
    static func decide(
        _ input: TimelineHomeRootBodyRenderSwitchInput
    ) -> TimelineHomeRootBodyRenderDecision {
        let wiring = input.wiringGateResult
        let explicitFlagPresent = hasExplicitCollectionViewLaunchFlag(input)
        let wiringGateEvaluated = wiring?.wiringGateEvaluated ?? false
        let wiringAllowed = wiring?.wiringAllowed == true && (wiring?.issueKinds.isEmpty ?? false)
        let wiringGateClean = wiringGateEvaluated && wiringAllowed
        let rootShellFirstPaintPreserved = input.rootShellPresentation == .immediate
            && input.rootShellMustRenderBeforeTimelineRestore
        let timelineAreaRestoreGateOnly = input.timelineRestoreGateScope == .timelineArea
            && !input.timelineGateCoversRootShell
            && !input.timelineGateCoversTabBar
            && !input.timelineGateContinuesGlobalSplash
        let networkStarted = input.networkStartedBeforeInteractiveScroll || (wiring?.networkStarted ?? false)
        let networkWaited = input.networkWaitedBeforeInteractiveScrollMS
        let dbWriteAttempted = input.dbWriteAttempted || (wiring?.dbWriteAttempted ?? false)
        let readMarkerAdvanced = input.readMarkerAdvanced || (wiring?.readMarkerAdvanced ?? false)
        let dataSourceApplyFromRootCalled = input.dataSourceApplyFromRootCalled
            || (wiring?.dataSourceApplyFromRootCalled ?? false)
        let extraNostrHomeTimelineStoreConstructed = input.extraNostrHomeTimelineStoreConstructed
            || (wiring?.extraNostrHomeTimelineStoreConstructed ?? false)
        let sameSessionDoubleMutationPrevented = wiring?.sameSessionDoubleMutationPrevented == true
        let rollbackRoute = wiring?.rollbackRoute ?? .legacy
        let manualFallbackRoute = wiring?.manualFallbackRoute ?? .legacy
        var issues: [TimelineHomeRootBodyRenderSwitchIssueKind] = []

        append(.explicitCollectionViewLaunchFlag, when: !explicitFlagPresent, to: &issues)
        append(.cleanWiringGate, when: !wiringGateClean, to: &issues)
        append(.rootShellFirstPaintPreserved, when: !rootShellFirstPaintPreserved, to: &issues)
        append(.timelineAreaRestoreGateOnly, when: !timelineAreaRestoreGateOnly, to: &issues)
        append(
            .networkNotStartedBeforeInteractiveScroll,
            when: networkStarted || networkWaited != 0,
            to: &issues
        )
        append(.dbWriteNotAttempted, when: dbWriteAttempted, to: &issues)
        append(.readMarkerUnchanged, when: readMarkerAdvanced, to: &issues)
        append(.dataSourceApplyFromRootNotCalled, when: dataSourceApplyFromRootCalled, to: &issues)
        append(.noExtraNostrHomeTimelineStore, when: extraNostrHomeTimelineStoreConstructed, to: &issues)
        append(.sameSessionDoubleMutationPrevented, when: !sameSessionDoubleMutationPrevented, to: &issues)
        append(.rollbackRouteLegacy, when: rollbackRoute != .legacy, to: &issues)
        append(.manualFallbackRouteLegacy, when: manualFallbackRoute != .legacy, to: &issues)

        let selectedRoute: TimelineHomeRootBodyRouteSelection = issues.isEmpty ? .collectionView : .legacy
        return TimelineHomeRootBodyRenderDecision(
            renderSwitchEvaluated: true,
            selectedRoute: selectedRoute,
            explicitCollectionViewFlagPresent: explicitFlagPresent,
            wiringGateEvaluated: wiringGateEvaluated,
            wiringAllowed: wiringAllowed,
            legacyRouteRendered: selectedRoute == .legacy,
            collectionViewRouteRendered: selectedRoute == .collectionView,
            rollbackRoute: rollbackRoute,
            manualFallbackRoute: manualFallbackRoute,
            rootShellPresentation: input.rootShellPresentation,
            rootShellMustRenderBeforeTimelineRestore: input.rootShellMustRenderBeforeTimelineRestore,
            rootShellFirstPaintPreserved: rootShellFirstPaintPreserved,
            timelineRestoreGateScope: input.timelineRestoreGateScope,
            timelineGateCoversRootShell: input.timelineGateCoversRootShell,
            timelineGateCoversTabBar: input.timelineGateCoversTabBar,
            timelineGateContinuesGlobalSplash: input.timelineGateContinuesGlobalSplash,
            networkStartedBeforeInteractiveScroll: networkStarted,
            networkWaitedBeforeInteractiveScrollMS: networkWaited,
            dbWriteAttempted: dbWriteAttempted,
            readMarkerAdvanced: readMarkerAdvanced,
            dataSourceApplyFromRootCalled: dataSourceApplyFromRootCalled,
            extraNostrHomeTimelineStoreConstructed: extraNostrHomeTimelineStoreConstructed,
            sameSessionDoubleMutationPrevented: sameSessionDoubleMutationPrevented,
            wiringArtifactSummary: wiring?.artifactSummary,
            issueKinds: issues,
            createdAtMS: input.createdAtMS
        )
    }

    private static func hasExplicitCollectionViewLaunchFlag(
        _ input: TimelineHomeRootBodyRenderSwitchInput
    ) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: input.launchArguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func append(
        _ issue: TimelineHomeRootBodyRenderSwitchIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeRootBodyRenderSwitchIssueKind]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}
