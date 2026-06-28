enum TimelineHomeRouteMode: String, Codable, Equatable, Sendable {
    case legacy
    case collectionView
    case unknown

    init(_ engineMode: AstrenzaTimelineEngineMode) {
        switch engineMode {
        case .legacy:
            self = .legacy
        case .collectionView:
            self = .collectionView
        }
    }
}

struct TimelineHomeRouteDependencyStatus: Codable, Equatable, Sendable {
    var repositoryStoreAvailable: Bool
    var windowComposerAvailable: Bool
    var restoreUseCaseAvailable: Bool
    var coordinatorAdapterAvailable: Bool
    var collectionViewControllerAvailable: Bool
    var diagnosticsSinkAvailable: Bool
    var runtimeGuardAllowsCollectionView: Bool
    var rolloutAllowsCollectionView: Bool

    static let allAvailable = TimelineHomeRouteDependencyStatus(
        repositoryStoreAvailable: true,
        windowComposerAvailable: true,
        restoreUseCaseAvailable: true,
        coordinatorAdapterAvailable: true,
        collectionViewControllerAvailable: true,
        diagnosticsSinkAvailable: true,
        runtimeGuardAllowsCollectionView: true,
        rolloutAllowsCollectionView: true
    )
}

struct TimelineHomeRouteDecisionIssue: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case unknownTimelineEngineMode
        case repositoryStoreUnavailable
        case windowComposerUnavailable
        case restoreUseCaseUnavailable
        case coordinatorAdapterUnavailable
        case collectionViewControllerUnavailable
        case diagnosticsSinkUnavailable
        case runtimeGuardDisabled
        case rolloutBlocked
    }

    var kind: Kind
    var argument: String? = nil
    var rawValue: String? = nil
}

struct TimelineHomeRouteDecision: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRouteMode
    var requestedMode: TimelineHomeRouteMode
    var effectiveMode: TimelineHomeRouteMode
    var issues: [TimelineHomeRouteDecisionIssue]
    var isFallback: Bool
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
}

enum TimelineHomeRouteAdapter {
    static func decide(
        modeResolution: TimelineHomeEngineModeResolution,
        dependencies: TimelineHomeRouteDependencyStatus
    ) -> TimelineHomeRouteDecision {
        let parserIssues = parserDecisionIssues(from: modeResolution)
        let requestedMode = parserIssues.isEmpty
            ? TimelineHomeRouteMode(modeResolution.mode)
            : .unknown

        guard parserIssues.isEmpty else {
            return decision(
                selectedRoute: .legacy,
                requestedMode: requestedMode,
                issues: parserIssues
            )
        }

        guard modeResolution.mode == .collectionView else {
            return decision(
                selectedRoute: .legacy,
                requestedMode: requestedMode,
                issues: []
            )
        }

        let dependencyIssues = dependencyDecisionIssues(from: dependencies)
        guard dependencyIssues.isEmpty else {
            return decision(
                selectedRoute: .legacy,
                requestedMode: requestedMode,
                issues: dependencyIssues
            )
        }

        return decision(
            selectedRoute: .collectionView,
            requestedMode: requestedMode,
            issues: []
        )
    }

    private static func decision(
        selectedRoute: TimelineHomeRouteMode,
        requestedMode: TimelineHomeRouteMode,
        issues: [TimelineHomeRouteDecisionIssue]
    ) -> TimelineHomeRouteDecision {
        TimelineHomeRouteDecision(
            selectedRoute: selectedRoute,
            requestedMode: requestedMode,
            effectiveMode: selectedRoute,
            issues: issues,
            isFallback: selectedRoute == .legacy && requestedMode != .legacy,
            preventsDualMutation: true,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresDBWrite: false
        )
    }

    private static func parserDecisionIssues(
        from modeResolution: TimelineHomeEngineModeResolution
    ) -> [TimelineHomeRouteDecisionIssue] {
        modeResolution.issues.map { issue in
            TimelineHomeRouteDecisionIssue(
                kind: .unknownTimelineEngineMode,
                argument: issue.argument,
                rawValue: issue.rawValue
            )
        }
    }

    private static func dependencyDecisionIssues(
        from dependencies: TimelineHomeRouteDependencyStatus
    ) -> [TimelineHomeRouteDecisionIssue] {
        var issues: [TimelineHomeRouteDecisionIssue] = []

        if !dependencies.repositoryStoreAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .repositoryStoreUnavailable))
        }
        if !dependencies.windowComposerAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .windowComposerUnavailable))
        }
        if !dependencies.restoreUseCaseAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .restoreUseCaseUnavailable))
        }
        if !dependencies.coordinatorAdapterAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .coordinatorAdapterUnavailable))
        }
        if !dependencies.collectionViewControllerAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .collectionViewControllerUnavailable))
        }
        if !dependencies.diagnosticsSinkAvailable {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .diagnosticsSinkUnavailable))
        }
        if !dependencies.runtimeGuardAllowsCollectionView {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .runtimeGuardDisabled))
        }
        if !dependencies.rolloutAllowsCollectionView {
            issues.append(TimelineHomeRouteDecisionIssue(kind: .rolloutBlocked))
        }

        return issues
    }
}
