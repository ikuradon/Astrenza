import AstrenzaCore
import Combine
import Testing
@testable import Astrenza

@Suite("Home timeline published account context state")
@MainActor
struct PublishedAccountContextStateTests {
    @Test("Activation replaces account and sync policy atomically")
    func activationApplies() throws {
        let account = account()
        let policy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let state = HomeTimelinePublishedAccountContextState(
            syncPolicy: .default(networkType: .wifi)
        )

        let next = try #require(state.applying(.activate(
            account,
            syncPolicy: policy
        )))

        #expect(next.account == account)
        #expect(next.syncPolicy == policy)
    }

    @Test("Clear removes only the account and preserves its policy fallback")
    func clearPreservesSyncPolicy() throws {
        let policy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let state = HomeTimelinePublishedAccountContextState(
            account: account(),
            syncPolicy: policy
        )

        let next = try #require(state.applying(.clear))

        #expect(next.account == nil)
        #expect(next.syncPolicy == policy)
    }

    @Test("An unchanged transition avoids redundant state")
    func unchangedTransitionReturnsNil() {
        let account = account()
        let policy = NostrSyncPolicy.default(networkType: .wifi)
        let state = HomeTimelinePublishedAccountContextState(
            account: account,
            syncPolicy: policy
        )

        #expect(state.applying(.activate(
            account,
            syncPolicy: policy
        )) == nil)
    }

    @Test("The Store publishes each account context transition once")
    func storePublishesTransitionOnce() {
        let fallbackPolicy = NostrSyncPolicy.default(networkType: .wifi)
        let activePolicy = NostrSyncPolicy.default(
            networkType: .cellular,
            lowPowerMode: true
        )
        let account = account()
        let store = NostrHomeTimelineStore(
            eventStore: nil,
            syncPolicy: fallbackPolicy
        )
        var publicationCount = 0
        let observation = store.objectWillChange.sink { _ in
            publicationCount += 1
        }
        let transition = HomeTimelineAccountContextTransition.activate(
            account,
            syncPolicy: activePolicy
        )

        store.testingApplyAccountContextTransition(transition)
        store.testingApplyAccountContextTransition(transition)

        #expect(publicationCount == 1)
        #expect(store.account == account)
        #expect(store.currentSyncPolicy == activePolicy)

        store.testingApplyAccountContextTransition(.clear)

        #expect(publicationCount == 2)
        #expect(store.account == nil)
        #expect(store.currentSyncPolicy == activePolicy)
        withExtendedLifetime(observation) {}
    }

    private func account() -> NostrAccount {
        NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "account-context",
            readOnly: true
        )
    }
}
