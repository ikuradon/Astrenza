import SwiftUI
import SafariServices

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
        Button {
            if isObscured {
                withAnimation(.spring(duration: 0.28, bounce: 0.14)) {
                    isRevealed = true
                }
            } else {
                onOpen(media)
            }
        } label: {
            TimelineMediaView(media: media, isObscured: isObscured)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isObscured ? "\(accessibilityLabel), protected" : accessibilityLabel)
        .accessibilityIdentifier("timeline.attachment")
        .accessibilityHint(isObscured ? "Reveals the attachment without opening it" : "Opens the attachment")
        .accessibilityAction {
            if isObscured {
                isRevealed = true
            } else {
                onOpen(media)
            }
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
                viewerChrome
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(chromeToggleGesture)
        .simultaneousGesture(dismissalGesture)
        .animation(.spring(duration: 0.2, bounce: 0.08), value: isChromeVisible)
        .preferredColorScheme(.dark)
    }

    private var viewerChrome: some View {
        VStack {
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

            Spacer()

            if let galleryTiles, galleryTiles.count > 1 {
                Text("\(selectedTileIndex + 1) / \(galleryTiles.count)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
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

            VStack {
                Spacer()
                Text(tile.title)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.28), in: Capsule())
                    .padding(.bottom, 18)
            }
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
