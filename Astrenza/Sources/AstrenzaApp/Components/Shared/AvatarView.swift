import SwiftUI
import UIKit

struct AvatarView: View {
    let style: AvatarStyle
    let size: CGFloat

    var body: some View {
        ZStack {
            if style.pictureState.usesPlaceholder {
                ProceduralAvatarPlaceholder(style: style, size: size)
            } else if let imageURL = style.imageURL {
                CachedRemoteAvatarImage(url: imageURL, style: style, size: size)
            } else {
                resolvedAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var resolvedAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [style.primary, style.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: style.symbolName)
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
        }
    }
}

private struct CachedRemoteAvatarImage: View {
    let url: URL
    let style: AvatarStyle
    let size: CGFloat

    @StateObject private var loader = RemoteAvatarImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                ProceduralAvatarPlaceholder(
                    style: AvatarStyle(
                        primary: style.primary,
                        secondary: style.secondary,
                        symbolName: style.symbolName,
                        pictureState: loader.didFail ? .failed : .metadataPending,
                        placeholderSeed: style.placeholderSeed,
                        imageURL: style.imageURL
                    ),
                    size: size
                )
            }
        }
        .task(id: url) {
            await loader.load(url: url)
        }
    }
}

@MainActor
private final class RemoteAvatarImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false

    private var loadedURL: URL?

    func load(url: URL) async {
        guard loadedURL != url else { return }
        loadedURL = url
        didFail = false

        if let cachedImage = NostrImageCache.shared.memoryCachedImage(for: url) {
            image = cachedImage
            return
        }

        do {
            image = try await NostrImageCache.shared.image(for: url)
        } catch {
            didFail = true
        }
    }
}

private struct ProceduralAvatarPlaceholder: View {
    let style: AvatarStyle
    let size: CGFloat
    private let design: ProceduralAvatarDesign

    init(style: AvatarStyle, size: CGFloat) {
        self.style = style
        self.size = size
        let seed = style.placeholderSeed.isEmpty ? style.symbolName : style.placeholderSeed
        self.design = ProceduralAvatarDesign(seed: seed, fallbackPrimary: style.primary, fallbackSecondary: style.secondary)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: design.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(design.accent.opacity(0.24))
                .frame(width: size * design.largeBlobScale, height: size * design.largeBlobScale)
                .offset(x: size * design.largeBlobX, y: size * design.largeBlobY)
                .blur(radius: size * 0.02)

            ForEach(design.tokens) { token in
                tokenView(token)
            }

            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.18, y: -size * 0.2)

            if let marker = style.pictureState.markerSystemName {
                Image(systemName: marker)
                    .font(.system(size: size * 0.2, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(.black.opacity(0.18), in: Circle())
                    .offset(x: size * 0.23, y: size * 0.23)
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ token: ProceduralAvatarToken) -> some View {
        switch token.shape {
        case .circle:
            Circle()
                .fill(token.color.opacity(token.opacity))
                .frame(width: size * token.width, height: size * token.height)
                .rotationEffect(.degrees(token.rotation))
                .offset(x: size * token.offsetX, y: size * token.offsetY)
        case .capsule:
            Capsule()
                .fill(token.color.opacity(token.opacity))
                .frame(width: size * token.width, height: size * token.height)
                .rotationEffect(.degrees(token.rotation))
                .offset(x: size * token.offsetX, y: size * token.offsetY)
        case .roundedSquare:
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(token.color.opacity(token.opacity))
                .frame(width: size * token.width, height: size * token.height)
                .rotationEffect(.degrees(token.rotation))
                .offset(x: size * token.offsetX, y: size * token.offsetY)
        }
    }
}

private struct ProceduralAvatarDesign {
    let backgroundColors: [Color]
    let accent: Color
    let tokens: [ProceduralAvatarToken]
    let largeBlobScale: CGFloat
    let largeBlobX: CGFloat
    let largeBlobY: CGFloat

    init(seed: String, fallbackPrimary: Color, fallbackSecondary: Color) {
        var rng = SeededAvatarRandom(seed: seed)
        let hue = rng.nextDouble(in: 0...360)
        let secondaryHue = hue + rng.nextDouble(in: 35...95)
        let accentHue = hue + rng.nextDouble(in: 150...230)

        let primary = Color(hue: hue / 360, saturation: 0.74, brightness: 0.96)
        let secondary = Color(hue: secondaryHue.truncatingRemainder(dividingBy: 360) / 360, saturation: 0.68, brightness: 0.9)
        let accent = Color(hue: accentHue.truncatingRemainder(dividingBy: 360) / 360, saturation: 0.8, brightness: 1)

        self.backgroundColors = rng.nextBool() ? [primary, secondary] : [fallbackPrimary, fallbackSecondary]
        self.accent = accent
        self.largeBlobScale = CGFloat(rng.nextDouble(in: 0.78...1.1))
        self.largeBlobX = CGFloat(rng.nextDouble(in: -0.22...0.22))
        self.largeBlobY = CGFloat(rng.nextDouble(in: -0.2...0.24))

        self.tokens = (0..<5).map { index in
            ProceduralAvatarToken(
                id: index,
                shape: ProceduralAvatarToken.ShapeKind.allCases[rng.nextInt(in: 0..<ProceduralAvatarToken.ShapeKind.allCases.count)],
                color: rng.nextBool() ? .white : accent,
                opacity: CGFloat(rng.nextDouble(in: 0.22...0.58)),
                width: CGFloat(rng.nextDouble(in: 0.16...0.36)),
                height: CGFloat(rng.nextDouble(in: 0.12...0.34)),
                offsetX: CGFloat(rng.nextDouble(in: -0.32...0.32)),
                offsetY: CGFloat(rng.nextDouble(in: -0.3...0.3)),
                rotation: rng.nextDouble(in: -35...35)
            )
        }
    }
}

private struct ProceduralAvatarToken: Identifiable {
    enum ShapeKind: CaseIterable {
        case circle
        case capsule
        case roundedSquare
    }

    let id: Int
    let shape: ShapeKind
    let color: Color
    let opacity: CGFloat
    let width: CGFloat
    let height: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotation: Double
}

private struct SeededAvatarRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        self.state = hash == 0 ? 0x1234_ABCD : hash
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    mutating func nextInt(in range: Range<Int>) -> Int {
        range.lowerBound + Int(nextUnit() * Double(range.count))
    }

    mutating func nextBool() -> Bool {
        nextUnit() > 0.5
    }

    private mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixedState = state
        mixedState = (mixedState ^ (mixedState >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixedState = (mixedState ^ (mixedState >> 27)) &* 0x94D0_49BB_1331_11EB
        mixedState = mixedState ^ (mixedState >> 31)
        return Double(mixedState >> 11) / Double(1 << 53)
    }
}
