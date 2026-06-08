import AstrenzaCore
import Foundation

@MainActor
struct NostrSyncPolicySettingsStore {
    static let shared = NostrSyncPolicySettingsStore()

    private let defaults: UserDefaults
    private let keyPrefix = "astrenza.sync-policy"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func policy(
        accountID: String?,
        fallback: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> NostrSyncPolicy {
        guard let data = defaults.data(forKey: key(for: accountID)),
              let policy = try? JSONDecoder().decode(NostrSyncPolicy.self, from: data)
        else {
            return fallback
        }
        return policy
    }

    func save(_ policy: NostrSyncPolicy, accountID: String?) {
        guard let data = try? JSONEncoder().encode(policy) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    private func key(for accountID: String?) -> String {
        "\(keyPrefix).\(accountID ?? "global")"
    }
}
