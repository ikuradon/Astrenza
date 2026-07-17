import Foundation
import NostrProtocol

public enum NostrLoginError: Error, Equatable {
    case emptyInput
    case unsupportedInput
    case invalidNIP05
    case nip05NotFound
}

public struct NostrLoginResolver: Sendable {
    public var nip05Resolver: any NostrNIP05Resolving

    public init(nip05Resolver: any NostrNIP05Resolving = NostrNIP05Resolver(cache: nil)) {
        self.nip05Resolver = nip05Resolver
    }

    public func resolve(_ input: String) async throws -> NostrAccount {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NostrLoginError.emptyInput
        }

        if isLikelyNIP05(trimmed) {
            guard let normalizedIdentifier = NostrNIP05Address.normalizedIdentifier(trimmed) else {
                throw NostrLoginError.invalidNIP05
            }
            let resolved = await nip05Resolver.resolve(identifier: normalizedIdentifier, expectedPubkey: nil)
            guard let pubkey = resolved.pubkey,
                  NostrHex.isLowercaseHex(pubkey, byteCount: 32),
                  resolved.status == .verified
            else {
                throw NostrLoginError.nip05NotFound
            }
            return NostrAccount(
                pubkey: pubkey,
                displayIdentifier: resolved.identifier,
                readOnly: true,
                discoveryRelays: resolved.relays
            )
        }

        do {
            let pubkey = try NostrNIP19.publicKeyHex(from: trimmed)
            return NostrAccount(pubkey: pubkey, displayIdentifier: trimmed, readOnly: true)
        } catch {
            throw NostrLoginError.unsupportedInput
        }
    }

    private func isLikelyNIP05(_ input: String) -> Bool {
        guard !input.hasPrefix("npub1"),
              !input.hasPrefix("nostr:")
        else { return false }

        return NostrNIP05Address.normalizedIdentifier(input) != nil
    }

}
