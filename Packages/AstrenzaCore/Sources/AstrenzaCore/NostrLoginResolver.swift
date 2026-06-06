import Foundation

public enum NostrLoginError: Error, Equatable {
    case emptyInput
    case unsupportedInput
    case invalidNIP05
    case nip05NotFound
}

public struct NostrLoginResolver: Sendable {
    public var urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func resolve(_ input: String) async throws -> NostrAccount {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NostrLoginError.emptyInput
        }

        if isLikelyNIP05(trimmed) {
            let resolved = try await resolveNIP05(trimmed)
            return NostrAccount(pubkey: resolved.pubkey, displayIdentifier: resolved.identifier, readOnly: true)
        }

        do {
            let pubkey = try NostrNIP19.publicKeyHex(from: trimmed)
            return NostrAccount(pubkey: pubkey, displayIdentifier: trimmed, readOnly: true)
        } catch {
            throw NostrLoginError.unsupportedInput
        }
    }

    private func isLikelyNIP05(_ input: String) -> Bool {
        input.contains("@") && !input.hasPrefix("npub1") && !input.hasPrefix("nostr:")
    }

    private func resolveNIP05(_ input: String) async throws -> NIP05Resolution {
        let parts = input.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              parts[1].contains(".")
        else {
            throw NostrLoginError.invalidNIP05
        }

        let name = parts[0]
        let domain = parts[1]
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/.well-known/nostr.json"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else {
            throw NostrLoginError.invalidNIP05
        }

        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw NostrLoginError.nip05NotFound
        }

        let document = try JSONDecoder().decode(NIP05Document.self, from: data)
        guard let pubkey = document.names[name]?.lowercased(),
              NostrHex.isLowercaseHex(pubkey, byteCount: 32)
        else {
            throw NostrLoginError.nip05NotFound
        }

        return NIP05Resolution(pubkey: pubkey, identifier: input)
    }
}

private struct NIP05Document: Decodable {
    let names: [String: String]
}

private struct NIP05Resolution {
    let pubkey: String
    let identifier: String
}
