import Foundation

enum TimelineHomeRouteDebugOverride: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView

    var engineMode: AstrenzaTimelineEngineMode {
        switch self {
        case .legacy:
            .legacy
        case .collectionView:
            .collectionView
        }
    }
}

struct TimelineHomeRouteLaunchArgumentSource: Codable, Equatable, Sendable {
    var argument: String?
    var rawValue: String?

    init(arguments: [String]) {
        let prefix = "--timeline-engine="
        guard let argument = arguments.last(where: { $0.hasPrefix(prefix) }) else {
            self.argument = nil
            self.rawValue = nil
            return
        }

        self.argument = argument
        self.rawValue = String(argument.dropFirst(prefix.count))
    }
}

struct TimelineHomeRouteDebugFlagSource: Codable, Equatable, Sendable {
    var override: TimelineHomeRouteDebugOverride?
}

struct TimelineHomeRouteDependencyReadinessSummary: Codable, Equatable, Sendable {
    var routeStatus: TimelineHomeRouteDependencyStatus
    var issueKinds: [TimelineHomeRouteDecisionIssue.Kind]

    var allReady: Bool {
        issueKinds.isEmpty
    }

    var repositoryStoreAvailable: Bool {
        routeStatus.repositoryStoreAvailable
    }

    var windowComposerAvailable: Bool {
        routeStatus.windowComposerAvailable
    }

    var restoreUseCaseAvailable: Bool {
        routeStatus.restoreUseCaseAvailable
    }

    var coordinatorAdapterAvailable: Bool {
        routeStatus.coordinatorAdapterAvailable
    }

    var collectionViewControllerAvailable: Bool {
        routeStatus.collectionViewControllerAvailable
    }

    var diagnosticsSinkAvailable: Bool {
        routeStatus.diagnosticsSinkAvailable
    }

    var runtimeGuardAllowsCollectionView: Bool {
        routeStatus.runtimeGuardAllowsCollectionView
    }

    var rolloutAllowsCollectionView: Bool {
        routeStatus.rolloutAllowsCollectionView
    }

    static func make(
        from routeStatus: TimelineHomeRouteDependencyStatus
    ) -> TimelineHomeRouteDependencyReadinessSummary {
        var issueKinds: [TimelineHomeRouteDecisionIssue.Kind] = []

        if !routeStatus.repositoryStoreAvailable {
            issueKinds.append(.repositoryStoreUnavailable)
        }
        if !routeStatus.windowComposerAvailable {
            issueKinds.append(.windowComposerUnavailable)
        }
        if !routeStatus.restoreUseCaseAvailable {
            issueKinds.append(.restoreUseCaseUnavailable)
        }
        if !routeStatus.coordinatorAdapterAvailable {
            issueKinds.append(.coordinatorAdapterUnavailable)
        }
        if !routeStatus.collectionViewControllerAvailable {
            issueKinds.append(.collectionViewControllerUnavailable)
        }
        if !routeStatus.diagnosticsSinkAvailable {
            issueKinds.append(.diagnosticsSinkUnavailable)
        }
        if !routeStatus.runtimeGuardAllowsCollectionView {
            issueKinds.append(.runtimeGuardDisabled)
        }
        if !routeStatus.rolloutAllowsCollectionView {
            issueKinds.append(.rolloutBlocked)
        }

        return TimelineHomeRouteDependencyReadinessSummary(
            routeStatus: routeStatus,
            issueKinds: issueKinds
        )
    }
}

struct TimelineHomeRouteHostDiagnostics: Codable, Equatable, Sendable {
    var dependencyReadiness: TimelineHomeRouteDependencyReadinessSummary
    var instantiatesRoot: Bool
    var instantiatesLegacyHomeStore: Bool
    var instantiatesCollectionViewController: Bool
    var startsNetworkWork: Bool
    var performsDatabaseMutation: Bool
    var advancesReadMarker: Bool
    var callsDataSourceApply: Bool

    static func routeDecisionOnly(
        dependencyReadiness: TimelineHomeRouteDependencyReadinessSummary
    ) -> TimelineHomeRouteHostDiagnostics {
        TimelineHomeRouteHostDiagnostics(
            dependencyReadiness: dependencyReadiness,
            instantiatesRoot: false,
            instantiatesLegacyHomeStore: false,
            instantiatesCollectionViewController: false,
            startsNetworkWork: false,
            performsDatabaseMutation: false,
            advancesReadMarker: false,
            callsDataSourceApply: false
        )
    }
}

struct TimelineHomeRouteHostInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var debugOverride: TimelineHomeRouteDebugOverride?
    var dependencies: TimelineHomeRouteDependencyStatus

    init(
        launchArguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        dependencies: TimelineHomeRouteDependencyStatus
    ) {
        self.launchArguments = launchArguments
        self.debugOverride = debugOverride
        self.dependencies = dependencies
    }
}

struct TimelineHomeRouteHostDecision: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRouteMode
    var requestedMode: TimelineHomeRouteMode
    var effectiveMode: TimelineHomeRouteMode
    var launchArgumentSource: TimelineHomeRouteLaunchArgumentSource
    var debugOverrideSource: TimelineHomeRouteDebugFlagSource
    var dependencyReadiness: TimelineHomeRouteDependencyReadinessSummary
    var fallbackIssues: [TimelineHomeRouteDecisionIssue]
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var rootShellBehavior: TimelineHomeRouteRootShellBehavior
    var rootShellBehaviorUnchanged: Bool
    var timelineRestoreGateScope: TimelineRestoreGateScope?
    var diagnostics: TimelineHomeRouteHostDiagnostics
}

enum TimelineHomeRouteHost: Sendable {
    static func decide(
        _ input: TimelineHomeRouteHostInput
    ) -> TimelineHomeRouteHostDecision {
        let launchArgumentSource = TimelineHomeRouteLaunchArgumentSource(
            arguments: input.launchArguments
        )
        let debugOverrideSource = TimelineHomeRouteDebugFlagSource(
            override: input.debugOverride
        )
        let modeResolution = resolvedMode(
            arguments: input.launchArguments,
            debugOverride: input.debugOverride
        )
        let dependencyReadiness = TimelineHomeRouteDependencyReadinessSummary.make(
            from: input.dependencies
        )
        let selection = TimelineHomeRouteIntegrationSkeleton.select(
            modeResolution: modeResolution,
            dependencies: dependencyReadiness.routeStatus,
            source: input.debugOverride == nil ? .launchArguments : .resolvedMode
        )

        return TimelineHomeRouteHostDecision(
            selectedRoute: selection.selectedRoute,
            requestedMode: selection.routeDecision.requestedMode,
            effectiveMode: selection.routeDecision.effectiveMode,
            launchArgumentSource: launchArgumentSource,
            debugOverrideSource: debugOverrideSource,
            dependencyReadiness: dependencyReadiness,
            fallbackIssues: selection.fallbackIssues,
            preventsDualMutation: selection.preventsDualMutation,
            readMarkerChanged: selection.readMarkerChanged,
            requiresNetworkWork: selection.requiresNetworkWork,
            requiresDBWrite: selection.requiresDBWrite,
            rootShellBehavior: selection.rootShellBehavior,
            rootShellBehaviorUnchanged: selection.rootShellBehavior == .unchangedImmediate,
            timelineRestoreGateScope: selection.timelineAreaRestoreGateScope,
            diagnostics: .routeDecisionOnly(dependencyReadiness: dependencyReadiness)
        )
    }

    private static func resolvedMode(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride?
    ) -> TimelineHomeEngineModeResolution {
        guard let debugOverride else {
            return TimelineHomeEngineModeResolver.resolve(arguments: arguments)
        }

        return TimelineHomeEngineModeResolution(
            mode: debugOverride.engineMode,
            issues: []
        )
    }
}
