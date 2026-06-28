import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineSurfaceDependencyContainer")
struct TimelineSurfaceDependencyContainerTests {
    @Test("container can be built with fake dependencies")
    func containerCanBeBuiltWithFakeDependencies() {
        let container = Self.container()

        #expect(container.mode == .collectionView)
        #expect(container.snapshotCoordinator.coordinatorOwnsDataSourceApply)
        #expect(container.runtime.isClosedAndUnused)
        #expect(container.diagnosticsSink.destination == .localNoop)
        #expect(container.clock.nowMilliseconds() == 1_735_000_000_000)
    }

    @Test("container exposes repository composer restore coordinator and diagnostics dependencies")
    func containerExposesReadOnlyRestoreDependencies() async throws {
        let container = Self.container()
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
        let plan = container.makeInitialRestorePlan(from: composition, requestedAnchorItemKey: "note:visible")
        let expectation = container.initialRestore.coordinatorExpectation(
            for: plan,
            timestampMS: container.clock.nowMilliseconds()
        )

        #expect(window.rows.map(\.itemKey) == ["note:visible"])
        #expect(composition.initialWindow.visibleItemKeys == ["note:visible"])
        #expect(plan.snapshotPlan.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(expectation.expectsDataSourceApply == false)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
        #expect(expectation.diagnostics.readMarkerChanged == false)
        #expect(expectation.diagnostics.requiresNetworkWork == false)
        #expect(expectation.diagnostics.requiresDBWork == false)
    }

    @Test("closed runtime dependencies are absent and unused")
    func closedRuntimeDependenciesAreAbsentAndUnused() {
        let runtime = TimelineSurfaceRuntimeDependencies.closed

        #expect(runtime.remoteClient == .absent)
        #expect(runtime.mediaResolver == .absent)
        #expect(runtime.linkPreviewResolver == .absent)
        #expect(runtime.targetResolver == .absent)
        #expect(runtime.isClosedAndUnused)
    }

    @Test("container does not call data source apply or mutate database state")
    func containerDoesNotCallDataSourceApplyOrMutateDatabaseState() throws {
        let source = try sourceFile(named: "TimelineSurfaceDependencyContainer.swift")
        let container = Self.container()

        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
        #expect(container.snapshotCoordinator.allowsDirectDataSourceApply == false)
        #expect(container.snapshotCoordinator.allowsInitialRestoreItemRemovalOrAddition == false)
        #expect(container.runtime.isClosedAndUnused)
    }

    @Test("container source avoids root splash and legacy timeline symbols")
    func containerSourceAvoidsRootSplashAndLegacyTimelineSymbols() throws {
        let source = try sourceFile(named: "TimelineSurfaceDependencyContainer.swift")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("Timeline" + "FeedView"))
        #expect(!source.contains("Timeline" + "PostRow"))
        #expect(!source.contains("Timeline" + "Attachments"))
    }

    @Test("offline restore plan remains local and keeps pending rows out by default")
    func offlineRestorePlanRemainsLocalAndKeepsPendingRowsOutByDefault() throws {
        let window = Self.window(rows: [
            Self.row(itemKey: "note:visible", sourceEventID: Self.eventID("a"), sortAt: 300, tieBreakID: "a"),
            Self.row(itemKey: "note:pending", sourceEventID: Self.eventID("b"), pendingNew: true, sortAt: 200, tieBreakID: "b")
        ])
        let container = Self.container(window: window)
        let composition = try container.windowComposer.compose(
            window,
            .debug,
            .home,
            .initialRestore(maxVisibleCount: 10)
        )
        let plan = container.makeInitialRestorePlan(from: composition)

        #expect(plan.snapshotPlan.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(plan.diagnostics.pendingNewExcludedCount == 1)
        #expect(plan.diagnostics.localDBReadWork)
        #expect(plan.diagnostics.requiresNetworkWork == false)
        #expect(plan.diagnostics.requiresDBWork == false)
        #expect(plan.diagnostics.readMarkerChanged == false)
    }

    @Test("dependency models are Sendable")
    func dependencyModelsAreSendable() {
        assertSendable(TimelineSurfaceDependencyContainer.self)
        assertSendable(TimelineRepositoryStoreWindowComposing.self)
        assertSendable(TimelineInitialRestoreDependencies.self)
        assertSendable(TimelineSurfaceSnapshotCoordinatorExpectation.self)
        assertSendable(TimelineSurfaceRuntimeDependencies.self)
        assertSendable(TimelineSurfaceDiagnosticsSink.self)
        assertSendable(TimelineFixedClock.self)
    }

    private static func container(
        window: TimelineRepositoryInitialWindow = window()
    ) -> TimelineSurfaceDependencyContainer {
        TimelineSurfaceDependencyContainer.offline(
            mode: .collectionView,
            repositoryStore: FakeTimelineRepositoryStore(window: window),
            clock: TimelineFixedClock(nowMS: 1_735_000_000_000)
        )
    }

    private static func window(
        rows: [TimelineRepositoryFeedItemRow] = [
            row(itemKey: "note:visible", sourceEventID: eventID("a"), sortAt: 100, tieBreakID: "a")
        ],
        anchorItemKey: String? = "note:visible"
    ) -> TimelineRepositoryInitialWindow {
        TimelineRepositoryInitialWindow(
            feedID: 10,
            rows: rows,
            readState: nil,
            anchorItemKey: anchorItemKey,
            issues: [],
            diagnostics: TimelineRepositoryStoreDiagnostics(
                totalFeedItemRowCount: rows.count,
                sqlVisibleRowCount: rows.filter { !$0.pendingNew && $0.hiddenReason == nil }.count,
                excludedHiddenCount: rows.filter { $0.hiddenReason != nil }.count,
                excludedPendingNewCount: rows.filter(\.pendingNew).count,
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

private struct FakeTimelineRepositoryStore: TimelineRepositoryStore {
    let window: TimelineRepositoryInitialWindow

    func fetchInitialWindow(
        _ request: TimelineRepositoryReadRequest,
        policy: TimelineRepositoryVisiblePolicy
    ) async throws -> TimelineRepositoryInitialWindow {
        window
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
