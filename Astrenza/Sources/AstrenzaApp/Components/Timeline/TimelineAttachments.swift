import SwiftUI
import SafariServices
import UIKit
import simd

struct TimelineMediaView: View {
    let media: TimelineMedia
    var isObscured = false

    var body: some View {
        ZStack {
            content
                .blur(radius: isObscured ? 10 : 0)
                .saturation(isObscured ? 0.65 : 1)

            if isObscured {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.82)

                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 24, weight: .bold))
                    Text("From outside your follows")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Text("Tap to reveal")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch media {
        case .gallery(let tiles):
            GalleryAttachmentView(tiles: tiles)
        case .linkPreview(let preview):
            LinkPreviewAttachmentView(preview: preview)
        case .unresolvedLink(let preview):
            UnresolvedLinkAttachmentView(preview: preview)
        }
    }
}

struct TimelineAttachmentButton: View {
    let media: TimelineMedia
    let isProtected: Bool
    let accessibilityLabel: String
    let onOpen: (TimelineMedia) -> Void
    @State private var isRevealed = false

    private var isObscured: Bool {
        isProtected && !isRevealed
    }

    var body: some View {
        TimelineMediaView(media: media, isObscured: isObscured)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: activate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isObscured ? "\(accessibilityLabel), protected" : accessibilityLabel)
        .accessibilityIdentifier("timeline.attachment")
        .accessibilityHint(isObscured ? "Reveals the attachment without opening it" : "Opens the attachment")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            activate()
        }
    }

    private func activate() {
        if isObscured {
            withAnimation(.spring(duration: 0.28, bounce: 0.14)) {
                isRevealed = true
            }
        } else {
            onOpen(media)
        }
    }
}

struct TimelineBrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}

struct TimelineFullscreenMediaViewer: View {
    let media: TimelineMedia
    let onClose: () -> Void
    @State private var selectedTileIndex = 0
    @State private var isChromeVisible = false
    @GestureState private var dismissalDrag = CGSize.zero

    private var galleryTiles: [MediaTile]? {
        if case .gallery(let tiles) = media {
            return tiles
        }

        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let galleryTiles {
                galleryViewer(tiles: galleryTiles)
            } else {
                TimelineMediaView(media: media)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: dismissalDrag.height)
                    .scaleEffect(dismissalScale)
            }

            if isChromeVisible {
                TimelineFullscreenMediaChrome(
                    galleryTiles: galleryTiles,
                    selectedTileIndex: selectedTileIndex,
                    onClose: onClose
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(chromeToggleGesture)
        .simultaneousGesture(dismissalGesture)
        .animation(.spring(duration: 0.2, bounce: 0.08), value: isChromeVisible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func galleryViewer(tiles: [MediaTile]) -> some View {
        TabView(selection: $selectedTileIndex) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                TimelineFullscreenMediaPage(tile: tile)
                    .padding(.horizontal, 18)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .offset(y: dismissalDrag.height)
        .scaleEffect(dismissalScale)
        .animation(.spring(duration: 0.22, bounce: 0.08), value: selectedTileIndex)
    }

    private var dismissalGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .updating($dismissalDrag) { value, state, _ in
                guard isDismissalDrag(value) else { return }
                state = value.translation
            }
            .onEnded { value in
                guard isDismissalDrag(value) else { return }
                let predictedHeight = value.predictedEndTranslation.height
                if abs(predictedHeight) > 190 || abs(value.translation.height) > 150 {
                    onClose()
                }
            }
    }

    private var chromeToggleGesture: some Gesture {
        TapGesture()
            .onEnded {
                isChromeVisible.toggle()
            }
    }

    private var dismissalScale: CGFloat {
        let progress = min(abs(dismissalDrag.height) / 420, 1)
        return 1 - progress * 0.1
    }

    private func isDismissalDrag(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.height) > abs(value.translation.width) * 1.25
    }
}

private struct TimelineFullscreenMediaChrome: View {
    let galleryTiles: [MediaTile]?
    let selectedTileIndex: Int
    let onClose: () -> Void

    private var selectedTile: MediaTile? {
        guard let galleryTiles, galleryTiles.indices.contains(selectedTileIndex) else {
            return nil
        }

        return galleryTiles[selectedTileIndex]
    }

    var body: some View {
        VStack {
            closeButtonRow

            Spacer()

            if let selectedTile {
                mediaInfoPanel(tile: selectedTile)
            }
        }
    }

    private var closeButtonRow: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close media viewer")
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
    }

    private func mediaInfoPanel(tile: MediaTile) -> some View {
        VStack(spacing: 8) {
            Text(tile.altText ?? tile.title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let galleryTiles, galleryTiles.count > 1 {
                Text("\(selectedTileIndex + 1) / \(galleryTiles.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }
}

private struct TimelineFullscreenMediaPage: View {
    let tile: MediaTile
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset = CGSize.zero

    private var effectiveScale: CGFloat {
        min(max(scale * gestureScale, 1), 4.5)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: offset.width + gestureOffset.width,
            height: offset.height + gestureOffset.height
        )
    }

    var body: some View {
        pageContent
            .gesture(zoomGesture)
            .modifier(ZoomPanModifier(isEnabled: effectiveScale > 1.01, gesture: panGesture))
            .highPriorityGesture(doubleTapZoomGesture)
            .onChange(of: scale) { _, newValue in
                if newValue <= 1.01 {
                    withAnimation(.spring(duration: 0.22, bounce: 0.08)) {
                        offset = .zero
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Image \(tile.title)")
    }

    private var pageContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.04))

            LinearGradient(colors: tile.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Image(systemName: tile.symbolName)
                .font(.system(size: 82, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .aspectRatio(0.82, contentMode: .fit)
        .scaleEffect(effectiveScale)
        .offset(effectiveOffset)
    }

    private var doubleTapZoomGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(duration: 0.26, bounce: 0.1)) {
                    if effectiveScale > 1.01 {
                        scale = 1
                        offset = .zero
                    } else {
                        scale = 2.4
                    }
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.24, bounce: 0.1)) {
                    scale = min(max(scale * value.magnification, 1), 4.5)
                    if scale <= 1.01 {
                        offset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.22, bounce: 0.08)) {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                }
            }
    }
}

private struct ZoomPanModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(gesture)
        } else {
            content
        }
    }
}

struct TimelineInAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
    }
}

private struct GalleryAttachmentView: View {
    let tiles: [MediaTile]

    private let landscapeAspectRatio: CGFloat = 1.9
    private let portraitGalleryAspectRatio: CGFloat = 1 / 1.9

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
        .aspectRatio(resolvedAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var resolvedAspectRatio: CGFloat {
        switch tiles.count {
        case 1:
            guard let aspectRatio = tiles.first?.aspectRatio else { return landscapeAspectRatio }
            return min(max(aspectRatio, 0.72), landscapeAspectRatio)
        case 2, 3:
            return tiles.contains(where: \.isPortrait) ? portraitGalleryAspectRatio : landscapeAspectRatio
        default:
            return landscapeAspectRatio
        }
    }
}

private struct TimelineMediaTileView: View {
    let tile: MediaTile
    var overlayCount: Int?

    @StateObject private var loader = RemoteMediaImageLoader()

    var body: some View {
        ZStack {
            mediaContent
                .blur(radius: overlayCount == nil ? 0 : 8)

            if tile.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.42), in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
                    .blur(radius: overlayCount == nil ? 0 : 5)
            }

            if loader.image == nil {
                fallbackLabel
                    .opacity(overlayCount == nil ? 1 : 0.35)
            }

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
        .task(id: tile.url) {
            await loader.load(url: tile.url)
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            BlurHashPlaceholderView(blurhash: tile.blurhash, colors: tile.colors)

            Image(systemName: tile.symbolName)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .blur(radius: overlayCount == nil ? 0 : 5)
        }
    }

    private var fallbackLabel: some View {
        Text(tile.title)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

@MainActor
private final class RemoteMediaImageLoader: ObservableObject {
    @Published var image: UIImage?

    private var currentURL: URL?

    func load(url: URL?) async {
        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        if currentURL == url, image != nil { return }
        if currentURL != url {
            image = nil
        }
        currentURL = url

        if let cachedImage = NostrImageCache.shared.cachedImage(for: url) {
            image = cachedImage
            return
        }

        do {
            let loadedImage = try await NostrImageCache.shared.image(for: url)
            guard currentURL == url else { return }
            image = loadedImage
        } catch {
            guard currentURL == url else { return }
            image = nil
        }
    }
}

private struct BlurHashPlaceholderView: View {
    let blurhash: String?
    let colors: [Color]

    var body: some View {
        if let blurhash,
           let image = BlurHashDecoder.image(from: blurhash, width: 32, height: 32) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct LinkPreviewAttachmentView: View {
    let preview: LinkPreview

    var body: some View {
        VStack(spacing: 0) {
            LinkPreviewHeroView(preview: preview)
                .frame(height: preview.imageURL == nil ? 128 : 154)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if preview.style == .youtube {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.red)
                    }

                    Text(preview.host)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(preview.style == .youtube ? .red : Color.astrenzaAccent)
                        .lineLimit(1)
                }

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
        .frame(height: preview.imageURL == nil ? 226 : 252)
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
            if let imageURL = preview.imageURL {
                LinkPreviewRemoteImage(url: imageURL, style: preview.style)
            } else {
                fallbackHero
            }

            if preview.style == .youtube {
                YouTubePlayBadge()
            }
        }
    }

    private var fallbackHero: some View {
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
                            .fill((preview.style == .youtube ? Color.red : Color.green).opacity(0.3))
                        Image(systemName: preview.style == .youtube ? "play.rectangle.fill" : "link")
                            .font(.system(size: 25, weight: .black))
                            .foregroundStyle(preview.style == .youtube ? .red : .green)
                    }
                    .frame(width: 52, height: 52)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }
}

private struct LinkPreviewRemoteImage: View {
    let url: URL
    let style: LinkPreviewStyle
    @StateObject private var loader = RemoteLinkPreviewImageLoader()

    var body: some View {
        ZStack {
            Color.astrenzaAttachmentBackground

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .tint(style == .youtube ? .red : Color.astrenzaAccent)
            }

            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task(id: url) {
            await loader.load(url: url)
        }
    }
}

private struct YouTubePlayBadge: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.red)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .offset(x: 2)
        }
        .frame(width: 68, height: 46)
    }
}

@MainActor
private final class RemoteLinkPreviewImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var loadedURL: URL?

    func load(url: URL) async {
        guard loadedURL != url else { return }
        loadedURL = url

        if let cachedImage = NostrImageCache.shared.memoryCachedImage(for: url) {
            image = cachedImage
            return
        }

        image = try? await NostrImageCache.shared.image(for: url)
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

private enum BlurHashDecoder {
    private nonisolated(unsafe) static let cache = NSCache<NSString, UIImage>()

    static func image(from blurhash: String, width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0 else { return nil }
        let cacheKey = "\(blurhash)|\(width)x\(height)" as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let decodedImage = decode(blurhash, width: width, height: height) else { return nil }
        cache.setObject(decodedImage, forKey: cacheKey)
        return decodedImage
    }

    private static func decode(_ blurhash: String, width: Int, height: Int) -> UIImage? {
        let scalars = Array(blurhash.unicodeScalars)
        guard scalars.count >= 6,
              let sizeFlag = Base83.decode(scalars[0]),
              let quantizedMaximumValue = Base83.decode(scalars[1])
        else { return nil }

        let componentX = (sizeFlag % 9) + 1
        let componentY = (sizeFlag / 9) + 1
        let expectedLength = 4 + (2 * componentX * componentY)
        guard scalars.count == expectedLength else { return nil }

        let maximumValue = Double(quantizedMaximumValue + 1) / 166.0
        var colors: [SIMD3<Double>] = []
        colors.reserveCapacity(componentX * componentY)

        guard let dcValue = Base83.decode(String(String.UnicodeScalarView(scalars[2..<6]))) else {
            return nil
        }
        colors.append(decodeDC(dcValue))

        for index in 1..<(componentX * componentY) {
            let start = 4 + (index * 2)
            guard let acValue = Base83.decode(String(String.UnicodeScalarView(scalars[start..<(start + 2)]))) else {
                return nil
            }
            colors.append(decodeAC(acValue, maximumValue: maximumValue))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            for y in 0..<height {
                for x in 0..<width {
                    var linearRGB = SIMD3<Double>(repeating: 0)

                    for componentIndexY in 0..<componentY {
                        for componentIndexX in 0..<componentX {
                            let basis = cos(Double.pi * Double(x) * Double(componentIndexX) / Double(width))
                                * cos(Double.pi * Double(y) * Double(componentIndexY) / Double(height))
                            let color = colors[componentIndexX + componentIndexY * componentX]
                            linearRGB += color * basis
                        }
                    }

                    let uiColor = UIColor(
                        red: linearToSRGB(linearRGB.x),
                        green: linearToSRGB(linearRGB.y),
                        blue: linearToSRGB(linearRGB.z),
                        alpha: 1
                    )
                    context.cgContext.setFillColor(uiColor.cgColor)
                    context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private static func decodeDC(_ value: Int) -> SIMD3<Double> {
        let red = value >> 16
        let green = (value >> 8) & 255
        let blue = value & 255
        return SIMD3(
            srgbToLinear(red),
            srgbToLinear(green),
            srgbToLinear(blue)
        )
    }

    private static func decodeAC(_ value: Int, maximumValue: Double) -> SIMD3<Double> {
        let quantizedRed = value / (19 * 19)
        let quantizedGreen = (value / 19) % 19
        let quantizedBlue = value % 19
        return SIMD3(
            signedPow((Double(quantizedRed) - 9) / 9, 2) * maximumValue,
            signedPow((Double(quantizedGreen) - 9) / 9, 2) * maximumValue,
            signedPow((Double(quantizedBlue) - 9) / 9, 2) * maximumValue
        )
    }

    private static func signedPow(_ value: Double, _ exponent: Double) -> Double {
        copysign(pow(abs(value), exponent), value)
    }

    private static func srgbToLinear(_ value: Int) -> Double {
        let normalized = Double(value) / 255.0
        if normalized <= 0.04045 {
            return normalized / 12.92
        }
        return pow((normalized + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> CGFloat {
        let clampedValue = min(max(value, 0), 1)
        if clampedValue <= 0.0031308 {
            return CGFloat(clampedValue * 12.92)
        }
        return CGFloat((1.055 * pow(clampedValue, 1.0 / 2.4)) - 0.055)
    }

    private enum Base83 {
        private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~".unicodeScalars)
        private static let values = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })

        static func decode(_ scalar: Unicode.Scalar) -> Int? {
            values[scalar]
        }

        static func decode(_ string: String) -> Int? {
            var value = 0
            for scalar in string.unicodeScalars {
                guard let digit = values[scalar] else { return nil }
                value = value * 83 + digit
            }
            return value
        }
    }
}
