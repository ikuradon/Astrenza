import Testing
@testable import Astrenza

@Suite("Home timeline published activity state")
@MainActor
struct PublishedActivityStateTests {
    @Test("The change mask updates only its selected activity fields")
    func changeMaskPreservesUnselectedFields() throws {
        let state = HomeTimelinePublishedActivityState(
            phase: .failed("initial"),
            isRefreshing: true,
            isLoadingOlder: false,
            isRealtime: true
        )
        let transition = activityTransition(
            phase: .loaded,
            isRefreshing: false,
            isLoadingOlder: true,
            isRealtime: false,
            changes: [.phase, .loadingOlder]
        )

        let next = try #require(state.applying(transition))

        #expect(next.phase == .loaded)
        #expect(next.isRefreshing)
        #expect(next.isLoadingOlder)
        #expect(next.isRealtime)
    }

    @Test("Refreshing and realtime changes copy their canonical snapshot values")
    func refreshAndRealtimeChangesApply() throws {
        let state = HomeTimelinePublishedActivityState()
        let transition = activityTransition(
            isRefreshing: true,
            isRealtime: true,
            changes: [.refreshing, .realtime]
        )

        let next = try #require(state.applying(transition))

        #expect(next.phase == .idle)
        #expect(next.isRefreshing)
        #expect(!next.isLoadingOlder)
        #expect(next.isRealtime)
    }

    @Test("Empty transitions avoid publication while selected fields preserve assignment")
    func emptyTransitionReturnsNil() throws {
        let state = HomeTimelinePublishedActivityState()
        let empty = activityTransition(phase: .loaded, changes: [])
        let selectedEqual = activityTransition(phase: .idle, changes: [.phase])

        #expect(state.applying(empty) == nil)
        let next = try #require(state.applying(selectedEqual))
        #expect(next.phase == .idle)
    }

    @Test("A selected activity field notifies its observer once")
    func selectedActivityFieldNotifiesOnce() {
        let store = HomeTimelineStoreFactory.make(eventStore: nil)
        let observation = observePublishedState(store.phase)
        let transition = activityTransition(
            phase: .loaded,
            isRefreshing: true,
            isLoadingOlder: true,
            isRealtime: true,
            changes: [.phase, .refreshing, .loadingOlder, .realtime]
        )

        store.testingApplyActivityTransition(transition)

        #expect(observation.count == 1)
        #expect(store.phase == .loaded)
        #expect(store.isRefreshing)
        #expect(store.isLoadingOlder)
        #expect(store.isHomeTimelineRealtime)
    }
}

private func activityTransition(
    phase: NostrHomeTimelinePhase = .idle,
    isRefreshing: Bool = false,
    isLoadingOlder: Bool = false,
    isRealtime: Bool = false,
    changes: HomeTimelineActivityChanges
) -> HomeTimelineActivityTransition {
    HomeTimelineActivityTransition(
        snapshot: HomeTimelineActivitySnapshot(
            phase: phase,
            isRefreshing: isRefreshing,
            isLoadingOlder: isLoadingOlder,
            isRealtime: isRealtime
        ),
        changes: changes
    )
}
