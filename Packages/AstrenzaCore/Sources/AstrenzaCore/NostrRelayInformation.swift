import Foundation

public struct NostrRelayInformationDocument: Codable, Equatable, Sendable {
    public let name: String?
    public let description: String?
    public let pubkey: String?
    public let contact: String?
    public let supportedNips: [Int]
    public let software: String?
    public let version: String?
    public let limitation: NostrRelayLimitation?

    public init(
        name: String?,
        description: String?,
        pubkey: String?,
        contact: String?,
        supportedNips: [Int],
        software: String?,
        version: String?,
        limitation: NostrRelayLimitation?
    ) {
        self.name = name
        self.description = description
        self.pubkey = pubkey
        self.contact = contact
        self.supportedNips = supportedNips
        self.software = software
        self.version = version
        self.limitation = limitation
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case pubkey
        case contact
        case supportedNips = "supported_nips"
        case software
        case version
        case limitation
    }
}

public struct NostrRelayLimitation: Codable, Equatable, Sendable {
    public let maxMessageLength: Int?
    public let maxSubscriptions: Int?
    public let maxLimit: Int?
    public let maxSubIDLength: Int?
    public let authRequired: Bool?
    public let paymentRequired: Bool?
    public let restrictedWrites: Bool?

    public init(
        maxMessageLength: Int? = nil,
        maxSubscriptions: Int? = nil,
        maxLimit: Int? = nil,
        maxSubIDLength: Int? = nil,
        authRequired: Bool? = nil,
        paymentRequired: Bool? = nil,
        restrictedWrites: Bool? = nil
    ) {
        self.maxMessageLength = maxMessageLength
        self.maxSubscriptions = maxSubscriptions
        self.maxLimit = maxLimit
        self.maxSubIDLength = maxSubIDLength
        self.authRequired = authRequired
        self.paymentRequired = paymentRequired
        self.restrictedWrites = restrictedWrites
    }

    enum CodingKeys: String, CodingKey {
        case maxMessageLength = "max_message_length"
        case maxSubscriptions = "max_subscriptions"
        case maxLimit = "max_limit"
        case maxSubIDLength = "max_subid_length"
        case authRequired = "auth_required"
        case paymentRequired = "payment_required"
        case restrictedWrites = "restricted_writes"
    }
}

public protocol NostrRelayInformationFetching: Sendable {
    func information(for relayURL: String) async throws -> NostrRelayInformationDocument
}

public actor NostrRelayInformationCache {
    private let defaults: UserDefaults?
    private let key: String
    private var documents: [String: NostrRelayInformationDocument]

    public init(defaults: UserDefaults? = .standard, key: String = "nostr.relay.info.cache") {
        self.defaults = defaults
        self.key = key
        if let data = defaults?.data(forKey: key),
           let cached = try? JSONDecoder().decode([String: NostrRelayInformationDocument].self, from: data) {
            documents = Dictionary(
                cached.compactMap { key, value in
                    NostrRelayURL(key, mode: .userFacing).map { ($0.rawValue, value) }
                },
                uniquingKeysWith: { _, latest in latest }
            )
        } else {
            documents = [:]
        }
    }

    public func document(for relayURL: String) -> NostrRelayInformationDocument? {
        guard let identity = NostrRelayURL(relayURL, mode: .userFacing) else { return nil }
        return documents[identity.rawValue]
    }

    public func store(_ document: NostrRelayInformationDocument, for relayURL: String) {
        guard let identity = NostrRelayURL(relayURL, mode: .userFacing) else { return }
        documents[identity.rawValue] = document
        persist()
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(documents) else { return }
        defaults.set(data, forKey: key)
    }
}

public struct NostrRelayInformationClient: NostrRelayInformationFetching {
    public let cache: NostrRelayInformationCache
    public let dataLoader: NostrHTTPDataLoader

    public init(
        cache: NostrRelayInformationCache = NostrRelayInformationCache(),
        dataLoader: @escaping NostrHTTPDataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.cache = cache
        self.dataLoader = dataLoader
    }

    public func information(for relayURL: String) async throws -> NostrRelayInformationDocument {
        if let cached = await cache.document(for: relayURL) {
            return cached
        }

        let request = try relayInformationRequest(for: relayURL)
        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let document = try JSONDecoder().decode(NostrRelayInformationDocument.self, from: data)
        await cache.store(document, for: relayURL)
        return document
    }

    public func relayInformationRequest(for relayURL: String) throws -> URLRequest {
        guard var components = URLComponents(string: relayURL) else {
            throw URLError(.badURL)
        }

        switch components.scheme?.lowercased() {
        case "wss":
            components.scheme = "https"
        case "ws":
            components.scheme = "http"
        case "https", "http":
            break
        default:
            throw URLError(.unsupportedURL)
        }

        if components.path.isEmpty {
            components.path = "/"
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
        return request
    }
}
