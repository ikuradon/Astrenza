import Foundation
import AstrenzaCore

@MainActor
final class NostrSessionStore: ObservableObject {
    @Published private(set) var account: NostrAccount?
    @Published private(set) var signer: (any NostrEventSigning)?
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
            if let signingAccount = try? signingAccount(from: loginInput) {
                account = signingAccount.account
                signer = signingAccount.signer
                return
            }

            let resolved = try await resolver.resolve(loginInput)
            account = resolved
            signer = nil
            accountStorage.persist(resolved)
        } catch {
            errorMessage = loginErrorCopy(for: error)
        }
    }

    func logout() {
        account = nil
        signer = nil
        accountStorage.clear()
    }

    private func signingAccount(from input: String) throws -> (account: NostrAccount, signer: any NostrEventSigning) {
        let privateKeyHex = try NostrNIP19.privateKeyHex(from: input)
        let signer = try NostrPrivateKeySigner(privateKeyHex: privateKeyHex)
        return (
            NostrAccount(pubkey: signer.pubkey, displayIdentifier: "nsec account", readOnly: false),
            signer
        )
    }

    private func loginErrorCopy(for error: Error) -> String {
        switch error {
        case NostrLoginError.emptyInput:
            "Enter npub, hex pubkey, or NIP-05."
        case NostrLoginError.unsupportedInput:
            "Use npub, nsec, 64-character hex pubkey, or name@example.com."
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
