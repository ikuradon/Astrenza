import Foundation
import NostrProtocol

public struct NostrMediaAssetRecord: Codable, Equatable, Sendable {
    public let assetID: String
    public let eventID: String
    public let url: String
    public let mimeType: String?
    public let blurhash: String?
    public let width: Int?
    public let height: Int?
    public let alt: String?
    public let sha256: String?
    public let status: String
    public let localPath: String?
    public let createdAt: Int

    public init(
        assetID: String,
        eventID: String,
        url: String,
        mimeType: String?,
        blurhash: String?,
        width: Int?,
        height: Int?,
        alt: String?,
        sha256: String?,
        status: String,
        localPath: String?,
        createdAt: Int
    ) {
        self.assetID = assetID
        self.eventID = eventID
        self.url = url
        self.mimeType = mimeType
        self.blurhash = blurhash
        self.width = width
        self.height = height
        self.alt = alt
        self.sha256 = sha256
        self.status = status
        self.localPath = localPath
        self.createdAt = createdAt
    }
}

public enum NostrMediaParser {
    public static func mediaAssets(from event: NostrEvent, createdAt: Int) -> [NostrMediaAssetRecord] {
        NostrContentAttachmentClassifier.attachments(from: event)
            .filter { $0.kind == .media }
            .enumerated()
            .map { index, attachment in
            NostrMediaAssetRecord(
                assetID: assetID(eventID: event.id, attachment: attachment, fallbackIndex: index),
                eventID: event.id,
                url: attachment.url.absoluteString,
                mimeType: attachment.mimeType,
                blurhash: attachment.blurhash,
                width: attachment.width,
                height: attachment.height,
                alt: attachment.alt,
                sha256: attachment.sha256,
                status: "unresolved",
                localPath: nil,
                createdAt: createdAt
            )
        }
    }

    public static func directMediaURLs(in content: String) -> [URL] {
        NostrContentAttachmentClassifier.webURLs(in: content)
            .filter(isDirectMediaURL)
    }

    public static func isDirectMediaURL(_ url: URL) -> Bool {
        NostrContentAttachmentClassifier.isDirectMediaURL(url)
    }

    private static func mimeType(from url: URL) -> String? {
        NostrContentAttachmentClassifier.mimeType(from: url)
    }

    private static func assetID(
        eventID: String,
        attachment: NostrClassifiedAttachment,
        fallbackIndex: Int
    ) -> String {
        switch attachment.source {
        case .imeta(let position):
            return "\(eventID):imeta:\(position)"
        case .content:
            return "\(eventID):content:\(fallbackIndex)"
        }
    }
}
