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
final class NostrAccountSummaryCoordinator {
    typealias MetadataEventLoader = (
        _ eventStore: NostrEventStore?,
        _ pubkeys: Set<String>
    ) -> [NostrEvent]

    private struct CacheKey: Equatable {
        let accounts: [NostrAccount]
        let selectedPubkey: String?
        let metadataRevision: Int
        let eventStoreIdentity: ObjectIdentifier?
    }

    private struct AvatarPalette {
        let primary: Color
        let secondary: Color
        let symbolName: String
    }

    private let metadataEventLoader: MetadataEventLoader
    private var cachedKey: CacheKey?
    private var cachedSummaries: [NostrAccountSummary] = []

    init(metadataEventLoader: MetadataEventLoader? = nil) {
        self.metadataEventLoader = metadataEventLoader ?? Self.loadMetadataEvents
    }

    func summaries(
        accounts: [NostrAccount],
        selectedPubkey: String?,
        eventStore: NostrEventStore?,
        metadataRevision: Int
    ) -> [NostrAccountSummary] {
        let key = CacheKey(
            accounts: accounts,
            selectedPubkey: selectedPubkey,
            metadataRevision: metadataRevision,
            eventStoreIdentity: eventStore.map { ObjectIdentifier($0) }
        )
        if cachedKey == key {
            return cachedSummaries
        }

        let metadataByPubkey = metadataByPubkey(
            eventStore: eventStore,
            pubkeys: Set(accounts.map(\.pubkey))
        )
        let summaries = accounts.map { account in
            summary(
                for: account,
                metadata: metadataByPubkey[account.pubkey],
                selectedPubkey: selectedPubkey
            )
        }
        cachedKey = key
        cachedSummaries = summaries
        return summaries
    }

    private func metadataByPubkey(
        eventStore: NostrEventStore?,
        pubkeys: Set<String>
    ) -> [String: NostrProfileMetadata] {
        guard !pubkeys.isEmpty else { return [:] }
        return metadataEventLoader(eventStore, pubkeys).reduce(into: [:]) { result, event in
            guard result[event.pubkey] == nil,
                  let metadata = Self.profileMetadata(from: event)
            else { return }
            result[event.pubkey] = metadata
        }
    }

    private func summary(
        for account: NostrAccount,
        metadata: NostrProfileMetadata?,
        selectedPubkey: String?
    ) -> NostrAccountSummary {
        let npub = NIP19Display.npub(fromHexPubkey: account.pubkey) ?? account.pubkey
        let title = metadata?.bestName ?? fallbackTitle(for: account, npub: npub)
        let subtitle = clean(metadata?.nip05) ?? (account.readOnly ? "Read-only" : "Local signer")

        return NostrAccountSummary(
            id: account.pubkey,
            account: account,
            title: title,
            subtitle: subtitle,
            npub: abbreviated(npub),
            avatarStyle: avatarStyle(
                pubkey: account.pubkey,
                pictureURL: metadata?.pictureURL
            ),
            isSelected: selectedPubkey == account.pubkey,
            isReadOnly: account.readOnly
        )
    }

    private static func loadMetadataEvents(
        eventStore: NostrEventStore?,
        pubkeys: Set<String>
    ) -> [NostrEvent] {
        guard let eventStore else { return [] }
        return (try? eventStore.latestReplaceableEvents(
            pubkeys: pubkeys,
            kind: 0
        )) ?? []
    }

    private static func profileMetadata(from event: NostrEvent) -> NostrProfileMetadata? {
        guard let data = event.content.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrProfileMetadata.self, from: data)
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

    private static func avatarPalette(
        for pubkey: String
    ) -> AvatarPalette {
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
        let symbolIndex = deterministicIndex(
            for: String(pubkey.reversed()),
            modulo: symbols.count
        )
        return AvatarPalette(
            primary: colors[index].0,
            secondary: colors[index].1,
            symbolName: symbols[symbolIndex]
        )
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
}
