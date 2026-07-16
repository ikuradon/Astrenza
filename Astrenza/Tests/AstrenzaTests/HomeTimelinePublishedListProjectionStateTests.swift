import Testing
@testable import Astrenza

@Suite("Home timeline published list projection state")
@MainActor
struct PublishedListProjectionStateTests {
    @Test("An invalidation replaces the published cache revision")
    func invalidationApplies() throws {
        let state = HomeTimelinePublishedListProjectionState(revision: 3)

        let next = try #require(state.applying(
            HomeTimelineListProjectionInvalidation(revision: 4)
        ))

        #expect(next.revision == 4)
    }

    @Test("An already-published invalidation avoids redundant state")
    func unchangedInvalidationReturnsNil() {
        let state = HomeTimelinePublishedListProjectionState(revision: 4)

        #expect(state.applying(
            HomeTimelineListProjectionInvalidation(revision: 4)
        ) == nil)
    }

    @Test("A changed list revision notifies its observer once")
    func changedListRevisionNotifiesOnce() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        let observation = observePublishedState(store.listContentRevision)
        let invalidation = HomeTimelineListProjectionInvalidation(revision: 7)

        store.testingApplyListProjectionInvalidation(invalidation)
        store.testingApplyListProjectionInvalidation(invalidation)

        #expect(observation.count == 1)
        #expect(store.listContentRevision == 7)
    }
}
