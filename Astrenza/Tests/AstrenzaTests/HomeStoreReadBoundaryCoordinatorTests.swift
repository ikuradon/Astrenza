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
        fixture.source.entries = [
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
        #expect(fixture.source.appliedBoundaryIDs == [posts[1].id])
    }

    @Test("A newer restored viewport advances a stale persisted boundary")
    func advancesBoundaryToNewerRestoredViewport() async {
        let fixture = StoreReadBoundaryFixture()
        let posts = Array(MockTimelineData.posts.prefix(3))
        let boundaryEvent = StoreReadBoundaryFixture.makeEvent(
            eventID: posts[0].id,
            pubkey: fixture.account.pubkey,
            createdAt: posts[0].createdAt
        )
        fixture.source.entries = posts.map(TimelineFeedEntry.post)
        fixture.source.restoredViewportAnchorPostID = posts[0].id
        fixture.source.timelineEvents[posts[0].id] = boundaryEvent
        fixture.interaction.restoredBoundaryID = posts[2].id
        fixture.interaction.scheduleResult = true

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(didRestore)
        #expect(fixture.source.appliedBoundaryIDs == [posts[0].id])
        #expect(fixture.interaction.events == [
            .restore(
                fixture.account.pubkey,
                posts.map {
                    HomeTimelineReadPosition(
                        postID: $0.id,
                        createdAt: $0.createdAt
                    )
                }
            ),
            .schedule(fixture.account.pubkey, boundaryEvent.id)
        ])
    }

    @Test("A persisted boundary older than the projection advances to viewport")
    func advancesBoundaryOlderThanProjectionToViewport() async {
        let fixture = StoreReadBoundaryFixture()
        let posts = Array(MockTimelineData.posts.prefix(2))
        let boundaryEvent = StoreReadBoundaryFixture.makeEvent(
            eventID: posts[0].id,
            pubkey: fixture.account.pubkey,
            createdAt: posts[0].createdAt
        )
        fixture.source.entries = posts.map(TimelineFeedEntry.post)
        fixture.source.restoredViewportAnchorPostID = posts[0].id
        fixture.source.timelineEvents[posts[0].id] = boundaryEvent
        fixture.interaction.restoredBoundaryOutcome = .olderThanProjection

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(didRestore)
        #expect(fixture.source.appliedBoundaryIDs == [posts[0].id])
        #expect(fixture.interaction.events.last == .schedule(
            fixture.account.pubkey,
            boundaryEvent.id
        ))
    }

    @Test("An older restored viewport preserves the newer read boundary")
    func preservesBoundaryWhenRestoredViewportIsOlder() async {
        let fixture = StoreReadBoundaryFixture()
        let posts = Array(MockTimelineData.posts.prefix(3))
        fixture.source.entries = posts.map(TimelineFeedEntry.post)
        fixture.source.restoredViewportAnchorPostID = posts[2].id
        fixture.interaction.restoredBoundaryID = posts[0].id

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(didRestore)
        #expect(fixture.source.appliedBoundaryIDs == [posts[0].id])
        #expect(fixture.interaction.events.count == 1)
    }

    @Test("An unavailable viewport anchor cannot move the read boundary")
    func ignoresViewportAnchorOutsideProjection() async {
        let fixture = StoreReadBoundaryFixture()
        let post = MockTimelineData.posts[0]
        fixture.source.entries = [.post(post)]
        fixture.source.restoredViewportAnchorPostID = "outside-projection"
        fixture.interaction.restoredBoundaryID = post.id

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(didRestore)
        #expect(fixture.source.appliedBoundaryIDs == [post.id])
        #expect(fixture.interaction.events.count == 1)
    }

    @Test("A missing restored boundary leaves presentation unchanged")
    func ignoresMissingBoundary() async {
        let fixture = StoreReadBoundaryFixture()
        fixture.source.entries = MockTimelineData.posts.prefix(1).map {
            .post($0)
        }

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(!didRestore)
        #expect(fixture.source.appliedBoundaryIDs.isEmpty)
    }

    @Test("An account switch during restore rejects the stale boundary")
    func rejectsStaleAccount() async {
        let fixture = StoreReadBoundaryFixture()
        fixture.interaction.restoredBoundaryID = "boundary"
        fixture.interaction.onRestore = {
            fixture.source.account = fixture.replacementAccount
        }

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(!didRestore)
        #expect(fixture.source.appliedBoundaryIDs.isEmpty)
    }

    @Test("A viewport mode change during restore rejects the stale boundary")
    func rejectsStaleViewportAnchor() async {
        let fixture = StoreReadBoundaryFixture()
        let posts = Array(MockTimelineData.posts.prefix(2))
        fixture.source.entries = posts.map(TimelineFeedEntry.post)
        fixture.source.restoredViewportAnchorPostID = posts[0].id
        fixture.interaction.restoredBoundaryID = posts[1].id
        fixture.interaction.onRestore = {
            fixture.source.restoredViewportAnchorPostID = nil
        }

        let didRestore = await fixture.coordinator.restore(
            account: fixture.account
        )

        #expect(!didRestore)
        #expect(fixture.source.appliedBoundaryIDs.isEmpty)
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
        #expect(fixture.source.appliedBoundaryIDs.isEmpty)
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
        fixture.source.currentReadBoundaryPostID = event.id
        fixture.source.timelineEvents[event.id] = event
        fixture.interaction.scheduleResult = true
        fixture.interaction.boundaryWriteResult = expectedWrite

        let didSchedule = fixture.coordinator.scheduleSave()
        let write = try #require(fixture.coordinator.boundaryWrite())

        #expect(didSchedule)
        #expect(fixture.interaction.events == [
            .schedule(fixture.account.pubkey, event.id),
            .write(fixture.account.pubkey, event.id)
        ])
        #expect(fixture.source.lookedUpEventIDs == [event.id, event.id])
        #expect(write.scopeID == expectedWrite.scopeID)
        #expect(write.feedID == expectedWrite.feedID)
        #expect(write.boundary == expectedWrite.boundary)
        #expect(write.updatedAt == expectedWrite.updatedAt)
    }

    @Test("The coordinator owns its required state source")
    func retainsRequiredSource() {
        let account = StoreReadBoundaryFixture.makeAccount(
            pubkeyCharacter: "a"
        )
        let interaction = StoreReadBoundaryInteractionSpy()
        interaction.scheduleResult = true
        var source: StoreReadBoundarySourceSpy? =
            StoreReadBoundarySourceSpy(account: account)
        weak let weakSource = source
        let coordinator: HomeStoreReadBoundaryCoordinator
        if let source {
            coordinator = HomeStoreReadBoundaryCoordinator(
                interaction: interaction,
                source: source
            )
        } else {
            Issue.record("Expected a read-boundary source")
            return
        }

        source = nil

        #expect(weakSource != nil)
        #expect(coordinator.scheduleSave())
        #expect(interaction.events == [
            .schedule(account.pubkey, nil)
        ])
    }

    @Test("The state source exposes fresh snapshots and routes effects")
    func sourceRoutesStateAndEffects() {
        let account = StoreReadBoundaryFixture.makeAccount(
            pubkeyCharacter: "a"
        )
        let event = StoreReadBoundaryFixture.makeEvent(
            id: "1",
            pubkey: account.pubkey
        )
        let state = StoreReadBoundarySourceClosureState()
        let source = HomeStoreReadBoundarySource(
            snapshot: { state.snapshot },
            event: { eventID in
                state.requestedEventIDs.append(eventID)
                return eventID == event.id ? event : nil
            },
            applyRestoredBoundary: { postID in
                state.appliedBoundaryIDs.append(postID)
            }
        )

        state.snapshot = HomeStoreReadBoundarySnapshot(
            account: account,
            entries: [.post(MockTimelineData.posts[0])],
            currentBoundaryPostID: event.id,
            restoredViewportAnchorPostID: nil
        )

        #expect(source.snapshot().account == account)
        #expect(source.snapshot().entries.count == 1)
        #expect(source.timelineEvent(id: event.id) == event)
        source.applyRestoredReadBoundary(postID: event.id)
        #expect(state.requestedEventIDs == [event.id])
        #expect(state.appliedBoundaryIDs == [event.id])
    }
}

@MainActor
private struct StoreReadBoundaryFixture {
    let account: NostrAccount
    let replacementAccount: NostrAccount
    let source: StoreReadBoundarySourceSpy
    let interaction: StoreReadBoundaryInteractionSpy
    let coordinator: HomeStoreReadBoundaryCoordinator

    init() {
        let account = Self.makeAccount(pubkeyCharacter: "a")
        let source = StoreReadBoundarySourceSpy(account: account)
        let interaction = StoreReadBoundaryInteractionSpy()
        self.account = account
        replacementAccount = Self.makeAccount(pubkeyCharacter: "b")
        self.source = source
        self.interaction = interaction
        let coordinator = HomeStoreReadBoundaryCoordinator(
            interaction: interaction,
            source: source
        )
        self.coordinator = coordinator
    }

    static func makeAccount(pubkeyCharacter: Character) -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: pubkeyCharacter, count: 64),
            displayIdentifier: "read-boundary",
            readOnly: true
        )
    }

    static func makeEvent(
        id: Character,
        pubkey: String,
        createdAt: Int = 100
    ) -> NostrEvent {
        makeEvent(
            eventID: String(repeating: id, count: 64),
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    static func makeEvent(
        eventID: String,
        pubkey: String,
        createdAt: Int = 100
    ) -> NostrEvent {
        NostrEvent(
            id: eventID,
            pubkey: pubkey,
            createdAt: createdAt,
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
    var restoredBoundaryOutcome: HomeTimelineReadBoundaryRestoreOutcome?
    var scheduleResult = false
    var boundaryWriteResult: HomeTimelineReadBoundaryWrite?
    var cancelRestoreTask = false
    var onRestore: (@MainActor () -> Void)?
    private(set) var events: [Event] = []

    func restoredReadBoundary(
        accountID: String,
        positions: [HomeTimelineReadPosition]
    ) async -> HomeTimelineReadBoundaryRestoreOutcome {
        events.append(.restore(accountID, positions))
        onRestore?()
        if cancelRestoreTask {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }
        if let restoredBoundaryOutcome {
            return restoredBoundaryOutcome
        }
        return restoredBoundaryID.map {
            .resolved(postID: $0)
        } ?? .missing
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
private final class StoreReadBoundarySourceSpy:
    HomeStoreReadBoundarySourcing {
    var account: NostrAccount?
    var entries: [TimelineFeedEntry] = []
    var currentReadBoundaryPostID: String?
    var restoredViewportAnchorPostID: String?
    var timelineEvents: [String: NostrEvent] = [:]
    private(set) var lookedUpEventIDs: [String] = []
    private(set) var appliedBoundaryIDs: [String] = []

    init(account: NostrAccount?) {
        self.account = account
    }

    func snapshot() -> HomeStoreReadBoundarySnapshot {
        HomeStoreReadBoundarySnapshot(
            account: account,
            entries: entries,
            currentBoundaryPostID: currentReadBoundaryPostID,
            restoredViewportAnchorPostID: restoredViewportAnchorPostID
        )
    }

    func timelineEvent(id: String) -> NostrEvent? {
        lookedUpEventIDs.append(id)
        return timelineEvents[id]
    }

    func applyRestoredReadBoundary(postID: String) {
        appliedBoundaryIDs.append(postID)
    }
}

@MainActor
private final class StoreReadBoundarySourceClosureState {
    var snapshot = HomeStoreReadBoundarySnapshot(
        account: nil,
        entries: [],
        currentBoundaryPostID: nil,
        restoredViewportAnchorPostID: nil
    )
    var requestedEventIDs: [String] = []
    var appliedBoundaryIDs: [String] = []
}
