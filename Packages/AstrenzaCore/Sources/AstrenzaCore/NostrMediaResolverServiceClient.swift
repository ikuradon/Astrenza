import Foundation

public struct NostrMediaResolverServiceConfiguration: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
    public let serviceURL: URL?
    public let bearerToken: String
    public let isEnabled: Bool

    public init(
        serviceURLString: String,
        bearerToken: String,
        isEnabled: Bool = true
    ) {
        let trimmedURL = serviceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmedURL)
        self.serviceURL = Self.validatedServiceURL(url)
        self.bearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }

    public init(
        serviceURL: URL?,
        bearerToken: String,
        isEnabled: Bool = true
    ) {
        self.serviceURL = Self.validatedServiceURL(serviceURL)
        self.bearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
    }

    public var isUsable: Bool {
        isEnabled && serviceURL != nil && !bearerToken.isEmpty
    }

    public var description: String {
        let serviceURLDescription = Self.redactedURLDescription(serviceURL)
        return "NostrMediaResolverServiceConfiguration(serviceURL: \(serviceURLDescription), bearerToken: <redacted>, isEnabled: \(isEnabled))"
    }

    public var debugDescription: String {
        description
    }

    var resolveEndpointURL: URL? {
        guard isUsable, let serviceURL else { return nil }
        var components = URLComponents(url: serviceURL, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = ([basePath, "v1", "resolve"].filter { !$0.isEmpty }).joined(separator: "/")
        components?.path = endpointPath.hasPrefix("/") ? endpointPath : "/" + endpointPath
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private static func validatedServiceURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", isLoopbackHost(url.host) { return url }
        return nil
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private static func redactedURLDescription(_ url: URL?) -> String {
        guard let url else { return "nil" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? "nil"
    }
}

public enum NostrMediaResolverResolveKind: String, Codable, Sendable {
    case auto
    case html
    case image
}

public struct NostrMediaResolverResolveItem: Codable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let kind: NostrMediaResolverResolveKind

    public init(id: String, url: String, kind: NostrMediaResolverResolveKind = .auto) {
        self.id = id
        self.url = url
        self.kind = kind
    }
}

public struct NostrMediaResolverResolveResult: Decodable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let kind: String
    public let url: String
    public let finalURL: String
    public let title: String?
    public let description: String?
    public let siteName: String?
    public let image: NostrMediaResolverResolvedImage?
    public let cacheTTLSeconds: Int
    public let warnings: [String]
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case kind
        case url
        case finalURL = "finalUrl"
        case title
        case description
        case siteName
        case image
        case cacheTTLSeconds = "cacheTtlSeconds"
        case warnings
        case error
    }
}

public struct NostrMediaResolverResolvedImage: Decodable, Equatable, Sendable {
    public let url: String
    public let optimizedURL: String?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let blurhash: String?

    private enum CodingKeys: String, CodingKey {
        case url
        case optimizedURL = "optimizedUrl"
        case mimeType
        case width
        case height
        case blurhash
    }
}

public struct NostrMediaResolverServiceClient: CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    public let configuration: NostrMediaResolverServiceConfiguration
    public let dataLoader: NostrHTTPDataLoader

    public init(
        configuration: NostrMediaResolverServiceConfiguration,
        dataLoader: @escaping NostrHTTPDataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.configuration = configuration
        self.dataLoader = dataLoader
    }

    public var description: String {
        "NostrMediaResolverServiceClient(configuration: \(configuration), dataLoader: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public func resolve(items: [NostrMediaResolverResolveItem]) async throws -> [NostrMediaResolverResolveResult] {
        guard let endpointURL = configuration.resolveEndpointURL else {
            throw NostrMediaResolverServiceClientError.unusableConfiguration
        }

        var request = URLRequest(url: endpointURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(NostrMediaResolverResolveRequest(items: items))

        let (data, response) = try await dataLoader(request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw NostrMediaResolverServiceClientError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(NostrMediaResolverResolveResponse.self, from: data).results
    }
}

public enum NostrMediaResolverServiceClientError: Error, Equatable, Sendable {
    case unusableConfiguration
    case httpStatus(Int)
}

private struct NostrMediaResolverResolveRequest: Encodable {
    let items: [NostrMediaResolverResolveItem]
}

private struct NostrMediaResolverResolveResponse: Decodable {
    let results: [NostrMediaResolverResolveResult]
}
