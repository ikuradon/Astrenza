import Combine
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

    @Test("The Store publishes a list invalidation once")
    func storePublishesInvalidationOnce() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        var publicationCount = 0
        let observation = store.objectWillChange.sink { _ in
            publicationCount += 1
        }
        let invalidation = HomeTimelineListProjectionInvalidation(revision: 7)

        store.testingApplyListProjectionInvalidation(invalidation)
        store.testingApplyListProjectionInvalidation(invalidation)

        #expect(publicationCount == 1)
        #expect(store.listContentRevision == 7)
        withExtendedLifetime(observation) {}
    }
}
