import Foundation

enum TimelineHomeRouteIntegrationDecisionSource: String, Codable, Equatable, Sendable {
    case launchArguments
    case resolvedMode
}

enum TimelineHomeRouteRootShellBehavior: String, Codable, Equatable, Sendable {
    case unchangedImmediate
}

struct TimelineHomeRouteIntegrationActivation: Codable, Equatable, Sendable {
    var instantiatesLegacyTimelineStore: Bool
    var instantiatesProductionRoot: Bool
    var startsNetworkWork: Bool
    var performsDatabaseMutation: Bool
    var advancesReadMarker: Bool
    var marksLegacyVisibleMutationActive: Bool
    var marksCollectionViewVisibleMutationActive: Bool
    var callsDataSourceApply: Bool

    var hasDualVisibleMutation: Bool {
        marksLegacyVisibleMutationActive && marksCollectionViewVisibleMutationActive
    }

    static let routeDecisionOnly = TimelineHomeRouteIntegrationActivation(
        instantiatesLegacyTimelineStore: false,
        instantiatesProductionRoot: false,
        startsNetworkWork: false,
        performsDatabaseMutation: false,
        advancesReadMarker: false,
        marksLegacyVisibleMutationActive: false,
        marksCollectionViewVisibleMutationActive: false,
        callsDataSourceApply: false
    )
}

struct TimelineHomeRouteIntegrationDiagnostics: Codable, Equatable, Sendable {
    var activation: TimelineHomeRouteIntegrationActivation

    static let routeDecisionOnly = TimelineHomeRouteIntegrationDiagnostics(
        activation: .routeDecisionOnly
    )
}

struct TimelineHomeRouteSelection: Codable, Equatable, Sendable {
    var selectedRoute: TimelineHomeRouteMode
    var routeDecision: TimelineHomeRouteDecision
    var routeDecisionSource: TimelineHomeRouteIntegrationDecisionSource
    var fallbackIssues: [TimelineHomeRouteDecisionIssue]
    var preventsDualMutation: Bool
    var readMarkerChanged: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
    var rootShellBehavior: TimelineHomeRouteRootShellBehavior
    var timelineAreaRestoreGateScope: TimelineRestoreGateScope?
    var diagnostics: TimelineHomeRouteIntegrationDiagnostics
}

enum TimelineHomeRouteIntegrationSkeleton {
    static func select(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        dependencies: TimelineHomeRouteDependencyStatus
    ) -> TimelineHomeRouteSelection {
        select(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: arguments),
            dependencies: dependencies,
            source: .launchArguments
        )
    }

    static func select(
        modeResolution: TimelineHomeEngineModeResolution,
        dependencies: TimelineHomeRouteDependencyStatus,
        source: TimelineHomeRouteIntegrationDecisionSource = .resolvedMode
    ) -> TimelineHomeRouteSelection {
        let routeDecision = TimelineHomeRouteAdapter.decide(
            modeResolution: modeResolution,
            dependencies: dependencies
        )

        return TimelineHomeRouteSelection(
            selectedRoute: routeDecision.selectedRoute,
            routeDecision: routeDecision,
            routeDecisionSource: source,
            fallbackIssues: routeDecision.isFallback ? routeDecision.issues : [],
            preventsDualMutation: routeDecision.preventsDualMutation,
            readMarkerChanged: routeDecision.readMarkerChanged,
            requiresNetworkWork: routeDecision.requiresNetworkWork,
            requiresDBWrite: routeDecision.requiresDBWrite,
            rootShellBehavior: .unchangedImmediate,
            timelineAreaRestoreGateScope: routeDecision.selectedRoute == .collectionView ? .timelineArea : nil,
            diagnostics: .routeDecisionOnly
        )
    }
}
