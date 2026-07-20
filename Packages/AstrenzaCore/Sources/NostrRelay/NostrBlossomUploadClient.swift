import CryptoKit
import Foundation
import NostrCryptoAPI
import NostrProtocol

public struct NostrUploadedBlob: Codable, Equatable, Sendable {
    public let url: URL
    public let sha256: String
    public let size: Int
    public let type: String?
    public let uploaded: Int?

    public init(
        url: URL,
        sha256: String,
        size: Int,
        type: String?,
        uploaded: Int?
    ) {
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.type = type
        self.uploaded = uploaded
    }
}

public enum NostrBlossomUploadError: Error, Equatable, Sendable {
    case invalidServerURL
    case invalidResponse
    case rejected(statusCode: Int)
    case descriptorHashMismatch(expected: String, actual: String)
    case descriptorSizeMismatch(expected: Int, actual: Int)
}

public struct NostrBlossomUploadClient: Sendable {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func upload(
        data: Data,
        mimeType: String,
        serverURL: URL,
        accountID: String,
        signer: any NostrEventSigning,
        now: Int = Int(Date().timeIntervalSince1970)
    ) async throws -> NostrUploadedBlob {
        let sha256 = Self.sha256Hex(data)
        let endpoint = try uploadEndpoint(serverURL: serverURL)
        let authEvent = try await signer.sign(NostrUnsignedEvent(
            pubkey: accountID,
            createdAt: now,
            kind: 24_242,
            tags: [
                ["t", "upload"],
                ["x", sha256],
                ["expiration", String(now + 300)],
                ["server", (serverURL.host ?? serverURL.absoluteString).lowercased()]
            ],
            content: "Upload blob"
        ))
        let authData = try JSONEncoder().encode(authEvent)
        let authorization = authData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue(sha256, forHTTPHeaderField: "X-SHA-256")
        request.setValue("Nostr \(authorization)", forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await urlSession.upload(
            for: request,
            from: data
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NostrBlossomUploadError.invalidResponse
        }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NostrBlossomUploadError.rejected(
                statusCode: httpResponse.statusCode
            )
        }
        let descriptor = try JSONDecoder().decode(
            NostrUploadedBlob.self,
            from: responseData
        )
        guard descriptor.sha256.lowercased() == sha256 else {
            throw NostrBlossomUploadError.descriptorHashMismatch(
                expected: sha256,
                actual: descriptor.sha256
            )
        }
        guard descriptor.size == data.count else {
            throw NostrBlossomUploadError.descriptorSizeMismatch(
                expected: data.count,
                actual: descriptor.size
            )
        }
        guard descriptor.url.scheme == "https" || descriptor.url.scheme == "http" else {
            throw NostrBlossomUploadError.invalidResponse
        }
        return descriptor
    }

    private func uploadEndpoint(serverURL: URL) throws -> URL {
        guard var components = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ), components.scheme == "https" || components.scheme == "http" else {
            throw NostrBlossomUploadError.invalidServerURL
        }
        let basePath = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        components.path = basePath.isEmpty ? "/upload" : "/\(basePath)/upload"
        guard let url = components.url else {
            throw NostrBlossomUploadError.invalidServerURL
        }
        return url
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
