import Foundation

struct TimelineHomeCollectionViewRouteConstructionInput: Codable, Equatable, Sendable {
    var launchArguments: [String]
    var debugOverride: TimelineHomeRouteDebugOverride?
    var artifactChain: TimelineHomeConstructionArtifactChain?
    var createdAtMS: Int64

    init(
        launchArguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride? = nil,
        artifactChain: TimelineHomeConstructionArtifactChain?,
        createdAtMS: Int64
    ) {
        self.launchArguments = launchArguments
        self.debugOverride = debugOverride
        self.artifactChain = artifactChain
        self.createdAtMS = createdAtMS
    }
}

enum TimelineHomeCollectionViewRouteConstructionIssueKind: String, Codable, Equatable, Sendable {
    case missingExplicitCollectionViewFlag
    case requestedRouteNotCollectionView
    case artifactChainMissing
    case artifactChainDirty
    case readinessDirty
    case offscreenHarnessRejected
}

struct TimelineHomeCollectionViewRouteConstructionArtifactSummary: Codable, Equatable, Sendable {
    var requestedRoute: TimelineHomeRouteMode
    var constructionAllowed: Bool
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var routeDecisionSummary: String
    var constructionReadinessSummary: String
    var offscreenHarnessSummary: String
    var sideEffectSummary: String
    var rejectionIssueKinds: [TimelineHomeCollectionViewRouteConstructionIssueKind]
    var chainIssueKinds: [String]
    var deterministicSummary: String

    static func make(
        requestedRoute: TimelineHomeRouteMode,
        constructionAllowed: Bool,
        constructionKind: TimelineHomeCollectionViewRouteConstructionKind,
        renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision,
        routeActivationAllowed: Bool,
        consumer: TimelineHomeConstructionArtifactChainConsumer?,
        issueKinds: [TimelineHomeCollectionViewRouteConstructionIssueKind],
        chainIssueKinds: [String]
    ) -> TimelineHomeCollectionViewRouteConstructionArtifactSummary {
        let routeDecisionSummary = consumer?.diagnosticsSummaries.routeDecision ?? "none"
        let constructionReadinessSummary = consumer?.diagnosticsSummaries.constructionReadiness ?? "none"
        let offscreenHarnessSummary = consumer?.diagnosticsSummaries.offscreenHarness ?? "none"
        let sideEffectSummary = consumer?.sideEffectFlags.deterministicText ?? Self.cleanSideEffectSummary
        let deterministicSummary = [
            "requestedRoute=\(requestedRoute.rawValue)",
            "constructionAllowed=\(constructionAllowed)",
            "constructionKind=\(constructionKind.rawValue)",
            "renderedRouteAfterConstruction=\(renderedRouteAfterConstruction.rawValue)",
            "routeActivationAllowed=\(routeActivationAllowed)",
            "issues=\(issueKinds.map(\.rawValue).debugList)",
            "chainIssues=\(chainIssueKinds.debugList)",
            "sideEffects(\(sideEffectSummary))",
            "routeDecision={\(routeDecisionSummary)}",
            "constructionReadiness={\(constructionReadinessSummary)}",
            "offscreenHarness={\(offscreenHarnessSummary)}"
        ].joined(separator: " ")

        return TimelineHomeCollectionViewRouteConstructionArtifactSummary(
            requestedRoute: requestedRoute,
            constructionAllowed: constructionAllowed,
            constructionKind: constructionKind,
            renderedRouteAfterConstruction: renderedRouteAfterConstruction,
            routeActivationAllowed: routeActivationAllowed,
            routeDecisionSummary: routeDecisionSummary,
            constructionReadinessSummary: constructionReadinessSummary,
            offscreenHarnessSummary: offscreenHarnessSummary,
            sideEffectSummary: sideEffectSummary,
            rejectionIssueKinds: issueKinds,
            chainIssueKinds: chainIssueKinds,
            deterministicSummary: deterministicSummary
        )
    }

    private static var cleanSideEffectSummary: String {
        [
            "root=false",
            "home=false",
            "nostrStore=false",
            "collectionView=false",
            "network=false",
            "dbWrite=false",
            "readMarker=false",
            "dataSourceApply=false",
            "forbiddenDataSourceApply=false",
            "requiresNetworkWork=false",
            "requiresDBWrite=false"
        ].joined(separator: ",")
    }
}

struct TimelineHomeCollectionViewRouteConstructionResult: Codable, Equatable, Sendable {
    var requestedRoute: TimelineHomeRouteMode
    var constructionAttempted: Bool
    var constructionAllowed: Bool
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructed: Bool
    var collectionViewRouteConstructedFromRoot: Bool
    var timelineSurfaceConstructed: Bool
    var timelineSurfaceConstructedFromRoot: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var rootHomeRenderingChanged: Bool
    var legacyHomeRenderingPreserved: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyFromRootCalled: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var artifactSummary: TimelineHomeCollectionViewRouteConstructionArtifactSummary
    var issueKinds: [TimelineHomeCollectionViewRouteConstructionIssueKind]
    var createdAtMS: Int64
}

enum TimelineHomeCollectionViewRouteBuilder {
    static func construct(
        _ input: TimelineHomeCollectionViewRouteConstructionInput
    ) -> TimelineHomeCollectionViewRouteConstructionResult {
        TimelineHomeFlaggedCollectionViewRouteConstruction.evaluate(input)
    }
}

enum TimelineHomeFlaggedCollectionViewRouteConstruction {
    static func evaluate(
        _ input: TimelineHomeCollectionViewRouteConstructionInput
    ) -> TimelineHomeCollectionViewRouteConstructionResult {
        let requestedRoute = Self.requestedRoute(
            arguments: input.launchArguments,
            debugOverride: input.debugOverride
        )
        let hasExplicitFlag = Self.hasExplicitCollectionViewLaunchFlag(input.launchArguments)
        let consumer = input.artifactChain.map(TimelineHomeConstructionArtifactChainConsumer.init)
        let chainIssueKinds = Self.chainIssueKinds(for: consumer)
        let issueKinds = Self.issueKinds(
            requestedRoute: requestedRoute,
            hasExplicitFlag: hasExplicitFlag,
            consumer: consumer,
            chainIssueKinds: chainIssueKinds
        )
        let constructionAllowed = issueKinds.isEmpty
        let constructionKind = constructionAllowed
            ? consumer?.constructionKind ?? .productionClosed
            : .productionClosed
        let artifactSummary = TimelineHomeCollectionViewRouteConstructionArtifactSummary.make(
            requestedRoute: requestedRoute,
            constructionAllowed: constructionAllowed,
            constructionKind: constructionKind,
            renderedRouteAfterConstruction: .legacy,
            routeActivationAllowed: false,
            consumer: consumer,
            issueKinds: issueKinds,
            chainIssueKinds: chainIssueKinds
        )

        return TimelineHomeCollectionViewRouteConstructionResult(
            requestedRoute: requestedRoute,
            constructionAttempted: constructionAllowed,
            constructionAllowed: constructionAllowed,
            constructionKind: constructionKind,
            renderedRouteAfterConstruction: .legacy,
            routeActivationAllowed: false,
            collectionViewRouteConstructed: constructionAllowed,
            collectionViewRouteConstructedFromRoot: false,
            timelineSurfaceConstructed: false,
            timelineSurfaceConstructedFromRoot: false,
            timelineCollectionViewControllerConstructedFromRoot: false,
            rootHomeRenderingChanged: false,
            legacyHomeRenderingPreserved: true,
            noExtraNostrHomeTimelineStore: true,
            networkStarted: false,
            dbWriteAttempted: false,
            readMarkerAdvanced: false,
            dataSourceApplyFromRootCalled: false,
            coordinatorOwnedDataSourceApplyAllowed: constructionAllowed
                && (consumer?.coordinatorOwnedDataSourceApplyAllowed ?? false),
            artifactSummary: artifactSummary,
            issueKinds: issueKinds,
            createdAtMS: input.createdAtMS
        )
    }

    private static func issueKinds(
        requestedRoute: TimelineHomeRouteMode,
        hasExplicitFlag: Bool,
        consumer: TimelineHomeConstructionArtifactChainConsumer?,
        chainIssueKinds: [String]
    ) -> [TimelineHomeCollectionViewRouteConstructionIssueKind] {
        var issues: [TimelineHomeCollectionViewRouteConstructionIssueKind] = []

        append(.missingExplicitCollectionViewFlag, when: !hasExplicitFlag, to: &issues)
        append(.requestedRouteNotCollectionView, when: requestedRoute != .collectionView, to: &issues)

        guard let consumer else {
            append(.artifactChainMissing, when: true, to: &issues)
            return issues
        }

        append(.readinessDirty, when: !consumer.constructionReady || !consumer.constructionAllowed, to: &issues)
        append(.offscreenHarnessRejected, when: !consumer.offscreenHarnessAllowed || !consumer.noWindowAttached, to: &issues)
        append(.artifactChainDirty, when: !chainIssueKinds.isEmpty, to: &issues)

        return issues
    }

    private static func chainIssueKinds(
        for consumer: TimelineHomeConstructionArtifactChainConsumer?
    ) -> [String] {
        guard let consumer else {
            return []
        }

        var issues = consumer.combinedBlockedIssueKinds
        append("artifact.renderedRouteNotLegacy", when: !consumer.didRenderLegacy, to: &issues)
        append("artifact.activationOpen", when: consumer.routeActivationAllowed, to: &issues)
        append("artifact.collectionViewRouteConstructedFromRoot", when: consumer.collectionViewRouteConstructedFromRoot, to: &issues)
        append("artifact.timelineSurfaceConstructedFromRoot", when: consumer.timelineSurfaceConstructedFromRoot, to: &issues)
        append(
            "artifact.timelineCollectionViewControllerConstructedFromRoot",
            when: consumer.timelineCollectionViewControllerConstructedFromRoot,
            to: &issues
        )
        append("artifact.forbiddenDataSourceApply", when: consumer.forbiddenDataSourceApplyOutsideCoordinatorCalled, to: &issues)
        append("artifact.releaseBlockersPresent", when: !consumer.releaseBlockerFlags.isEmpty, to: &issues)
        append("artifact.sideEffectsDirty", when: consumer.sideEffectFlags.hasConstructionSideEffects, to: &issues)
        return issues
    }

    private static func requestedRoute(
        arguments: [String],
        debugOverride: TimelineHomeRouteDebugOverride?
    ) -> TimelineHomeRouteMode {
        if let debugOverride {
            return TimelineHomeRouteMode(debugOverride.engineMode)
        }

        let resolution = TimelineHomeEngineModeResolver.resolve(arguments: arguments)
        guard resolution.issues.isEmpty else {
            return .unknown
        }
        return TimelineHomeRouteMode(resolution.mode)
    }

    private static func hasExplicitCollectionViewLaunchFlag(_ arguments: [String]) -> Bool {
        TimelineHomeRouteLaunchArgumentSource(arguments: arguments).rawValue == AstrenzaTimelineEngineMode
            .collectionView
            .rawValue
    }

    private static func append(
        _ issue: TimelineHomeCollectionViewRouteConstructionIssueKind,
        when condition: Bool,
        to issues: inout [TimelineHomeCollectionViewRouteConstructionIssueKind]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }

    private static func append(
        _ issue: String,
        when condition: Bool,
        to issues: inout [String]
    ) {
        guard condition, !issues.contains(issue) else {
            return
        }
        issues.append(issue)
    }
}

private extension TimelineHomeConstructionArtifactChainSideEffectFlags {
    var hasConstructionSideEffects: Bool {
        rootViewConstructed
            || homeTimelineViewConstructed
            || nostrHomeTimelineStoreConstructed
            || timelineCollectionViewControllerConstructed
            || networkStarted
            || dbWriteAttempted
            || readMarkerAdvanced
            || dataSourceApplyCalled
            || forbiddenDataSourceApplyOutsideCoordinatorCalled
            || requiresNetworkWork
            || requiresDBWrite
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}
