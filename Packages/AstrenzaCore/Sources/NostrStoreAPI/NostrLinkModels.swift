import Foundation

public struct NostrLinkPreviewRecord: Codable, Equatable, Sendable {
    public let url: String
    public let normalizedURL: String
    public let status: String
    public let title: String?
    public let summary: String?
    public let siteName: String?
    public let imageURL: String?
    public let fetchedAt: Int?
    public let expiresAt: Int?
    public let error: String?

    public init(
        url: String,
        normalizedURL: String,
        status: String,
        title: String?,
        summary: String?,
        siteName: String?,
        imageURL: String?,
        fetchedAt: Int?,
        expiresAt: Int?,
        error: String?
    ) {
        self.url = url
        self.normalizedURL = normalizedURL
        self.status = status
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
        self.error = error
    }
}

public enum NostrLinkParser {
    public static func webURLs(in content: String) -> [URL] {
        NostrContentAttachmentClassifier.webURLs(in: content)
    }

    public static func normalizedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}
