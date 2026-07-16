import CoreGraphics

@MainActor
protocol HomeTimelineViewportPersistenceBacking: AnyObject {
    func viewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState?

    func latestViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState?

    func layoutCache(
        accountID: String,
        timelineKey: String
    ) -> TimelineLayoutCache

    func scheduleViewportStateSave(_ state: TimelineViewportState)

    func scheduleLayoutCacheSave(
        _ cache: TimelineLayoutCache,
        accountID: String,
        timelineKey: String
    )

    func flushPendingSaves()
}

extension TimelineRestoreStore: HomeTimelineViewportPersistenceBacking {
    func scheduleViewportStateSave(_ state: TimelineViewportState) {
        scheduleViewportStateSave(state, delay: 0.75)
    }

    func scheduleLayoutCacheSave(
        _ cache: TimelineLayoutCache,
        accountID: String,
        timelineKey: String
    ) {
        scheduleLayoutCacheSave(
            cache,
            accountID: accountID,
            timelineKey: timelineKey,
            delay: 0.75
        )
    }
}

struct HomeTimelineViewportRestoreSnapshot: Equatable {
    let viewportState: TimelineViewportState?
    let layoutCache: TimelineLayoutCache
}

@MainActor
final class HomeViewportPersistenceCoordinator {
    typealias FallbackViewportLoader = @MainActor (
        _ accountID: String,
        _ timelineKey: String
    ) -> TimelineViewportState?

    private let persistence: any HomeTimelineViewportPersistenceBacking
    private let fallbackViewportLoader: FallbackViewportLoader

    init(
        persistence: any HomeTimelineViewportPersistenceBacking,
        fallbackViewportLoader: @escaping FallbackViewportLoader
    ) {
        self.persistence = persistence
        self.fallbackViewportLoader = fallbackViewportLoader
    }

    func restoreSnapshot(
        accountID: String,
        timelineKey: String
    ) -> HomeTimelineViewportRestoreSnapshot {
        persistence.flushPendingSaves()
        let viewportState = persistence.viewportState(
            accountID: accountID,
            timelineKey: timelineKey
        ) ?? fallbackViewportLoader(accountID, timelineKey)
        return HomeTimelineViewportRestoreSnapshot(
            viewportState: viewportState,
            layoutCache: persistence.layoutCache(
                accountID: accountID,
                timelineKey: timelineKey
            )
        )
    }

    func latestViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        persistence.latestViewportState(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func scheduleViewportStateSave(
        _ state: TimelineViewportState,
        accountID: String,
        timelineKey: String
    ) {
        persistence.scheduleViewportStateSave(TimelineViewportState(
            accountID: accountID,
            timelineKey: timelineKey,
            anchorPostID: state.anchorPostID,
            anchorOffset: state.anchorOffset,
            contentOffset: state.contentOffset,
            updatedAt: state.updatedAt
        ))
    }

    func scheduleLayoutCacheSave(
        _ cache: TimelineLayoutCache,
        accountID: String,
        timelineKey: String
    ) {
        persistence.scheduleLayoutCacheSave(
            cache,
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func flushPendingSaves() {
        persistence.flushPendingSaves()
    }
}
