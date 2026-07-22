import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline viewport store synchronizer")
@MainActor
struct ViewportStoreSynchronizerTests {
    @Test("Newest-window updates preserve read and publication semantics")
    func newestWindowUpdatesPreserveSemantics() {
        let store = ViewportStoreHandlerSpy()
        let synchronizer = HomeTimelineViewportStoreSynchronizer(store: store)

        synchronizer.applyNewestWindowUpdate(
            update(isAtNewest: true, shouldPublish: false),
            context: .liveHome
        )
        synchronizer.applyNewestWindowUpdate(
            update(isAtNewest: true, shouldPublish: true),
            context: .liveHome
        )
        synchronizer.applyNewestWindowUpdate(
            update(isAtNewest: false, shouldPublish: false),
            context: .liveHome
        )
        synchronizer.applyNewestWindowUpdate(
            update(isAtNewest: false, shouldPublish: true),
            context: .liveHome
        )

        #expect(store.calls == [
            .markNewestRead,
            .markNewestRead,
            .setNewestWindow(true),
            .setNewestWindow(false)
        ])
    }

    @Test("Home retap preserves projection effect order")
    func homeRetapPreservesEffectOrder() {
        let store = ViewportStoreHandlerSpy()
        let synchronizer = HomeTimelineViewportStoreSynchronizer(store: store)
        let returnAnchor = makeViewport(postID: "return-anchor")

        synchronizer.applyHomeRetap(
            .restore(returnAnchor),
            context: .liveHome
        )
        synchronizer.applyHomeRetap(.showNewest, context: .liveHome)

        #expect(store.calls == [
            .setNewestWindow(false),
            .setRestoreAnchor("return-anchor"),
            .clearRestoreAnchorWithoutReload,
            .setNewestWindow(false)
        ])
    }

    @Test("Restore snapshot selects its projection window deterministically")
    func restoreSnapshotSelectsProjectionWindow() {
        let store = ViewportStoreHandlerSpy()
        let synchronizer = HomeTimelineViewportStoreSynchronizer(store: store)
        let restoredViewport = makeViewport(postID: "restored")

        synchronizer.applyRestoreSnapshot(
            HomeTimelineViewportRestoreSnapshot(
                viewportState: restoredViewport,
                layoutCache: TimelineLayoutCache()
            ),
            context: .liveHome
        )
        synchronizer.applyRestoreSnapshot(
            HomeTimelineViewportRestoreSnapshot(
                viewportState: nil,
                layoutCache: TimelineLayoutCache()
            ),
            context: .liveHome
        )

        #expect(store.calls == [
            .setRestoreAnchor("restored"),
            .setNewestWindow(false),
            .setRestoreAnchor(nil),
            .setNewestWindow(false)
        ])
    }

    @Test("Viewport effects require an account on the Home timeline")
    func viewportEffectsRequireLiveHome() {
        let store = ViewportStoreHandlerSpy()
        let synchronizer = HomeTimelineViewportStoreSynchronizer(store: store)
        let snapshot = HomeTimelineViewportRestoreSnapshot(
            viewportState: nil,
            layoutCache: TimelineLayoutCache()
        )

        for context in [
            HomeTimelineInteractionContext(
                hasLiveAccount: false,
                timeline: .home
            ),
            HomeTimelineInteractionContext(
                hasLiveAccount: true,
                timeline: .relays
            )
        ] {
            synchronizer.applyNewestWindowUpdate(
                update(isAtNewest: true, shouldPublish: true),
                context: context
            )
            synchronizer.applyHomeRetap(.showNewest, context: context)
            synchronizer.applyRestoreSnapshot(snapshot, context: context)
        }

        #expect(store.calls.isEmpty)
    }

    private func update(
        isAtNewest: Bool,
        shouldPublish: Bool
    ) -> HomeTimelineViewportState.NewestWindowUpdate {
        HomeTimelineViewportState.NewestWindowUpdate(
            isAtNewestWindow: isAtNewest,
            shouldUpdateState: false,
            shouldPublishToStore: shouldPublish
        )
    }

    private func makeViewport(postID: TimelinePost.ID) -> TimelineViewportState {
        TimelineViewportState(
            accountID: "account",
            timelineKey: TimelineKind.home.id,
            anchorPostID: postID,
            anchorOffset: 18,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension HomeTimelineInteractionContext {
    static let liveHome = HomeTimelineInteractionContext(
        hasLiveAccount: true,
        timeline: .home
    )
}

@MainActor
private final class ViewportStoreHandlerSpy:
    HomeTimelineViewportStoreHandling {
    enum Call: Equatable {
        case setRestoreAnchor(String?)
        case setNewestWindow(Bool)
        case markNewestRead
        case clearRestoreAnchorWithoutReload
    }

    private(set) var calls: [Call] = []

    func setRestoreProjectionAnchor(_ anchorEventID: String?) {
        calls.append(.setRestoreAnchor(anchorEventID))
    }

    func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool) {
        calls.append(.setNewestWindow(isAtNewestWindow))
    }

    func markNewestMaterializedWindowRead() {
        calls.append(.markNewestRead)
    }

    func clearRestoreProjectionAnchorWithoutReload() {
        calls.append(.clearRestoreAnchorWithoutReload)
    }
}
