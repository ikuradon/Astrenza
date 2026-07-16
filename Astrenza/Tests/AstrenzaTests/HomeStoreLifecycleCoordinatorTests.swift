import Testing
@testable import Astrenza

@Suite("Home Store lifecycle coordinator")
@MainActor
struct HomeStoreLifecycleCoordinatorTests {
    @Test("account開始は最新contextとaccountを境界へ渡す")
    func startReadsFreshContext() {
        let fixture = StoreLifecycleCoordinatorFixture()

        fixture.coordinator.start(account: fixture.contextFixture.account)
        fixture.contextFixture.clearSnapshots()
        fixture.coordinator.start(account: fixture.contextFixture.account)

        #expect(fixture.contexts.reads == [
            .accountStart,
            .accountStart
        ])
        #expect(fixture.accountStart.calls == [
            StoreAccountStartSpy.Call(
                accountID: fixture.contextFixture.account.pubkey,
                hasRelayRuntime: true
            ),
            StoreAccountStartSpy.Call(
                accountID: fixture.contextFixture.account.pubkey,
                hasRelayRuntime: false
            )
        ])
    }

    @Test("停止はmaterializationをcancelしてから最新contextでaccountをresetする")
    func cancelPreservesCleanupOrder() {
        let fixture = StoreLifecycleCoordinatorFixture()

        fixture.coordinator.cancel()

        #expect(fixture.order.steps == [
            .cancelMaterialization,
            .resetAccount
        ])
        #expect(fixture.contexts.reads == [.accountReset])
        #expect(fixture.accountReset.calls == [
            StoreAccountResetSpy.Call(
                resolvedRelays: ["wss://relay.example"],
                readBoundaryScopeID: fixture.contextFixture.account.pubkey
            )
        ])
    }

    @Test("refreshとolder loadは各実行時のaccount・lifecycle・最新contextを渡す")
    func loadsReadFreshContexts() async {
        let fixture = StoreLifecycleCoordinatorFixture()

        await fixture.coordinator.refreshLatest(
            account: fixture.contextFixture.account,
            lifecycle: fixture.contextFixture.lifecycle
        )
        fixture.contextFixture.clearSnapshots()
        await fixture.coordinator.loadOlder(
            account: fixture.contextFixture.account,
            lifecycle: fixture.contextFixture.lifecycle
        )

        #expect(fixture.contexts.reads == [.load, .load])
        #expect(fixture.load.calls == [
            .refreshLatest(
                accountID: fixture.contextFixture.account.pubkey,
                lifecycle: fixture.contextFixture.lifecycle,
                state: HomeTimelineLoadInteractionState(
                    hasRelayRuntime: true,
                    hasTimelineEvents: true
                )
            ),
            .loadOlder(
                accountID: fixture.contextFixture.account.pubkey,
                lifecycle: fixture.contextFixture.lifecycle,
                state: HomeTimelineLoadInteractionState(
                    hasRelayRuntime: false,
                    hasTimelineEvents: false
                )
            )
        ])
    }
}
