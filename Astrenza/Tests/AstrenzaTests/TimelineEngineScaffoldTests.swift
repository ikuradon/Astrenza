import Foundation
import Testing
@testable import Astrenza

@Suite("TimelineEngine scaffold")
struct TimelineEngineScaffoldTests {
    @Test("TimelineEntryID identity is stable item key only")
    func timelineEntryIDIdentityIsStableItemKeyOnly() throws {
        let eventID = EventID(hex: String(repeating: "a", count: 64))
        let first = TimelineEntryID(
            rawValue: "home:100:a",
            sourceEventID: eventID,
            sortAt: 100,
            tieBreakID: "a"
        )
        let second = TimelineEntryID(
            rawValue: "home:100:a",
            sourceEventID: EventID(hex: String(repeating: "b", count: 64)),
            sortAt: 200,
            tieBreakID: "b"
        )

        #expect(first == second)
        #expect(Set([first, second]).count == 1)

        let data = try JSONEncoder().encode(first)
        let decoded = try JSONDecoder().decode(TimelineEntryID.self, from: data)

        #expect(decoded.rawValue == first.rawValue)
        #expect(decoded.sourceEventID == eventID)
        #expect(decoded.sortAt == 100)
        #expect(decoded.tieBreakID == "a")
    }

    @Test("TimelineVisualAnchor is stable item key based and codable")
    func timelineVisualAnchorIsStableItemKeyBasedAndCodable() throws {
        let anchor = TimelineVisualAnchor(
            accountID: AccountID(rawValue: "account-a"),
            feedID: FeedID(rawValue: 1),
            timelineKey: TimelineKey(rawValue: "home"),
            anchorItemKey: "home:100:a",
            anchorEventID: EventID(hex: String(repeating: "c", count: 64)),
            anchorSortAt: 100,
            anchorTieBreakID: "a",
            cellTopDeltaFromViewportTop: -12.5,
            viewportHeight: 844,
            viewportWidth: 390,
            contentInsetTop: 0,
            contentInsetBottom: 34,
            lastVisibleTopItemKey: "home:100:a",
            lastVisibleBottomItemKey: "home:096:d",
            markerEventID: nil,
            markerSortAt: nil,
            capturedAtMS: 1_735_000_000_000,
            schemaVersion: 1
        )

        let data = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(TimelineVisualAnchor.self, from: data)

        #expect(decoded == anchor)
    }

    @Test("Snapshot and resolve reasons never advance read marker")
    func snapshotAndResolveReasonsNeverAdvanceReadMarker() throws {
        let reason = TimelineSnapshotReason.reconfigure(.media)

        #expect(!TimelineSnapshotReason.initialRestore.advancesReadMarker)
        #expect(!TimelineSnapshotReason.userInsertedPendingNew.advancesReadMarker)
        #expect(!reason.advancesReadMarker)
        #expect(ResolveApplyReason.media.snapshotReason == reason)

        let data = try JSONEncoder().encode(reason)
        let decoded = try JSONDecoder().decode(TimelineSnapshotReason.self, from: data)

        #expect(decoded == reason)
    }

    @Test("Resolve coordinator produces reconfigure intent for existing IDs only")
    func resolveCoordinatorProducesReconfigureIntentForExistingIDsOnly() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let resolved = [
            TimelineEntryID(rawValue: "home:099:b"),
            TimelineEntryID(rawValue: "home:098:c"),
            TimelineEntryID(rawValue: "home:099:b")
        ]

        let intent = TimelineResolveApplyCoordinator().reconfigureIntent(
            resolvedIDs: resolved,
            existingIDs: existing,
            reason: .profile
        )

        #expect(intent.reason == .profile)
        #expect(intent.mutationStyle == .reconfigure)
        #expect(intent.entryIDs == [TimelineEntryID(rawValue: "home:099:b")])
        #expect(intent.missingIDs == [TimelineEntryID(rawValue: "home:098:c")])
        #expect(intent.insertedIDs.isEmpty)
        #expect(intent.deletedIDs.isEmpty)
    }

    @Test("Position recorder selects anchor by stable ID and viewport delta")
    func positionRecorderSelectsAnchorByStableIDAndViewportDelta() throws {
        let frames = [
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:100:a"), minY: 80, maxY: 150),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:099:b"), minY: 160, maxY: 240),
            TimelineVisibleItemFrame(entryID: TimelineEntryID(rawValue: "home:098:c"), minY: 250, maxY: 320)
        ]

        let selection = try #require(TimelinePositionRecorder.anchorSelection(
            visibleFrames: frames,
            viewportTop: 100
        ))

        #expect(selection.anchorItemKey == "home:100:a")
        #expect(selection.cellTopDeltaFromViewportTop == -20)
        #expect(selection.lastVisibleTopItemKey == "home:100:a")
        #expect(selection.lastVisibleBottomItemKey == "home:098:c")
    }

    @Test("Snapshot coordinator filters reconfigure IDs without mutating item identity")
    func snapshotCoordinatorFiltersReconfigureIDsWithoutMutatingItemIdentity() {
        let existing = [
            TimelineEntryID(rawValue: "home:100:a"),
            TimelineEntryID(rawValue: "home:099:b")
        ]
        let plan = TimelineSnapshotCoordinator.makeMutationPlan(
            currentIDs: existing,
            proposedIDs: existing,
            reconfigureIDs: [
                TimelineEntryID(rawValue: "home:099:b"),
                TimelineEntryID(rawValue: "home:098:c")
            ],
            reason: .reconfigure(.quote)
        )

        #expect(plan.itemIDs == existing)
        #expect(plan.reconfigureIDs == [TimelineEntryID(rawValue: "home:099:b")])
        #expect(plan.insertedIDs.isEmpty)
        #expect(plan.deletedIDs.isEmpty)
    }
}
