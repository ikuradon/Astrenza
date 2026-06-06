import Foundation
import AstrenzaCore

@MainActor
final class NostrSessionStore: ObservableObject {
    @Published private(set) var account: NostrAccount?
    @Published var loginInput = ""
    @Published private(set) var isLoggingIn = false
    @Published private(set) var errorMessage: String?

    private let resolver: NostrLoginResolver
    private let accountStorage: NostrSessionAccountStorage

    init(
        resolver: NostrLoginResolver = NostrLoginResolver(),
        defaults: UserDefaults = .standard,
        restoreAccount: Bool = true
    ) {
        self.resolver = resolver
        accountStorage = NostrSessionAccountStorage(defaults: defaults)
        if restoreAccount {
            account = accountStorage.restore()
        }
    }

    func login() async {
        isLoggingIn = true
        errorMessage = nil
        defer {
            isLoggingIn = false
        }

        do {
            let resolved = try await resolver.resolve(loginInput)
            account = resolved
            accountStorage.persist(resolved)
        } catch {
            errorMessage = loginErrorCopy(for: error)
        }
    }

    func logout() {
        account = nil
        accountStorage.clear()
    }

    private func loginErrorCopy(for error: Error) -> String {
        switch error {
        case NostrLoginError.emptyInput:
            "Enter npub, hex pubkey, or NIP-05."
        case NostrLoginError.unsupportedInput:
            "Use npub, 64-character hex pubkey, or name@example.com for read-only login."
        case NostrLoginError.invalidNIP05:
            "That NIP-05 address does not look valid."
        case NostrLoginError.nip05NotFound:
            "NIP-05 did not resolve to a public key."
        default:
            "Login failed: \(error.localizedDescription)"
        }
    }
}

private struct NostrSessionAccountStorage {
    private let defaults: UserDefaults
    private let storageKey = "astrenza.readonly.account"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func restore() -> NostrAccount? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(NostrAccount.self, from: data)
    }

    func persist(_ account: NostrAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
