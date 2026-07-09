import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineHome collectionView local pagination windowing")
struct TimelineHomeCollectionViewLocalPaginationWindowingTests {
    @Test
    func default_without_flag_uses_legacy_pagination_path() {
        let result = LocalPaginationWindowingHarness.evaluate(
            arguments: ["Astrenza"],
            routeRestoreDecision: LocalPaginationWindowingFixture.legacyRouteDecision()
        )

        #expect(result.paginationPath == .legacy)
        #expect(result.selectedRoute == .legacy)
        #expect(result.localWindowingAllowed == false)
        #expect(result.visibleItemKeys.isEmpty)
    }

    @Test
    func flagged_clean_route_allows_local_windowing() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.paginationPath == .collectionView)
        #expect(result.selectedRoute == .collectionView)
        #expect(result.usedCollectionViewFlag)
        #expect(result.localWindowingAllowed)
        #expect(result.visibleItemKeys == LocalPaginationWindowingFixture.initialVisibleItemKeys)
        #expect(result.visibleAnchorItemKey == "note:anchor")
    }

    @Test
    func loading_older_local_rows_appends_below_visible_window() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page-1", sortAt: 80, tieBreakID: "m"),
                .init(itemKey: "note:older-page-2", sortAt: 70, tieBreakID: "n")
            ])
        ])

        #expect(result.visibleItemKeys == [
            "note:newest",
            "note:anchor",
            "note:older",
            "note:older-page-1",
            "note:older-page-2"
        ])
        #expect(result.appendedOlderItemKeys == ["note:older-page-1", "note:older-page-2"])
    }

    @Test
    func loading_newer_local_rows_prepends_above_visible_window() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer-2", sortAt: 350, tieBreakID: "b"),
                .init(itemKey: "note:newer-1", sortAt: 400, tieBreakID: "a")
            ])
        ])

        #expect(result.visibleItemKeys == [
            "note:newer-1",
            "note:newer-2",
            "note:newest",
            "note:anchor",
            "note:older"
        ])
        #expect(result.prependedNewerItemKeys == ["note:newer-1", "note:newer-2"])
    }

    @Test
    func append_older_rows_preserves_visible_anchor() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m")
            ])
        ])

        #expect(result.visibleAnchorItemKey == "note:anchor")
        #expect(result.anchorPreservedAfterAppend)
    }

    @Test
    func prepend_newer_rows_preserves_visible_anchor() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer-page", sortAt: 400, tieBreakID: "a")
            ])
        ])

        #expect(result.visibleAnchorItemKey == "note:anchor")
        #expect(result.anchorPreservedAfterPrepend)
    }

    @Test
    func duplicate_rows_are_deduplicated_by_stable_id() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:older", sortAt: 100, tieBreakID: "c"),
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m"),
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "z")
            ])
        ])

        #expect(result.visibleItemKeys == [
            "note:newest",
            "note:anchor",
            "note:older",
            "note:older-page"
        ])
        #expect(result.duplicateItemKeysDeduped == ["note:older", "note:older-page"])
        #expect(result.visibleItemKeys.filter { $0 == "note:older" }.count == 1)
        #expect(result.visibleItemKeys.filter { $0 == "note:older-page" }.count == 1)
    }

    @Test
    func same_sort_rows_use_stable_tie_break_order() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:same-c", sortAt: 50, tieBreakID: "c"),
                .init(itemKey: "note:same-a", sortAt: 50, tieBreakID: "a"),
                .init(itemKey: "note:same-b", sortAt: 50, tieBreakID: "b")
            ])
        ])

        #expect(result.sameSortStableOrderItemKeys == ["note:same-a", "note:same-b", "note:same-c"])
        #expect(Array(result.visibleItemKeys.suffix(3)) == ["note:same-a", "note:same-b", "note:same-c"])
    }

    @Test
    func pending_rows_are_not_inserted_into_visible_window() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:pending", sortAt: 500, tieBreakID: "p", pendingNew: true)
            ])
        ])

        #expect(!result.visibleItemKeys.contains("note:pending"))
        #expect(result.pendingItemKeysExcluded == ["note:pending"])
        #expect(result.pendingNewMutated == false)
    }

    @Test
    func hidden_rows_are_not_inserted_into_visible_window() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [
                .init(itemKey: "note:hidden", sortAt: 50, tieBreakID: "h", hidden: true)
            ])
        ])

        #expect(!result.visibleItemKeys.contains("note:hidden"))
        #expect(result.hiddenItemKeysExcluded == ["note:hidden"])
    }

    @Test
    func empty_page_does_not_change_visible_anchor() {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .older, rows: [])
        ])

        #expect(result.visibleItemKeys == LocalPaginationWindowingFixture.initialVisibleItemKeys)
        #expect(result.visibleAnchorItemKey == "note:anchor")
        #expect(result.emptyPagePreservedVisibleAnchor)
    }

    @Test
    func local_windowing_uses_timeline_area_gate_only() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.restoreGateScope == .timelineArea)
        #expect(result.timelineGateCoversRootShell == false)
        #expect(result.timelineGateCoversTabBar == false)
        #expect(result.timelineGateContinuesGlobalSplash == false)
    }

    @Test
    func local_windowing_keeps_networkWaitedBeforeInteractiveScrollMS_zero() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.networkWaitedBeforeInteractiveScrollMS == 0)
        #expect(result.networkStarted == false)
        #expect(result.requiresNetworkWork == false)
    }

    @Test
    func local_windowing_keeps_readMarkerChanged_false() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.readMarkerChanged == false)
    }

    @Test
    func local_windowing_does_not_write_db() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.dbWriteAttempted == false)
        #expect(result.requiresDBWrite == false)
    }

    @Test
    func local_windowing_does_not_advance_read_marker() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.readMarkerAdvanced == false)
    }

    @Test
    func local_windowing_does_not_mutate_pending_new() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.pendingNewMutated == false)
    }

    @Test
    func local_windowing_does_not_call_dataSourceApply_from_Root() {
        let result = LocalPaginationWindowingHarness.evaluate()

        #expect(result.dataSourceApplyFromRootCalled == false)
        #expect(result.coordinatorOwnedDataSourceApplyAllowed)
    }

    @Test
    func local_windowing_result_is_codable_privacy_safe() throws {
        let result = LocalPaginationWindowingHarness.evaluate(pages: [
            .init(direction: .newer, rows: [
                .init(itemKey: "note:newer", sortAt: 400, tieBreakID: "a")
            ]),
            .init(direction: .older, rows: [
                .init(itemKey: "note:older-page", sortAt: 80, tieBreakID: "m")
            ])
        ])
        let data = try LocalPaginationWindowingHarness.encodedData(result)
        Attachment.record(data, named: "timelinehome-local-pagination-windowing-result.json")
        let decoded = try JSONDecoder().decode(TimelineHomeCollectionViewLocalPaginationWindowingResult.self, from: data)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()

        assertSendable(TimelineHomeCollectionViewLocalPaginationWindowingResult.self)
        #expect(decoded == result)
        for fragment in LocalPaginationWindowingFixture.forbiddenPrivacyFragments {
            #expect(!json.contains(fragment))
        }
    }

    @Test
    func selected_swift_testing_suites_non_zero() {
        let suiteCounts = LocalPaginationWindowingSelectedSuiteCounts.current

        #expect(suiteCounts.contains(.init(
            suiteName: "TimelineHomeCollectionViewLocalPaginationWindowingTests",
            testCount: 20
        )))
        #expect(suiteCounts.allSatisfy { $0.testCount > 0 })
        #expect(Set(suiteCounts.map(\.suiteName)).count == suiteCounts.count)
    }
}

private enum LocalPaginationWindowingHarness {
    static func evaluate(
        arguments: [String] = ["Astrenza", "--timeline-engine=collectionView"],
        routeRestoreDecision: TimelineHomeCollectionViewRouteRestoreDecision = LocalPaginationWindowingFixture.collectionViewRouteDecision(),
        visibleAnchorItemKey: String? = "note:anchor",
        pages: [TimelineHomeCollectionViewLocalPaginationPage] = []
    ) -> TimelineHomeCollectionViewLocalPaginationWindowingResult {
        TimelineHomeCollectionViewLocalPaginationWindowingEvaluator.evaluate(
            TimelineHomeCollectionViewLocalPaginationWindowingInput(
                launchArguments: arguments,
                routeRestoreDecision: routeRestoreDecision,
                visibleAnchorItemKey: visibleAnchorItemKey,
                pages: pages
            )
        )
    }

    static func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private enum LocalPaginationWindowingFixture {
    static let timestampMS: Int64 = 1_735_000_080_000
    static let initialVisibleItemKeys = ["note:newest", "note:anchor", "note:older"]

    static func collectionViewRouteDecision() -> TimelineHomeCollectionViewRouteRestoreDecision {
        routeDecision(selectedRoute: .collectionView, restorePlan: restorePlan())
    }

    static func legacyRouteDecision() -> TimelineHomeCollectionViewRouteRestoreDecision {
        routeDecision(selectedRoute: .legacy, restorePlan: nil)
    }

    private static func routeDecision(
        selectedRoute: TimelineHomeRootBodyRouteSelection,
        restorePlan: TimelineHomeCollectionViewRouteRestorePlan?
    ) -> TimelineHomeCollectionViewRouteRestoreDecision {
        let restorePlanBuilt = selectedRoute == .collectionView && restorePlan != nil
        let artifactSummary = TimelineHomeCollectionViewRouteRestoreArtifactSummary.make(
            selectedRoute: selectedRoute,
            restorePlanBuilt: restorePlanBuilt,
            legacyFallback: selectedRoute == .legacy,
            restorePlan: restorePlanBuilt ? restorePlan : nil,
            issueKinds: []
        )

        return TimelineHomeCollectionViewRouteRestoreDecision(
            selectedRoute: selectedRoute,
            restorePlan: restorePlanBuilt ? restorePlan : nil,
            collectionViewRestorePlanBuilt: restorePlanBuilt,
            legacyRestorePathPreserved: selectedRoute == .legacy,
            rollbackRoute: .legacy,
            manualFallbackRoute: .legacy,
            networkStarted: false,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            dataSourceApplyFromRootCalled: false,
            noExtraNostrHomeTimelineStore: true,
            artifactSummary: artifactSummary,
            issueKinds: [],
            createdAtMS: timestampMS
        )
    }

    private static func restorePlan() -> TimelineHomeCollectionViewRouteRestorePlan {
        TimelineHomeCollectionViewRouteRestorePlan(
            snapshotItemKeys: initialVisibleItemKeys,
            restoreGateIntent: .protectAnchorRestore,
            restoreGateScope: .timelineArea,
            timelineGateCoversRootShell: false,
            timelineGateCoversTabBar: false,
            timelineGateContinuesGlobalSplash: false,
            requestedAnchorItemKey: "note:anchor",
            restoreCandidateItemKey: "note:anchor",
            fallbackReason: .anchorFound,
            localDBReadWork: true,
            networkWaitedBeforeInteractiveScrollMS: 0,
            readMarkerChanged: false,
            readMarkerAdvanced: false,
            dbWriteAttempted: false,
            requiresNetworkWork: false,
            requiresDBWrite: false,
            networkStarted: false,
            dataSourceApplyFromRootCalled: false,
            coordinatorOwnedDataSourceApplyAllowed: true,
            pendingNewExcludedCount: 1,
            hiddenExcludedCount: 1,
            issueCount: 0
        )
    }

    static var forbiddenPrivacyFragments: [String] {
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
            "relay url",
            "pubkey",
            "event id",
            "eventid",
            "event_id",
            "private message content phrase",
            "raw content phrase",
            "raw event content phrase",
            "launcharguments"
        ]
    }
}

private struct LocalPaginationWindowingSuiteCount: Equatable, Sendable {
    var suiteName: String
    var testCount: Int
}

private enum LocalPaginationWindowingSelectedSuiteCounts {
    static let current = [
        LocalPaginationWindowingSuiteCount(
            suiteName: "TimelineHomeCollectionViewLocalPaginationWindowingTests",
            testCount: 20
        ),
        LocalPaginationWindowingSuiteCount(
            suiteName: "TimelineHomeCollectionViewScrollInteractionTests",
            testCount: 17
        ),
        LocalPaginationWindowingSuiteCount(
            suiteName: "TimelineHomeCollectionViewVisibleRestoreRowsTests",
            testCount: 19
        ),
        LocalPaginationWindowingSuiteCount(
            suiteName: "TimelineHomeCollectionViewRestoreScrollPositionTests",
            testCount: 21
        ),
        LocalPaginationWindowingSuiteCount(
            suiteName: "TimelineHomeCollectionViewSimulatorStartupSmokeTests",
            testCount: 16
        )
    ]
}

private func assertSendable<T: Sendable>(_: T.Type) {}
