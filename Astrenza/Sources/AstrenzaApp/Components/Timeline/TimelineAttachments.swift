import SwiftUI

struct TimelineMediaView: View {
    let media: TimelineMedia

    var body: some View {
        switch media {
        case .weather:
            WeatherAttachmentView()
        case .gallery(let tiles):
            GalleryAttachmentView(tiles: tiles)
        case .linkPreview(let preview):
            LinkPreviewAttachmentView(preview: preview)
        case .unresolvedLink(let preview):
            UnresolvedLinkAttachmentView(preview: preview)
        }
    }
}

private struct WeatherAttachmentView: View {
    var body: some View {
        HStack(spacing: 0) {
            WeatherDayView(title: "今日 6/2", symbol: "moon.stars.fill", temperature: "27°", low: "17°", tint: .yellow)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            WeatherDayView(title: "明日 6/3", symbol: "sun.max.fill", temperature: "32°", low: "18°", tint: .orange)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 126)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct WeatherDayView: View {
    let title: String
    let symbol: String
    let temperature: String
    let low: String
    let tint: Color

    var body: some View {
        VStack(spacing: 9) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(tint)
            HStack(spacing: 11) {
                Text(temperature)
                    .foregroundStyle(.red.opacity(0.86))
                Text(low)
                    .foregroundStyle(.blue.opacity(0.86))
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GalleryAttachmentView: View {
    let tiles: [MediaTile]

    private let aspectRatio: CGFloat = 1.9

    var body: some View {
        Group {
            switch tiles.count {
            case 0:
                EmptyView()
            case 1:
                TimelineMediaTileView(tile: tiles[0])
            case 2:
                HStack(spacing: 2) {
                    TimelineMediaTileView(tile: tiles[0])
                    TimelineMediaTileView(tile: tiles[1])
                }
            case 3:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        TimelineMediaTileView(tile: tiles[0])
                        TimelineMediaTileView(tile: tiles[1])
                    }
                    TimelineMediaTileView(tile: tiles[2])
                }
            default:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        TimelineMediaTileView(tile: tiles[0])
                        TimelineMediaTileView(tile: tiles[1])
                    }
                    HStack(spacing: 2) {
                        TimelineMediaTileView(tile: tiles[2])
                        TimelineMediaTileView(
                            tile: tiles[3],
                            overlayCount: tiles.count > 4 ? tiles.count - 4 : nil
                        )
                    }
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TimelineMediaTileView: View {
    let tile: MediaTile
    var overlayCount: Int?

    var body: some View {
        ZStack {
            LinearGradient(colors: tile.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .blur(radius: overlayCount == nil ? 0 : 8)

            Image(systemName: tile.symbolName)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .blur(radius: overlayCount == nil ? 0 : 5)

            Text(tile.title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .opacity(overlayCount == nil ? 1 : 0.35)

            if let overlayCount {
                Rectangle()
                    .fill(.black.opacity(0.34))

                Text("+\(overlayCount)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
        .clipped()
    }
}

private struct LinkPreviewAttachmentView: View {
    let preview: LinkPreview

    var body: some View {
        VStack(spacing: 0) {
            LinkPreviewHeroView(preview: preview)
                .frame(height: 128)

            VStack(alignment: .leading, spacing: 5) {
                Text(preview.host)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.astrenzaAccent)
                    .lineLimit(1)

                Text(preview.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(preview.subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 226)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LinkPreviewHeroView: View {
    let preview: LinkPreview

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.94, blue: 0.95)

            VStack(alignment: .leading, spacing: 12) {
                Text(preview.host)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                HStack(alignment: .top) {
                    Text(preview.title)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.15, blue: 0.18))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.3))
                        Image(systemName: "link")
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(.green)
                    }
                    .frame(width: 52, height: 52)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text("21 comments")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.gray)
            }
            .padding(18)
        }
    }
}

private struct UnresolvedLinkAttachmentView: View {
    let preview: UnresolvedLinkPreview

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color.astrenzaAccent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.host)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(preview.url)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}
