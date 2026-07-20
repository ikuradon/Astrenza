import Testing
@testable import Astrenza

@Suite("Home Store viewport coordinator")
@MainActor
struct HomeStoreViewportCoordinatorTests {
    @Test("各commandを最新のviewport contextとともに転送する")
    func routesCommandsWithFreshContexts() async {
        let fixture = StoreViewportCoordinatorFixture()
        fixture.interaction.applyPendingEventsResult = true
        fixture.interaction.clearPendingEventsResult = true

        fixture.coordinator.setRestoreProjectionAnchor("anchor")
        fixture.coordinator.refresh()
        await fixture.coordinator.refreshLatest()
        fixture.coordinator.setTimelineAtNewestWindow(false)
        fixture.coordinator.setTimelineScrollActive(true)
        fixture.coordinator.dismissUnreadBadge()
        fixture.coordinator.markMaterializedPostsRead(
            visiblePostIDs: ["visible"]
        )
        fixture.coordinator.markNewestMaterializedWindowRead()
        let didApplyPending = await fixture.coordinator.applyPendingNewEvents()
        fixture.coordinator.loadOlder()
        let didClearPending = fixture.coordinator.clearPendingNewEvents()

        #expect(didApplyPending)
        #expect(didClearPending)
        #expect(fixture.interaction.calls == [
            .setRestoreAnchor("anchor", fixture.accountID),
            .refresh(fixture.accountID),
            .refreshLatest(fixture.accountID),
            .setNewestWindow(false, fixture.accountID),
            .setScrollActive(true, fixture.accountID),
            .dismissUnreadBadge(fixture.accountID),
            .markMaterializedPostsRead(["visible"], fixture.accountID),
            .markNewestMaterializedWindowRead(fixture.accountID),
            .applyPendingEvents(fixture.accountID),
            .loadOlder(fixture.accountID),
            .clearPendingEvents(fixture.accountID)
        ])
        #expect(fixture.contexts.readCount == 11)
    }

    @Test("projection viewport stateはcontext取得なしで参照・更新する")
    func routesProjectionStateWithoutContext() {
        let fixture = StoreViewportCoordinatorFixture(
            restoreAnchorEventID: "anchor",
            isAtNewestWindow: false,
            pendingEventCount: 4
        )
        fixture.projection.applyResult = true

        #expect(fixture.coordinator.restoreProjectionAnchorEventID == "anchor")
        #expect(!fixture.coordinator.isTimelineAtNewestWindow)
        #expect(fixture.coordinator.pendingEventCount == 4)
        #expect(fixture.coordinator.applyProjectionViewportTransition(
            .resetToNewest
        ))
        #expect(fixture.projection.transitions == [.resetToNewest])
        #expect(fixture.contexts.readCount == 0)
    }

    @Test("同時のpending event適用は1処理を共有する")
    func coalescesConcurrentPendingEventApplications() async {
        let fixture = StoreViewportCoordinatorFixture()
        let gate = StoreViewportPendingEventsGate()

        await confirmation("pending event適用は1回だけ開始される") { started in
            fixture.interaction.onApplyPendingEvents = {
                started()
                return await gate.wait()
            }

            let first = Task {
                await fixture.coordinator.applyPendingNewEvents()
            }
            while !gate.isWaiting {
                await Task.yield()
            }
            let second = Task {
                await fixture.coordinator.applyPendingNewEvents()
            }
            await Task.yield()

            #expect(fixture.interaction.calls == [
                .applyPendingEvents(fixture.accountID)
            ])
            #expect(fixture.contexts.readCount == 1)

            gate.resume(returning: true)
            #expect(await first.value)
            #expect(await second.value)
        }
    }

    #if DEBUG
    @Test("debug用pending event置換も最新contextで転送する")
    func routesDebugPendingReplacement() {
        let fixture = StoreViewportCoordinatorFixture()

        fixture.coordinator.replacePendingEventIDs(["pending"])

        #expect(fixture.interaction.calls == [
            .replacePendingEventIDs(["pending"], fixture.accountID)
        ])
        #expect(fixture.contexts.readCount == 1)
    }
    #endif
}

@MainActor
private final class StoreViewportPendingEventsGate {
    private var continuation: CheckedContinuation<Bool, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
