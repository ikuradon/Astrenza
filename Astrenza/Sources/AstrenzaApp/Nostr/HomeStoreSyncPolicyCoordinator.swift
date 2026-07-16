import AstrenzaCore

@MainActor
protocol HomeStoreSyncPolicySourcing: AnyObject {
    var accountContext: HomeTimelinePublishedAccountContextState { get }
}

extension HomeTimelinePublishedStateCoordinator:
    HomeStoreSyncPolicySourcing {}

@MainActor
protocol HomeStoreAccountRestarting: AnyObject {
    func restart(account: NostrAccount)
}

extension HomeStoreLifecycleCoordinator: HomeStoreAccountRestarting {}

@MainActor
final class HomeStoreSyncPolicyCoordinator {
    private let source: any HomeStoreSyncPolicySourcing
    private let lifecycle: any HomeStoreAccountRestarting
    private let settingsStore: NostrSyncPolicySettingsStore

    init(
        source: any HomeStoreSyncPolicySourcing,
        lifecycle: any HomeStoreAccountRestarting,
        settingsStore: NostrSyncPolicySettingsStore
    ) {
        self.source = source
        self.lifecycle = lifecycle
        self.settingsStore = settingsStore
    }

    func apply(_ policy: NostrSyncPolicy, accountID: String?) {
        settingsStore.save(policy, accountID: accountID)
        let context = source.accountContext
        guard let account = context.account,
              account.pubkey == accountID,
              context.syncPolicy != policy
        else { return }
        lifecycle.restart(account: account)
    }
}
