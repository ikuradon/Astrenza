import Foundation

struct TimelineHomeRootRouteCallSiteResult: Codable, Equatable, Sendable {
    var didInvokePreflight: Bool
    var preflight: TimelineHomeRootRoutePreflightResult
    var visibleRoute: TimelineHomeRouteMode
    var legacyHomeRemainsDefault: Bool
    var collectionViewRouteConstructed: Bool
    var nostrHomeTimelineStoreConstructedByCallSite: Bool
    var networkStartedByCallSite: Bool
    var dbWriteAttemptedByCallSite: Bool
    var readMarkerAdvancedByCallSite: Bool
    var dataSourceApplyCalledByCallSite: Bool
    var rootShellBehaviorUnchanged: Bool
    var localDiagnosticsArtifactRecorded: Bool
    var localDiagnosticsRecordCount: Int
    var localDiagnosticsDebugSummary: TimelineHomeRouteDiagnosticsDebugSummary?
    var localDiagnosticsExport: TimelineHomeRouteDiagnosticsExport?
}

enum TimelineHomeRootRouteCallSite {
    @discardableResult
    static func invoke(
        launchArguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy,
        createdAtMS: Int64,
        diagnosticsSink: ((TimelineHomeRouteDiagnosticsExport) -> Void)? = nil
    ) -> TimelineHomeRootRouteCallSiteResult {
        var localDiagnosticsSink = TimelineHomeRouteDiagnosticsSink(retentionLimit: 1)
        return invoke(
            launchArguments: launchArguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS,
            localDiagnosticsSink: &localDiagnosticsSink,
            diagnosticsSink: diagnosticsSink
        )
    }

    @discardableResult
    static func invoke(
        launchArguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus = .rootCallSiteDefaultLegacy,
        createdAtMS: Int64,
        localDiagnosticsSink: inout TimelineHomeRouteDiagnosticsSink,
        diagnosticsSink: ((TimelineHomeRouteDiagnosticsExport) -> Void)? = nil
    ) -> TimelineHomeRootRouteCallSiteResult {
        let preflight = TimelineHomeRootRoutePreflight.invoke(TimelineHomeRootRoutePreflightInput(
            launchArguments: launchArguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS
        ))
        localDiagnosticsSink.record(preflight.artifact)
        diagnosticsSink?(preflight.diagnosticsExport)
        let localDiagnosticsExport = localDiagnosticsSink.export()
        let localDiagnosticsArtifactRecorded = localDiagnosticsSink.records.last == preflight.artifact

        return TimelineHomeRootRouteCallSiteResult(
            didInvokePreflight: true,
            preflight: preflight,
            visibleRoute: .legacy,
            legacyHomeRemainsDefault: true,
            collectionViewRouteConstructed: false,
            nostrHomeTimelineStoreConstructedByCallSite: false,
            networkStartedByCallSite: false,
            dbWriteAttemptedByCallSite: false,
            readMarkerAdvancedByCallSite: false,
            dataSourceApplyCalledByCallSite: false,
            rootShellBehaviorUnchanged: preflight.diagnostics.rootShellBehaviorUnchanged,
            localDiagnosticsArtifactRecorded: localDiagnosticsArtifactRecorded,
            localDiagnosticsRecordCount: localDiagnosticsSink.records.count,
            localDiagnosticsDebugSummary: localDiagnosticsSink.latestDebugSummary,
            localDiagnosticsExport: localDiagnosticsExport
        )
    }

    @discardableResult
    static func invokeDefaultProductionPreflight() -> TimelineHomeRootRouteCallSiteResult {
        invoke(
            launchArguments: TimelineHomeRootRouteCallSiteEnvironment.currentLaunchArguments(),
            debugOverride: nil,
            dependencies: .rootCallSiteDefaultLegacy,
            createdAtMS: TimelineHomeRootRouteCallSiteEnvironment.currentCreatedAtMS()
        )
    }
}

enum TimelineHomeRootRouteCallSiteEnvironment {
    static func currentLaunchArguments() -> [String] {
        ProcessInfo.processInfo.arguments
    }

    static func currentCreatedAtMS(date: Date = Date()) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

extension TimelineHomeRouteDependencyStatus {
    static let rootCallSiteDefaultLegacy = TimelineHomeRouteDependencyStatus(
        repositoryStoreAvailable: false,
        windowComposerAvailable: false,
        restoreUseCaseAvailable: false,
        coordinatorAdapterAvailable: false,
        collectionViewControllerAvailable: false,
        diagnosticsSinkAvailable: true,
        runtimeGuardAllowsCollectionView: false,
        rolloutAllowsCollectionView: false
    )
}
