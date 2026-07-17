import Foundation
import AstrenzaCore

@MainActor
final class NostrSessionStore: ObservableObject {
    @Published private(set) var account: NostrAccount?
    @Published private(set) var accounts: [NostrAccount] = []
    @Published private(set) var signer: (any NostrEventSigning)?
    @Published var loginInput = ""
    @Published private(set) var isLoggingIn = false
    @Published private(set) var errorMessage: String?

    private let resolver: NostrLoginResolver
    private let accountStorage: NostrSessionAccountStorage
    private let accountSummaryCoordinator: NostrAccountSummaryCoordinator

    init(
        resolver: NostrLoginResolver = NostrLoginResolver(),
        defaults: UserDefaults = .standard,
        restoreAccount: Bool = true,
        accountSummaryCoordinator: NostrAccountSummaryCoordinator = .init()
    ) {
        self.resolver = resolver
        accountStorage = NostrSessionAccountStorage(defaults: defaults)
        self.accountSummaryCoordinator = accountSummaryCoordinator
        if restoreAccount {
            let restored = accountStorage.restore()
            accounts = restored.accounts
            account = restored.selectedAccount
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
                installAccount(signingAccount.account, signer: signingAccount.signer)
                return
            }

            let resolved = try await resolver.resolve(loginInput)
            installAccount(resolved, signer: nil)
        } catch {
            errorMessage = loginErrorCopy(for: error)
        }
    }

    func prepareForLogin() {
        loginInput = ""
        errorMessage = nil
    }

    func logout() {
        account = nil
        accounts = []
        signer = nil
        accountStorage.clear()
    }

    func selectAccount(_ pubkey: String) {
        guard let selected = accounts.first(where: { $0.pubkey == pubkey }) else { return }
        account = selected
        signer = nil
        persistAccounts()
    }

    func removeAccount(_ pubkey: String) {
        accounts.removeAll { $0.pubkey == pubkey }
        if account?.pubkey == pubkey {
            account = accounts.first
            signer = nil
        }
        persistAccounts()
    }

    func accountSummaries(
        eventStore: NostrEventStore?,
        metadataRevision: Int
    ) -> [NostrAccountSummary] {
        accountSummaryCoordinator.summaries(
            accounts: accounts,
            selectedPubkey: account?.pubkey,
            eventStore: eventStore,
            metadataRevision: metadataRevision
        )
    }

    private func signingAccount(from input: String) throws -> (account: NostrAccount, signer: any NostrEventSigning) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("nsec1") || trimmed.hasPrefix("nostr:nsec1") else {
            throw NostrLoginError.unsupportedInput
        }

        let privateKeyHex = try NostrNIP19.privateKeyHex(from: trimmed)
        let signer = try NostrPrivateKeySigner(privateKeyHex: privateKeyHex)
        return (
            NostrAccount(pubkey: signer.pubkey, displayIdentifier: "nsec account", readOnly: false),
            signer
        )
    }

    private func installAccount(_ newAccount: NostrAccount, signer newSigner: (any NostrEventSigning)?) {
        accounts.removeAll { $0.pubkey == newAccount.pubkey }
        accounts.insert(newAccount, at: 0)
        account = newAccount
        signer = newSigner
        persistAccounts()
    }

    private func persistAccounts() {
        accountStorage.persist(accounts: accounts, selectedPubkey: account?.pubkey)
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
    private let storageKey = "astrenza.session.accounts"
    private let legacyStorageKey = "astrenza.readonly.account"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func restore() -> NostrSessionRestoration {
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(NostrSessionSnapshot.self, from: data) {
            return NostrSessionRestoration(
                accounts: uniqued(snapshot.accounts),
                selectedPubkey: snapshot.selectedPubkey
            )
        }

        guard let data = defaults.data(forKey: legacyStorageKey),
              let legacyAccount = try? JSONDecoder().decode(NostrAccount.self, from: data)
        else {
            return NostrSessionRestoration(accounts: [], selectedPubkey: nil)
        }

        return NostrSessionRestoration(accounts: [legacyAccount], selectedPubkey: legacyAccount.pubkey)
    }

    func persist(accounts: [NostrAccount], selectedPubkey: String?) {
        let snapshot = NostrSessionSnapshot(accounts: uniqued(accounts), selectedPubkey: selectedPubkey)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }

    private func uniqued(_ accounts: [NostrAccount]) -> [NostrAccount] {
        var seen: Set<String> = []
        return accounts.filter { account in
            guard !seen.contains(account.pubkey) else { return false }
            seen.insert(account.pubkey)
            return true
        }
    }
}

private struct NostrSessionSnapshot: Codable {
    let accounts: [NostrAccount]
    let selectedPubkey: String?
}

private struct NostrSessionRestoration {
    let accounts: [NostrAccount]
    let selectedPubkey: String?

    var selectedAccount: NostrAccount? {
        guard let selectedPubkey,
              let selected = accounts.first(where: { $0.pubkey == selectedPubkey })
        else {
            return accounts.first
        }
        return selected
    }
}
