import Foundation
import SwiftUI
import AstrenzaCore

struct NostrTimelineMediaProjection {
    static func media(
        assets: [NostrMediaAssetRecord],
        mediaAttachments: [NostrClassifiedAttachment],
        linkURLs: [URL],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord],
        palette: (primary: Color, secondary: Color)
    ) -> TimelineMedia? {
        if let media = persistedMedia(assets: assets, palette: palette) {
            return media
        }
        if let media = fallbackMedia(attachments: mediaAttachments, palette: palette) {
            return media
        }
        return linkPreview(
            linkURLs: linkURLs,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL
        )
    }

    static func linkPreviewStyle(for url: URL) -> LinkPreviewStyle {
        guard let host = url.host?.lowercased() else { return .standard }
        if host == "youtu.be" ||
            host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtube-nocookie.com" ||
            host.hasSuffix(".youtube-nocookie.com") {
            return .youtube
        }
        return .standard
    }

    private static func persistedMedia(
        assets: [NostrMediaAssetRecord],
        palette: (primary: Color, secondary: Color)
    ) -> TimelineMedia? {
        let tiles = assets.prefix(5).compactMap { asset -> MediaTile? in
            guard let url = URL(string: asset.url) else { return nil }
            return mediaTile(
                url: url,
                mimeType: asset.mimeType,
                alt: asset.alt,
                width: asset.width,
                height: asset.height,
                blurhash: asset.blurhash,
                palette: palette
            )
        }
        guard !tiles.isEmpty else { return nil }
        return .gallery(Array(tiles))
    }

    private static func fallbackMedia(
        attachments: [NostrClassifiedAttachment],
        palette: (primary: Color, secondary: Color)
    ) -> TimelineMedia? {
        guard !attachments.isEmpty else { return nil }
        let tiles = attachments.prefix(5).map { attachment in
            mediaTile(
                url: attachment.url,
                mimeType: attachment.mimeType,
                alt: attachment.alt,
                width: attachment.width,
                height: attachment.height,
                blurhash: attachment.blurhash,
                palette: palette
            )
        }
        return .gallery(Array(tiles))
    }

    private static func linkPreview(
        linkURLs: [URL],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord]
    ) -> TimelineMedia? {
        guard let link = linkURLs.first else { return nil }
        let normalizedURL = NostrLinkParser.normalizedURLString(link)
        if let preview = linkPreviewsByNormalizedURL[normalizedURL],
           preview.status == "resolved",
           let title = preview.title {
            return .linkPreview(LinkPreview(
                title: title,
                subtitle: preview.summary ?? preview.siteName ?? normalizedURL,
                host: preview.siteName ?? link.host ?? link.absoluteString,
                url: preview.url,
                imageURL: preview.imageURL.flatMap(URL.init(string:)),
                style: linkPreviewStyle(for: link)
            ))
        }
        return .unresolvedLink(UnresolvedLinkPreview(host: link.host ?? link.absoluteString, url: link.absoluteString))
    }

    private static func mediaTile(
        url: URL,
        mimeType: String?,
        alt: String?,
        width: Int?,
        height: Int?,
        blurhash: String?,
        palette: (primary: Color, secondary: Color)
    ) -> MediaTile {
        MediaTile(
            title: alt ?? (url.lastPathComponent.isEmpty ? (url.host ?? "media") : url.lastPathComponent),
            colors: [palette.primary, palette.secondary],
            symbolName: mimeType?.hasPrefix("video/") == true ? "play.rectangle" : "photo",
            url: url,
            altText: alt,
            width: width,
            height: height,
            blurhash: blurhash
        )
    }
}
