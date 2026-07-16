import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store read boundary coordinator")
@MainActor
struct HomeStoreReadBoundaryCoordinatorTests {
    @Test("Restore projects post positions and applies the resolved boundary")
    func restoresReadBoundary() async throws {
        let fixture = StoreReadBoundaryFixture()
        let posts = Array(MockTimelineData.posts.prefix(2))
        let expectedPositions = posts.map {
            HomeTimelineReadPosition(postID: $0.id, createdAt: $0.createdAt)
        }
        fixture.target.entries = [
            .deleted(TimelineDeletedEntry(id: "deleted")),
            .post(posts[0]),
            .post(posts[1])
        ]
        fixture.interaction.restoredBoundaryID = posts[1].id

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(didRestore)
        #expect(fixture.interaction.events == [
            .restore(fixture.account.pubkey, expectedPositions)
        ])
        #expect(fixture.target.appliedBoundaryIDs == [posts[1].id])
    }

    @Test("A missing restored boundary leaves presentation unchanged")
    func ignoresMissingBoundary() async {
        let fixture = StoreReadBoundaryFixture()
        fixture.target.entries = MockTimelineData.posts.prefix(1).map {
            .post($0)
        }

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(!didRestore)
        #expect(fixture.target.appliedBoundaryIDs.isEmpty)
    }

    @Test("An account switch during restore rejects the stale boundary")
    func rejectsStaleAccount() async {
        let fixture = StoreReadBoundaryFixture()
        fixture.interaction.restoredBoundaryID = "boundary"
        fixture.interaction.onRestore = {
            fixture.target.account = fixture.replacementAccount
        }

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(!didRestore)
        #expect(fixture.target.appliedBoundaryIDs.isEmpty)
    }

    @Test("Cancellation after read-state I/O rejects the restored boundary")
    func rejectsCancelledRestore() async {
        let fixture = StoreReadBoundaryFixture()
        fixture.interaction.restoredBoundaryID = "boundary"
        fixture.interaction.cancelRestoreTask = true

        let didRestore = await Task { @MainActor in
            await fixture.coordinator.restore(account: fixture.account)
        }.value

        #expect(!didRestore)
        #expect(fixture.target.appliedBoundaryIDs.isEmpty)
    }

    @Test("Save and session flush share the current boundary event")
    func projectsCurrentBoundaryEvent() throws {
        let fixture = StoreReadBoundaryFixture()
        let event = StoreReadBoundaryFixture.makeEvent(
            id: "1",
            pubkey: fixture.account.pubkey
        )
        let expectedWrite = HomeTimelineReadBoundaryWrite(
            scopeID: fixture.account.pubkey,
            feedID: "feed:home",
            boundary: NostrTimelineEntryCursor(
                sortTimestamp: event.createdAt,
                eventID: event.id
            ),
            updatedAt: 200
        )
        fixture.target.currentReadBoundaryPostID = event.id
        fixture.target.timelineEvents[event.id] = event
        fixture.interaction.scheduleResult = true
        fixture.interaction.boundaryWriteResult = expectedWrite

        let didSchedule = fixture.coordinator.scheduleSave()
        let write = try #require(fixture.coordinator.boundaryWrite())

        #expect(didSchedule)
        #expect(fixture.interaction.events == [
            .schedule(fixture.account.pubkey, event.id),
            .write(fixture.account.pubkey, event.id)
        ])
        #expect(fixture.target.lookedUpEventIDs == [event.id, event.id])
        #expect(write.scopeID == expectedWrite.scopeID)
        #expect(write.feedID == expectedWrite.feedID)
        #expect(write.boundary == expectedWrite.boundary)
        #expect(write.updatedAt == expectedWrite.updatedAt)
    }

    @Test("The coordinator does not retain its Store target")
    func doesNotRetainTarget() async {
        let account = StoreReadBoundaryFixture.makeAccount(
            pubkeyCharacter: "a"
        )
        let interaction = StoreReadBoundaryInteractionSpy()
        var target: StoreReadBoundaryTargetSpy? =
            StoreReadBoundaryTargetSpy(account: account)
        weak let weakTarget = target
        let coordinator = HomeStoreReadBoundaryCoordinator(
            interaction: interaction
        )
        if let target {
            coordinator.bind(target: target)
        }

        target = nil

        #expect(weakTarget == nil)
        #expect(!coordinator.scheduleSave())
        #expect(coordinator.boundaryWrite() == nil)
        let didRestore = await coordinator.restore(account: account)
        #expect(!didRestore)
        #expect(interaction.events.isEmpty)
    }
}

@MainActor
private struct StoreReadBoundaryFixture {
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let target: StoreReadBoundaryTargetSpy
    let interaction: StoreReadBoundaryInteractionSpy
    let coordinator: HomeStoreReadBoundaryCoordinator

    init() {
        let account = Self.makeAccount(pubkeyCharacter: "a")
        let target = StoreReadBoundaryTargetSpy(account: account)
        let interaction = StoreReadBoundaryInteractionSpy()
        self.account = account
        replacementAccount = Self.makeAccount(pubkeyCharacter: "b")
        self.target = target
        self.interaction = interaction
        let coordinator = HomeStoreReadBoundaryCoordinator(
            interaction: interaction
        )
        coordinator.bind(target: target)
        self.coordinator = coordinator
    }

    static func makeAccount(pubkeyCharacter: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: pubkeyCharacter, count: 64),
            displayIdentifier: "read-boundary",
            readOnly: true
        )
    }

    static func makeEvent(id: Character, pubkey: String) -> NostrEvent {
        NostrEvent(
            id: String(repeating: id, count: 64),
            pubkey: pubkey,
            createdAt: 100,
            kind: 1,
            tags: [],
            content: "boundary",
            sig: String(repeating: "0", count: 128)
        )
    }
}

@MainActor
private final class StoreReadBoundaryInteractionSpy:
    HomeStoreReadBoundaryInteracting {
    enum Event: Equatable {
        case restore(String, [HomeTimelineReadPosition])
        case schedule(String, String?)
        case write(String, String?)
    }

    var restoredBoundaryID: String?
    var scheduleResult = false
    var boundaryWriteResult: HomeTimelineReadBoundaryWrite?
    var cancelRestoreTask = false
    var onRestore: (@MainActor () -> Void)?
    private(set) var events: [Event] = []

    func restoredReadBoundaryPostID(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> String? {
        events.append(.restore(accountID, positions))
        onRestore?()
        if cancelRestoreTask {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        return restoredBoundaryID
    }

    func readBoundaryWrite(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> HomeTimelineReadBoundaryWrite? {
        events.append(.write(accountID, boundaryEvent?.id))
        return boundaryWriteResult
    }

    func scheduleReadBoundarySave(
        accountID: String,
        boundaryEvent: NostrEvent?
    ) -> Bool {
        events.append(.schedule(accountID, boundaryEvent?.id))
        return scheduleResult
    }
}

@MainActor
private final class StoreReadBoundaryTargetSpy:
    HomeStoreReadBoundaryTarget {
    var account: NostrAccount?
    var entries: [TimelineFeedEntry] = []
    var currentReadBoundaryPostID: String?
    var timelineEvents: [String: NostrEvent] = [:]
    private(set) var lookedUpEventIDs: [String] = []
    private(set) var appliedBoundaryIDs: [String] = []

    init(account: NostrAccount?) {
        self.account = account
    }

    func timelineEvent(id: String) -> NostrEvent? {
        lookedUpEventIDs.append(id)
        return timelineEvents[id]
    }

    func applyRestoredReadBoundary(postID: String) {
        appliedBoundaryIDs.append(postID)
    }
}
