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

    @Test("A selected content field notifies its observer once")
    func selectedContentFieldNotifiesOnce() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)
        let observation = observePublishedState(store.resolvedRelays)

        store.testingApplyContentSnapshot(.initial)
        #expect(observation.count == 0)

        store.testingApplyContentSnapshot(contentSnapshot(
            resolvedRelays: ["wss://relay.example"],
            followedPubkeys: ["follow"],
            hasMoreOlder: false
        ))

        #expect(observation.count == 1)
        #expect(store.resolvedRelays == ["wss://relay.example"])
        #expect(store.followedPubkeys == ["follow"])
        #expect(!store.hasMoreOlder)
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
