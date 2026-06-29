import Foundation

struct TimelineHomeRootRouteGuardInput: Codable, Equatable, Sendable {
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

struct TimelineHomeRootRouteGuardResult: Equatable, Sendable {
    var decision: TimelineHomeRouteHostDecision
    var artifact: TimelineHomeRouteDecisionArtifact
    var diagnosticsExport: TimelineHomeRouteDiagnosticsExport
}

enum TimelineHomeRootRouteGuard: Sendable {
    static func evaluate(
        _ input: TimelineHomeRootRouteGuardInput
    ) -> TimelineHomeRootRouteGuardResult {
        let decision = TimelineHomeRouteHost.decide(TimelineHomeRouteHostInput(
            launchArguments: input.launchArguments,
            debugOverride: rootSafeDebugOverride(input.debugOverride),
            dependencies: input.dependencies
        ))
        let artifact = TimelineHomeRouteDecisionArtifact.make(
            from: decision,
            createdAtMS: input.createdAtMS,
            source: .rootPreflight
        )

        return TimelineHomeRootRouteGuardResult(
            decision: decision,
            artifact: artifact,
            diagnosticsExport: TimelineHomeRouteDiagnosticsExport(
                artifacts: [artifact],
                summary: artifact.summary
            )
        )
    }

    private static func rootSafeDebugOverride(
        _ debugOverride: TimelineHomeRouteDebugOverride?
    ) -> TimelineHomeRouteDebugOverride? {
        guard debugOverride == .legacy else {
            return nil
        }
        return debugOverride
    }
}
