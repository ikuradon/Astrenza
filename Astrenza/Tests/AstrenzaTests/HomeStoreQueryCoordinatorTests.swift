import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home Store query coordinator")
@MainActor
struct HomeStoreQueryCoordinatorTests {
    @Test("Public queries receive every current Store snapshot field")
    func routesPublicQueriesWithFreshSnapshot() {
        let fixture = StoreQueryFixture()
        let post = fixture.interaction.postResult

        expectPublicQueryResults(fixture: fixture, post: post)

        let expected = StoreQuerySnapshotRecord(target: fixture.target)
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

        fixture.target.account = fixture.replacementAccount
        fixture.target.entries = []
        fixture.target.resolvedRelays = []
        fixture.target.syncPolicy = .default(
            networkType: .cellular,
            lowPowerMode: false
        )
        fixture.target.resolvedContentRevision = 41
        fixture.target.listContentRevision = 43

        _ = fixture.coordinator.listEntries(limit: 1)

        #expect(fixture.interaction.snapshots.last ==
            StoreQuerySnapshotRecord(target: fixture.target))
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
        fixture.target.queryPreferredEvents = [preferredEvent]
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

    @Test("The coordinator does not retain its Store target")
    func doesNotRetainTarget() {
        let interaction = StoreQueryInteractionSpy()
        var target: StoreQueryTargetSpy? = StoreQueryTargetSpy(
            account: StoreQueryFixture.makeAccount(character: "a"),
            entries: [],
            resolvedRelays: [],
            syncPolicy: .default(),
            resolvedContentRevision: 0,
            listContentRevision: 0,
            queryPreferredEvents: []
        )
        weak let weakTarget = target
        let coordinator = HomeStoreQueryCoordinator(
            interaction: interaction,
            target: target!
        )

        target = nil
        _ = coordinator.listEntries(limit: 5)

        #expect(weakTarget == nil)
        #expect(interaction.snapshots == [.empty])
    }
}
