import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHomeLaunchRestoreContract")
struct TimelineHomeLaunchRestoreContractTests {
    @Test("legacy route keeps root shell immediate without collectionView restore gate")
    func legacyRouteKeepsRootShellImmediateWithoutCollectionViewRestoreGate() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.legacy),
            initialRestorePlan: nil
        )

        #expect(plan.selectedRoute == .legacy)
        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.rootShellPolicy.rootShellMustRenderBeforeTimelineRestore)
        #expect(plan.timelineAreaGateState == .hidden)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.coversRootShell == false)
        #expect(plan.timelineAreaGate.coversTabBar == false)
        #expect(plan.firstInteractiveScrollPolicy == .allowedAfterLocalRestoreWithoutNetwork)
        #expect(plan.restoreFallbackPresentation == nil)
        #expect(plan.diagnostics.rootShellAvailable)
        #expect(plan.diagnostics.timelineAreaGated == false)
        #expect(plan.diagnostics.firstInteractiveScrollAllowed)
        #expect(plan.diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(plan.diagnostics.readMarkerChanged == false)
        #expect(plan.issues.isEmpty)
    }

    @Test("collectionView route with valid restore protects anchor restore only inside timeline area")
    func collectionViewRouteWithValidRestoreProtectsAnchorRestoreOnlyInsideTimelineArea() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(plan.selectedRoute == .collectionView)
        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.timelineAreaGateState == .protectAnchorRestore)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.coversRootShell == false)
        #expect(plan.timelineAreaGate.coversTabBar == false)
        #expect(plan.timelineAreaGate.fallbackPresentation == .inlineSkeleton)
        #expect(plan.restoreFallbackPresentation == .inlineSkeleton)
        #expect(plan.diagnostics.rootShellAvailable)
        #expect(plan.diagnostics.timelineAreaGated)
        #expect(plan.diagnostics.firstInteractiveScrollAllowed)
        #expect(plan.diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(plan.diagnostics.requiresNetworkWorkBeforeInteractiveScroll == false)
        #expect(plan.diagnostics.requiresDBWriteBeforeInteractiveScroll == false)
        #expect(plan.issues.isEmpty)
    }

    @Test("empty local cache stays scoped to timeline area empty state without global splash")
    func emptyLocalCacheStaysScopedToTimelineAreaEmptyStateWithoutGlobalSplash() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .emptyLocalCache, itemCount: 0)
        )

        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.timelineAreaGateState == .emptyLocalCache)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.continuesGlobalSplash == false)
        #expect(plan.timelineAreaGate.fallbackPresentation == .emptyState)
        #expect(plan.restoreFallbackPresentation == .emptyState)
        #expect(plan.diagnostics.rootShellAvailable)
        #expect(plan.diagnostics.timelineAreaGated)
        #expect(plan.diagnostics.firstInteractiveScrollAllowed)
        #expect(plan.issues.isEmpty)
    }

    @Test("recoverable failure stays scoped to timeline area recoverable state")
    func recoverableFailureStaysScopedToTimelineAreaRecoverableState() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .recoverableFailure)
        )

        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.timelineAreaGateState == .recoverableFailure)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.continuesGlobalSplash == false)
        #expect(plan.timelineAreaGate.fallbackPresentation == .recoverableState)
        #expect(plan.restoreFallbackPresentation == .recoverableState)
        #expect(plan.diagnostics.firstInteractiveScrollAllowed)
        #expect(plan.issues.isEmpty)
    }

    @Test("network wait before interactive scroll is rejected with typed issue")
    func networkWaitBeforeInteractiveScrollIsRejectedWithTypedIssue() {
        var diagnostics = TimelineHomeLaunchRestoreDiagnostics.safeDefault
        diagnostics.networkWaitedBeforeInteractiveScrollMS = 1

        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore),
            diagnosticsOverride: diagnostics
        )

        #expect(plan.issues.map(\.kind).contains(.networkWaitedBeforeInteractiveScroll))
        #expect(plan.diagnostics.firstInteractiveScrollAllowed == false)
    }

    @Test("readMarkerChanged true is rejected with typed issue")
    func readMarkerChangedTrueIsRejectedWithTypedIssue() {
        var diagnostics = TimelineHomeLaunchRestoreDiagnostics.safeDefault
        diagnostics.readMarkerChanged = true

        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore),
            diagnosticsOverride: diagnostics
        )

        #expect(plan.issues.map(\.kind).contains(.readMarkerChangedBeforeInteractiveScroll))
        #expect(plan.diagnostics.firstInteractiveScrollAllowed == false)
    }

    @Test("DB write before interactive scroll is rejected with typed issue")
    func dbWriteBeforeInteractiveScrollIsRejectedWithTypedIssue() {
        var diagnostics = TimelineHomeLaunchRestoreDiagnostics.safeDefault
        diagnostics.requiresDBWriteBeforeInteractiveScroll = true

        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore),
            diagnosticsOverride: diagnostics
        )

        #expect(plan.issues.map(\.kind).contains(.dbWriteRequiredBeforeInteractiveScroll))
        #expect(plan.diagnostics.firstInteractiveScrollAllowed == false)
    }

    @Test("fallback route keeps root shell immediate")
    func fallbackRouteKeepsRootShellImmediate() {
        var dependencies = TimelineHomeRouteDependencyStatus.allAvailable
        dependencies.repositoryStoreAvailable = false

        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: TimelineHomeRouteAdapter.decide(
                modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                    "Astrenza",
                    "--timeline-engine=collectionView"
                ]),
                dependencies: dependencies
            ),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(plan.selectedRoute == .legacy)
        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.timelineAreaGateState == .hidden)
        #expect(plan.diagnostics.rootShellAvailable)
        #expect(plan.issues.map(\.kind).contains(.routeFellBackToLegacy))
    }

    @Test("unknown flag parser issue does not block root shell")
    func unknownFlagParserIssueDoesNotBlockRootShell() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: TimelineHomeRouteAdapter.decide(
                modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: [
                    "Astrenza",
                    "--timeline-engine=grid"
                ]),
                dependencies: .allAvailable
            ),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(plan.selectedRoute == .legacy)
        #expect(plan.rootShellPresentation == .immediate)
        #expect(plan.timelineAreaGateState == .hidden)
        #expect(plan.diagnostics.rootShellAvailable)
        #expect(plan.diagnostics.firstInteractiveScrollAllowed)
        #expect(plan.issues.map(\.kind).contains(.unknownRouteFellBackToLegacy))
    }

    @Test("restore gate scope is timeline area and never global root")
    func restoreGateScopeIsTimelineAreaAndNeverGlobalRoot() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(plan.rootShellPolicy.timelineGateCoversRootShell == false)
        #expect(plan.rootShellPolicy.timelineGateCoversTabBar == false)
        #expect(plan.timelineAreaGate.scope == .timelineArea)
        #expect(plan.timelineAreaGate.coversRootShell == false)
        #expect(plan.timelineAreaGate.coversTabBar == false)
        #expect(plan.timelineAreaGate.continuesGlobalSplash == false)
    }

    @Test("remote and resolver dependencies are not required before interactive scroll")
    func remoteAndResolverDependenciesAreNotRequiredBeforeInteractiveScroll() {
        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )

        #expect(plan.diagnostics.requiresNetworkWorkBeforeInteractiveScroll == false)
        #expect(plan.diagnostics.requiresRemoteSyncBeforeInteractiveScroll == false)
        #expect(plan.diagnostics.requiresOGPResolveBeforeInteractiveScroll == false)
        #expect(plan.diagnostics.requiresMediaResolveBeforeInteractiveScroll == false)
        #expect(plan.diagnostics.requiresProfileResolveBeforeInteractiveScroll == false)
        #expect(plan.issues.isEmpty)
    }

    @Test("launch restore contract models are Codable Equatable and Sendable")
    func launchRestoreContractModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineHomeLaunchRestoreContract.self)
        assertSendable(TimelineRootShellRestorePolicy.self)
        assertSendable(TimelineAreaRestoreGateContract.self)
        assertSendable(TimelineHomeLaunchRestorePlan.self)
        assertSendable(TimelineHomeLaunchRestoreIssue.self)
        assertSendable(TimelineHomeLaunchRestoreDiagnostics.self)

        let plan = TimelineHomeLaunchRestoreContract.makePlan(
            routeDecision: routeDecision(.collectionView),
            initialRestorePlan: initialRestorePlan(gateIntent: .protectAnchorRestore)
        )
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(TimelineHomeLaunchRestorePlan.self, from: data)

        #expect(decoded == plan)
    }

    @Test("launch restore contract source stays pure")
    func launchRestoreContractSourceStaysPure() throws {
        let source = try sourceFile(named: "TimelineHomeLaunchRestoreContract.swift")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Timeline" + "FeedView"))
        #expect(!source.contains("Timeline" + "PostRow"))
        #expect(!source.contains("Timeline" + "Attachments"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Relays"))
        #expect(!source.contains("GR" + "DB"))
        #expect(!source.contains("exec" + "ute("))
        #expect(!source.contains("wri" + "te("))
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
    }

    private func routeDecision(_ route: TimelineHomeRouteMode) -> TimelineHomeRouteDecision {
        let arguments: [String]
        switch route {
        case .legacy, .unknown:
            arguments = ["Astrenza"]
        case .collectionView:
            arguments = ["Astrenza", "--timeline-engine=collectionView"]
        }

        return TimelineHomeRouteAdapter.decide(
            modeResolution: TimelineHomeEngineModeResolver.resolve(arguments: arguments),
            dependencies: .allAvailable
        )
    }

    private func initialRestorePlan(
        gateIntent: TimelineInitialRestoreGateIntent,
        itemCount: Int = 1
    ) -> TimelineInitialRestorePlan {
        let itemIDs = (0..<itemCount).map { TimelineEntryID(rawValue: "note:\($0)") }
        let candidateEntryID = itemIDs.first
        let fallbackReason: TimelineRepositoryBoundaryFallbackReason = itemCount == 0
            ? .noVisibleRows
            : .anchorFound

        return TimelineInitialRestorePlan(
            snapshotPlan: TimelineInitialRestoreSnapshotPlan(
                reason: .initialRestore,
                mutationStyle: .snapshot,
                itemIDs: itemIDs,
                reconfigureIDs: [],
                insertedIDs: [],
                deletedIDs: [],
                callsDataSourceApply: false
            ),
            anchorPlan: TimelineInitialRestoreAnchorPlan(
                requestedAnchorItemKey: candidateEntryID?.rawValue,
                candidateItemKey: candidateEntryID?.rawValue,
                candidateEntryID: candidateEntryID,
                anchorSource: candidateEntryID == nil ? .none : .scrollAnchor,
                fallbackReason: fallbackReason,
                scrollAnchorOffsetPX: 0,
                viewportHeightPX: 800,
                viewportWidthPX: 390,
                contentInsetTopPX: 0,
                contentInsetBottomPX: 0,
                savedAtMS: 1
            ),
            restoreGateIntent: gateIntent,
            diagnostics: TimelineInitialRestoreDiagnostics(
                inputRowCount: itemCount,
                snapshotItemCount: itemCount,
                fallbackReason: fallbackReason,
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
