import Foundation

public struct NostrLinkPreviewResolver: Sendable {
    public let dataLoader: NostrHTTPDataLoader
    public let now: @Sendable () -> Date
    public let cacheTTLSeconds: Int

    public init(
        dataLoader: @escaping NostrHTTPDataLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        cacheTTLSeconds: Int = 60 * 60 * 24
    ) {
        self.dataLoader = dataLoader
        self.now = now
        self.cacheTTLSeconds = cacheTTLSeconds
    }

    public func resolve(_ preview: NostrLinkPreviewRecord) async -> NostrLinkPreviewRecord {
        guard let url = URL(string: preview.url) ?? URL(string: preview.normalizedURL) else {
            return failedPreview(from: preview, message: "invalid URL")
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Astrenza/1.0 LinkPreview", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await dataLoader(request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return failedPreview(from: preview, message: "HTTP \(httpResponse.statusCode)")
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return failedPreview(from: preview, message: "unsupported encoding")
            }
            let initialMetadata = NostrOpenGraphParser.metadata(from: html, baseURL: url)
            let metadata = await metadataWithOEmbedFallback(initialMetadata, html: html, baseURL: url)
            let fetchedAt = Int(now().timeIntervalSince1970)
            return NostrLinkPreviewRecord(
                url: preview.url,
                normalizedURL: preview.normalizedURL,
                status: "resolved",
                title: metadata.title,
                summary: metadata.summary,
                siteName: metadata.siteName,
                imageURL: metadata.imageURL,
                fetchedAt: fetchedAt,
                expiresAt: fetchedAt + cacheTTLSeconds,
                error: nil
            )
        } catch {
            return failedPreview(from: preview, message: error.localizedDescription)
        }
    }

    private func metadataWithOEmbedFallback(
        _ metadata: NostrOpenGraphMetadata,
        html: String,
        baseURL: URL
    ) async -> NostrOpenGraphMetadata {
        guard metadata.imageURL == nil,
              let oEmbedURL = NostrOpenGraphParser.oEmbedURL(from: html, baseURL: baseURL)
        else { return metadata }

        var request = URLRequest(url: oEmbedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Astrenza/1.0 LinkPreview", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await dataLoader(request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return metadata
            }
            let oEmbed = try JSONDecoder().decode(NostrOEmbedResponse.self, from: data)
            let oEmbedSiteName = metadata.siteName == baseURL.host ? oEmbed.providerName ?? metadata.siteName : metadata.siteName
            return NostrOpenGraphMetadata(
                title: metadata.title ?? oEmbed.title,
                summary: metadata.summary,
                siteName: oEmbedSiteName,
                imageURL: oEmbed.thumbnailURL.flatMap { NostrOpenGraphParser.absoluteURLString($0, baseURL: baseURL) }
            )
        } catch {
            return metadata
        }
    }

    private func failedPreview(from preview: NostrLinkPreviewRecord, message: String) -> NostrLinkPreviewRecord {
        let fetchedAt = Int(now().timeIntervalSince1970)
        return NostrLinkPreviewRecord(
            url: preview.url,
            normalizedURL: preview.normalizedURL,
            status: "failed",
            title: nil,
            summary: nil,
            siteName: nil,
            imageURL: nil,
            fetchedAt: fetchedAt,
            expiresAt: fetchedAt + min(cacheTTLSeconds, 60 * 30),
            error: message
        )
    }
}

public struct NostrOpenGraphMetadata: Equatable, Sendable {
    public let title: String?
    public let summary: String?
    public let siteName: String?
    public let imageURL: String?
}

private struct NostrOEmbedResponse: Decodable {
    let title: String?
    let providerName: String?
    let thumbnailURL: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case providerName = "provider_name"
        case thumbnailURL = "thumbnail_url"
    }
}

public enum NostrOpenGraphParser {
    public static func metadata(from html: String, baseURL: URL) -> NostrOpenGraphMetadata {
        let properties = metaProperties(in: html)
        let title = firstNonEmpty([
            properties["og:title"],
            properties["twitter:title"],
            titleTag(in: html)
        ])
        let summary = firstNonEmpty([
            properties["og:description"],
            properties["twitter:description"],
            properties["description"]
        ])
        let siteName = firstNonEmpty([
            properties["og:site_name"],
            baseURL.host
        ])
        let imageURL = firstNonEmpty([
            properties["og:image"],
            properties["twitter:image"]
        ]).flatMap { absoluteURLString($0, baseURL: baseURL) }

        return NostrOpenGraphMetadata(
            title: title,
            summary: summary,
            siteName: siteName,
            imageURL: imageURL
        )
    }

    public static func oEmbedURL(from html: String, baseURL: URL) -> URL? {
        let pattern = #"<link\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: nsRange) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(in: String(html[attributesRange]))
            guard let rel = values["rel"]?.lowercased(),
                  rel.split(separator: " ").contains("alternate"),
                  let type = values["type"]?.lowercased(),
                  type == "application/json+oembed" || type == "text/json+oembed",
                  let href = values["href"],
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }
            return url
        }

        return nil
    }

    private static func metaProperties(in html: String) -> [String: String] {
        let pattern = #"<meta\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }

        var result: [String: String] = [:]
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: nsRange) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = String(html[attributesRange])
            let values = attributeValues(in: attributes)
            let key = values["property"] ?? values["name"]
            guard let key, let content = values["content"], !content.isEmpty else { continue }
            result[key.lowercased()] = htmlDecoded(content)
        }
        return result
    }

    private static func titleTag(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: nsRange),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        return htmlDecoded(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func attributeValues(in attributes: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        var result: [String: String] = [:]
        let nsRange = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        for match in regex.matches(in: attributes, range: nsRange) {
            guard let nameRange = Range(match.range(at: 1), in: attributes),
                  let valueRange = Range(match.range(at: 3), in: attributes)
            else { continue }
            result[String(attributes[nameRange]).lowercased()] = htmlDecoded(String(attributes[valueRange]))
        }
        return result
    }

    public static func absoluteURLString(_ raw: String, baseURL: URL) -> String? {
        URL(string: raw, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .first
    }

    private static func htmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
