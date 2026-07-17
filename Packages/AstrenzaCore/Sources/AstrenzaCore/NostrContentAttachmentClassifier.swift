import Foundation
import NostrProtocol

public enum NostrURLAttachmentKind: String, Codable, Sendable {
    case media
    case linkPreview
    case unsupported
}

public enum NostrURLAttachmentSource: Equatable, Sendable {
    case imeta(position: Int)
    case content(position: Int)
}

public struct NostrClassifiedAttachment: Equatable, Sendable {
    public let url: URL
    public let normalizedURL: String
    public let kind: NostrURLAttachmentKind
    public let source: NostrURLAttachmentSource
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let blurhash: String?
    public let alt: String?
    public let sha256: String?

    public init(
        url: URL,
        normalizedURL: String,
        kind: NostrURLAttachmentKind,
        source: NostrURLAttachmentSource,
        mimeType: String?,
        width: Int?,
        height: Int?,
        blurhash: String?,
        alt: String?,
        sha256: String?
    ) {
        self.url = url
        self.normalizedURL = normalizedURL
        self.kind = kind
        self.source = source
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.blurhash = blurhash
        self.alt = alt
        self.sha256 = sha256
    }
}

public enum NostrRemotePreviewRequestKind: String, Codable, Sendable {
    case media
    case linkPreview
}

public enum NostrRemotePreviewFetchMode: String, Codable, Sendable {
    case automatic
    case queued
    case tapRequired
}

public struct NostrRemotePreviewRequest: Codable, Equatable, Sendable {
    public var url: URL
    public var kind: NostrRemotePreviewRequestKind
    public var eventID: String
    public var requestedAt: Int

    public init(
        url: URL,
        kind: NostrRemotePreviewRequestKind,
        eventID: String,
        requestedAt: Int
    ) {
        self.url = url
        self.kind = kind
        self.eventID = eventID
        self.requestedAt = requestedAt
    }
}

public struct NostrRemotePreviewDecision: Equatable, Sendable {
    public var request: NostrRemotePreviewRequest
    public var fetchMode: NostrRemotePreviewFetchMode

    public init(
        request: NostrRemotePreviewRequest,
        fetchMode: NostrRemotePreviewFetchMode
    ) {
        self.request = request
        self.fetchMode = fetchMode
    }
}

public struct NostrURLMetadata: Equatable, Sendable {
    public let url: URL
    public let normalizedURL: String
    public let contentType: String?
    public let contentLength: Int?
    public let width: Int?
    public let height: Int?
    public let title: String?
    public let summary: String?
    public let siteName: String?
    public let imageURL: String?

    public init(
        url: URL,
        normalizedURL: String,
        contentType: String?,
        contentLength: Int?,
        width: Int?,
        height: Int?,
        title: String?,
        summary: String?,
        siteName: String?,
        imageURL: String?
    ) {
        self.url = url
        self.normalizedURL = normalizedURL
        self.contentType = contentType
        self.contentLength = contentLength
        self.width = width
        self.height = height
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.imageURL = imageURL
    }
}

public protocol NostrURLMetadataResolver: Sendable {
    func resolve(url: URL) async -> NostrURLMetadata
}

public enum NostrContentAttachmentClassifier {
    public static func attachments(from event: NostrEvent) -> [NostrClassifiedAttachment] {
        var seen = Set<String>()
        var output: [NostrClassifiedAttachment] = []
        var hasIMetaMedia = false

        for (position, tag) in event.tags.enumerated() {
            guard let attachment = attachment(fromIMetaTag: tag, position: position),
                  seen.insert(attachment.normalizedURL).inserted
            else { continue }
            hasIMetaMedia = true
            output.append(attachment)
        }

        for (position, url) in webURLsWithPositions(in: event.content) {
            let normalizedURL = NostrLinkParser.normalizedURLString(url)
            let isDirectMedia = isDirectMediaURL(url)
            guard !hasIMetaMedia || !isDirectMedia else { continue }
            guard seen.insert(normalizedURL).inserted else { continue }
            output.append(NostrClassifiedAttachment(
                url: url,
                normalizedURL: normalizedURL,
                kind: isDirectMedia ? .media : .linkPreview,
                source: .content(position: position),
                mimeType: mimeType(from: url),
                width: nil,
                height: nil,
                blurhash: nil,
                alt: nil,
                sha256: nil
            ))
        }

        return output
    }

    public static func mediaURLs(from event: NostrEvent) -> [URL] {
        attachments(from: event)
            .filter { $0.kind == .media }
            .map(\.url)
    }

    public static func linkPreviewURLs(from event: NostrEvent) -> [URL] {
        attachments(from: event)
            .filter { $0.kind == .linkPreview }
            .map(\.url)
    }

    public static func remotePreviewDecisions(
        from event: NostrEvent,
        policy: NostrSyncPolicy,
        requestedAt: Int
    ) -> [NostrRemotePreviewDecision] {
        attachments(from: event).compactMap { attachment in
            switch attachment.kind {
            case .media:
                return NostrRemotePreviewDecision(
                    request: NostrRemotePreviewRequest(
                        url: attachment.url,
                        kind: .media,
                        eventID: event.id,
                        requestedAt: requestedAt
                    ),
                    fetchMode: policy.tapToLoadMedia ? .tapRequired : .automatic
                )
            case .linkPreview:
                return NostrRemotePreviewDecision(
                    request: NostrRemotePreviewRequest(
                        url: attachment.url,
                        kind: .linkPreview,
                        eventID: event.id,
                        requestedAt: requestedAt
                    ),
                    fetchMode: linkPreviewFetchMode(for: policy)
                )
            case .unsupported:
                return nil
            }
        }
    }

    public static func linkPreviewFetchMode(for policy: NostrSyncPolicy) -> NostrRemotePreviewFetchMode {
        if policy.disableOGPOnCellular && policy.networkType == .cellular {
            return .tapRequired
        }
        return policy.queueOGPPreviews ? .queued : .automatic
    }

    public static func webURLs(in content: String) -> [URL] {
        webURLsWithPositions(in: content).map(\.url)
    }

    public static func isDirectMediaURL(_ url: URL) -> Bool {
        guard let mimeType = mimeType(from: url) else { return false }
        return mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/")
    }

    public static func mimeType(from url: URL) -> String? {
        let path = url.path.lowercased()
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return "image/jpeg" }
        if path.hasSuffix(".png") { return "image/png" }
        if path.hasSuffix(".gif") { return "image/gif" }
        if path.hasSuffix(".webp") { return "image/webp" }
        if path.hasSuffix(".heic") { return "image/heic" }
        if path.hasSuffix(".avif") { return "image/avif" }
        if path.hasSuffix(".mp4") { return "video/mp4" }
        if path.hasSuffix(".mov") { return "video/quicktime" }
        if path.hasSuffix(".m4v") { return "video/x-m4v" }
        if path.hasSuffix(".webm") { return "video/webm" }
        return nil
    }

    private static func webURLsWithPositions(in content: String) -> [(position: Int, url: URL)] {
        var seen = Set<String>()
        var output: [(position: Int, url: URL)] = []
        let tokens = content.split(whereSeparator: \.isWhitespace)

        for token in tokens {
            let trimmed = token.trimmingCharacters(in: trailingURLPunctuation)
            guard let url = URL(string: trimmed),
                  url.scheme == "http" || url.scheme == "https"
            else { continue }

            let normalizedURL = NostrLinkParser.normalizedURLString(url)
            guard seen.insert(normalizedURL).inserted else { continue }
            output.append((position: output.count, url: url))
        }

        return output
    }

    private static func attachment(fromIMetaTag tag: [String], position: Int) -> NostrClassifiedAttachment? {
        guard tag.first == "imeta" else { return nil }

        var fields: [String: String] = [:]
        for rawField in tag.dropFirst() {
            guard let value = fieldValue(rawField) else { continue }
            fields[fieldName(rawField), default: value] = value
        }

        guard let rawURL = fields["url"],
              let url = URL(string: rawURL),
              url.scheme == "http" || url.scheme == "https"
        else { return nil }

        let dimensions = fields["dim"].flatMap(parseDimensions)
        return NostrClassifiedAttachment(
            url: url,
            normalizedURL: NostrLinkParser.normalizedURLString(url),
            kind: .media,
            source: .imeta(position: position),
            mimeType: fields["m"] ?? mimeType(from: url),
            width: dimensions?.width,
            height: dimensions?.height,
            blurhash: fields["blurhash"],
            alt: fields["alt"],
            sha256: fields["x"] ?? fields["ox"]
        )
    }

    private static func fieldName(_ raw: String) -> String {
        raw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? raw
    }

    private static func fieldValue(_ raw: String) -> String? {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let value = String(parts[1])
        return value.isEmpty ? nil : value
    }

    private static func parseDimensions(_ raw: String) -> (width: Int, height: Int)? {
        let parts = raw.lowercased().split(separator: "x", maxSplits: 1)
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1])
        else { return nil }
        return (width, height)
    }

    private static var trailingURLPunctuation: CharacterSet {
        CharacterSet(charactersIn: ".,;:!?)]}>\n")
    }
}
