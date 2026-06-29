import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeRouteIntegrationSkeleton")
struct TimelineHomeRouteIntegrationSkeletonTests {
    @Test("default mode uses legacy home route")
    func defaultModeUsesLegacyHomeRoute() {
        let selection = routeSelection(arguments: ["Astrenza"])

        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.requestedMode == .legacy)
        #expect(selection.routeDecision.effectiveMode == .legacy)
        #expect(selection.fallbackIssues.isEmpty)
        #expect(selection.routeDecisionSource == .launchArguments)
        #expect(selection.timelineAreaRestoreGateScope == nil)
    }

    @Test("explicit legacy uses legacy home route")
    func explicitLegacyUsesLegacyHomeRoute() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=legacy"
        ])

        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.requestedMode == .legacy)
        #expect(selection.routeDecision.effectiveMode == .legacy)
        #expect(selection.fallbackIssues.isEmpty)
        #expect(selection.timelineAreaRestoreGateScope == nil)
    }

    @Test("collectionView flag with ready dependencies selects collectionView route")
    func collectionViewFlagWithReadyDependenciesSelectsCollectionViewRoute() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(selection.selectedRoute == .collectionView)
        #expect(selection.routeDecision.requestedMode == .collectionView)
        #expect(selection.routeDecision.effectiveMode == .collectionView)
        #expect(selection.fallbackIssues.isEmpty)
        #expect(selection.timelineAreaRestoreGateScope == .timelineArea)
        #expect(selection.preventsDualMutation)
    }

    @Test("collectionView flag with missing dependencies falls back to legacy")
    func collectionViewFlagWithMissingDependenciesFallsBackToLegacy() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false

        let selection = routeSelection(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.isFallback)
        #expect(selection.fallbackIssues.map(\.kind) == [.repositoryStoreUnavailable])
        #expect(selection.timelineAreaRestoreGateScope == nil)
    }

    @Test("unknown flag falls back to legacy")
    func unknownFlagFallsBackToLegacy() throws {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=grid"
        ])

        let issue = try #require(selection.fallbackIssues.first)
        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.requestedMode == .unknown)
        #expect(selection.routeDecision.isFallback)
        #expect(issue.kind == .unknownTimelineEngineMode)
        #expect(issue.argument == "--timeline-engine=grid")
        #expect(issue.rawValue == "grid")
    }

    @Test("runtime disabled falls back to legacy")
    func runtimeDisabledFallsBackToLegacy() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.runtimeGuardAllowsCollectionView = false

        let selection = routeSelection(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        let issue = try #require(selection.fallbackIssues.first)
        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.isFallback)
        #expect(issue.kind == .runtimeGuardDisabled)
    }

    @Test("rollout blocked falls back to legacy")
    func rolloutBlockedFallsBackToLegacy() throws {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.rolloutAllowsCollectionView = false

        let selection = routeSelection(
            arguments: ["Astrenza", "--timeline-engine=collectionView"],
            dependencies: dependencies
        )

        let issue = try #require(selection.fallbackIssues.first)
        #expect(selection.selectedRoute == .legacy)
        #expect(selection.routeDecision.isFallback)
        #expect(issue.kind == .rolloutBlocked)
    }

    @Test("route integration does not instantiate legacy timeline store")
    func routeIntegrationDoesNotInstantiateLegacyTimelineStore() {
        let legacy = routeSelection(arguments: ["Astrenza"])
        let collectionView = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(legacy.diagnostics.activation.instantiatesLegacyTimelineStore == false)
        #expect(collectionView.diagnostics.activation.instantiatesLegacyTimelineStore == false)
    }

    @Test("route integration does not instantiate production root")
    func routeIntegrationDoesNotInstantiateProductionRoot() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(selection.diagnostics.activation.instantiatesProductionRoot == false)
    }

    @Test("route integration does not start network")
    func routeIntegrationDoesNotStartNetwork() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(selection.requiresNetworkWork == false)
        #expect(selection.diagnostics.activation.startsNetworkWork == false)
    }

    @Test("route integration does not require database mutation")
    func routeIntegrationDoesNotRequireDatabaseMutation() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(selection.requiresDBWrite == false)
        #expect(selection.diagnostics.activation.performsDatabaseMutation == false)
    }

    @Test("route integration does not advance read marker")
    func routeIntegrationDoesNotAdvanceReadMarker() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])

        #expect(selection.readMarkerChanged == false)
        #expect(selection.diagnostics.activation.advancesReadMarker == false)
    }

    @Test("legacy and collectionView do not both mark visible mutation active")
    func legacyAndCollectionViewDoNotBothMarkVisibleMutationActive() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])
        let activation = selection.diagnostics.activation

        #expect(selection.preventsDualMutation)
        #expect(activation.hasDualVisibleMutation == false)
        #expect(activation.marksLegacyVisibleMutationActive == false)
        #expect(activation.marksCollectionViewVisibleMutationActive == false)
    }

    @Test("dataSource apply remains coordinator owned")
    func dataSourceApplyRemainsCoordinatorOwned() throws {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])
        let source = try sourceFile(named: "TimelineHomeRouteIntegrationSkeleton.swift")

        #expect(selection.diagnostics.activation.callsDataSourceApply == false)
        #expect(!source.contains("dataSource." + "apply"))
    }

    @Test("root shell contract remains immediate")
    func rootShellContractRemainsImmediate() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: selection.routeDecision,
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(selection.rootShellBehavior == .unchangedImmediate)
        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.rootShellPolicy.rootShellMustRenderBeforeTimelineRestore)
        #expect(plan.rootShellPolicy.timelineGateCoversRootShell == false)
        #expect(plan.rootShellPolicy.timelineGateCoversTabBar == false)
    }

    @Test("timeline restore gate remains timeline area only")
    func timelineRestoreGateRemainsTimelineAreaOnly() {
        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: selection.routeDecision,
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(selection.timelineAreaRestoreGateScope == .timelineArea)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.coversRootShell == false)
        #expect(plan.timelineAreaGate.coversTabBar == false)
        #expect(plan.timelineAreaGate.continuesGlobalSplash == false)
        #expect(plan.diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(plan.diagnostics.readMarkerChanged == false)
    }

    @Test("route integration source stays pure")
    func routeIntegrationSourceStaysPure() throws {
        let source = try sourceFile(named: "TimelineHomeRouteIntegrationSkeleton.swift")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("Timeline" + "FeedView"))
        #expect(!source.contains("Timeline" + "PostRow"))
        #expect(!source.contains("Timeline" + "Attachments"))
        #expect(!source.contains("Timeline" + "CollectionViewController("))
        #expect(!source.contains("TimelineSurface("))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("actor " + "Resolve" + "Coordinator"))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
    }

    @Test("route integration models are Codable Equatable and Sendable")
    func routeIntegrationModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeRouteIntegrationDecisionSource.self)
        assertSendable(TimelineHomeRouteRootShellBehavior.self)
        assertSendable(TimelineHomeRouteIntegrationActivation.self)
        assertSendable(TimelineHomeRouteIntegrationDiagnostics.self)
        assertSendable(TimelineHomeRouteSelection.self)

        let selection = routeSelection(arguments: [
            "Astrenza",
            "--timeline-engine=collectionView"
        ])
        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(TimelineHomeRouteSelection.self, from: data)

        #expect(decoded == selection)
    }

    private func routeSelection(
        arguments: [String],
        dependencies: TimelineHomeRouteDependencyStatus = .allAvailable
    ) -> TimelineHomeRouteSelection {
        TimelineHomeRouteIntegrationSkeleton.select(
            arguments: arguments,
            dependencies: dependencies
        )
    }

    private func initialRestorePlan(
        gateIntent: TimelineInitialRestoreGateIntent
    ) -> TimelineInitialRestorePlan {
        let entryID = TimelineEntryID(rawValue: "note:visible")
        return TimelineInitialRestorePlan(
            snapshotPlan: TimelineInitialRestoreSnapshotPlan(
                reason: .initialRestore,
                mutationStyle: .snapshot,
                itemIDs: [entryID],
                reconfigureIDs: [],
                insertedIDs: [],
                deletedIDs: [],
                callsDataSourceApply: false
            ),
            anchorPlan: TimelineInitialRestoreAnchorPlan(
                requestedAnchorItemKey: entryID.rawValue,
                candidateItemKey: entryID.rawValue,
                candidateEntryID: entryID,
                anchorSource: .scrollAnchor,
                fallbackReason: .anchorFound,
                scrollAnchorOffsetPX: 0,
                viewportHeightPX: 800,
                viewportWidthPX: 390,
                contentInsetTopPX: 0,
                contentInsetBottomPX: 0,
                savedAtMS: 1
            ),
            restoreGateIntent: gateIntent,
            diagnostics: TimelineInitialRestoreDiagnostics(
                inputRowCount: 1,
                snapshotItemCount: 1,
                fallbackReason: .anchorFound,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresDBWork: false,
                localDBReadWork: true,
                networkWaitedBeforeInteractiveScrollMS: 0,
                pendingNewExcludedCount: 0,
                hiddenExcludedCount: 0,
                issueCount: 0,
                repositoryIssueDiagnostics: [],
                boundaryIssues: [],
                localInitialWindowQueryDurationMS: 0,
                initialSnapshotApplyDurationMS: 0,
                anchorRestoreDurationMS: 0,
                restoreGateDurationMS: 0
            ),
            issues: []
        )
    }

    private func sourceFile(named fileName: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/\(fileName)"),
            encoding: .utf8
        )
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
