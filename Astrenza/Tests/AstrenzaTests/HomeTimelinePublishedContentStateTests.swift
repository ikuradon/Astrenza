import Combine
import Testing
@testable import Astrenza

@Suite("Home timeline published content state")
@MainActor
struct PublishedContentStateTests {
    @Test("A snapshot updates every changed published content field")
    func changedSnapshotApplies() throws {
        let state = HomeTimelinePublishedContentState(
            resolvedRelays: ["wss://old.example"],
            followedPubkeys: ["old-follow"],
            hasMoreOlder: true
        )
        let snapshot = contentSnapshot(
            resolvedRelays: ["wss://new.example"],
            followedPubkeys: ["new-follow"],
            hasMoreOlder: false
        )

        let next = try #require(state.applying(snapshot))

        #expect(next.resolvedRelays == ["wss://new.example"])
        #expect(next.followedPubkeys == ["new-follow"])
        #expect(!next.hasMoreOlder)
    }

    @Test("An unchanged snapshot avoids redundant publication state")
    func unchangedSnapshotReturnsNil() {
        let state = HomeTimelinePublishedContentState(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["follow"],
            hasMoreOlder: false
        )
        let snapshot = contentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["follow"],
            hasMoreOlder: false
        )

        #expect(state.applying(snapshot) == nil)
    }

    @Test("A multi-field content snapshot publishes from the Store once")
    func storePublishesSnapshotAtomically() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        var publicationCount = 0
        let observation = store.objectWillChange.sink { _ in
            publicationCount += 1
        }

        store.testingApplyContentSnapshot(.initial)
        #expect(publicationCount == 0)

        store.testingApplyContentSnapshot(contentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["follow"],
            hasMoreOlder: false
        ))

        #expect(publicationCount == 1)
        #expect(store.resolvedRelays == ["wss://relay.example"])
        #expect(store.followedPubkeys == ["follow"])
        #expect(!store.hasMoreOlder)
        withExtendedLifetime(observation) {}
    }
}

private func contentSnapshot(
    resolvedRelays: [String],
    followedPubkeys: [String],
    hasMoreOlder: Bool
) -> HomeTimelineContentSnapshot {
    HomeTimelineContentSnapshot(
        resolvedRelays: resolvedRelays,
        followedPubkeys: followedPubkeys,
        noteEvents: [],
        metadataEvents: [],
        relayListEvent: nil,
        contactListEvent: nil,
        hasMoreOlder: hasMoreOlder
    )
}
