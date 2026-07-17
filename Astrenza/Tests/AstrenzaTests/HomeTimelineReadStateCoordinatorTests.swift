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

        let fallbackBoundary = await fixture.coordinator.restoredReadBoundary(
            feedID: fixture.feedID,
            positions: [
                HomeTimelineReadPosition(postID: "newer", createdAt: 300),
                HomeTimelineReadPosition(postID: "z-middle", createdAt: 250),
                HomeTimelineReadPosition(postID: "older", createdAt: 200)
            ]
        )
        #expect(fallbackBoundary == .resolved(postID: "z-middle"))
    }

    @Test("A persisted cursor older than the projection remains distinguishable")
    @MainActor
    func restorationReportsBoundaryOlderThanProjection() async throws {
        let fixture = try fixture(delayNanoseconds: 0)
        try fixture.eventStore.saveFeedReadBoundary(
            feedID: fixture.feedID,
            readBoundary: NostrTimelineEntryCursor(
                sortTimestamp: 100,
                eventID: "persisted-old"
            ),
            updatedAt: 302
        )

        let outcome = await fixture.coordinator.restoredReadBoundary(
            feedID: fixture.feedID,
            positions: [
                HomeTimelineReadPosition(postID: "new", createdAt: 300),
                HomeTimelineReadPosition(postID: "middle", createdAt: 200)
            ]
        )

        #expect(outcome == .olderThanProjection)
    }

    @Test("A failed boundary write stays pending and retries until it is durable")
    @MainActor
    func failedBoundaryWriteRetries() async throws {
        let persistence = FlakyReadStatePersistence(failuresBeforeSuccess: 1)
        let coordinator = HomeTimelineReadStateCoordinator(
            persistenceWorker: persistence,
            readBoundaryDelayNanoseconds: 0,
            persistenceRetryDelayNanoseconds: 100_000_000
        )
        let boundary = NostrTimelineEntryCursor(
            sortTimestamp: 400,
            eventID: "durable"
        )
        let write = HomeTimelineReadBoundaryWrite(
            scopeID: "account",
            feedID: "feed",
            boundary: boundary,
            updatedAt: 401
        )

        #expect(coordinator.scheduleReadBoundarySave(write))
        try await waitUntil {
            await persistence.attemptCount() == 1
        }
        #expect(coordinator.hasPendingReadBoundaryWrite)

        try await waitUntil {
            await persistence.savedBoundaries() == [boundary]
        }
        #expect(!coordinator.hasPendingReadBoundaryWrite)
        #expect(await persistence.attemptCount() == 2)
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
        _ predicate: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ReadStateCoordinatorTestError.timeout
    }
}

@Suite("Home timeline read boundary interaction workflow")
@MainActor
struct HomeReadBoundaryInteractionWorkflowTests {
    @Test("Active feed maps visible positions and events to read-state operations")
    func activeFeedMapsReadStateOperations() async throws {
        let accountID = String(repeating: "a", count: 64)
        let feedID = HomeFeedProjectionBuilder.feedID(accountID: accountID)
        let feedIdentity = ReadBoundaryFeedIdentitySpy(
            accountID: accountID,
            feedID: feedID
        )
        let readState = ReadBoundaryStateSpy(
            restoredResult: .resolved(postID: "boundary")
        )
        let workflow = HomeReadBoundaryInteractionWorkflow(
            feedIdentity: feedIdentity,
            readState: readState,
            timestamp: { 321 }
        )
        let positions = [
            HomeTimelineReadPosition(postID: "boundary", createdAt: 100)
        ]
        let event = boundaryEvent(accountID: accountID)

        #expect(await workflow.restoredReadBoundary(
            accountID: accountID,
            positions: positions
        ) == .resolved(postID: "boundary"))
        #expect(workflow.scheduleReadBoundarySave(
            accountID: accountID,
            boundaryEvent: event
        ))

        #expect(readState.restoredFeedID == feedID)
        #expect(readState.restoredPositions == positions)
        let write = try #require(readState.scheduledWrite)
        #expect(write.scopeID == accountID)
        #expect(write.feedID == feedID)
        #expect(write.boundary == NostrTimelineEntryCursor(
            sortTimestamp: event.createdAt,
            eventID: event.id
        ))
        #expect(write.updatedAt == 321)
    }

    @Test("Missing active feed prevents read-state restoration and writes")
    func missingActiveFeedPreventsReadStateOperations() async {
        let readState = ReadBoundaryStateSpy(
            restoredResult: .resolved(postID: "unexpected")
        )
        let workflow = HomeReadBoundaryInteractionWorkflow(
            feedIdentity: ReadBoundaryFeedIdentitySpy(
                accountID: "active",
                feedID: "feed"
            ),
            readState: readState,
            timestamp: { 321 }
        )

        #expect(await workflow.restoredReadBoundary(
            accountID: "inactive",
            positions: []
        ) == .missing)
        #expect(!workflow.scheduleReadBoundarySave(
            accountID: "inactive",
            boundaryEvent: nil
        ))
        #expect(readState.restoredCallCount == 0)
        #expect(readState.scheduledWrite == nil)
    }

    private func boundaryEvent(accountID: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: accountID,
            createdAt: 123,
            kind: 1,
            tags: [],
            content: "boundary",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private final class ReadBoundaryFeedIdentitySpy: HomeFeedIdentityResolving {
    private let accountID: String
    private let feedID: String

    init(accountID: String, feedID: String) {
        self.accountID = accountID
        self.feedID = feedID
    }

    func feedID(accountID: String) -> String? {
        accountID == self.accountID ? feedID : nil
    }
}

@MainActor
private final class ReadBoundaryStateSpy: HomeTimelineReadStateCoordinating {
    private let restoredResult: HomeTimelineReadBoundaryRestoreOutcome
    private(set) var restoredFeedID: String?
    private(set) var restoredPositions: [HomeTimelineReadPosition] = []
    private(set) var restoredCallCount = 0
    private(set) var scheduledWrite: HomeTimelineReadBoundaryWrite?

    init(restoredResult: HomeTimelineReadBoundaryRestoreOutcome) {
        self.restoredResult = restoredResult
    }

    func restoredReadBoundary(
        feedID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> HomeTimelineReadBoundaryRestoreOutcome {
        restoredFeedID = feedID
        restoredPositions = positions
        restoredCallCount += 1
        return restoredResult
    }

    func scheduleReadBoundarySave(
        _ write: HomeTimelineReadBoundaryWrite
    ) -> Bool {
        scheduledWrite = write
        return true
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

private actor FlakyReadStatePersistence: HomeTimelineReadStatePersisting {
    private var remainingFailures: Int
    private var attempts = 0
    private var boundaries: [NostrTimelineEntryCursor?] = []

    init(failuresBeforeSuccess: Int) {
        remainingFailures = failuresBeforeSuccess
    }

    func restoredReadState(feedID _: String) throws -> NostrFeedReadStateRecord? {
        nil
    }

    func saveReadBoundary(
        feedID _: String,
        boundary: NostrTimelineEntryCursor?,
        updatedAt _: Int
    ) throws {
        attempts += 1
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw FlakyReadStatePersistenceError.failed
        }
        boundaries.append(boundary)
    }

    func attemptCount() -> Int {
        attempts
    }

    func savedBoundaries() -> [NostrTimelineEntryCursor?] {
        boundaries
    }
}

private enum FlakyReadStatePersistenceError: Error {
    case failed
}
