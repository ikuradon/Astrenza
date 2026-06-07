import Foundation

public typealias NostrHTTPDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public enum NostrNIP05Status: String, Codable, Equatable, Sendable {
    case absent
    case unchecked
    case verified
    case invalid
    case failed
}

public struct NostrNIP05Resolution: Codable, Equatable, Sendable {
    public let identifier: String
    public let pubkey: String?
    public let relays: [String]
    public let status: NostrNIP05Status
    public let resolvedAt: Date

    public init(
        identifier: String,
        pubkey: String?,
        relays: [String],
        status: NostrNIP05Status,
        resolvedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.pubkey = pubkey
        self.relays = relays
        self.status = status
        self.resolvedAt = resolvedAt
    }
}

public protocol NostrNIP05Resolving: Sendable {
    func resolve(identifier: String, expectedPubkey: String?) async -> NostrNIP05Resolution
}

public actor NostrNIP05Cache {
    private let defaults: UserDefaults?
    private let key: String
    private var resolutions: [String: NostrNIP05Resolution]

    public init(defaults: UserDefaults? = .standard, key: String = "nostr.nip05.cache") {
        self.defaults = defaults
        self.key = key
        if let data = defaults?.data(forKey: key),
           let cached = try? JSONDecoder().decode([String: NostrNIP05Resolution].self, from: data) {
            resolutions = cached
        } else {
            resolutions = [:]
        }
    }

    public func resolution(for identifier: String, expectedPubkey: String?) -> NostrNIP05Resolution? {
        resolutions[cacheKey(identifier: identifier, expectedPubkey: expectedPubkey)]
    }

    public func store(_ resolution: NostrNIP05Resolution, expectedPubkey: String?) {
        resolutions[cacheKey(identifier: resolution.identifier, expectedPubkey: expectedPubkey)] = resolution
        persist()
    }

    private func cacheKey(identifier: String, expectedPubkey: String?) -> String {
        "\(identifier.lowercased())|\(expectedPubkey?.lowercased() ?? "*")"
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(resolutions) else { return }
        defaults.set(data, forKey: key)
    }
}

public struct NostrNIP05Resolver: NostrNIP05Resolving {
    public let cache: NostrNIP05Cache?
    public let dataLoader: NostrHTTPDataLoader

    public init(
        cache: NostrNIP05Cache? = NostrNIP05Cache(),
        dataLoader: @escaping NostrHTTPDataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.cache = cache
        self.dataLoader = dataLoader
    }

    public func resolve(identifier: String, expectedPubkey: String?) async -> NostrNIP05Resolution {
        let normalizedIdentifier = NostrNIP05Address.normalizedIdentifier(identifier)
            ?? identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            return NostrNIP05Resolution(identifier: identifier, pubkey: nil, relays: [], status: .absent)
        }

        if let cached = await cache?.resolution(for: normalizedIdentifier, expectedPubkey: expectedPubkey) {
            return cached
        }

        guard let address = NostrNIP05Address.parse(normalizedIdentifier),
              let request = address.request
        else {
            let resolution = NostrNIP05Resolution(identifier: normalizedIdentifier, pubkey: nil, relays: [], status: .invalid)
            await cache?.store(resolution, expectedPubkey: expectedPubkey)
            return resolution
        }

        do {
            let (data, response) = try await dataLoader(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let document = try? JSONDecoder().decode(NostrNIP05Document.self, from: data)
            else {
                let resolution = NostrNIP05Resolution(identifier: normalizedIdentifier, pubkey: nil, relays: [], status: .failed)
                await cache?.store(resolution, expectedPubkey: expectedPubkey)
                return resolution
            }

            let resolvedPubkey = document.names[address.name]?.lowercased()
            let relays = resolvedPubkey.flatMap { document.relays?[$0] } ?? []
            let status: NostrNIP05Status
            if let resolvedPubkey, NostrHex.isLowercaseHex(resolvedPubkey, byteCount: 32) {
                if let expectedPubkey {
                    status = resolvedPubkey == expectedPubkey.lowercased() ? .verified : .invalid
                } else {
                    status = .verified
                }
            } else {
                status = .invalid
            }

            let resolution = NostrNIP05Resolution(
                identifier: normalizedIdentifier,
                pubkey: resolvedPubkey,
                relays: relays,
                status: status
            )
            await cache?.store(resolution, expectedPubkey: expectedPubkey)
            return resolution
        } catch {
            let resolution = NostrNIP05Resolution(identifier: normalizedIdentifier, pubkey: nil, relays: [], status: .failed)
            await cache?.store(resolution, expectedPubkey: expectedPubkey)
            return resolution
        }
    }
}

public struct NostrNIP05Address: Equatable, Sendable {
    public let name: String
    public let domain: String

    public static func normalizedIdentifier(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parse(trimmed) {
            return "\(parsed.name)@\(parsed.domain)"
        }

        guard isBareDomain(trimmed) else { return nil }
        return "_@\(trimmed.lowercased())"
    }

    public static func parse(_ identifier: String) -> NostrNIP05Address? {
        let parts = identifier.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              parts[1].contains(".")
        else { return nil }

        return NostrNIP05Address(name: parts[0], domain: parts[1].lowercased())
    }

    private static func isBareDomain(_ input: String) -> Bool {
        let domain = input.lowercased()
        guard domain.contains("."),
              !domain.contains("@"),
              !domain.contains("/"),
              !domain.contains(":"),
              domain.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }

    public var request: URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/.well-known/nostr.json"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        return request
    }
}

private struct NostrNIP05Document: Decodable {
    let names: [String: String]
    let relays: [String: [String]]?
}
