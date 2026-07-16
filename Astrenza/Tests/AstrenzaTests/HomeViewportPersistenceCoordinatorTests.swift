import CoreGraphics
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline viewport persistence coordinator")
struct HomeViewportPersistenceCoordinatorTests {
    @Test("Restore flushes pending saves and prefers the local viewport")
    @MainActor
    func restorePrefersLocalViewport() {
        let localViewport = makeViewport(
            accountID: "account",
            timelineKey: "home",
            postID: "local"
        )
        let fallbackViewport = makeViewport(
            accountID: "account",
            timelineKey: "home",
            postID: "fallback"
        )
        let cache = TimelineLayoutCache(measuredHeights: ["local": 180])
        let persistence = ViewportPersistenceBackingSpy(
            viewportState: localViewport,
            layoutCache: cache
        )
        var fallbackRequests: [ViewportIdentity] = []
        let coordinator = HomeViewportPersistenceCoordinator(
            persistence: persistence,
            fallbackViewportLoader: { accountID, timelineKey in
                fallbackRequests.append(.init(
                    accountID: accountID,
                    timelineKey: timelineKey
                ))
                return fallbackViewport
            }
        )

        let snapshot = coordinator.restoreSnapshot(
            accountID: "account",
            timelineKey: "home"
        )

        #expect(snapshot == HomeTimelineViewportRestoreSnapshot(
            viewportState: localViewport,
            layoutCache: cache
        ))
        #expect(fallbackRequests.isEmpty)
        #expect(persistence.calls == [
            .flush,
            .viewportState(.init(accountID: "account", timelineKey: "home")),
            .layoutCache(.init(accountID: "account", timelineKey: "home"))
        ])
    }

    @Test("Restore uses the projection fallback when local state is absent")
    @MainActor
    func restoreUsesProjectionFallback() {
        let fallbackViewport = makeViewport(
            accountID: "account",
            timelineKey: "home",
            postID: "fallback"
        )
        let persistence = ViewportPersistenceBackingSpy()
        var fallbackRequests: [ViewportIdentity] = []
        let coordinator = HomeViewportPersistenceCoordinator(
            persistence: persistence,
            fallbackViewportLoader: { accountID, timelineKey in
                fallbackRequests.append(.init(
                    accountID: accountID,
                    timelineKey: timelineKey
                ))
                return fallbackViewport
            }
        )

        let snapshot = coordinator.restoreSnapshot(
            accountID: "account",
            timelineKey: "home"
        )

        #expect(snapshot.viewportState == fallbackViewport)
        #expect(fallbackRequests == [
            .init(accountID: "account", timelineKey: "home")
        ])
        #expect(persistence.calls == [
            .flush,
            .viewportState(.init(accountID: "account", timelineKey: "home")),
            .layoutCache(.init(accountID: "account", timelineKey: "home"))
        ])
    }

    @Test("Viewport saves are rebound to the visible account and timeline")
    @MainActor
    func viewportSaveUsesVisibleIdentity() throws {
        let persistence = ViewportPersistenceBackingSpy()
        let coordinator = makeCoordinator(persistence: persistence)
        let measuredState = makeViewport(
            accountID: "stale-account",
            timelineKey: "stale-timeline",
            postID: "anchor"
        )

        coordinator.scheduleViewportStateSave(
            measuredState,
            accountID: "visible-account",
            timelineKey: "home"
        )

        let savedState = try #require(persistence.scheduledViewportState)
        #expect(savedState.accountID == "visible-account")
        #expect(savedState.timelineKey == "home")
        #expect(savedState.anchorPostID == measuredState.anchorPostID)
        #expect(savedState.anchorOffset == measuredState.anchorOffset)
        #expect(savedState.contentOffset == measuredState.contentOffset)
        #expect(savedState.updatedAt == measuredState.updatedAt)
    }

    @Test("Latest viewport and layout writes preserve pending persistence semantics")
    @MainActor
    func latestViewportAndLayoutWritesDelegateToPersistence() {
        let latestViewport = makeViewport(
            accountID: "account",
            timelineKey: "home",
            postID: "latest"
        )
        let cache = TimelineLayoutCache(measuredHeights: ["latest": 220])
        let persistence = ViewportPersistenceBackingSpy(
            latestViewportState: latestViewport
        )
        let coordinator = makeCoordinator(persistence: persistence)

        let restoredLatest = coordinator.latestViewportState(
            accountID: "account",
            timelineKey: "home"
        )
        coordinator.scheduleLayoutCacheSave(
            cache,
            accountID: "account",
            timelineKey: "home"
        )
        coordinator.flushPendingSaves()

        #expect(restoredLatest == latestViewport)
        #expect(persistence.scheduledLayoutCache == cache)
        #expect(persistence.scheduledLayoutIdentity == .init(
            accountID: "account",
            timelineKey: "home"
        ))
        #expect(persistence.calls == [
            .latestViewportState(.init(accountID: "account", timelineKey: "home")),
            .scheduleLayoutCache(.init(accountID: "account", timelineKey: "home")),
            .flush
        ])
    }

    @MainActor
    private func makeCoordinator(
        persistence: ViewportPersistenceBackingSpy
    ) -> HomeViewportPersistenceCoordinator {
        HomeViewportPersistenceCoordinator(
            persistence: persistence,
            fallbackViewportLoader: { _, _ in nil }
        )
    }

    private func makeViewport(
        accountID: String,
        timelineKey: String,
        postID: TimelinePost.ID
    ) -> TimelineViewportState {
        TimelineViewportState(
            accountID: accountID,
            timelineKey: timelineKey,
            anchorPostID: postID,
            anchorOffset: 18,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private struct ViewportIdentity: Equatable {
    let accountID: String
    let timelineKey: String
}

@MainActor
private final class ViewportPersistenceBackingSpy:
    HomeTimelineViewportPersistenceBacking {
    enum Call: Equatable {
        case viewportState(ViewportIdentity)
        case latestViewportState(ViewportIdentity)
        case layoutCache(ViewportIdentity)
        case scheduleViewportState
        case scheduleLayoutCache(ViewportIdentity)
        case flush
    }

    private let viewportStateResult: TimelineViewportState?
    private let latestViewportStateResult: TimelineViewportState?
    private let layoutCacheResult: TimelineLayoutCache
    private(set) var calls: [Call] = []
    private(set) var scheduledViewportState: TimelineViewportState?
    private(set) var scheduledLayoutCache: TimelineLayoutCache?
    private(set) var scheduledLayoutIdentity: ViewportIdentity?

    init(
        viewportState: TimelineViewportState? = nil,
        latestViewportState: TimelineViewportState? = nil,
        layoutCache: TimelineLayoutCache = TimelineLayoutCache()
    ) {
        viewportStateResult = viewportState
        latestViewportStateResult = latestViewportState
        layoutCacheResult = layoutCache
    }

    func viewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        calls.append(.viewportState(.init(
            accountID: accountID,
            timelineKey: timelineKey
        )))
        return viewportStateResult
    }

    func latestViewportState(
        accountID: String,
        timelineKey: String
    ) -> TimelineViewportState? {
        calls.append(.latestViewportState(.init(
            accountID: accountID,
            timelineKey: timelineKey
        )))
        return latestViewportStateResult
    }

    func layoutCache(
        accountID: String,
        timelineKey: String
    ) -> TimelineLayoutCache {
        calls.append(.layoutCache(.init(
            accountID: accountID,
            timelineKey: timelineKey
        )))
        return layoutCacheResult
    }

    func scheduleViewportStateSave(_ state: TimelineViewportState) {
        calls.append(.scheduleViewportState)
        scheduledViewportState = state
    }

    func scheduleLayoutCacheSave(
        _ cache: TimelineLayoutCache,
        accountID: String,
        timelineKey: String
    ) {
        calls.append(.scheduleLayoutCache(.init(
            accountID: accountID,
            timelineKey: timelineKey
        )))
        scheduledLayoutCache = cache
        scheduledLayoutIdentity = .init(
            accountID: accountID,
            timelineKey: timelineKey
        )
    }

    func flushPendingSaves() {
        calls.append(.flush)
    }
}
