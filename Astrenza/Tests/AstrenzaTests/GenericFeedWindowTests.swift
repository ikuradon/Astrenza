import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Generic Feed window")
struct GenericFeedWindowTests {
    @Test("older page merge preserves a bounded bidirectional window")
    @MainActor
    func olderPageMergePreservesBoundedBidirectionalWindow() throws {
        let definition = NostrFeedDefinitionRecord(
            feedID: "home/account",
            accountID: "account",
            kind: "home",
            specificationJSON: Data("{}".utf8),
            specificationHash: "specification",
            revision: 4,
            createdAt: 1,
            updatedAt: 1
        )
        let current = feedWindow(
            definition: definition,
            indices: 0..<400,
            gaps: [feedGap(newer: 390, older: 391, state: .unresolved, updatedAt: 1)],
            deletedIndices: [100]
        )
        let loaded = feedWindow(
            definition: definition,
            indices: 320..<560,
            gaps: [
                feedGap(newer: 390, older: 391, state: .requested, updatedAt: 2),
                feedGap(newer: 399, older: 400, state: .unresolved, updatedAt: 2)
            ],
            deletedIndices: [500]
        )
        let store = HomeTimelineStoreFactory.make(eventStore: try NostrEventStore.inMemory())

        let merged = store.testingMergedProjectionWindow(
            current,
            with: loaded,
            centeredOn: eventID(399)
        )

        #expect(merged.memberships.count == 480)
        #expect(merged.events.count == 480)
        #expect(merged.memberships.first?.eventID == eventID(80))
        #expect(merged.memberships.last?.eventID == eventID(559))
        #expect(merged.memberships.contains { $0.eventID == eventID(399) })
        #expect(merged.deletedItems.map(\.targetEventID).sorted() == [eventID(100), eventID(500)])
        #expect(merged.gaps.count == 2)
        #expect(merged.gaps.first { $0.newerEventID == eventID(390) }?.state == .requested)
    }

    private func feedWindow(
        definition: NostrFeedDefinitionRecord,
        indices: Range<Int>,
        gaps: [NostrFeedGapRecord],
        deletedIndices: [Int]
    ) -> NostrFeedWindow {
        let memberships = indices.map { index in
            NostrFeedMembershipRecord(
                feedID: definition.feedID,
                eventID: eventID(index),
                sortTimestamp: 10_000 - index,
                reason: "test",
                insertedAt: 1,
                feedRevision: definition.revision
            )
        }
        let events = indices.map { index in
            NostrEvent(
                id: eventID(index),
                pubkey: String(repeating: "a", count: 64),
                createdAt: 10_000 - index,
                kind: 1,
                tags: [],
                content: "event \(index)",
                sig: String(repeating: "b", count: 128)
            )
        }
        let deletedItems = deletedIndices.map { index in
            NostrDeletedFeedItemRecord(
                feedID: definition.feedID,
                feedRevision: definition.revision,
                targetEventID: eventID(index),
                deletionEventID: "deletion-\(index)",
                deletedAt: 2,
                sortTimestamp: 10_000 - index
            )
        }
        return NostrFeedWindow(
            definition: definition,
            memberships: memberships,
            events: events,
            deletedItems: deletedItems,
            gaps: gaps
        )
    }

    private func feedGap(
        newer: Int,
        older: Int,
        state: NostrFeedGapState,
        updatedAt: Int
    ) -> NostrFeedGapRecord {
        NostrFeedGapRecord(
            feedID: "home/account",
            feedRevision: 4,
            newerEventID: eventID(newer),
            olderEventID: eventID(older),
            state: state,
            createdAt: 1,
            updatedAt: updatedAt
        )
    }

    private func eventID(_ index: Int) -> String {
        String(format: "event-%04d", index)
    }
}
