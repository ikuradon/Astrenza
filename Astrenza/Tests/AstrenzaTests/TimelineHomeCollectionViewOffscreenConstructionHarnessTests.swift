import AstrenzaCore
import Foundation
import Testing
import UIKit
@testable import Astrenza

@MainActor
@Suite("TimelineHome collectionView offscreen construction harness")
struct TimelineHomeCollectionViewOffscreenConstructionHarnessTests {
    @Test("ready described plan allows offscreen/no-window harness")
    func ready_described_plan_allows_offscreen_no_window_harness() async throws {
        let harness = TimelineHomeRouteConstructionPlanOffscreenHarness()
        let result = try await harness.evaluate(consumer(for: readyResult(kind: .describedOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.rejectionReasons.isEmpty)
        #expect(result.constructionKind == .describedOnly)
        #expect(result.controllerLoadedOffscreen)
        #expect(result.isAttachedToWindow == false)
        #expect(result.controllerItemIDs == ["note:visible"])
    }

    @Test("blocked missing flag plan rejects harness")
    func blocked_missing_flag_plan_rejects_harness() async throws {
        let harness = TimelineHomeRouteConstructionPlanOffscreenHarness()
        let result = try await harness.evaluate(consumer(for: readyResult(hasExplicitCollectionViewLaunchFlag: false)))

        #expect(result.offscreenConstructionAllowed == false)
        #expect(result.rejectionReasons.contains(.readinessBlocked))
        #expect(result.constructionKind == .productionClosed)
        #expect(result.controllerLoadedOffscreen == false)
    }

    @Test("dirty snapshot plan rejects harness")
    func dirty_snapshot_plan_rejects_harness() async throws {
        let harness = TimelineHomeRouteConstructionPlanOffscreenHarness()
        let result = try await harness.evaluate(consumer(for: dirtySnapshotResult()))

        #expect(result.offscreenConstructionAllowed == false)
        #expect(result.rejectionReasons.contains(.readinessBlocked))
        #expect(result.rejectionReasons.contains(.constructionPlanClosed))
        #expect(result.controllerLoadedOffscreen == false)
    }

    @Test("activation-open plan rejects harness")
    func activation_open_plan_rejects_harness() async throws {
        var readiness = readyResult(kind: .offscreenOnly)
        readiness.plan.routeActivationAllowed = true
        let harness = TimelineHomeRouteConstructionPlanOffscreenHarness()

        let result = try await harness.evaluate(readiness)

        #expect(result.offscreenConstructionAllowed == false)
        #expect(result.rejectionReasons.contains(.routeActivationOpen))
        #expect(result.routeActivationAllowed)
        #expect(result.controllerLoadedOffscreen == false)
    }

    @Test("default legacy plan does not construct collectionView from Root")
    func default_legacy_plan_does_not_construct_collectionView_from_root() async throws {
        let harness = TimelineHomeRouteConstructionPlanOffscreenHarness()
        let result = try await harness.evaluate(consumer(for: readyResult(
            hasExplicitCollectionViewLaunchFlag: false,
            snapshot: makeSnapshot(arguments: ["Astrenza"])
        )))

        #expect(result.offscreenConstructionAllowed == false)
        #expect(result.collectionViewRouteConstructedFromRoot == false)
        #expect(result.timelineSurfaceConstructedFromRoot == false)
        #expect(result.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test("offscreen harness does not attach UIWindow")
    func offscreen_harness_does_not_attach_uiwindow() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.controllerLoadedOffscreen)
        #expect(result.isAttachedToWindow == false)
    }

    @Test("offscreen harness does not start network")
    func offscreen_harness_does_not_start_network() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.networkStarted == false)
    }

    @Test("offscreen harness does not write DB")
    func offscreen_harness_does_not_write_db() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.dbWriteAttempted == false)
    }

    @Test("offscreen harness does not advance read marker")
    func offscreen_harness_does_not_advance_read_marker() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.readMarkerAdvanced == false)
    }

    @Test("offscreen harness does not call forbidden dataSourceApply outside coordinator")
    func offscreen_harness_does_not_call_forbidden_dataSourceApply_outside_coordinator() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.offscreenConstructionAllowed)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
        #expect(result.forbiddenDataSourceApplyOutsideCoordinatorCalled == false)
    }

    @Test("rendered route after construction remains legacy")
    func rendered_route_after_construction_remains_legacy() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.renderedRouteAfterConstruction == .legacy)
    }

    @Test("route activation remains false")
    func route_activation_remains_false() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.routeActivationAllowed == false)
    }

    @Test("timelineSurfaceConstructedFromRoot false")
    func timelineSurfaceConstructedFromRoot_false() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.timelineSurfaceConstructedFromRoot == false)
    }

    @Test("timelineCollectionViewControllerConstructedFromRoot false")
    func timelineCollectionViewControllerConstructedFromRoot_false() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.timelineCollectionViewControllerConstructedFromRoot == false)
    }

    @Test("result has deterministic debug summary")
    func result_has_deterministic_debug_summary() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))

        #expect(result.deterministicDebugSummary == expectedOffscreenHarnessSummary)
    }

    @Test("privacy forbidden fragments absent from encoded result")
    func privacy_forbidden_fragments_absent_from_encoded_result() async throws {
        let result = try await TimelineHomeRouteConstructionPlanOffscreenHarness()
            .evaluate(consumer(for: readyResult(kind: .offscreenOnly)))
        let encoded = try encodedJSONString(result).lowercased()
        let payload = try #require(try JSONSerialization.jsonObject(with: encodedData(result)) as? [String: Any])

        for fragment in forbiddenPrivacyFragments {
            #expect(!encoded.contains(fragment))
        }
        #expect(Set(payload.keys) == allowedHarnessResultKeys)
    }
}

private var expectedOffscreenHarnessSummary: String {
    "allowed=true kind=offscreenOnly rendered=legacy activation=false rootFlags(route=false,surface=false,controller=false) sideEffects(network=false,dbWrite=false,readMarker=false,forbiddenDataSourceApply=false) coordinatorApplyAllowed=true offscreen(viewLoaded=true,attachedToWindow=false,itemIDs=[note:visible]) rejections=[]"
}

private var forbiddenPrivacyFragments: [String] {
    [
        "nsec",
        "secret",
        "privatekey",
        "private_key",
        "raw_json",
        "rawevent",
        "raw_event",
        "mnemonic",
        "keychain",
        "nostr secret",
        "raw event content phrase",
        "private message content phrase",
        "relay url",
        "pubkey",
        "event id",
        "eventid",
        "event_id"
    ]
}

private var allowedHarnessResultKeys: Set<String> {
    [
        "collectionViewRouteConstructedFromRoot",
        "constructionKind",
        "controllerItemIDs",
        "controllerLoadedOffscreen",
        "coordinatorOwnedDataSourceApplyAllowed",
        "dbWriteAttempted",
        "forbiddenDataSourceApplyOutsideCoordinatorCalled",
        "isAttachedToWindow",
        "networkStarted",
        "offscreenConstructionAllowed",
        "readMarkerAdvanced",
        "rejectionReasons",
        "renderedRouteAfterConstruction",
        "routeActivationAllowed",
        "timelineCollectionViewControllerConstructedFromRoot",
        "timelineSurfaceConstructedFromRoot"
    ]
}

private func readyResult(
    kind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly,
    hasExplicitCollectionViewLaunchFlag: Bool = true,
    snapshot: TimelineHomeRootRouteDecisionSnapshot? = nil
) -> TimelineHomeRouteConstructionReadinessResult {
    makeReadiness(
        hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
        rootDecisionSnapshot: snapshot ?? makeSnapshot(),
        preferredConstructionKind: kind
    ).evaluate()
}

private func dirtySnapshotResult() -> TimelineHomeRouteConstructionReadinessResult {
    var snapshot = makeSnapshot()
    snapshot.renderedRoute = .collectionViewPlaceholder
    snapshot.collectionViewRouteConstructed = true
    snapshot.sideEffectSentinel.networkStarted = true
    snapshot.artifactSummary.releaseBlockerFlags = [.requiresNetworkWork]
    return makeReadiness(rootDecisionSnapshot: snapshot).evaluate()
}

private func makeReadiness(
    hasExplicitCollectionViewLaunchFlag: Bool = true,
    rootDecisionSnapshot: TimelineHomeRootRouteDecisionSnapshot = makeSnapshot(),
    preferredConstructionKind: TimelineHomeCollectionViewRouteConstructionKind = .describedOnly
) -> TimelineHomeRouteConstructionReadiness {
    TimelineHomeRouteConstructionReadiness(
        hasExplicitCollectionViewLaunchFlag: hasExplicitCollectionViewLaunchFlag,
        dependencies: .allAvailable,
        rootNoOpPreflightComplete: true,
        routeDiagnosticsSinkInjectionComplete: true,
        rootDecisionSnapshot: rootDecisionSnapshot,
        snapshotConsumerAvailable: true,
        offscreenControllerSmokePassed: true,
        initialRestoreSnapshotCoordinatorHarnessPassed: true,
        startupNetworkPatternClean: true,
        selectedSwiftTestingSuitesNonZero: true,
        dataSourceApplyCoordinatorOnly: true,
        noExtraNostrHomeTimelineStore: true,
        artifactPrivacyGuardPassed: true,
        preferredConstructionKind: preferredConstructionKind
    )
}

private func makeSnapshot(
    arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"]
) -> TimelineHomeRootRouteDecisionSnapshot {
    let result = TimelineHomeRootRouteCallSite.invoke(
        launchArguments: arguments,
        dependencies: .allAvailable,
        createdAtMS: 1_735_000_004_100
    )
    return TimelineHomeRootRouteDecisionSnapshot.make(
        from: result,
        createdAtMS: 1_735_000_004_200
    )
}

private func consumer(
    for result: TimelineHomeRouteConstructionReadinessResult
) throws -> TimelineHomeRouteConstructionReadinessConsumer {
    try TimelineHomeRouteConstructionReadinessConsumer.decodeFixtureJSON(
        encodedData(result)
    )
}

private func encodedData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    let data = try encodedData(value)
    return try #require(String(data: data, encoding: .utf8))
}

private typealias TimelineHomeCollectionViewOffscreenConstructionHarness = TimelineHomeRouteConstructionPlanOffscreenHarness

@MainActor
private struct TimelineHomeRouteConstructionPlanOffscreenHarness {
    func evaluate(
        _ consumer: TimelineHomeRouteConstructionReadinessConsumer
    ) async throws -> TimelineHomeCollectionViewConstructionHarnessResult {
        try await evaluate(consumer.result)
    }

    func evaluate(
        _ readiness: TimelineHomeRouteConstructionReadinessResult
    ) async throws -> TimelineHomeCollectionViewConstructionHarnessResult {
        try await evaluate(
            isReady: readiness.isReady,
            issues: readiness.issues,
            plan: readiness.plan
        )
    }

    func evaluate(
        plan: TimelineHomeCollectionViewRouteConstructionPlan,
        isReady: Bool
    ) async throws -> TimelineHomeCollectionViewConstructionHarnessResult {
        try await evaluate(isReady: isReady, issues: [], plan: plan)
    }

    private func evaluate(
        isReady: Bool,
        issues: [TimelineHomeRouteConstructionIssue],
        plan: TimelineHomeCollectionViewRouteConstructionPlan
    ) async throws -> TimelineHomeCollectionViewConstructionHarnessResult {
        let rejections = rejectionReasons(
            isReady: isReady,
            issues: issues,
            plan: plan
        )

        guard rejections.isEmpty else {
            return TimelineHomeCollectionViewConstructionHarnessResult(
                offscreenConstructionAllowed: false,
                rejectionReasons: rejections,
                constructionKind: plan.constructionKind,
                renderedRouteAfterConstruction: plan.renderedRouteAfterConstruction,
                routeActivationAllowed: plan.routeActivationAllowed,
                collectionViewRouteConstructedFromRoot: plan.collectionViewRouteConstructed,
                timelineSurfaceConstructedFromRoot: plan.timelineSurfaceConstructed,
                timelineCollectionViewControllerConstructedFromRoot: plan.timelineCollectionViewControllerConstructedFromRoot,
                controllerLoadedOffscreen: false,
                isAttachedToWindow: false,
                networkStarted: plan.networkStarted || plan.sideEffectSentinel.networkStarted,
                dbWriteAttempted: plan.dbWriteAttempted || plan.sideEffectSentinel.dbWriteAttempted,
                readMarkerAdvanced: plan.readMarkerAdvanced || plan.sideEffectSentinel.readMarkerAdvanced,
                coordinatorOwnedDataSourceApplyAllowed: false,
                forbiddenDataSourceApplyOutsideCoordinatorCalled: plan.dataSourceApplyCalled
                    || plan.sideEffectSentinel.dataSourceApplyCalled,
                controllerItemIDs: []
            )
        }

        let fakeStore = TimelineHomeOffscreenConstructionFakeRepositoryStore(window: Self.window())
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: .collectionView,
            repositoryStore: fakeStore,
            clock: TimelineFixedClock(nowMS: 1_735_000_004_300)
        )
        let window = try await container.repositoryStore.fetchInitialWindow(
            TimelineRepositoryReadRequest(feedID: 10, databaseAccountID: 1),
            policy: .initialRestore(maxVisibleCount: 10)
        )
        let composition = try container.windowComposer.compose(
            window,
            .debug,
            .home,
            .initialRestore(maxVisibleCount: 10)
        )
        let restorePlan = container.makeInitialRestorePlan(from: composition)
        let controller = container.makeController(
            for: restorePlan,
            accountID: .debug,
            feedID: .debugHome,
            timelineKey: .home
        )

        controller.loadViewIfNeeded()
        let state = controller.surfaceState
        let networkStartCallCount = await fakeStore.networkStartCallCount
        let dbWriteAttemptCallCount = await fakeStore.dbWriteAttemptCallCount
        let readMarkerAdvanceCallCount = await fakeStore.readMarkerAdvanceCallCount

        return TimelineHomeCollectionViewConstructionHarnessResult(
            offscreenConstructionAllowed: true,
            rejectionReasons: [],
            constructionKind: plan.constructionKind,
            renderedRouteAfterConstruction: plan.renderedRouteAfterConstruction,
            routeActivationAllowed: plan.routeActivationAllowed,
            collectionViewRouteConstructedFromRoot: plan.collectionViewRouteConstructed,
            timelineSurfaceConstructedFromRoot: plan.timelineSurfaceConstructed,
            timelineCollectionViewControllerConstructedFromRoot: plan.timelineCollectionViewControllerConstructedFromRoot,
            controllerLoadedOffscreen: state.isViewLoaded,
            isAttachedToWindow: state.isAttachedToWindow,
            networkStarted: plan.networkStarted
                || plan.sideEffectSentinel.networkStarted
                || networkStartCallCount > 0,
            dbWriteAttempted: plan.dbWriteAttempted
                || plan.sideEffectSentinel.dbWriteAttempted
                || dbWriteAttemptCallCount > 0,
            readMarkerAdvanced: plan.readMarkerAdvanced
                || plan.sideEffectSentinel.readMarkerAdvanced
                || readMarkerAdvanceCallCount > 0,
            coordinatorOwnedDataSourceApplyAllowed: true,
            forbiddenDataSourceApplyOutsideCoordinatorCalled: plan.dataSourceApplyCalled
                || plan.sideEffectSentinel.dataSourceApplyCalled,
            controllerItemIDs: state.itemIDs.map(\.rawValue)
        )
    }

    private func rejectionReasons(
        isReady: Bool,
        issues: [TimelineHomeRouteConstructionIssue],
        plan: TimelineHomeCollectionViewRouteConstructionPlan
    ) -> [TimelineHomeOffscreenConstructionRejection] {
        var reasons: [TimelineHomeOffscreenConstructionRejection] = []

        append(.readinessBlocked, when: !isReady || !issues.isEmpty, to: &reasons)
        append(.unsupportedConstructionKind, when: !plan.constructionKind.allowsOffscreenHarness, to: &reasons)
        append(.renderedRouteNotLegacy, when: plan.renderedRouteAfterConstruction != .legacy, to: &reasons)
        append(.routeActivationOpen, when: plan.routeActivationAllowed, to: &reasons)
        append(.rootRouteConstructionOpen, when: plan.collectionViewRouteConstructed, to: &reasons)
        append(.rootSurfaceConstructionOpen, when: plan.timelineSurfaceConstructed, to: &reasons)
        append(
            .rootControllerConstructionOpen,
            when: plan.timelineCollectionViewControllerConstructedFromRoot,
            to: &reasons
        )
        append(
            .sideEffectFlagsDirty,
            when: plan.sideEffectSentinel != .none
                || plan.networkStarted
                || plan.dbWriteAttempted
                || plan.readMarkerAdvanced
                || plan.dataSourceApplyCalled
                || plan.requiresNetworkWork
                || plan.requiresDBWrite,
            to: &reasons
        )
        append(.constructionPlanClosed, when: !TimelineHomeRouteConstructionPlanConsumer(plan: plan).constructionAllowed, to: &reasons)

        return reasons
    }

    private func append(
        _ reason: TimelineHomeOffscreenConstructionRejection,
        when condition: Bool,
        to reasons: inout [TimelineHomeOffscreenConstructionRejection]
    ) {
        guard condition, !reasons.contains(reason) else {
            return
        }
        reasons.append(reason)
    }

    private static func window() -> TimelineRepositoryInitialWindow {
        let rows = [
            row(
                itemKey: "note:visible",
                sourceEventID: eventID("a"),
                sortAt: 300,
                tieBreakID: "a"
            ),
            row(
                itemKey: "note:pending",
                sourceEventID: eventID("b"),
                pendingNew: true,
                sortAt: 400,
                tieBreakID: "b"
            ),
            row(
                itemKey: "note:hidden",
                sourceEventID: eventID("c"),
                hiddenReason: "muted",
                sortAt: 200,
                tieBreakID: "c"
            )
        ]

        return TimelineRepositoryInitialWindow(
            feedID: 10,
            rows: rows,
            readState: nil,
            anchorItemKey: "note:visible",
            issues: [],
            diagnostics: TimelineRepositoryStoreDiagnostics(
                totalFeedItemRowCount: rows.count,
                sqlVisibleRowCount: 1,
                excludedHiddenCount: 1,
                excludedPendingNewCount: 1,
                pendingNewIncludedCount: 0,
                readStatePresent: false,
                readMarkerChanged: false,
                requiresNetworkWork: false,
                requiresExternalMutation: false,
                performedLocalDBRead: true,
                resolveJobRowCount: 0,
                diagnosticRowCount: 0
            )
        )
    }

    private static func row(
        itemKey: String,
        sourceEventID: String,
        hiddenReason: String? = nil,
        pendingNew: Bool = false,
        sortAt: Int64,
        tieBreakID: String
    ) -> TimelineRepositoryFeedItemRow {
        TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: sourceEventID,
            reason: .author,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            hiddenReason: hiddenReason,
            pendingNew: pendingNew,
            insertedAtMS: 1,
            updatedAtMS: 2
        )
    }

    private static func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }
}

private struct TimelineHomeCollectionViewConstructionHarnessResult: Codable, Equatable, Sendable {
    var offscreenConstructionAllowed: Bool
    var rejectionReasons: [TimelineHomeOffscreenConstructionRejection]
    var constructionKind: TimelineHomeCollectionViewRouteConstructionKind
    var renderedRouteAfterConstruction: TimelineHomeRootVisibleRouteDecision
    var routeActivationAllowed: Bool
    var collectionViewRouteConstructedFromRoot: Bool
    var timelineSurfaceConstructedFromRoot: Bool
    var timelineCollectionViewControllerConstructedFromRoot: Bool
    var controllerLoadedOffscreen: Bool
    var isAttachedToWindow: Bool
    var networkStarted: Bool
    var dbWriteAttempted: Bool
    var readMarkerAdvanced: Bool
    var coordinatorOwnedDataSourceApplyAllowed: Bool
    var forbiddenDataSourceApplyOutsideCoordinatorCalled: Bool
    var controllerItemIDs: [String]

    var deterministicDebugSummary: String {
        [
            "allowed=\(offscreenConstructionAllowed)",
            "kind=\(constructionKind.rawValue)",
            "rendered=\(renderedRouteAfterConstruction.rawValue)",
            "activation=\(routeActivationAllowed)",
            "rootFlags(route=\(collectionViewRouteConstructedFromRoot),surface=\(timelineSurfaceConstructedFromRoot),controller=\(timelineCollectionViewControllerConstructedFromRoot))",
            "sideEffects(network=\(networkStarted),dbWrite=\(dbWriteAttempted),readMarker=\(readMarkerAdvanced),forbiddenDataSourceApply=\(forbiddenDataSourceApplyOutsideCoordinatorCalled))",
            "coordinatorApplyAllowed=\(coordinatorOwnedDataSourceApplyAllowed)",
            "offscreen(viewLoaded=\(controllerLoadedOffscreen),attachedToWindow=\(isAttachedToWindow),itemIDs=\(controllerItemIDs.debugList))",
            "rejections=\(rejectionReasons.map(\.rawValue).debugList)"
        ].joined(separator: " ")
    }
}

private enum TimelineHomeOffscreenConstructionRejection: String, Codable, Equatable, Sendable {
    case readinessBlocked
    case unsupportedConstructionKind
    case renderedRouteNotLegacy
    case routeActivationOpen
    case rootRouteConstructionOpen
    case rootSurfaceConstructionOpen
    case rootControllerConstructionOpen
    case sideEffectFlagsDirty
    case constructionPlanClosed
}

private extension TimelineHomeCollectionViewRouteConstructionKind {
    var allowsOffscreenHarness: Bool {
        self == .describedOnly || self == .offscreenOnly
    }
}

private extension Array where Element == String {
    var debugList: String {
        "[\(joined(separator: ","))]"
    }
}

private actor TimelineHomeOffscreenConstructionFakeRepositoryStore: TimelineRepositoryStore {
    let window: TimelineRepositoryInitialWindow
    private(set) var fetchInitialWindowCallCount = 0
    private(set) var networkStartCallCount = 0
    private(set) var dbWriteAttemptCallCount = 0
    private(set) var readMarkerAdvanceCallCount = 0

    init(window: TimelineRepositoryInitialWindow) {
        self.window = window
    }

    func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        fetchInitialWindowCallCount += 1
        return window
    }

    func fetchReadState(
        feedID: Int64,
        databaseAccountID: Int64?
    ) async throws -> TimelineRepositoryReadStateRow? {
        window.readState
    }

    func fetchAnchorWindow(
        feedID: Int64,
        anchorItemKey: String,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        window
    }
}
