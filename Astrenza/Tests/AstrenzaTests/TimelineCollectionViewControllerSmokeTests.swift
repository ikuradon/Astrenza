import AstrenzaCore
import Foundation
import Testing
import UIKit
@testable import Astrenza

@MainActor
@Suite("TimelineCollectionViewControllerSmoke")
struct TimelineCollectionViewControllerSmokeTests {
    @Test("offscreen controller loads from fake TimelineSurface dependencies without window")
    func offscreenControllerLoadsFromFakeTimelineSurfaceDependenciesWithoutWindow() async throws {
        let fakeStore = FakeTimelineSurfaceRepositoryStore(window: Self.window())
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: .collectionView,
            repositoryStore: fakeStore,
            clock: TimelineFixedClock(nowMS: 1_735_000_000_000)
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
        let plan = container.makeInitialRestorePlan(from: composition)

        let controller = container.makeController(
            for: plan,
            accountID: .debug,
            feedID: .debugHome,
            timelineKey: .home
        )

        #expect(controller.surfaceState.isViewLoaded == false)
        #expect(controller.surfaceState.itemIDs.map(\.rawValue) == ["note:visible"])

        controller.loadViewIfNeeded()
        let state = controller.surfaceState

        #expect(state.isViewLoaded)
        #expect(state.hasCollectionView)
        #expect(state.isAttachedToWindow == false)
        #expect(state.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(await fakeStore.fetchInitialWindowCallCount == 1)
        #expect(await fakeStore.networkStartCallCount == 0)
    }

    @Test("initial restore expectation stays coordinator owned local and pending neutral")
    func initialRestoreExpectationStaysCoordinatorOwnedLocalAndPendingNeutral() async throws {
        let fakeStore = FakeTimelineSurfaceRepositoryStore(window: Self.window())
        let container = TimelineSurfaceDependencyContainer.offline(
            mode: .collectionView,
            repositoryStore: fakeStore,
            clock: TimelineFixedClock(nowMS: 1_735_000_000_000)
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
        let plan = container.makeInitialRestorePlan(from: composition)
        let expectation = container.initialRestore.coordinatorExpectation(
            for: plan,
            timestampMS: container.clock.nowMilliseconds()
        )

        #expect(expectation.snapshot.itemIDs.map(\.rawValue) == ["note:visible"])
        #expect(expectation.expectsDataSourceApply == false)
        #expect(expectation.expectsInsertOrDeleteMutation == false)
        #expect(expectation.expectsResolveReconfigure == false)
        #expect(expectation.diagnostics.readMarkerChanged == false)
        #expect(expectation.diagnostics.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(expectation.diagnostics.requiresNetworkWork == false)
        #expect(expectation.diagnostics.requiresDBWork == false)
        #expect(expectation.diagnostics.pendingNewExcludedCount == 1)
        #expect(expectation.diagnostics.hiddenExcludedCount == 1)
        #expect(container.runtime.isClosedAndUnused)
        #expect(container.diagnosticsSink.destination == .localNoop)
        #expect(await fakeStore.networkStartCallCount == 0)
    }

    @Test("controller smoke source stays isolated from Home root splash network and direct apply")
    func controllerSmokeSourceStaysIsolatedFromHomeRootSplashNetworkAndDirectApply() throws {
        let source = try [
            "TimelineSurfaceDependencyContainer.swift",
            "TimelineCollectionViewController.swift"
        ]
            .map(sourceFile(named:))
            .joined(separator: "\n")

        #expect(!source.contains("Astrenza" + "RootView"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("Nostr" + "HomeTimelineStore"))
        #expect(!source.contains("Astrenza" + "StartupSplashView"))
        #expect(!source.contains("Timeline" + "FeedView"))
        #expect(!source.contains("Timeline" + "PostRow"))
        #expect(!source.contains("Timeline" + "Attachments"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("set" + "Default" + "Re" + "lays"))
        #expect(!source.contains("dataSource." + "apply"))
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
}

private actor FakeTimelineSurfaceRepositoryStore: TimelineRepositoryStore {
    let window: TimelineRepositoryInitialWindow
    private(set) var fetchInitialWindowCallCount = 0
    private(set) var networkStartCallCount = 0

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
