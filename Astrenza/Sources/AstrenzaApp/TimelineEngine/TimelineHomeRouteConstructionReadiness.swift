import Foundation

enum TimelineHomeRouteConstructionGate: String, CaseIterable, Codable, Equatable, Sendable {
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
    case visibleRouteCollectionViewPlaceholder
    case renderedRouteLegacy
    case collectionViewRouteNotConstructed
    case legacyHomeRendered
    case rootShellUnchanged
    case preventsDualMutation
    case artifactMissingDependenciesEmpty
    case artifactFallbackIssueKindsEmpty
    case artifactReleaseBlockerFlagsEmpty
    case timelineRestoreGateTimelineAreaOnly
    case rootOrGlobalRestoreGateNotAllowed
    case routeActivationRenderingSwitchClosed
    case timelineSurfaceNotConstructedFromRoot
    case timelineCollectionViewControllerNotConstructedFromRoot
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
    var routeActivationRenderingSwitchClosed: Bool = true
    var timelineSurfaceConstructedFromRoot: Bool = false
    var timelineCollectionViewControllerConstructedFromRoot: Bool = false
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
                .rootDecisionSnapshotAvailable,
                when: snapshot.diagnosticsRecordCount <= 0,
                to: &issues
            )
            appendIssue(
                .rootDecisionSnapshotObservedCollectionView,
                when: !snapshot.collectionViewDecisionObserved || snapshot.requestedRouteDecision != .collectionView,
                to: &issues
            )
            appendIssue(
                .visibleRouteCollectionViewPlaceholder,
                when: snapshot.visibleRoute != .collectionViewPlaceholder,
                to: &issues
            )
            appendIssue(.renderedRouteLegacy, when: snapshot.renderedRoute != .legacy, to: &issues)
            appendIssue(
                .collectionViewRouteNotConstructed,
                when: snapshot.collectionViewRouteConstructed,
                to: &issues
            )
            appendIssue(.legacyHomeRendered, when: !snapshot.legacyHomeRendered, to: &issues)
            appendIssue(.rootShellUnchanged, when: !snapshot.rootShellUnchanged, to: &issues)
            appendIssue(
                .rootShellUnchanged,
                when: snapshot.rootShellPresentation != .immediate
                    || !snapshot.rootShellMustRenderBeforeTimelineRestore,
                to: &issues
            )
            appendIssue(
                .timelineRestoreGateTimelineAreaOnly,
                when: snapshot.timelineRestoreGateScope != .timelineArea,
                to: &issues
            )
            appendIssue(
                .rootOrGlobalRestoreGateNotAllowed,
                when: snapshot.timelineGateCoversRootShell
                    || snapshot.timelineGateCoversTabBar
                    || snapshot.timelineGateContinuesGlobalSplash,
                to: &issues
            )
            appendIssue(
                .networkWaitedBeforeInteractiveScrollZero,
                when: snapshot.firstInteractiveScrollPolicy != .allowedAfterLocalRestoreWithoutNetwork,
                to: &issues
            )
            appendIssue(
                .networkWaitedBeforeInteractiveScrollZero,
                when: snapshot.networkWaitedBeforeInteractiveScrollMS != 0,
                to: &issues
            )
            appendIssue(.preventsDualMutation, when: !snapshot.preventsDualMutation, to: &issues)
            appendIssue(.readMarkerUnchanged, when: snapshot.readMarkerChanged, to: &issues)
            appendIssue(
                .requiresNetworkWorkFalse,
                when: snapshot.requiresNetworkWork
                    || snapshot.requiresRemoteSyncBeforeInteractiveScroll
                    || snapshot.requiresOGPResolveBeforeInteractiveScroll
                    || snapshot.requiresMediaResolveBeforeInteractiveScroll
                    || snapshot.requiresProfileResolveBeforeInteractiveScroll,
                to: &issues
            )
            appendIssue(.requiresDBWriteFalse, when: snapshot.requiresDBWrite, to: &issues)
            appendIssue(
                .dataSourceApplyCoordinatorOnly,
                when: snapshot.dataSourceApplyCalled || !dataSourceApplyCoordinatorOnly,
                to: &issues
            )
            appendIssue(.sideEffectSentinelClean, when: !snapshot.sideEffectSentinel.isClean, to: &issues)
            appendArtifactIssues(snapshot.artifactSummary, to: &issues)
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
        appendIssue(.routeActivationRenderingSwitchClosed, when: !routeActivationRenderingSwitchClosed, to: &issues)
        appendIssue(
            .timelineSurfaceNotConstructedFromRoot,
            when: timelineSurfaceConstructedFromRoot,
            to: &issues
        )
        appendIssue(
            .timelineCollectionViewControllerNotConstructedFromRoot,
            when: timelineCollectionViewControllerConstructedFromRoot,
            to: &issues
        )
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

    private func appendArtifactIssues(
        _ artifact: TimelineHomeRootRouteArtifactSnapshot,
        to issues: inout [TimelineHomeRouteConstructionIssue]
    ) {
        appendIssue(.rootDecisionSnapshotAvailable, when: artifact == .unavailable, to: &issues)
        appendIssue(
            .rootDecisionSnapshotAvailable,
            when: artifact.artifactKind != TimelineHomeRouteDecisionArtifact.artifactKind
                || artifact.artifactVersion != TimelineHomeRouteDecisionArtifact.artifactVersion
                || artifact.eventName != TimelineHomeRouteDecisionArtifact.eventName
                || artifact.source != .rootPreflight
                || artifact.schemaVersion != 1,
            to: &issues
        )
        appendIssue(
            .rootDecisionSnapshotObservedCollectionView,
            when: artifact.selectedRoute != .collectionView
                || artifact.requestedMode != .collectionView
                || artifact.effectiveMode != .collectionView
                || !artifact.collectionViewAllowed,
            to: &issues
        )
        appendIssue(.artifactMissingDependenciesEmpty, when: !artifact.missingDependencies.isEmpty, to: &issues)
        appendIssue(.artifactFallbackIssueKindsEmpty, when: !artifact.fallbackIssueKinds.isEmpty, to: &issues)
        appendIssue(.artifactReleaseBlockerFlagsEmpty, when: !artifact.releaseBlockerFlags.isEmpty, to: &issues)
        appendIssue(.artifactFallbackIssueKindsEmpty, when: artifact.legacyFallback, to: &issues)
        appendIssue(.runtimeAllowed, when: !artifact.runtimeAllowed, to: &issues)
        appendIssue(.rolloutAllowed, when: !artifact.rolloutAllowed, to: &issues)
        appendIssue(
            .rootShellUnchanged,
            when: artifact.rootShellBehavior != .unchangedImmediate || !artifact.rootShellBehaviorUnchanged,
            to: &issues
        )
        appendIssue(
            .timelineRestoreGateTimelineAreaOnly,
            when: artifact.timelineRestoreGateScope != .timelineArea,
            to: &issues
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
