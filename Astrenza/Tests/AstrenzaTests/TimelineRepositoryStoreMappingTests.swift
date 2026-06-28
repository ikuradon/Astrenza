import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("TimelineRepositoryStore mapping")
struct TimelineRepositoryStoreMappingTests {
    @Test("Core feed item row maps to app TimelineRepositoryFeedItemDraftRow without Core importing app types")
    func coreFeedItemRowMapsToAppDraftRow() throws {
        let row = TimelineRepositoryFeedItemRow(
            feedID: 10,
            itemKey: "quote:\(eventID("a"))",
            sourceEventID: eventID("a"),
            subjectEventID: nil,
            reason: .quote,
            actorPubkey: pubkey("b"),
            sortAt: 123,
            tieBreakID: "a",
            hiddenReason: nil,
            collapsed: true,
            pendingNew: false,
            insertedAtMS: 1,
            updatedAtMS: 2
        )

        let draft = try TimelineRepositoryStoreDraftMapper.feedItemDraft(from: row)

        #expect(draft.itemKey == row.itemKey)
        #expect(draft.sourceEventID == EventID(hex: row.sourceEventID))
        #expect(draft.subjectEventID == nil)
        #expect(draft.reason == .quote)
        #expect(draft.actorPubkey == row.actorPubkey)
        #expect(draft.sortAt == row.sortAt)
        #expect(draft.tieBreakID == row.tieBreakID)
        #expect(draft.collapsed == true)
        #expect(draft.pendingNew == false)
        #expect(draft.isMissingTargetFallbackCapable == true)
    }

    @Test("Core read state row maps to app TimelineReadStateDraft while marker and anchor stay distinct")
    func coreReadStateRowMapsToAppReadStateDraft() throws {
        let row = TimelineRepositoryReadStateRow(
            databaseAccountID: 1,
            feedID: 10,
            markerSortAt: 100,
            markerEventID: eventID("c"),
            scrollAnchorItemKey: "note:\(eventID("a"))",
            scrollAnchorEventID: eventID("a"),
            scrollAnchorSortAt: 200,
            scrollAnchorTieBreakID: "a",
            scrollAnchorOffsetPX: 12,
            viewportHeightPX: 640,
            viewportWidthPX: 390,
            contentInsetTopPX: 8,
            contentInsetBottomPX: 16,
            lastVisibleTopID: "note:\(eventID("d"))",
            lastVisibleBottomID: "note:\(eventID("e"))",
            restoreFallbackReason: "anchorFound",
            clientStateJSON: "{}",
            lastViewedAtMS: 10,
            updatedAtMS: 20
        )

        let draft = TimelineRepositoryStoreDraftMapper.readStateDraft(
            from: row,
            accountID: AccountID(rawValue: "account"),
            timelineKey: .home
        )

        #expect(draft.accountID == AccountID(rawValue: "account"))
        #expect(draft.feedID == FeedID(rawValue: 10))
        #expect(draft.timelineKey == .home)
        #expect(draft.scrollAnchorItemKey == row.scrollAnchorItemKey)
        #expect(draft.scrollAnchorEventID == EventID(hex: eventID("a")))
        #expect(draft.markerEventID == EventID(hex: eventID("c")))
        #expect(draft.markerSortAt == 100)
        #expect(draft.scrollAnchorEventID != draft.markerEventID)
        #expect(draft.savedAtMS == 20)
    }
}

private enum TimelineRepositoryStoreDraftMapper {
    private typealias AppFeedItemReason = Astrenza.TimelineRepositoryFeedItemReason

    static func feedItemDraft(
        from row: TimelineRepositoryFeedItemRow
    ) throws -> TimelineRepositoryFeedItemDraftRow {
        guard let reason = AppFeedItemReason(rawValue: row.reason.rawValue) else {
            throw MappingError.unsupportedReason
        }

        return TimelineRepositoryFeedItemDraftRow(
            itemKey: row.itemKey,
            sourceEventID: EventID(hex: row.sourceEventID),
            subjectEventID: row.subjectEventID.map(EventID.init(hex:)),
            reason: reason,
            actorPubkey: row.actorPubkey,
            sortAt: row.sortAt,
            tieBreakID: row.tieBreakID,
            hiddenReason: row.hiddenReason,
            collapsed: row.collapsed,
            pendingNew: row.pendingNew,
            isMissingTargetFallbackCapable: row.reason == .repost || row.reason == .quote
        )
    }

    static func readStateDraft(
        from row: TimelineRepositoryReadStateRow,
        accountID: AccountID,
        timelineKey: TimelineKey
    ) -> TimelineReadStateDraft {
        TimelineReadStateDraft(
            accountID: accountID,
            feedID: FeedID(rawValue: row.feedID),
            timelineKey: timelineKey,
            scrollAnchorItemKey: row.scrollAnchorItemKey,
            scrollAnchorEventID: row.scrollAnchorEventID.map(EventID.init(hex:)),
            scrollAnchorSortAt: row.scrollAnchorSortAt,
            scrollAnchorTieBreakID: row.scrollAnchorTieBreakID,
            scrollAnchorOffsetPX: row.scrollAnchorOffsetPX,
            viewportHeightPX: row.viewportHeightPX,
            viewportWidthPX: row.viewportWidthPX,
            contentInsetTopPX: row.contentInsetTopPX,
            contentInsetBottomPX: row.contentInsetBottomPX,
            markerEventID: row.markerEventID.map(EventID.init(hex:)),
            markerSortAt: row.markerSortAt,
            lastVisibleTopItemKey: row.lastVisibleTopID,
            lastVisibleBottomItemKey: row.lastVisibleBottomID,
            restoreFallbackReason: row.restoreFallbackReason.flatMap(TimelineRepositoryBoundaryFallbackReason.init(rawValue:)),
            savedAtMS: row.updatedAtMS,
            schemaVersion: 2
        )
    }
}

private enum MappingError: Error {
    case unsupportedReason
}

private func eventID(_ seed: Character) -> String {
    String(repeating: String(seed), count: 64)
}

private func pubkey(_ seed: Character) -> String {
    String(repeating: String(seed), count: 64)
}
