import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline read state coordinator")
struct HomeTimelineReadStateCoordinatorTests {
    @Test("Read boundary writes coalesce to the latest cursor")
    @MainActor
    func readBoundaryWritesCoalesce() async throws {
        let fixture = try fixture(delayNanoseconds: 80_000_000)
        let firstBoundary = NostrTimelineEntryCursor(sortTimestamp: 90, eventID: "first")
        let latestBoundary = NostrTimelineEntryCursor(sortTimestamp: 95, eventID: "latest")

        #expect(fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: firstBoundary, updatedAt: 100)
        ))
        #expect(fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: latestBoundary, updatedAt: 101)
        ))

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(try fixture.eventStore.feedReadState(feedID: fixture.feedID) == nil)
        try await waitUntil {
            guard let state = try? fixture.eventStore.feedReadState(feedID: fixture.feedID) else {
                return false
            }
            return state.readBoundary == latestBoundary
        }

        #expect(!fixture.coordinator.hasPendingReadBoundaryWrite)
    }

    @Test("Ending an account scope flushes the current read boundary")
    @MainActor
    func endingScopeFlushesCurrentBoundary() async throws {
        let fixture = try fixture(delayNanoseconds: 5_000_000_000)
        let pendingBoundary = NostrTimelineEntryCursor(sortTimestamp: 90, eventID: "pending")
        let currentBoundary = NostrTimelineEntryCursor(sortTimestamp: 100, eventID: "current")

        fixture.coordinator.scheduleReadBoundarySave(
            readWrite(fixture: fixture, boundary: pendingBoundary, updatedAt: 201)
        )
        fixture.coordinator.endSession(flushing: readWrite(
            fixture: fixture,
            boundary: currentBoundary,
            updatedAt: 202
        ))

        #expect(!fixture.coordinator.hasPendingReadBoundaryWrite)
        try await waitUntil {
            guard let state = try? fixture.eventStore.feedReadState(feedID: fixture.feedID) else {
                return false
            }
            return state.readBoundary == currentBoundary
        }
    }

    @Test("Restoration maps a missing boundary cursor to the visible timeline")
    @MainActor
    func restorationMapsPersistedBoundary() async throws {
        let fixture = try fixture(delayNanoseconds: 0)
        try fixture.eventStore.saveFeedReadBoundary(
            feedID: fixture.feedID,
            readBoundary: NostrTimelineEntryCursor(sortTimestamp: 250, eventID: "middle"),
            updatedAt: 301
        )

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
    private func fixture(
        delayNanoseconds: UInt64
    ) throws -> ReadStateFixture {
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
                persistenceWorker: worker,
                readBoundaryDelayNanoseconds: delayNanoseconds
            )
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
        throw ReadStateCoordinatorTestError.timeout
    }
}

@MainActor
private struct ReadStateFixture {
    let accountID: String
    let feedID: String
    let eventStore: NostrEventStore
    let coordinator: HomeTimelineReadStateCoordinator
}

private enum ReadStateCoordinatorTestError: Error {
    case timeout
}
