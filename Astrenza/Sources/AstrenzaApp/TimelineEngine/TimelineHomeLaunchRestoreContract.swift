import Foundation

enum TimelineRootShellPresentation: String, Equatable, Codable, Sendable {
    case immediate
}

enum TimelineRestoreGateScope: String, Equatable, Codable, Sendable {
    case timelineArea
}

enum TimelineAreaRestoreGateState: String, Equatable, Codable, Sendable {
    case hidden
    case protectAnchorRestore
    case emptyLocalCache
    case recoverableFailure
}

enum TimelineFirstInteractiveScrollPolicy: String, Equatable, Codable, Sendable {
    case allowedAfterLocalRestoreWithoutNetwork
}

struct TimelineRootShellRestorePolicy: Equatable, Codable, Sendable {
    var rootShellMustRenderBeforeTimelineRestore: Bool
    var presentation: TimelineRootShellPresentation
    var timelineGateCoversRootShell: Bool
    var timelineGateCoversTabBar: Bool

    static let immediate = TimelineRootShellRestorePolicy(
        rootShellMustRenderBeforeTimelineRestore: true,
        presentation: .immediate,
        timelineGateCoversRootShell: false,
        timelineGateCoversTabBar: false
    )
}

struct TimelineAreaRestoreGateContract: Equatable, Codable, Sendable {
    var scope: TimelineRestoreGateScope
    var state: TimelineAreaRestoreGateState
    var fallbackPresentation: TimelineRestoreGateFallbackPresentation?
    var coversRootShell: Bool
    var coversTabBar: Bool
    var continuesGlobalSplash: Bool

    static func make(state: TimelineAreaRestoreGateState) -> TimelineAreaRestoreGateContract {
        TimelineAreaRestoreGateContract(
            scope: .timelineArea,
            state: state,
            fallbackPresentation: state.fallbackPresentation,
            coversRootShell: false,
            coversTabBar: false,
            continuesGlobalSplash: false
        )
    }
}

struct TimelineHomeLaunchRestoreDiagnostics: Equatable, Codable, Sendable {
    var rootShellAvailable: Bool
    var timelineAreaGated: Bool
    var firstInteractiveScrollAllowed: Bool
    var networkWaitedBeforeInteractiveScrollMS: Double
    var readMarkerChanged: Bool
    var requiresNetworkWorkBeforeInteractiveScroll: Bool
    var requiresDBWriteBeforeInteractiveScroll: Bool
    var requiresRemoteSyncBeforeInteractiveScroll: Bool
    var requiresOGPResolveBeforeInteractiveScroll: Bool
    var requiresMediaResolveBeforeInteractiveScroll: Bool
    var requiresProfileResolveBeforeInteractiveScroll: Bool
    var restoreFallbackPresentation: TimelineRestoreGateFallbackPresentation?

    static let safeDefault = TimelineHomeLaunchRestoreDiagnostics(
        rootShellAvailable: true,
        timelineAreaGated: false,
        firstInteractiveScrollAllowed: true,
        networkWaitedBeforeInteractiveScrollMS: 0,
        readMarkerChanged: false,
        requiresNetworkWorkBeforeInteractiveScroll: false,
        requiresDBWriteBeforeInteractiveScroll: false,
        requiresRemoteSyncBeforeInteractiveScroll: false,
        requiresOGPResolveBeforeInteractiveScroll: false,
        requiresMediaResolveBeforeInteractiveScroll: false,
        requiresProfileResolveBeforeInteractiveScroll: false,
        restoreFallbackPresentation: nil
    )
}

struct TimelineHomeLaunchRestoreIssue: Equatable, Codable, Sendable {
    enum Kind: String, Equatable, Codable, Sendable {
        case routeFellBackToLegacy
        case unknownRouteFellBackToLegacy
        case dualMutationNotPrevented
        case rootShellUnavailable
        case timelineGateEscapedTimelineArea
        case networkWaitedBeforeInteractiveScroll
        case readMarkerChangedBeforeInteractiveScroll
        case networkWorkRequiredBeforeInteractiveScroll
        case dbWriteRequiredBeforeInteractiveScroll
        case remoteSyncRequiredBeforeInteractiveScroll
        case ogpResolveRequiredBeforeInteractiveScroll
        case mediaResolveRequiredBeforeInteractiveScroll
        case profileResolveRequiredBeforeInteractiveScroll
    }

    var kind: Kind
    var isBlocking: Bool
    var source: String?
}

struct TimelineHomeLaunchRestorePlan: Equatable, Codable, Sendable {
    var selectedRoute: TimelineHomeRouteMode
    var rootShellPresentation: TimelineRootShellPresentation
    var rootShellPolicy: TimelineRootShellRestorePolicy
    var timelineAreaGateState: TimelineAreaRestoreGateState
    var timelineAreaGate: TimelineAreaRestoreGateContract
    var firstInteractiveScrollPolicy: TimelineFirstInteractiveScrollPolicy
    var restoreFallbackPresentation: TimelineRestoreGateFallbackPresentation?
    var diagnostics: TimelineHomeLaunchRestoreDiagnostics
    var issues: [TimelineHomeLaunchRestoreIssue]
}

enum TimelineHomeLaunchRestoreContract: Sendable {
    static func makePlan(
        routeDecision: TimelineHomeRouteDecision,
        initialRestorePlan: TimelineInitialRestorePlan?,
        diagnosticsOverride: TimelineHomeLaunchRestoreDiagnostics? = nil
    ) -> TimelineHomeLaunchRestorePlan {
        let selectedRoute = routeDecision.selectedRoute
        let restorePlan = selectedRoute == .collectionView ? initialRestorePlan : nil
        let gateState = restorePlan?.restoreGateIntent.timelineAreaGateState ?? .hidden
        let rootShellPolicy = TimelineRootShellRestorePolicy.immediate
        let timelineAreaGate = TimelineAreaRestoreGateContract.make(state: gateState)
        var diagnostics = diagnosticsOverride ?? makeDiagnostics(
            routeDecision: routeDecision,
            restorePlan: restorePlan,
            gateState: gateState
        )
        diagnostics.rootShellAvailable = rootShellPolicy.rootShellMustRenderBeforeTimelineRestore
        diagnostics.timelineAreaGated = gateState != .hidden
        diagnostics.restoreFallbackPresentation = timelineAreaGate.fallbackPresentation

        var issues = routeIssues(from: routeDecision)
        issues += policyIssues(from: rootShellPolicy, gate: timelineAreaGate, diagnostics: diagnostics)
        diagnostics.firstInteractiveScrollAllowed = !issues.contains { $0.isBlocking }

        return TimelineHomeLaunchRestorePlan(
            selectedRoute: selectedRoute,
            rootShellPresentation: rootShellPolicy.presentation,
            rootShellPolicy: rootShellPolicy,
            timelineAreaGateState: gateState,
            timelineAreaGate: timelineAreaGate,
            firstInteractiveScrollPolicy: .allowedAfterLocalRestoreWithoutNetwork,
            restoreFallbackPresentation: timelineAreaGate.fallbackPresentation,
            diagnostics: diagnostics,
            issues: issues
        )
    }

    private static func makeDiagnostics(
        routeDecision: TimelineHomeRouteDecision,
        restorePlan: TimelineInitialRestorePlan?,
        gateState: TimelineAreaRestoreGateState
    ) -> TimelineHomeLaunchRestoreDiagnostics {
        TimelineHomeLaunchRestoreDiagnostics(
            rootShellAvailable: true,
            timelineAreaGated: gateState != .hidden,
            firstInteractiveScrollAllowed: true,
            networkWaitedBeforeInteractiveScrollMS: restorePlan?.diagnostics.networkWaitedBeforeInteractiveScrollMS ?? 0,
            readMarkerChanged: routeDecision.readMarkerChanged || (restorePlan?.diagnostics.readMarkerChanged ?? false),
            requiresNetworkWorkBeforeInteractiveScroll: routeDecision.requiresNetworkWork || (restorePlan?.diagnostics.requiresNetworkWork ?? false),
            requiresDBWriteBeforeInteractiveScroll: routeDecision.requiresDBWrite || (restorePlan?.diagnostics.requiresDBWork ?? false),
            requiresRemoteSyncBeforeInteractiveScroll: false,
            requiresOGPResolveBeforeInteractiveScroll: false,
            requiresMediaResolveBeforeInteractiveScroll: false,
            requiresProfileResolveBeforeInteractiveScroll: false,
            restoreFallbackPresentation: gateState.fallbackPresentation
        )
    }

    private static func routeIssues(
        from routeDecision: TimelineHomeRouteDecision
    ) -> [TimelineHomeLaunchRestoreIssue] {
        var issues: [TimelineHomeLaunchRestoreIssue] = []

        if routeDecision.isFallback {
            let hasUnknownParserIssue = routeDecision.issues.contains { $0.kind == .unknownTimelineEngineMode }
            issues.append(TimelineHomeLaunchRestoreIssue(
                kind: hasUnknownParserIssue ? .unknownRouteFellBackToLegacy : .routeFellBackToLegacy,
                isBlocking: false,
                source: "routeDecision"
            ))
        }

        if !routeDecision.preventsDualMutation {
            issues.append(TimelineHomeLaunchRestoreIssue(
                kind: .dualMutationNotPrevented,
                isBlocking: true,
                source: "routeDecision"
            ))
        }

        return issues
    }

    private static func policyIssues(
        from rootShellPolicy: TimelineRootShellRestorePolicy,
        gate: TimelineAreaRestoreGateContract,
        diagnostics: TimelineHomeLaunchRestoreDiagnostics
    ) -> [TimelineHomeLaunchRestoreIssue] {
        var issues: [TimelineHomeLaunchRestoreIssue] = []

        if !rootShellPolicy.rootShellMustRenderBeforeTimelineRestore || !diagnostics.rootShellAvailable {
            issues.append(blockingIssue(.rootShellUnavailable, source: "rootShellPolicy"))
        }
        if gate.scope != .timelineArea || gate.coversRootShell || gate.coversTabBar || gate.continuesGlobalSplash {
            issues.append(blockingIssue(.timelineGateEscapedTimelineArea, source: "timelineAreaGate"))
        }
        if diagnostics.networkWaitedBeforeInteractiveScrollMS > 0 {
            issues.append(blockingIssue(.networkWaitedBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.readMarkerChanged {
            issues.append(blockingIssue(.readMarkerChangedBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresNetworkWorkBeforeInteractiveScroll {
            issues.append(blockingIssue(.networkWorkRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresDBWriteBeforeInteractiveScroll {
            issues.append(blockingIssue(.dbWriteRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresRemoteSyncBeforeInteractiveScroll {
            issues.append(blockingIssue(.remoteSyncRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresOGPResolveBeforeInteractiveScroll {
            issues.append(blockingIssue(.ogpResolveRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresMediaResolveBeforeInteractiveScroll {
            issues.append(blockingIssue(.mediaResolveRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }
        if diagnostics.requiresProfileResolveBeforeInteractiveScroll {
            issues.append(blockingIssue(.profileResolveRequiredBeforeInteractiveScroll, source: "diagnostics"))
        }

        return issues
    }

    private static func blockingIssue(
        _ kind: TimelineHomeLaunchRestoreIssue.Kind,
        source: String
    ) -> TimelineHomeLaunchRestoreIssue {
        TimelineHomeLaunchRestoreIssue(
            kind: kind,
            isBlocking: true,
            source: source
        )
    }
}

private extension TimelineInitialRestoreGateIntent {
    var timelineAreaGateState: TimelineAreaRestoreGateState {
        switch self {
        case .noGate:
            .hidden
        case .protectAnchorRestore:
            .protectAnchorRestore
        case .emptyLocalCache:
            .emptyLocalCache
        case .recoverableFailure:
            .recoverableFailure
        }
    }
}

private extension TimelineAreaRestoreGateState {
    var fallbackPresentation: TimelineRestoreGateFallbackPresentation? {
        switch self {
        case .hidden:
            nil
        case .protectAnchorRestore:
            .inlineSkeleton
        case .emptyLocalCache:
            .emptyState
        case .recoverableFailure:
            .recoverableState
        }
    }
}
