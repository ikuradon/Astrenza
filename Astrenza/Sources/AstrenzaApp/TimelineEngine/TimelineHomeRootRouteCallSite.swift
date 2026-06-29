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
        let preflight = TimelineHomeRootRoutePreflight.invoke(TimelineHomeRootRoutePreflightInput(
            launchArguments: launchArguments,
            debugOverride: debugOverride,
            dependencies: dependencies,
            createdAtMS: createdAtMS
        ))
        diagnosticsSink?(preflight.diagnosticsExport)

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
            localDiagnosticsArtifactRecorded: true
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
