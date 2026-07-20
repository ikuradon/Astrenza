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
                RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.82)

                VStack(spacing: AstrenzaSpacing.point8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.astrenza(.point24, weight: .bold))
                    Text("From outside your follows")
                        .font(.astrenza(.point14, weight: .heavy, design: .rounded))
                    Text("Tap to reveal")
                        .font(.astrenza(.point12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                .foregroundStyle(.primary)
            }

            if media.requiresTapToLoadRemoteMedia && !isObscured {
                RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.72)

                VStack(spacing: AstrenzaSpacing.point7) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.astrenza(.point22, weight: .bold))
                    Text("Tap to load")
                        .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.primary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
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
    let onOpen: (TimelineMedia, Int) -> Void
    @State private var isRevealed = false
    @State private var isRemoteLoadAllowed = false
    @State private var measuredSize = CGSize.zero

    private var isObscured: Bool {
        isProtected && !isRevealed
    }

    private var isDeferredRemoteLoad: Bool {
        media.requiresTapToLoadRemoteMedia && !isRemoteLoadAllowed
    }

    private var visibleMedia: TimelineMedia {
        isRemoteLoadAllowed ? media.allowingRemoteMediaLoading() : media
    }

    var body: some View {
        TimelineMediaView(media: visibleMedia, isObscured: isObscured)
            .contentShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TimelineAttachmentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(TimelineAttachmentSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                measuredSize = size
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        activate(at: value.location)
                    }
            )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityIdentifier("timeline.attachment")
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            activate(at: nil)
        }
    }

    private func activate(at location: CGPoint?) {
        if isObscured {
            withAnimation(.spring(duration: AstrenzaMotion.emphasized, bounce: 0.14)) {
                isRevealed = true
            }
        } else if isDeferredRemoteLoad {
            withAnimation(.spring(duration: AstrenzaMotion.emphasized, bounce: 0.14)) {
                isRemoteLoadAllowed = true
            }
        } else {
            onOpen(visibleMedia, selectedTileIndex(at: location))
        }
    }

    private var accessibilityLabelText: String {
        if isObscured {
            return "\(accessibilityLabel), protected"
        }
        if isDeferredRemoteLoad {
            return "\(accessibilityLabel), not loaded"
        }
        return accessibilityLabel
    }

    private var accessibilityHintText: String {
        if isObscured {
            return "Reveals the attachment without opening it"
        }
        if isDeferredRemoteLoad {
            return "Loads the attachment without opening it"
        }
        return "Opens the attachment"
    }

    private func selectedTileIndex(at location: CGPoint?) -> Int {
        guard case .gallery(let tiles) = media,
              let location,
              measuredSize.width > 0,
              measuredSize.height > 0
        else {
            return 0
        }

        switch tiles.count {
        case 0, 1:
            return 0
        case 2:
            return location.x < measuredSize.width / 2 ? 0 : 1
        case 3:
            if location.y < measuredSize.height / 2 {
                return location.x < measuredSize.width / 2 ? 0 : 1
            }
            return 2
        default:
            let isLeft = location.x < measuredSize.width / 2
            let isTop = location.y < measuredSize.height / 2
            switch (isTop, isLeft) {
            case (true, true):
                return 0
            case (true, false):
                return 1
            case (false, true):
                return 2
            case (false, false):
                return 3
            }
        }
    }
}

struct TimelineBrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}

struct TimelineFullscreenMediaRequest: Identifiable {
    let id = UUID()
    let media: TimelineMedia
    let initialTileIndex: Int
}

private struct TimelineAttachmentSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextValue = nextValue()
        if nextValue.width > 0, nextValue.height > 0 {
            value = nextValue
        }
    }
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

    init(media: TimelineMedia, initialTileIndex: Int = 0, onClose: @escaping () -> Void) {
        self.media = media
        self.onClose = onClose
        _selectedTileIndex = State(initialValue: initialTileIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let galleryTiles {
                galleryViewer(tiles: galleryTiles)
            } else {
                TimelineMediaView(media: media)
                    .padding(.horizontal, AstrenzaSpacing.point12)
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
        .animation(.spring(duration: AstrenzaMotion.responsive, bounce: 0.08), value: isChromeVisible)
    }

    @ViewBuilder
    private func galleryViewer(tiles: [MediaTile]) -> some View {
        TabView(selection: $selectedTileIndex) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                TimelineFullscreenMediaPage(tile: tile)
                    .padding(.horizontal, AstrenzaSpacing.point18)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            selectedTileIndex = min(max(selectedTileIndex, 0), max(tiles.count - 1, 0))
        }
        .offset(y: dismissalDrag.height)
        .scaleEffect(dismissalScale)
        .animation(.spring(duration: AstrenzaMotion.standard, bounce: 0.08), value: selectedTileIndex)
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
                    .font(.astrenza(.point17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close media viewer")
        }
        .padding(.top, AstrenzaSpacing.point18)
        .padding(.horizontal, AstrenzaSpacing.point18)
    }

    private func mediaInfoPanel(tile: MediaTile) -> some View {
        VStack(spacing: AstrenzaSpacing.point8) {
            Text(tile.altText ?? tile.title)
                .font(.astrenza(.point15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let galleryTiles, galleryTiles.count > 1 {
                Text("\(selectedTileIndex + 1) / \(galleryTiles.count)")
                    .font(.astrenza(.point13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point14)
        .padding(.vertical, AstrenzaSpacing.point10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous))
        .padding(.horizontal, AstrenzaSpacing.point26)
        .padding(.bottom, AstrenzaSpacing.point24)
    }
}

private struct TimelineFullscreenMediaPage: View {
    let tile: MediaTile
    @StateObject private var loader = RemoteMediaImageLoader()
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
                    withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.08)) {
                        offset = .zero
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Image \(tile.title)")
            .task(id: tile.url) {
                await loader.load(url: tile.url)
            }
    }

    private var pageContent: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fullscreenPlaceholder
            }

            if tile.isVideo {
                Image(systemName: "play.fill")
                    .font(.astrenza(.point30, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(.black.opacity(0.44), in: Circle())
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 5)
            }

            if tile.url != nil, loader.image == nil {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .padding(.top, 112)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(effectiveScale)
        .offset(effectiveOffset)
    }

    private var fullscreenPlaceholder: some View {
        ZStack {
            BlurHashPlaceholderView(blurhash: tile.blurhash, colors: tile.colors)

            Image(systemName: tile.symbolName)
                .font(.astrenza(.point82, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .aspectRatio(tile.aspectRatio ?? 0.82, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point18, style: .continuous))
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
                withAnimation(.spring(duration: AstrenzaMotion.relaxed, bounce: 0.1)) {
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
                withAnimation(.spring(duration: AstrenzaMotion.standard, bounce: 0.08)) {
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

    var body: some View {
        if tiles.count == 1 {
            SingleMediaAttachmentView(tile: tiles[0])
        } else {
            GalleryAttachmentLayout(aspectRatio: resolvedAspectRatio) {
                galleryGrid
            }
            .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var galleryGrid: some View {
        switch tiles.count {
        case 0:
            EmptyView()
        case 2:
            HStack(spacing: AstrenzaSpacing.point2) {
                TimelineMediaTileView(tile: tiles[0])
                TimelineMediaTileView(tile: tiles[1])
            }
        case 3:
            VStack(spacing: AstrenzaSpacing.point2) {
                HStack(spacing: AstrenzaSpacing.point2) {
                    TimelineMediaTileView(tile: tiles[0])
                    TimelineMediaTileView(tile: tiles[1])
                }
                TimelineMediaTileView(tile: tiles[2])
            }
        default:
            VStack(spacing: AstrenzaSpacing.point2) {
                HStack(spacing: AstrenzaSpacing.point2) {
                    TimelineMediaTileView(tile: tiles[0])
                    TimelineMediaTileView(tile: tiles[1])
                }
                HStack(spacing: AstrenzaSpacing.point2) {
                    TimelineMediaTileView(tile: tiles[2])
                    TimelineMediaTileView(
                        tile: tiles[3],
                        overlayCount: tiles.count > 4 ? tiles.count - 4 : nil
                    )
                }
            }
        }
    }

    private var resolvedAspectRatio: CGFloat {
        TimelineMediaLayoutMetrics.galleryAspectRatio(for: tiles)
    }
}

private struct SingleMediaAttachmentView: View {
    let tile: MediaTile

    var body: some View {
        SingleMediaAttachmentLayout(aspectRatio: tile.aspectRatio) {
            TimelineMediaTileView(
                tile: tile,
                contentMode: .fit
            )
                .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelineAttachmentResolvedWidth: Equatable {
    let reportedWidth: CGFloat
    let measurementWidth: CGFloat
}

enum TimelineAttachmentLayoutMetrics {
    static let fallbackAvailableWidth: CGFloat = 320

    static func resolvedWidth(for proposedWidth: CGFloat?) -> TimelineAttachmentResolvedWidth {
        guard let proposedWidth, proposedWidth.isFinite else {
            return TimelineAttachmentResolvedWidth(
                reportedWidth: fallbackAvailableWidth,
                measurementWidth: fallbackAvailableWidth
            )
        }

        guard proposedWidth > 0 else {
            return TimelineAttachmentResolvedWidth(
                reportedWidth: 0,
                measurementWidth: fallbackAvailableWidth
            )
        }

        return TimelineAttachmentResolvedWidth(
            reportedWidth: proposedWidth,
            measurementWidth: proposedWidth
        )
    }
}

private struct GalleryAttachmentLayout: Layout {
    let aspectRatio: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = TimelineAttachmentLayoutMetrics.resolvedWidth(for: proposal.width)
        return CGSize(
            width: width.reportedWidth,
            height: width.measurementWidth / aspectRatio
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

private struct SingleMediaAttachmentLayout: Layout {
    let aspectRatio: CGFloat?

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = TimelineAttachmentLayoutMetrics.resolvedWidth(for: proposal.width)
        let mediaSize = TimelineMediaLayoutMetrics.singleMediaSize(
            aspectRatio: aspectRatio,
            availableWidth: width.measurementWidth
        )
        return CGSize(width: width.reportedWidth, height: mediaSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let mediaSize = TimelineMediaLayoutMetrics.singleMediaSize(
            aspectRatio: aspectRatio,
            availableWidth: bounds.width
        )
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: mediaSize.width, height: mediaSize.height)
        )
    }
}

private struct TimelineMediaTileView: View {
    let tile: MediaTile
    var overlayCount: Int?
    var contentMode: ContentMode = .fill

    @StateObject private var loader = RemoteMediaImageLoader()

    var body: some View {
        ZStack {
            mediaContent
                .blur(radius: overlayCount == nil ? 0 : 8)

            if tile.isVideo {
                    Image(systemName: "play.fill")
                    .font(.astrenza(.point20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
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
                    .font(.astrenza(.point24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
        .clipped()
        .task(id: "\(tile.id)|\(tile.remoteLoadMode.rawValue)") {
            if tile.remoteLoadMode == .automatic {
                await loader.load(url: tile.url)
            } else {
                await loader.load(url: nil)
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let image = loader.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            BlurHashPlaceholderView(blurhash: tile.blurhash, colors: tile.colors)

            Image(systemName: tile.symbolName)
                .font(.astrenza(.point34, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .blur(radius: overlayCount == nil ? 0 : 5)
        }
    }

    private var fallbackLabel: some View {
        Text(tile.title)
            .font(.astrenza(.point12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(AstrenzaSpacing.point10)
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

        do {
            let loadedImage = try await NostrImageCache.shared.image(
                for: url,
                maximumPixelSize: NostrImageCache.mediaMaximumPixelSize
            )
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

enum LinkPreviewCardLayout {
    static let remoteImageHeroHeight: CGFloat = 154
    static let fallbackHeroHeight: CGFloat = 128
    static let minimumMetadataHeight: CGFloat = 98
    static let fallbackTitleMeasurementWidth: CGFloat = 320

    static func heroHeight(for preview: LinkPreview) -> CGFloat {
        preview.imageURL != nil && preview.remoteImageLoadMode == .automatic
            ? remoteImageHeroHeight
            : fallbackHeroHeight
    }
}

struct LinkPreviewAttachmentView: View {
    let preview: LinkPreview

    var body: some View {
        LinkPreviewCardStackLayout(
            heroHeight: LinkPreviewCardLayout.heroHeight(for: preview)
        ) {
            LinkPreviewHeroView(preview: preview)
                .clipped()

            metadata
        }
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point5) {
            HStack(spacing: AstrenzaSpacing.point6) {
                if preview.style == .youtube {
                    Image(systemName: "play.rectangle.fill")
                        .font(.astrenza(.point11, weight: .black))
                        .foregroundStyle(.red)
                        .fixedSize()
                }

                Text(preview.host)
                    .font(.astrenza(.point13, weight: .heavy, design: .rounded))
                    .foregroundStyle(preview.style == .youtube ? .red : Color.astrenzaAccent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("\(preview.title)")
                .font(.astrenza(.point15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(preview.subtitle)
                .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, AstrenzaSpacing.point12)
        .padding(.vertical, AstrenzaSpacing.point10)
        .frame(
            maxWidth: .infinity,
            minHeight: LinkPreviewCardLayout.minimumMetadataHeight,
            alignment: .topLeading
        )
    }
}

private struct LinkPreviewCardStackLayout: Layout {
    let heroHeight: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = TimelineAttachmentLayoutMetrics.resolvedWidth(for: proposal.width)
        let metadataHeight = resolvedMetadataHeight(
            subviews[1].sizeThatFits(
                ProposedViewSize(width: width.measurementWidth, height: nil)
            ).height
        )
        return CGSize(
            width: width.reportedWidth,
            height: heroHeight + metadataHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: heroHeight
            )
        )

        let metadataHeight = max(0, bounds.height - heroHeight)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + heroHeight),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: metadataHeight
            )
        )
    }

    private func resolvedMetadataHeight(_ measuredHeight: CGFloat) -> CGFloat {
        let minimumHeight = LinkPreviewCardLayout.minimumMetadataHeight
        guard measuredHeight > minimumHeight + 1 else {
            return minimumHeight
        }
        return measuredHeight
    }
}

private struct LinkPreviewHeroView: View {
    let preview: LinkPreview

    var body: some View {
        ZStack {
            if let imageURL = preview.imageURL,
               preview.remoteImageLoadMode == .automatic {
                LinkPreviewRemoteImage(url: imageURL, style: preview.style)
            } else {
                fallbackHero
            }

            if preview.style == .youtube {
                YouTubePlayBadge()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallbackHero: some View {
        AstrenzaPalette.linkPreviewFallbackBackground
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: AstrenzaSpacing.point12) {
                    Text(preview.host)
                        .font(.astrenza(.point12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)

                    HStack(alignment: .top) {
                        Text("\(heroTitle)")
                            .font(.astrenza(.point25, weight: .black, design: .rounded))
                            .foregroundStyle(AstrenzaPalette.linkPreviewFallbackText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: AstrenzaSpacing.point8)

                        ZStack {
                            Circle()
                                .fill((preview.style == .youtube ? Color.red : Color.green).opacity(0.3))
                            Image(systemName: preview.style == .youtube ? "play.rectangle.fill" : "link")
                                .font(.astrenza(.point25, weight: .black))
                                .foregroundStyle(preview.style == .youtube ? .red : .green)
                        }
                        .frame(width: 52, height: 52)
                    }

                    Spacer(minLength: 0)
                }
                .padding(AstrenzaSpacing.point18)
            }
            .clipped()
    }

    private var heroTitle: String {
        let words = preview.title.split(separator: " ")
        guard words.count > 1 else { return preview.title }

        let baseFont = UIFont.astrenza(.point25, weight: .black)
        let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded)
            ?? baseFont.fontDescriptor
        let font = UIFont(descriptor: roundedDescriptor, size: baseFont.pointSize)
        let naturalLineWidth = max(
            0,
            LinkPreviewCardLayout.fallbackTitleMeasurementWidth - 112
        ) / 0.82
        var firstLine = String(words[0])
        var consumedWords = 1

        for word in words.dropFirst() {
            let candidate = firstLine + " " + word
            let width = (candidate as NSString).size(
                withAttributes: [.font: font]
            ).width
            guard width <= naturalLineWidth else { break }
            firstLine = candidate
            consumedWords += 1
        }

        guard consumedWords < words.count else { return preview.title }
        return firstLine + "\n" + words.dropFirst(consumedWords).joined(separator: " ")
    }
}

private struct LinkPreviewRemoteImage: View {
    let url: URL
    let style: LinkPreviewStyle
    @StateObject private var loader = RemoteLinkPreviewImageLoader()

    var body: some View {
        Color.astrenzaAttachmentBackground
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .tint(style == .youtube ? .red : Color.astrenzaAccent)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.28), .clear, .black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
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
                .font(.astrenza(.point22, weight: .black))
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

        let loadedImage = try? await NostrImageCache.shared.image(
            for: url,
            maximumPixelSize: NostrImageCache.linkPreviewMaximumPixelSize
        )
        guard loadedURL == url else { return }
        image = loadedImage
    }
}

private struct UnresolvedLinkAttachmentView: View {
    let preview: UnresolvedLinkPreview

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "link")
                    .font(.astrenza(.point15, weight: .black))
                    .foregroundStyle(Color.astrenzaAccent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point4) {
                Text(preview.host)
                    .font(.astrenza(.point12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(preview.url)
                    .font(.astrenza(.point11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transformEffect(
                        CGAffineTransform(translationX: 0, y: 1 / 3)
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AstrenzaSpacing.point10)
        .frame(height: 62)
        .background(Color.astrenzaAttachmentBackground, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
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
