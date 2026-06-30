import Foundation

enum TimelineHomeRouteConstructionGate: String, Codable, Equatable, Sendable {
    case explicitCollectionViewLaunchFlag
    case dependencyReadiness
    case runtimeAllowed
    case rolloutAllowed
    case rootNoOpPreflightComplete
    case routeDiagnosticsSinkInjectionComplete
    case rootDecisionSnapshotAvailable
    case rootDecisionSnapshotObservedCollectionView
    case snapshotConsumerAvailable
    case offscreenControllerSmokePassed
    case initialRestoreSnapshotCoordinatorHarnessPassed
    case startupNetworkPatternClean
    case selectedSwiftTestingSuitesNonZero
    case networkWaitedBeforeInteractiveScrollZero
    case readMarkerUnchanged
    case requiresNetworkWorkFalse
    case requiresDBWriteFalse
    case dataSourceApplyCoordinatorOnly
    case noExtraNostrHomeTimelineStore
    case artifactPrivacyGuardPassed
    case sideEffectSentinelClean
    case productionRouteActivationClosed
}

struct TimelineHomeRouteConstructionIssue: Codable, Equatable, Sendable {
    var gate: TimelineHomeRouteConstructionGate
}

enum TimelineHomeCollectionViewRouteConstructionTarget: String, Codable, Equatable, Sendable {
    case collectionViewRoute
}

enum TimelineHomeCollectionViewRouteConstructionKind: String, Codable, Equatable, Sendable {
    case describedOnly
    case offscreenOnly
    case productionClosed
}

struct TimelineHomeCollectionViewRouteConstructionPlan: Codable, Equatable, Sendable {
    var target: TimelineHomeCollectionViewRouteConstructionTarget
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructed: Bool
    var timelineSurfaceConstructed: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var diagnosticsArtifactSummary: TimelineHomeRootRouteArtifactSnapshot
    var sideEffectSentinel: TimelineHomeRootRoutePreflightSideEffectSentinel
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var dataSourceApplyCalled: Bool
    var requiresNetworkWork: Bool
    var requiresDBWrite: Bool
}

struct TimelineHomeRouteConstructionReadinessResult: Codable, Equatable, Sendable {
    var isReady: Bool
    var issues: [TimelineHomeRouteConstructionIssue]
    var plan: TimelineHomeCollectionViewRouteConstructionPlan
}

struct TimelineHomeRouteConstructionReadiness: Codable, Equatable, Sendable {
    var hasExplicitCollectionViewLaunchFlag: Bool
    var dependencies: TimelineHomeRouteDependencyStatus
    var rootNoOpPreflightComplete: Bool
    var routeDiagnosticsSinkInjectionComplete: Bool
    var rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot?
    var snapshotConsumerAvailable: Bool
    var offscreenControllerSmokePassed: Bool
    var initialRestoreSnapshotCoordinatorHarnessPassed: Bool
    var startupNetworkPatternClean: Bool
    var selectedSwiftTestingSuitesNonZero: Bool
    var dataSourceApplyCoordinatorOnly: Bool
    var noExtraNostrHomeTimelineStore: Bool
    var artifactPrivacyGuardPassed: Bool
    var preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind

    func evaluate() -> TimelineHomeRouteConstructionReadinessResult {
        var issues: [TimelineHomeRouteConstructionIssue] = []

        appendIssue(.explicitCollectionViewLaunchFlag, when: !hasExplicitCollectionViewLaunchFlag, to: &issues)
        appendIssue(.dependencyReadiness, when: !dependencies.appConstructionReady, to: &issues)
        appendIssue(.runtimeAllowed, when: !dependencies.runtimeGuardAllowsCollectionView, to: &issues)
        appendIssue(.rolloutAllowed, when: !dependencies.rolloutAllowsCollectionView, to: &issues)
        appendIssue(.rootNoOpPreflightComplete, when: !rootNoOpPreflightComplete, to: &issues)
        appendIssue(.routeDiagnosticsSinkInjectionComplete, when: !routeDiagnosticsSinkInjectionComplete, to: &issues)

        if let snapshot = rootDecisionSnapshot {
            appendIssue(.rootDecisionSnapshotAvailable, when: snapshot.artifactSummary == .unavailable, to: &issues)
            appendIssue(
                .rootDecisionSnapshotObservedCollectionView,
                when: !snapshot.collectionViewDecisionObserved,
                to: &issues
            )
            appendIssue(
                .networkWaitedBeforeInteractiveScrollZero,
                when: snapshot.networkWaitedBeforeInteractiveScrollMS != 0,
                to: &issues
            )
            appendIssue(.readMarkerUnchanged, when: snapshot.readMarkerChanged, to: &issues)
            appendIssue(.requiresNetworkWorkFalse, when: snapshot.requiresNetworkWork, to: &issues)
            appendIssue(.requiresDBWriteFalse, when: snapshot.requiresDBWrite, to: &issues)
            appendIssue(
                .dataSourceApplyCoordinatorOnly,
                when: snapshot.dataSourceApplyCalled || !dataSourceApplyCoordinatorOnly,
                to: &issues
            )
            appendIssue(.sideEffectSentinelClean, when: !snapshot.sideEffectSentinel.isClean, to: &issues)
        } else {
            appendIssue(.rootDecisionSnapshotAvailable, when: true, to: &issues)
        }

        appendIssue(.snapshotConsumerAvailable, when: !snapshotConsumerAvailable, to: &issues)
        appendIssue(.offscreenControllerSmokePassed, when: !offscreenControllerSmokePassed, to: &issues)
        appendIssue(
            .initialRestoreSnapshotCoordinatorHarnessPassed,
            when: !initialRestoreSnapshotCoordinatorHarnessPassed,
            to: &issues
        )
        appendIssue(.startupNetworkPatternClean, when: !startupNetworkPatternClean, to: &issues)
        appendIssue(.selectedSwiftTestingSuitesNonZero, when: !selectedSwiftTestingSuitesNonZero, to: &issues)
        appendIssue(.dataSourceApplyCoordinatorOnly, when: !dataSourceApplyCoordinatorOnly, to: &issues)
        appendIssue(.noExtraNostrHomeTimelineStore, when: !noExtraNostrHomeTimelineStore, to: &issues)
        appendIssue(.artifactPrivacyGuardPassed, when: !artifactPrivacyGuardPassed, to: &issues)
        appendIssue(.productionRouteActivationClosed, when: preferredConstructionKind == .productionClosed, to: &issues)

        let isReady = issues.isEmpty
        return TimelineHomeRouteConstructionReadinessResult(
            isReady: isReady,
            issues: issues,
            plan: makePlan(isReady: isReady)
        )
    }

    private func makePlan(isReady: Bool) -> TimelineHomeCollectionViewRouteConstructionPlan {
        TimelineHomeCollectionViewRouteConstructionPlan(
            target: .collectionViewRoute,
            constructionKind: isReady ? preferredConstructionKind : .productionClosed,
            renderedRouteAfterConstruction: .legacy,
            routeActivationAllowed: false,
            collectionViewRouteConstructed: false,
            timelineSurfaceConstructed: false,
            timelineCollectionViewControllerConstructedFromRoot: false,
            diagnosticsArtifactSummary: rootDecisionSnapshot?.artifactSummary ?? .unavailable,
            sideEffectSentinel: .none,
            networkStarted: false,
            dbWriteAttempted: false,
            readMarkerAdvanced: false,
            dataSourceApplyCalled: false,
            requiresNetworkWork: false,
            requiresDBWrite: false
        )
    }

    private func appendIssue(
        _ gate: TimelineHomeRouteConstructionGate,
        when condition: Bool,
        to issues: inout [TimelineHomeRouteConstructionIssue]
    ) {
        guard condition else {
            return
        }
        issues.append(TimelineHomeRouteConstructionIssue(gate: gate))
    }
}

private extension TimelineHomeRouteDependencyStatus {
    var appConstructionReady: Bool {
        repositoryStoreAvailable
            && windowComposerAvailable
            && restoreUseCaseAvailable
            && coordinatorAdapterAvailable
            && collectionViewControllerAvailable
            && diagnosticsSinkAvailable
    }
}

private extension TimelineHomeRootRoutePreflightSideEffectSentinel {
    var isClean: Bool {
        !rootViewConstructed
            && !homeTimelineViewConstructed
            && !nostrHomeTimelineStoreConstructed
            && !timelineCollectionViewControllerConstructed
            && !networkStarted
            && !dbWriteAttempted
            && !readMarkerAdvanced
            && !dataSourceApplyCalled
    }
}
