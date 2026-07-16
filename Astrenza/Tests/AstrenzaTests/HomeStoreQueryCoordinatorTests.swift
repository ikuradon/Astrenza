import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store query coordinator")
@MainActor
struct HomeStoreQueryCoordinatorTests {
    @Test("Live source projects current published state and preferred events")
    func liveSourceProjectsCurrentState() {
        let fixture = StoreQueryLiveSourceFixture()

        #expect(StoreQuerySnapshotRecord(snapshot: fixture.source.snapshot()) ==
            StoreQuerySnapshotRecord(
                accountID: fixture.account.pubkey,
                fallbackEntryIDs: [fixture.post.id],
                resolvedRelayCount: 2,
                syncPolicy: fixture.syncPolicy,
                homeContentRevision: 17,
                listContentRevision: 19
            ))
        #expect(fixture.source.preferredEvents.map(\.id) == [
            fixture.preferredEvent.id
        ])

        fixture.events.preferredEvents = []
        fixture.publishedState.applyAccountContextTransition(.clear)

        #expect(fixture.source.snapshot().accountID == nil)
        #expect(fixture.source.preferredEvents.isEmpty)
    }

    @Test("Query snapshot observation ignores display-only publications")
    func liveSourceObservationIsFocused() {
        let fixture = StoreQueryLiveSourceFixture()
        let observation = observePublishedState(fixture.source.snapshot())

        fixture.publishedState.applyPresentationTransition(
            HomeTimelinePresentationTransition(
                snapshot: HomeTimelinePresentationSnapshot(
                    entries: [],
                    filterStatus: TimelineFilterStatus(activeRuleCount: 2),
                    materializedUnreadCount: 3,
                    visibleUnreadBadgeCount: 2,
                    resolvedContentRevision: 0,
                    realtimeFollowSourceRevision: nil
                ),
                changes: [.filterStatus, .unreadCounts],
                didChangeReadState: false
            )
        )

        #expect(observation.count == 0)
    }

    @Test("Public queries receive every current Store snapshot field")
    func routesPublicQueriesWithFreshSnapshot() {
        let fixture = StoreQueryFixture()
        let post = fixture.interaction.postResult

        expectPublicQueryResults(fixture: fixture, post: post)

        let expected = StoreQuerySnapshotRecord(source: fixture.source)
        #expect(fixture.interaction.snapshots.count == 7)
        for snapshot in fixture.interaction.snapshots {
            #expect(snapshot == expected)
        }
        #expect(fixture.interaction.routes == [
            "bookmark:\(post.id):\(fixture.account.pubkey)",
            "list:12",
            "post:\(post.id)",
            "profile:author:true",
            "profile-projection:author:true:34",
            "profile-posts:author:56",
            "ancestors:\(post.id):7",
            "replies:\(post.id):8"
        ])

        fixture.source.account = fixture.replacementAccount
        fixture.source.entries = []
        fixture.source.resolvedRelays = []
        fixture.source.syncPolicy = .default(
            networkType: .cellular,
            lowPowerMode: false
        )
        fixture.source.resolvedContentRevision = 41
        fixture.source.listContentRevision = 43

        _ = fixture.coordinator.listEntries(limit: 1)

        #expect(fixture.interaction.snapshots.last ==
            StoreQuerySnapshotRecord(source: fixture.source))
        #expect(fixture.source.snapshotCount == 9)
    }

    @Test("Event lookup, database backfill, and invalidation share the query boundary")
    func routesProjectionSupportQueries() throws {
        let fixture = StoreQueryFixture()
        let preferredEvent = StoreQueryFixture.makeEvent(
            id: "preferred",
            pubkey: "author"
        )
        let currentEvent = StoreQueryFixture.makeEvent(
            id: "current",
            pubkey: "author"
        )
        fixture.source.preferredEvents = [preferredEvent]
        let current = NostrHomeTimelineState(
            relays: [],
            followedPubkeys: ["author", "second-author"],
            noteEvents: [currentEvent],
            metadataEvents: []
        )

        let event = fixture.coordinator.timelineEvent(id: preferredEvent.id)
        let backfill = fixture.coordinator.olderBackfillEvents(
            account: fixture.account,
            current: current
        )
        let invalidation = fixture.coordinator.invalidateListEntries()

        #expect(event?.id == fixture.interaction.eventResult.id)
        #expect(backfill?.map(\.id) == [fixture.interaction.eventResult.id])
        #expect(invalidation.revision == 29)
        #expect(fixture.interaction.eventRequests == [
            StoreQueryEventRequest(
                eventID: preferredEvent.id,
                preferredEventIDs: [preferredEvent.id]
            )
        ])
        #expect(fixture.interaction.backfillQueries == [
            StoreQueryBackfillRecord(
                accountID: fixture.account.pubkey,
                followedPubkeys: current.followedPubkeys,
                currentEventIDs: [currentEvent.id],
                limit: 1_000
            )
        ])
        #expect(fixture.interaction.invalidationCount == 1)
    }

    @Test("Queries remain available after composition releases its local source")
    func retainsRequiredSource() {
        let interaction = StoreQueryInteractionSpy()
        let account = StoreQueryFixture.makeAccount(character: "a")
        var source: StoreQuerySourceSpy? = StoreQuerySourceSpy(
            account: account,
            entries: [],
            resolvedRelays: [],
            syncPolicy: .default(),
            resolvedContentRevision: 0,
            listContentRevision: 0,
            preferredEvents: []
        )
        weak let weakSource = source
        let coordinator = HomeStoreQueryCoordinator(
            source: source!,
            interaction: interaction
        )

        source = nil
        _ = coordinator.listEntries(limit: 5)

        #expect(weakSource != nil)
        #expect(interaction.snapshots == [StoreQuerySnapshotRecord(
            accountID: account.pubkey,
            fallbackEntryIDs: [],
            resolvedRelayCount: 0,
            syncPolicy: .default(),
            homeContentRevision: 0,
            listContentRevision: 0
        )])
    }
}

@MainActor
private struct StoreQueryLiveSourceFixture {
    let account: NostrAccount
    let post: TimelinePost
    let preferredEvent: NostrEvent
    let syncPolicy: NostrSyncPolicy
    let publishedState: HomeTimelinePublishedStateCoordinator
    let events: StoreQueryEventSourceSpy
    let source: HomeStoreQuerySource

    init() {
        let account = StoreQueryFixture.makeAccount(character: "a")
        let post = MockTimelineData.posts[0]
        let preferredEvent = StoreQueryFixture.makeEvent(
            id: "preferred",
            pubkey: "author"
        )
        let syncPolicy = NostrSyncPolicy.default(
            networkType: .wifi,
            lowPowerMode: true
        )
        let publishedState = HomeTimelinePublishedStateCoordinator(
            syncPolicy: .default()
        )
        let events = StoreQueryEventSourceSpy(
            preferredEvents: [preferredEvent]
        )
        Self.configure(
            publishedState,
            account: account,
            post: post,
            syncPolicy: syncPolicy
        )
        self.account = account
        self.post = post
        self.preferredEvent = preferredEvent
        self.syncPolicy = syncPolicy
        self.publishedState = publishedState
        self.events = events
        source = HomeStoreQuerySource(
            publishedState: publishedState,
            events: events
        )
    }

    private static func configure(
        _ publishedState: HomeTimelinePublishedStateCoordinator,
        account: NostrAccount,
        post: TimelinePost,
        syncPolicy: NostrSyncPolicy
    ) {
        publishedState.applyAccountContextTransition(.activate(
            account,
            syncPolicy: syncPolicy
        ))
        publishedState.applyContentSnapshot(HomeTimelineContentSnapshot(
            resolvedRelays: ["wss://one.example", "wss://two.example"],
            followedPubkeys: [],
            noteEvents: [],
            metadataEvents: [],
            relayListEvent: nil,
            contactListEvent: nil,
            hasMoreOlder: true
        ))
        publishedState.applyPresentationTransition(
            HomeTimelinePresentationTransition(
                snapshot: HomeTimelinePresentationSnapshot(
                    entries: [.post(post)],
                    filterStatus: TimelineFilterStatus(),
                    materializedUnreadCount: 0,
                    visibleUnreadBadgeCount: 0,
                    resolvedContentRevision: 17,
                    realtimeFollowSourceRevision: nil
                ),
                changes: [.entries, .resolvedContentRevision],
                didChangeReadState: false
            )
        )
        publishedState.applyListProjectionInvalidation(
            HomeTimelineListProjectionInvalidation(revision: 19)
        )
    }
}
