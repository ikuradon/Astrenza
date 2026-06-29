import Foundation

struct TimelineHomeRootRoutePreflightInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var debugOverride: TimelineHomeRouteDebugOverride?
    var dependencies: TimelineHomeRouteDependencyStatus
    var createdAtMS: Int64

    init(
        launchArguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus,
        createdAtMS: Int64
    ) {
        self.launchArguments = launchArguments
        self.debugOverride = debugOverride
        self.dependencies = dependencies
        self.createdAtMS = createdAtMS
    }
}

struct TimelineHomeRootRoutePreflightInvocation: Codable, Equatable, Sendable {
    var input: TimelineHomeRootRoutePreflightInput
    var guardInput: TimelineHomeRootRouteGuardInput
}

struct TimelineHomeRootRoutePreflightSideEffectSentinel: Codable, Equatable, Sendable {
    var rootViewConstructed: Bool
    var homeTimelineViewConstructed: Bool
    var nostrHomeTimelineStoreConstructed: Bool
    var timelineCollectionViewControllerConstructed: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyCalled: Bool

    static let none = TimelineHomeRootRoutePreflightSideEffectSentinel(
        rootViewConstructed: false,
        homeTimelineViewConstructed: false,
        nostrHomeTimelineStoreConstructed: false,
        timelineCollectionViewControllerConstructed: false,
        networkStarted: false,
        dbWriteAttempted: false,
        readMarkerAdvanced: false,
        dataSourceApplyCalled: false
    )
}

struct TimelineHomeRootRoutePreflightDiagnostics: Codable, Equatable, Sendable {
    var sideEffects: TimelineHomeRootRoutePreflightSideEffectSentinel
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var rootShellBehavior: TimelineHomeRouteRootShellBehavior
    var rootShellBehaviorUnchanged: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
}

struct TimelineHomeRootRoutePreflightResult: Codable, Equatable, Sendable {
    var invocation: TimelineHomeRootRoutePreflightInvocation
    var decision: TimelineHomeRouteHostDecision
    var artifact: TimelineHomeRouteDecisionArtifact
    var diagnosticsExport: TimelineHomeRouteDiagnosticsExport
    var diagnostics: TimelineHomeRootRoutePreflightDiagnostics
    var sideEffects: TimelineHomeRootRoutePreflightSideEffectSentinel
}

enum TimelineHomeRootRoutePreflight: Sendable {
    static func invoke(
        _ input: TimelineHomeRootRoutePreflightInput
    ) -> TimelineHomeRootRoutePreflightResult {
        let guardInput = TimelineHomeRootRouteGuardInput(
            launchArguments: input.launchArguments,
            debugOverride: input.debugOverride,
            dependencies: input.dependencies,
            createdAtMS: input.createdAtMS
        )
        let guardResult = TimelineHomeRootRouteGuard.evaluate(guardInput)
        let sideEffects = TimelineHomeRootRoutePreflightSideEffectSentinel.none

        return TimelineHomeRootRoutePreflightResult(
            invocation: TimelineHomeRootRoutePreflightInvocation(
                input: input,
                guardInput: guardInput
            ),
            decision: guardResult.decision,
            artifact: guardResult.artifact,
            diagnosticsExport: guardResult.diagnosticsExport,
            diagnostics: TimelineHomeRootRoutePreflightDiagnostics(
                sideEffects: sideEffects,
                preventsDualMutation: guardResult.decision.preventsDualMutation,
                readMarkerChanged: guardResult.decision.readMarkerChanged,
                requiresNetworkWork: guardResult.decision.requiresNetworkWork,
                requiresDBWrite: guardResult.decision.requiresDBWrite,
                rootShellBehavior: guardResult.decision.rootShellBehavior,
                rootShellBehaviorUnchanged: guardResult.decision.rootShellBehaviorUnchanged,
                timelineRestoreGateScope: guardResult.decision.timelineRestoreGateScope
            ),
            sideEffects: sideEffects
        )
    }
}
