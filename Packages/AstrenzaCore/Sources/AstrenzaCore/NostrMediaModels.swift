import Foundation

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
        let imetaAssets = event.tags.enumerated().compactMap { position, tag in
            mediaAsset(fromIMetaTag: tag, event: event, position: position, createdAt: createdAt)
        }
        if !imetaAssets.isEmpty {
            return imetaAssets
        }

        return directMediaURLs(in: event.content).enumerated().map { index, url in
            NostrMediaAssetRecord(
                assetID: "\(event.id):content:\(index)",
                eventID: event.id,
                url: url.absoluteString,
                mimeType: mimeType(from: url),
                blurhash: nil,
                width: nil,
                height: nil,
                alt: nil,
                sha256: nil,
                status: "unresolved",
                localPath: nil,
                createdAt: createdAt
            )
        }
    }

    public static func directMediaURLs(in content: String) -> [URL] {
        var seen = Set<String>()
        return content
            .split(whereSeparator: \.isWhitespace)
            .compactMap { token -> URL? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\n"))
                guard let url = URL(string: trimmed),
                      url.scheme == "http" || url.scheme == "https",
                      isDirectMediaURL(url)
                else { return nil }
                return seen.insert(url.absoluteString).inserted ? url : nil
            }
    }

    public static func isDirectMediaURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [
            ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".avif",
            ".mp4", ".mov", ".m4v", ".webm"
        ].contains { path.hasSuffix($0) }
    }

    private static func mediaAsset(
        fromIMetaTag tag: [String],
        event: NostrEvent,
        position: Int,
        createdAt: Int
    ) -> NostrMediaAssetRecord? {
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
        return NostrMediaAssetRecord(
            assetID: "\(event.id):imeta:\(position)",
            eventID: event.id,
            url: url.absoluteString,
            mimeType: fields["m"] ?? mimeType(from: url),
            blurhash: fields["blurhash"],
            width: dimensions?.width,
            height: dimensions?.height,
            alt: fields["alt"],
            sha256: fields["x"] ?? fields["ox"],
            status: "unresolved",
            localPath: nil,
            createdAt: createdAt
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

    private static func mimeType(from url: URL) -> String? {
        let path = url.path.lowercased()
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") {
            return "image/jpeg"
        } else if path.hasSuffix(".png") {
            return "image/png"
        } else if path.hasSuffix(".gif") {
            return "image/gif"
        } else if path.hasSuffix(".webp") {
            return "image/webp"
        } else if path.hasSuffix(".heic") {
            return "image/heic"
        } else if path.hasSuffix(".avif") {
            return "image/avif"
        } else if path.hasSuffix(".mp4") {
            return "video/mp4"
        } else if path.hasSuffix(".mov") {
            return "video/quicktime"
        } else if path.hasSuffix(".m4v") {
            return "video/x-m4v"
        } else if path.hasSuffix(".webm") {
            return "video/webm"
        }
        return nil
    }
}
