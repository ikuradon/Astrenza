import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline read state coordinator")
struct HomeTimelineReadStateCoordinatorTests {
    @Test("Viewport and read boundary writes coalesce independently")
    @MainActor
    func writesCoalesceIndependently() async throws {
        let fixture = try fixture(delayNanoseconds: 80_000_000)
        let firstBoundary = NostrTimelineEntryCursor(sortTimestamp: 90, eventID: "first")
        let latestBoundary = NostrTimelineEntryCursor(sortTimestamp: 95, eventID: "latest")

        #expect(fixture.coordinator.scheduleViewportState(
            viewport(accountID: fixture.accountID, anchor: "first", updatedAt: 100),
            feedID: fixture.feedID,
            scopeID: fixture.accountID
        ))
        #expect(fixture.coordinator.scheduleViewportState(
            viewport(accountID: fixture.accountID, anchor: "latest", updatedAt: 101),
            feedID: fixture.feedID,
            scopeID: fixture.accountID
        ))
        #expect(fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: firstBoundary, updatedAt: 102)
        ))
        #expect(fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: latestBoundary, updatedAt: 103)
        ))

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(try fixture.eventStore.feedReadState(feedID: fixture.feedID) == nil)
        try await waitUntil {
            guard let state = try? fixture.eventStore.feedReadState(feedID: fixture.feedID) else {
                return false
            }
            return state.viewportAnchorEventID == "latest" && state.readBoundary == latestBoundary
        }

        #expect(!fixture.coordinator.hasPendingViewportWrite)
        #expect(!fixture.coordinator.hasPendingReadBoundaryWrite)
    }

    @Test("Ending an account scope flushes the latest viewport and current read boundary")
    @MainActor
    func endingScopeFlushesLatestState() async throws {
        let fixture = try fixture(delayNanoseconds: 5_000_000_000)
        let pendingBoundary = NostrTimelineEntryCursor(sortTimestamp: 90, eventID: "pending")
        let currentBoundary = NostrTimelineEntryCursor(sortTimestamp: 100, eventID: "current")

        fixture.coordinator.scheduleViewportState(
            viewport(accountID: fixture.accountID, anchor: "session-end", updatedAt: 200),
            feedID: fixture.feedID,
            scopeID: fixture.accountID
        )
        fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: pendingBoundary, updatedAt: 201)
        )
        fixture.coordinator.endSession(flushing: readWrite(
            fixture: fixture,
            boundary: currentBoundary,
            updatedAt: 202
        ))

        #expect(!fixture.coordinator.hasPendingViewportWrite)
        #expect(!fixture.coordinator.hasPendingReadBoundaryWrite)
        try await waitUntil {
            guard let state = try? fixture.eventStore.feedReadState(feedID: fixture.feedID) else {
                return false
            }
            return state.viewportAnchorEventID == "session-end" &&
                state.readBoundary == currentBoundary
        }
    }

    @Test("Restoration maps persisted viewport and missing boundary cursors")
    @MainActor
    func restorationMapsPersistedState() async throws {
        let fixture = try fixture(delayNanoseconds: 0)
        try fixture.eventStore.saveFeedViewportState(
            feedID: fixture.feedID,
            viewportAnchorEventID: "anchor",
            viewportAnchorOffset: 24,
            updatedAt: 300
        )
        try fixture.eventStore.saveFeedReadBoundary(
            feedID: fixture.feedID,
            readBoundary: NostrTimelineEntryCursor(sortTimestamp: 250, eventID: "middle"),
            updatedAt: 301
        )

        let viewport = try #require(fixture.coordinator.restoredViewportState(
            accountID: fixture.accountID,
            timelineKey: "home"
        ))
        #expect(viewport.anchorPostID == "anchor")
        #expect(viewport.anchorOffset == 24)
        #expect(fixture.coordinator.restoredViewportState(
            accountID: fixture.accountID,
            timelineKey: "lists"
        ) == nil)

        let fallbackBoundary = await fixture.coordinator.restoredReadBoundaryPostID(
            feedID: fixture.feedID,
            positions: [
                HomeTimelineReadPosition(postID: "newer", createdAt: 300),
                HomeTimelineReadPosition(postID: "z-middle", createdAt: 250),
                HomeTimelineReadPosition(postID: "older", createdAt: 200)
            ]
        )
        #expect(fallbackBoundary == "z-middle")
    }

    @MainActor
    private func fixture(delayNanoseconds: UInt64) throws -> ReadStateFixture {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a", count: 64)
        let feedID = HomeFeedProjectionBuilder.feedID(accountID: accountID)
        try eventStore.saveFeedDefinition(NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "read-state-coordinator",
            revision: 1,
            createdAt: 1,
            updatedAt: 1
        ))
        let worker = HomeTimelinePersistenceWorker(eventStore: eventStore)
        return ReadStateFixture(
            accountID: accountID,
            feedID: feedID,
            eventStore: eventStore,
            coordinator: HomeTimelineReadStateCoordinator(
                eventStore: eventStore,
                persistenceWorker: worker,
                viewportDelayNanoseconds: delayNanoseconds,
                readBoundaryDelayNanoseconds: delayNanoseconds
            )
        )
    }

    private func viewport(
        accountID: String,
        anchor: String,
        updatedAt: TimeInterval
    ) -> TimelineViewportState {
        TimelineViewportState(
            accountID: accountID,
            timelineKey: "home",
            anchorPostID: anchor,
            anchorOffset: 18,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    private func readWrite(
        fixture: ReadStateFixture,
        boundary: NostrTimelineEntryCursor?,
        updatedAt: Int
    ) -> HomeTimelineReadBoundaryWrite {
        HomeTimelineReadBoundaryWrite(
            scopeID: fixture.accountID,
            feedID: fixture.feedID,
            boundary: boundary,
            updatedAt: updatedAt
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw HomeTimelineReadStateCoordinatorTestError.timeout
    }
}

@MainActor
private struct ReadStateFixture {
    let accountID: String
    let feedID: String
    let eventStore: NostrEventStore
    let coordinator: HomeTimelineReadStateCoordinator
}

private enum HomeTimelineReadStateCoordinatorTestError: Error {
    case timeout
}
