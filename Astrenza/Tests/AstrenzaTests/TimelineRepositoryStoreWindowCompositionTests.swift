import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineRepositoryStore window composition")
struct TimelineRepositoryStoreWindowCompositionTests {
    @Test("Core initial window maps to app draft rows and can pass through fixture boundary")
    func coreInitialWindowMapsToAppDraftRowsAndFixtureBoundary() throws {
        let coreWindow = window(
            rows: [
                row(
                    itemKey: "note:\(eventID("a"))",
                    sourceEventID: eventID("a"),
                    subjectEventID: eventID("a"),
                    reason: .author,
                    actorPubkey: pubkey("b"),
                    sortAt: 300,
                    tieBreakID: "a"
                ),
                row(
                    itemKey: "note:\(eventID("c"))",
                    sourceEventID: eventID("c"),
                    subjectEventID: eventID("c"),
                    reason: .author,
                    actorPubkey: pubkey("d"),
                    sortAt: 200,
                    tieBreakID: "c"
                )
            ],
            anchorItemKey: "note:\(eventID("a"))"
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10),
            boundary: FixtureTimelineRepositoryBoundary()
        )

        #expect(composed.initialWindow.feedID == FeedID(rawValue: coreWindow.feedID))
        #expect(composed.initialWindow.visibleItemKeys == coreWindow.rows.map(\.itemKey))
        #expect(composed.initialWindow.visibleRows.map(\.sourceEventID) == [
            EventID(hex: eventID("a")),
            EventID(hex: eventID("c"))
        ])
        #expect(composed.initialWindow.visibleRows.allSatisfy { $0.entryID != nil })
        #expect(composed.initialWindow.anchorItemKey == coreWindow.anchorItemKey)
        #expect(composed.initialWindow.diagnostics.readMarkerChanged == false)
        #expect(composed.initialWindow.diagnostics.requiresNetworkWork == false)
        #expect(composed.initialWindow.diagnostics.requiresDBWork == false)
    }

    @Test("Core read state maps marker and scroll anchor as distinct app draft fields")
    func coreReadStateMapsMarkerAndScrollAnchorDistinctly() throws {
        let coreWindow = window(
            readState: readState(
                markerEventID: eventID("e"),
                markerSortAt: 150,
                scrollAnchorItemKey: "note:\(eventID("a"))",
                scrollAnchorEventID: eventID("a"),
                scrollAnchorSortAt: 300,
                scrollAnchorTieBreakID: "a",
                lastVisibleTopID: "note:\(eventID("6"))",
                lastVisibleBottomID: "note:\(eventID("7"))",
                restoreFallbackReason: "anchorFound"
            ),
            rows: [
                row(
                    itemKey: "note:\(eventID("a"))",
                    sourceEventID: eventID("a"),
                    subjectEventID: eventID("a"),
                    sortAt: 300,
                    tieBreakID: "a"
                )
            ],
            anchorItemKey: "note:\(eventID("a"))"
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        let readState = try #require(composed.readState)
        #expect(readState.markerEventID == EventID(hex: eventID("e")))
        #expect(readState.markerSortAt == 150)
        #expect(readState.scrollAnchorItemKey == "note:\(eventID("a"))")
        #expect(readState.scrollAnchorEventID == EventID(hex: eventID("a")))
        #expect(readState.scrollAnchorEventID != readState.markerEventID)
        #expect(readState.restoreFallbackReason == TimelineRepositoryBoundaryFallbackReason.anchorFound)
        #expect(composed.initialWindow.anchorItemKey == "note:\(eventID("a"))")
    }

    @Test("Missing-target quote and repost rows remain fallback-capable")
    func missingTargetQuoteAndRepostRowsRemainFallbackCapable() throws {
        let coreWindow = window(
            rows: [
                row(
                    itemKey: "quote:\(eventID("4"))",
                    sourceEventID: eventID("4"),
                    subjectEventID: nil,
                    reason: .quote,
                    sortAt: 400,
                    tieBreakID: "4"
                ),
                row(
                    itemKey: "repost:\(eventID("5"))",
                    sourceEventID: eventID("5"),
                    subjectEventID: nil,
                    reason: .repost,
                    sortAt: 300,
                    tieBreakID: "5"
                )
            ],
            anchorItemKey: "quote:\(eventID("4"))"
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(composed.initialWindow.visibleRows.map(\.itemKey) == coreWindow.rows.map(\.itemKey))
        #expect(composed.initialWindow.visibleRows.allSatisfy { $0.isMissingTargetFallbackCapable })
        #expect(composed.initialWindow.visibleRows.allSatisfy { $0.subjectEventID == nil })
    }

    @Test("Hidden pending and collapsed flags are preserved in source-model drafts")
    func hiddenPendingAndCollapsedFlagsArePreserved() throws {
        let coreWindow = window(
            rows: [
                row(
                    itemKey: "note:\(eventID("8"))",
                    sourceEventID: eventID("8"),
                    subjectEventID: eventID("8"),
                    hiddenReason: "muted",
                    collapsed: false,
                    pendingNew: false,
                    sortAt: 300,
                    tieBreakID: "8"
                ),
                row(
                    itemKey: "note:\(eventID("9"))",
                    sourceEventID: eventID("9"),
                    subjectEventID: eventID("9"),
                    collapsed: true,
                    pendingNew: true,
                    sortAt: 200,
                    tieBreakID: "9"
                )
            ],
            anchorItemKey: nil
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .explicitUserPendingNew(itemKeys: ["note:\(eventID("9"))"], maxVisibleCount: 10)
        )

        let drafts = composed.draftRows
        #expect(drafts[0].hiddenReason == "muted")
        #expect(drafts[1].pendingNew == true)
        #expect(drafts[1].collapsed == true)
        #expect(composed.initialWindow.visibleItemKeys == ["note:\(eventID("9"))"])
        #expect(composed.initialWindow.diagnostics.excludedHiddenCount == 1)
        #expect(composed.initialWindow.diagnostics.pendingNewIncludedCount == 1)
    }

    @Test("Core issues map to app diagnostics and remain attached")
    func coreIssuesMapToAppDiagnosticsAndRemainAttached() throws {
        let coreWindow = window(
            rows: [
                row(
                    itemKey: "note:\(eventID("a"))",
                    sourceEventID: eventID("a"),
                    subjectEventID: eventID("a"),
                    sortAt: 100,
                    tieBreakID: "a"
                )
            ],
            anchorItemKey: "note:\(eventID("a"))",
            issues: TimelineRepositoryStoreIssue.Kind.allCases.map {
                TimelineRepositoryStoreIssue(kind: $0, feedID: 10, itemKey: "note:\($0.rawValue)")
            },
            diagnostics: Self.diagnostics(
                totalFeedItemRowCount: 3,
                sqlVisibleRowCount: 1,
                excludedHiddenCount: 1,
                excludedPendingNewCount: 1,
                readStatePresent: true
            )
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(composed.storeIssueDiagnostics.count == TimelineRepositoryStoreIssue.Kind.allCases.count)
        #expect(Set(composed.storeIssueDiagnostics.map { $0.issue.kind.rawValue }) == Set(TimelineRepositoryStoreIssue.Kind.allCases.map(\.rawValue)))
        #expect(composed.compositionDiagnostics.totalFeedItemRowCount == 3)
        #expect(composed.compositionDiagnostics.sqlVisibleRowCount == 1)
        #expect(composed.compositionDiagnostics.excludedHiddenCount == 1)
        #expect(composed.compositionDiagnostics.excludedPendingNewCount == 1)
        #expect(composed.compositionDiagnostics.readMarkerChanged == false)
        #expect(composed.compositionDiagnostics.requiresNetworkWork == false)
        #expect(composed.compositionDiagnostics.requiresDBWork == false)
    }

    @Test("Composition never implies snapshot mutation Home wiring network or read marker advancement")
    func compositionNeverImpliesMutationHomeWiringNetworkOrReadMarkerAdvancement() throws {
        let coreWindow = window(
            rows: [
                row(
                    itemKey: "note:\(eventID("a"))",
                    sourceEventID: eventID("a"),
                    subjectEventID: eventID("a"),
                    sortAt: 100,
                    tieBreakID: "a"
                )
            ],
            anchorItemKey: "note:\(eventID("a"))"
        )

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            coreWindow,
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/AstrenzaApp/TimelineEngine/TimelineRepositoryStoreWindowComposer.swift"),
            encoding: .utf8
        )

        #expect(composed.initialWindow.diagnostics.readMarkerChanged == false)
        #expect(composed.compositionDiagnostics.readMarkerChanged == false)
        #expect(composed.compositionDiagnostics.requiresNetworkWork == false)
        #expect(composed.compositionDiagnostics.requiresDBWork == false)
        #expect(!source.contains("dataSource." + "apply"))
        #expect(!source.contains("delete" + "Items"))
        #expect(!source.contains("insert" + "Items"))
        #expect(!source.contains("Home" + "TimelineView"))
        #expect(!source.contains("URL" + "Session"))
        #expect(!source.contains("Web" + "Socket"))
        #expect(!source.contains("Resolve" + "Coordinator"))
    }

    @Test("Composition models are Codable Equatable and Sendable")
    func compositionModelsAreCodableEquatableAndSendable() throws {
        assertSendable(TimelineRepositoryStoreWindowComposition.self)
        assertSendable(TimelineRepositoryStoreWindowCompositionDiagnostics.self)
        assertSendable(TimelineRepositoryStoreWindowCompositionIssue.self)
        assertSendable(TimelineRepositoryStoreWindowCompositionError.self)

        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            window(
                rows: [
                    row(
                        itemKey: "note:\(eventID("a"))",
                        sourceEventID: eventID("a"),
                        subjectEventID: eventID("a"),
                        sortAt: 100,
                        tieBreakID: "a"
                    )
                ],
                anchorItemKey: "note:\(eventID("a"))"
            ),
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        let data = try JSONEncoder().encode(composed)
        let decoded = try JSONDecoder().decode(TimelineRepositoryStoreWindowComposition.self, from: data)
        #expect(decoded == composed)
    }

    @Test("Invalid event pubkey and fallback values throw typed composition issues")
    func invalidCoreValuesThrowTypedCompositionIssues() throws {
        #expect(throws: TimelineRepositoryStoreWindowCompositionError.self) {
            try TimelineRepositoryStoreWindowComposer.compose(
                window(
                    rows: [
                        row(
                            itemKey: "note:invalid-event-id",
                            sourceEventID: "invalid",
                            sortAt: 100,
                            tieBreakID: "a"
                        )
                    ],
                    anchorItemKey: nil
                ),
                accountID: .debug,
                timelineKey: .home,
                policy: .initialRestore(maxVisibleCount: 10)
            )
        }

        #expect(throws: TimelineRepositoryStoreWindowCompositionError.self) {
            try TimelineRepositoryStoreWindowComposer.compose(
                window(
                    readState: readState(restoreFallbackReason: "not-supported"),
                    rows: [],
                    anchorItemKey: nil
                ),
                accountID: .debug,
                timelineKey: .home,
                policy: .initialRestore(maxVisibleCount: 10)
            )
        }

        #expect(throws: TimelineRepositoryStoreWindowCompositionError.self) {
            try TimelineRepositoryStoreWindowComposer.compose(
                window(
                    rows: [
                        row(
                            itemKey: "note:\(eventID("a"))",
                            sourceEventID: eventID("a"),
                            actorPubkey: "invalid-pubkey",
                            sortAt: 100,
                            tieBreakID: "a"
                        )
                    ],
                    anchorItemKey: nil
                ),
                accountID: .debug,
                timelineKey: .home,
                policy: .initialRestore(maxVisibleCount: 10)
            )
        }
    }

    @Test("All current Core issue kinds have composition diagnostics coverage")
    func allCurrentCoreIssueKindsHaveCompositionDiagnosticsCoverage() throws {
        let composed = try TimelineRepositoryStoreWindowComposer.compose(
            window(
                issues: TimelineRepositoryStoreIssue.Kind.allCases.map {
                    TimelineRepositoryStoreIssue(kind: $0, feedID: 10, itemKey: "note:\($0.rawValue)")
                }
            ),
            accountID: .debug,
            timelineKey: .home,
            policy: .initialRestore(maxVisibleCount: 10)
        )

        #expect(Set(composed.storeIssueDiagnostics.map { $0.issue.kind.rawValue }) == Set(TimelineRepositoryStoreIssue.Kind.allCases.map(\.rawValue)))
    }

    private func window(
        readState: TimelineRepositoryReadStateRow? = nil,
        rows: [TimelineRepositoryFeedItemRow] = [],
        anchorItemKey: String? = nil,
        issues: [TimelineRepositoryStoreIssue] = [],
        diagnostics: TimelineRepositoryStoreDiagnostics = Self.diagnostics()
    ) -> TimelineRepositoryInitialWindow {
        TimelineRepositoryInitialWindow(
            feedID: 10,
            rows: rows,
            readState: readState,
            anchorItemKey: anchorItemKey,
            issues: issues,
            diagnostics: diagnostics
        )
    }

    private func row(
        itemKey: String,
        sourceEventID: String,
        subjectEventID: String? = nil,
        reason: AstrenzaCore.TimelineRepositoryFeedItemReason = .author,
        actorPubkey: String? = nil,
        hiddenReason: String? = nil,
        collapsed: Bool = false,
        pendingNew: Bool = false,
        sortAt: Int64,
        tieBreakID: String
    ) -> TimelineRepositoryFeedItemRow {
        TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: itemKey,
            sourceEventID: sourceEventID,
            subjectEventID: subjectEventID,
            reason: reason,
            actorPubkey: actorPubkey,
            sortAt: sortAt,
            tieBreakID: tieBreakID,
            hiddenReason: hiddenReason,
            collapsed: collapsed,
            pendingNew: pendingNew,
            insertedAtMS: 1,
            updatedAtMS: 2
        )
    }

    private func readState(
        markerEventID: String? = nil,
        markerSortAt: Int64? = nil,
        scrollAnchorItemKey: String? = nil,
        scrollAnchorEventID: String? = nil,
        scrollAnchorSortAt: Int64? = nil,
        scrollAnchorTieBreakID: String? = nil,
        lastVisibleTopID: String? = nil,
        lastVisibleBottomID: String? = nil,
        restoreFallbackReason: String? = nil
    ) -> TimelineRepositoryReadStateRow {
        TimelineRepositoryReadStateRow(
            databaseAccountID: 1,
            feedID: 10,
            markerSortAt: markerSortAt,
            markerEventID: markerEventID,
            scrollAnchorItemKey: scrollAnchorItemKey,
            scrollAnchorEventID: scrollAnchorEventID,
            scrollAnchorSortAt: scrollAnchorSortAt,
            scrollAnchorTieBreakID: scrollAnchorTieBreakID,
            scrollAnchorOffsetPX: 12,
            viewportHeightPX: 640,
            viewportWidthPX: 390,
            contentInsetTopPX: 8,
            contentInsetBottomPX: 16,
            lastVisibleTopID: lastVisibleTopID,
            lastVisibleBottomID: lastVisibleBottomID,
            restoreFallbackReason: restoreFallbackReason,
            clientStateJSON: "{}",
            lastViewedAtMS: 1000,
            updatedAtMS: 2000
        )
    }

    private static func diagnostics(
        totalFeedItemRowCount: Int = 0,
        sqlVisibleRowCount: Int = 0,
        excludedHiddenCount: Int = 0,
        excludedPendingNewCount: Int = 0,
        pendingNewIncludedCount: Int = 0,
        readStatePresent: Bool = false
    ) -> TimelineRepositoryStoreDiagnostics {
        TimelineRepositoryStoreDiagnostics(
            totalFeedItemRowCount: totalFeedItemRowCount,
            sqlVisibleRowCount: sqlVisibleRowCount,
            excludedHiddenCount: excludedHiddenCount,
            excludedPendingNewCount: excludedPendingNewCount,
            pendingNewIncludedCount: pendingNewIncludedCount,
            readStatePresent: readStatePresent,
            readMarkerChanged: false,
            requiresNetworkWork: false,
            requiresExternalMutation: false,
            performedLocalDBRead: true,
            resolveJobRowCount: 0,
            diagnosticRowCount: 0
        )
    }

    private func eventID(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }

    private func pubkey(_ seed: Character) -> String {
        String(repeating: String(seed), count: 64)
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
