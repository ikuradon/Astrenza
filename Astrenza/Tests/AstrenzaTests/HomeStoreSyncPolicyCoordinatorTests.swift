import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home Store sync policy coordinator")
@MainActor
struct HomeStoreSyncPolicyCoordinatorTests {
    @Test("選択中アカウントのモード変更を保存して同期を再起動する")
    func restartsActiveAccountAfterSavingPolicy() throws {
        let fixture = try fixture()

        fixture.coordinator.apply(
            fixture.fullOutboxPolicy,
            accountID: fixture.account.pubkey
        )

        #expect(fixture.settingsStore.policy(
            accountID: fixture.account.pubkey
        ) == fixture.fullOutboxPolicy)
        #expect(fixture.lifecycle.restartedAccounts == [fixture.account])
    }

    @Test("別アカウントのモード変更は保存だけ行い現在の同期を維持する")
    func doesNotRestartInactiveAccount() throws {
        let fixture = try fixture()
        let inactiveAccountID = String(repeating: "b", count: 64)

        fixture.coordinator.apply(
            fixture.fullOutboxPolicy,
            accountID: inactiveAccountID
        )

        #expect(fixture.settingsStore.policy(
            accountID: inactiveAccountID
        ) == fixture.fullOutboxPolicy)
        #expect(fixture.lifecycle.restartedAccounts.isEmpty)
    }

    private func fixture() throws -> SyncPolicyCoordinatorFixture {
        let suiteName = "HomeStoreSyncPolicyCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "active",
            readOnly: true
        )
        let currentPolicy = NostrSyncPolicy.default(networkType: .wifi)
        let settingsStore = NostrSyncPolicySettingsStore(defaults: defaults)
        let source = SyncPolicySourceSpy(
            accountContext: HomeTimelinePublishedAccountContextState(
                account: account,
                syncPolicy: currentPolicy
            )
        )
        let lifecycle = SyncPolicyLifecycleSpy()
        let coordinator = HomeStoreSyncPolicyCoordinator(
            source: source,
            lifecycle: lifecycle,
            settingsStore: settingsStore
        )
        return SyncPolicyCoordinatorFixture(
            account: account,
            settingsStore: settingsStore,
            lifecycle: lifecycle,
            coordinator: coordinator
        )
    }
}

@MainActor
private struct SyncPolicyCoordinatorFixture {
    let account: NostrAccount
    let settingsStore: NostrSyncPolicySettingsStore
    let lifecycle: SyncPolicyLifecycleSpy
    let coordinator: HomeStoreSyncPolicyCoordinator

    let fullOutboxPolicy = NostrSyncPolicy(
        mode: .fullOutbox,
        networkType: .wifi,
        lowPowerMode: false,
        tapToLoadMedia: false,
        queueOGPPreviews: true,
        disableOGPOnCellular: false
    )
}

@MainActor
private final class SyncPolicySourceSpy: HomeStoreSyncPolicySourcing {
    let accountContext: HomeTimelinePublishedAccountContextState

    init(accountContext: HomeTimelinePublishedAccountContextState) {
        self.accountContext = accountContext
    }
}

@MainActor
private final class SyncPolicyLifecycleSpy: HomeStoreAccountRestarting {
    private(set) var restartedAccounts: [NostrAccount] = []

    func restart(account: NostrAccount) {
        restartedAccounts.append(account)
    }
}
