import Testing
@testable import Astrenza

@Suite("Home timeline list projection cache")
struct HomeTimelineListProjectionCacheTests {
    @Test("Empty materialization results are cached")
    @MainActor
    func emptyResultsAreCached() {
        let cache = HomeTimelineListProjectionCache()
        let key = makeKey()
        var materializationCount = 0

        let first = cache.entries(for: key) {
            materializationCount += 1
            return []
        }
        let second = cache.entries(for: key) {
            materializationCount += 1
            return [.deleted(TimelineDeletedEntry(id: "unexpected"))]
        }

        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(materializationCount == 1)
    }

    @Test(
        "Every cache key field participates in lookup",
        arguments: [
            HomeTimelineListProjectionCache.Key(
                accountID: "account-b",
                limit: 500,
                homeContentRevision: 7
            ),
            HomeTimelineListProjectionCache.Key(
                accountID: "account-a",
                limit: 200,
                homeContentRevision: 7
            ),
            HomeTimelineListProjectionCache.Key(
                accountID: "account-a",
                limit: 500,
                homeContentRevision: 8
            )
        ]
    )
    @MainActor
    func cacheKeyFields(mismatchedKey: HomeTimelineListProjectionCache.Key) {
        let cache = HomeTimelineListProjectionCache()
        var materializationCount = 0

        _ = cache.entries(for: makeKey()) {
            materializationCount += 1
            return [.deleted(TimelineDeletedEntry(id: "initial"))]
        }
        let entries = cache.entries(for: mismatchedKey) {
            materializationCount += 1
            return [.deleted(TimelineDeletedEntry(id: "replacement"))]
        }

        #expect(entries.map(\.id) == ["replacement"])
        #expect(materializationCount == 2)
    }

    @Test("Invalidation advances revision and forces rematerialization")
    @MainActor
    func invalidationForcesRematerialization() {
        let cache = HomeTimelineListProjectionCache()
        let key = makeKey()
        var materializationCount = 0

        _ = cache.entries(for: key) {
            materializationCount += 1
            return [.deleted(TimelineDeletedEntry(id: "initial"))]
        }
        let firstInvalidation = cache.invalidate()
        let entries = cache.entries(for: key) {
            materializationCount += 1
            return [.deleted(TimelineDeletedEntry(id: "replacement"))]
        }
        let secondInvalidation = cache.invalidate()

        #expect(firstInvalidation.revision == 1)
        #expect(secondInvalidation.revision == 2)
        #expect(cache.revision == 2)
        #expect(entries.map(\.id) == ["replacement"])
        #expect(materializationCount == 2)
    }

    private func makeKey() -> HomeTimelineListProjectionCache.Key {
        HomeTimelineListProjectionCache.Key(
            accountID: "account-a",
            limit: 500,
            homeContentRevision: 7
        )
    }
}
