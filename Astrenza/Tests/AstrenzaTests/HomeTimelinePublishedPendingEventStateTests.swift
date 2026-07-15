import Combine
import Testing
@testable import Astrenza

@Suite("Home timeline published pending event state")
@MainActor
struct PublishedPendingEventStateTests {
    @Test("A count publication replaces the pending event count")
    func countPublicationApplies() throws {
        let state = HomeTimelinePublishedPendingEventState(count: 2)

        let next = try #require(state.applying(
            HomeTimelinePendingEventCountPublication(count: 3)
        ))

        #expect(next.count == 3)
    }

    @Test("An already-published count avoids redundant state")
    func unchangedCountReturnsNil() {
        let state = HomeTimelinePublishedPendingEventState(count: 3)

        #expect(state.applying(
            HomeTimelinePendingEventCountPublication(count: 3)
        ) == nil)
    }

    @Test("The Store publishes a pending event count once")
    func storePublishesCountOnce() {
        let store = NostrHomeTimelineStore(eventStore: nil)
        var publicationCount = 0
        let observation = store.objectWillChange.sink { _ in
            publicationCount += 1
        }
        let publication = HomeTimelinePendingEventCountPublication(count: 4)

        store.testingApplyPendingEventCountPublication(publication)
        store.testingApplyPendingEventCountPublication(publication)

        #expect(publicationCount == 1)
        #expect(store.unmaterializedNewCount == 4)
        withExtendedLifetime(observation) {}
    }
}
