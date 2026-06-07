import Foundation
import AstrenzaCore
import SwiftUI

struct NostrAccountSummary: Identifiable {
    let id: String
    let account: NostrAccount
    let title: String
    let subtitle: String
    let npub: String
    let avatarStyle: AvatarStyle
    let isSelected: Bool
    let isReadOnly: Bool

    var signerLabel: String {
        isReadOnly ? "Read-only" : "Local signer"
    }
}

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

    init(
        resolver: NostrLoginResolver = NostrLoginResolver(),
        defaults: UserDefaults = .standard,
        restoreAccount: Bool = true
    ) {
        self.resolver = resolver
        accountStorage = NostrSessionAccountStorage(defaults: defaults)
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

    func accountSummaries(eventStore: NostrEventStore?) -> [NostrAccountSummary] {
        accounts.map { accountSummary(for: $0, eventStore: eventStore) }
    }

    func accountSummary(for account: NostrAccount, eventStore: NostrEventStore?) -> NostrAccountSummary {
        let metadataEvent = try? eventStore?.latestReplaceableEvent(pubkey: account.pubkey, kind: 0)
        let metadata = metadataEvent.flatMap(Self.profileMetadata)
        let npub = NIP19Display.npub(fromHexPubkey: account.pubkey) ?? account.pubkey
        let title = metadata?.bestName ?? fallbackTitle(for: account, npub: npub)
        let subtitle = clean(metadata?.nip05) ?? (account.readOnly ? "Read-only" : "Local signer")

        return NostrAccountSummary(
            id: account.pubkey,
            account: account,
            title: title,
            subtitle: subtitle,
            npub: abbreviated(npub),
            avatarStyle: avatarStyle(pubkey: account.pubkey, pictureURL: metadata?.pictureURL),
            isSelected: self.account?.pubkey == account.pubkey,
            isReadOnly: account.readOnly
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

    private func fallbackTitle(for account: NostrAccount, npub: String) -> String {
        guard let identifier = clean(account.displayIdentifier),
              identifier != "nsec account"
        else {
            return abbreviated(npub)
        }
        return identifier
    }

    private func avatarStyle(pubkey: String, pictureURL: URL?) -> AvatarStyle {
        let palette = Self.avatarPalette(for: pubkey)
        return AvatarStyle(
            primary: palette.primary,
            secondary: palette.secondary,
            symbolName: palette.symbolName,
            pictureState: pictureURL == nil ? .missing : .resolved,
            placeholderSeed: pubkey,
            imageURL: pictureURL
        )
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
    }

    private static func avatarPalette(for pubkey: String) -> (primary: Color, secondary: Color, symbolName: String) {
        let colors: [(Color, Color)] = [
            (.purple, .cyan),
            (.indigo, .pink),
            (.mint, .blue),
            (.orange, .yellow),
            (.teal, .green),
            (.red, .purple),
            (.blue, .white)
        ]
        let symbols = [
            "sparkles",
            "antenna.radiowaves.left.and.right",
            "quote.bubble.fill",
            "arrow.2.circlepath",
            "terminal.fill",
            "camera.aperture",
            "person.fill"
        ]
        let index = deterministicIndex(for: pubkey, modulo: colors.count)
        let symbolIndex = deterministicIndex(for: String(pubkey.reversed()), modulo: symbols.count)
        return (colors[index].0, colors[index].1, symbols[symbolIndex])
    }

    private static func deterministicIndex(for value: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        let total = value.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return total % modulo
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(12))...\(value.suffix(6))"
    }

    private func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
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
