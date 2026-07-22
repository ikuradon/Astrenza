import SwiftUI
import UIKit

extension ComposeCustomEmojiCandidate {
    static let mockValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":60fpsparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":aicp:", glyph: "🤖", tint: .yellow),
        ComposeCustomEmojiCandidate(shortcode: ":android:", glyph: "🤖", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":angelparrot:", glyph: "🪽", tint: .mint),
        ComposeCustomEmojiCandidate(shortcode: ":astrenza:", glyph: "✦", tint: .purple),
        ComposeCustomEmojiCandidate(shortcode: ":apple:", glyph: "🍎", tint: .red)
    ]

    static let customPickerValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":aicp:", glyph: "🤖", tint: .yellow),
        ComposeCustomEmojiCandidate(shortcode: ":android:", glyph: "🤖", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":dejavu:", glyph: "♨︎", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":sleepycat:", glyph: "🐱", tint: .brown),
        ComposeCustomEmojiCandidate(shortcode: ":git:", glyph: "◆", tint: .red),
        ComposeCustomEmojiCandidate(shortcode: ":github:", glyph: "◕", tint: .gray),
        ComposeCustomEmojiCandidate(shortcode: ":gitlab:", glyph: "🦊", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":intel:", glyph: "intel", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":spinner:", glyph: "◌", tint: .gray),
        ComposeCustomEmojiCandidate(shortcode: ":mastodon:", glyph: "m", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":rustacean:", glyph: "♜", tint: .cyan),
        ComposeCustomEmojiCandidate(shortcode: ":saba:", glyph: "🥫", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":fire:", glyph: "🔥", tint: .orange),
        ComposeCustomEmojiCandidate(shortcode: ":phone:", glyph: "▯", tint: .teal),
        ComposeCustomEmojiCandidate(shortcode: ":vlc:", glyph: "🔺", tint: .orange)
    ]

    static let partyParrotValues: [ComposeCustomEmojiCandidate] = [
        ComposeCustomEmojiCandidate(shortcode: ":60fpsparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":angelparrot:", glyph: "🪽", tint: .mint),
        ComposeCustomEmojiCandidate(shortcode: ":partyparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":fastparrot:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":peekparrot:", glyph: "◖", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":rightparrot:", glyph: "◗", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":leftparrot:", glyph: "◔", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":parrotwave:", glyph: "🐦", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":beerparrot:", glyph: "🍺", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":gentlemanparrot:", glyph: "🎩", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":pirateparrot:", glyph: "🏴", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":birthdayparrot:", glyph: "🎉", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":blondeparrot:", glyph: "👱", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":confusedparrot:", glyph: "🌀", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":shuffleparrot:", glyph: "🪩", tint: .pink),
        ComposeCustomEmojiCandidate(shortcode: ":sadparrot:", glyph: "🐦", tint: .blue),
        ComposeCustomEmojiCandidate(shortcode: ":brazilparrot:", glyph: "🇧🇷", tint: .green),
        ComposeCustomEmojiCandidate(shortcode: ":christmasparrot:", glyph: "🎅", tint: .red)
    ]
}

extension ComposeCustomEmojiSet {
    static let previewValues: [ComposeCustomEmojiSet] = [
        ComposeCustomEmojiSet(
            id: "preview-custom",
            title: "CUSTOM",
            imageURL: nil,
            detail: nil,
            emojis: ComposeCustomEmojiCandidate.customPickerValues
        ),
        ComposeCustomEmojiSet(
            id: "preview-party-parrot",
            title: "PARTY PARROT",
            imageURL: nil,
            detail: nil,
            emojis: ComposeCustomEmojiCandidate.partyParrotValues
        )
    ]
}

struct ComposeCustomEmojiPicker: View {
    let isContinuousInput: Bool
    let emojiSets: [ComposeCustomEmojiSet]
    let isResolving: Bool
    let onSelect: (ComposeCustomEmojiCandidate) -> Void
    let onReturn: () -> Void
    @State private var selectedSetID: String?
    private let columns = [GridItem(
        .adaptive(minimum: 34, maximum: 44),
        spacing: AstrenzaSpacing.point16
    )]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if isResolving {
                    resolvingHeader
                }

                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        if emojiSets.isEmpty {
                            emptyState
                        } else {
                            if emojiSets.count > 1 {
                                setRail { setID in
                                    selectedSetID = setID
                                    withAnimation(.easeInOut(duration: AstrenzaMotion.quick)) {
                                        proxy.scrollTo(setID, anchor: .top)
                                    }
                                }
                            }

                            ScrollView {
                                LazyVStack(
                                    alignment: .leading,
                                    spacing: AstrenzaSpacing.point18
                                ) {
                                    ForEach(emojiSets) { set in
                                        VStack(
                                            alignment: .leading,
                                            spacing: AstrenzaSpacing.point6
                                        ) {
                                            setHeader(set)

                                            emojiGrid(set.emojis)
                                                .padding(.horizontal, AstrenzaSpacing.point18)
                                                .padding(.bottom, AstrenzaSpacing.point6)
                                        }
                                        .id(set.id)
                                    }
                                }
                                .padding(.bottom, isContinuousInput ? 72 : AstrenzaSpacing.point24)
                            }
                        }
                    }
                }
            }

            if isContinuousInput {
                Button(action: onReturn) {
                    Image(systemName: "return")
                        .font(.astrenza(.point20, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 48)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AstrenzaRadius.point12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, AstrenzaSpacing.point12)
                .padding(.bottom, AstrenzaSpacing.point12)
                .accessibilityLabel("Finish emoji input")
                .accessibilityIdentifier("compose.emoji.finish")
            }
        }
        .frame(height: 330)
        .background(AstrenzaPalette.emojiPickerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .frame(height: 1)
        }
        .onAppear {
            selectedSetID = selectedSetID ?? emojiSets.first?.id
        }
        .onChange(of: emojiSets.map(\.id)) { _, setIDs in
            if selectedSetID.flatMap({ setIDs.contains($0) }) != true {
                selectedSetID = setIDs.first
            }
        }
        .accessibilityLabel("Custom emoji picker")
    }

    private var resolvingHeader: some View {
        HStack(spacing: AstrenzaSpacing.point8) {
            ProgressView()
                .controlSize(.small)
            Text("Resolving custom emoji sets…")
                .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .frame(height: 32)
        .accessibilityIdentifier("compose.emoji.resolving")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Custom Emojis",
            systemImage: "face.smiling",
            description: Text(
                isResolving
                    ? "Looking for your kind 10030 emoji list and kind 30030 sets."
                    : "Add an emoji list in a Nostr client to use it here."
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setRail(
        onSelectSet: @escaping (String) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AstrenzaSpacing.point8) {
                ForEach(emojiSets) { set in
                    Button {
                        onSelectSet(set.id)
                    } label: {
                        ComposeEmojiSetIcon(set: set)
                            .frame(width: 32, height: 32)
                            .padding(AstrenzaSpacing.point3)
                            .background(
                                Color.white.opacity(
                                    selectedSetID == set.id ? 0.16 : 0.001
                                ),
                                in: RoundedRectangle(
                                    cornerRadius: AstrenzaRadius.point8,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(set.title)
                }
            }
            .padding(.horizontal, AstrenzaSpacing.point14)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(height: 1)
        }
    }

    private func setHeader(_ set: ComposeCustomEmojiSet) -> some View {
        HStack(spacing: AstrenzaSpacing.point8) {
            ComposeEmojiSetIcon(set: set)
                .frame(width: 22, height: 22)
            Text(set.title.uppercased())
                .font(.astrenza(.point13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .padding(.top, AstrenzaSpacing.point14)
        .padding(.bottom, AstrenzaSpacing.point6)
    }

    private func emojiGrid(
        _ values: [ComposeCustomEmojiCandidate]
    ) -> some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: AstrenzaSpacing.point18
        ) {
            ForEach(values) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    ComposeCustomEmojiGridCell(candidate: candidate)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ComposeEmojiSetIcon: View {
    let set: ComposeCustomEmojiSet

    var body: some View {
        fallback
            .overlay {
                if let imageURL = set.imageURL {
                    ComposeCachedEmojiImage(url: imageURL)
                }
            }
    }

    private var fallback: some View {
        Text(set.title.prefix(1).uppercased())
            .font(.astrenza(.point14, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.astrenzaAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.astrenzaAccent.opacity(0.14),
                in: RoundedRectangle(
                    cornerRadius: AstrenzaRadius.point8,
                    style: .continuous
                )
            )
    }
}

struct ComposeCustomEmojiGridCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        ZStack {
            Circle()
                .fill(candidate.tint.opacity(candidate.glyph.count > 2 ? 0.12 : 0.18))

            ComposeCustomEmojiIcon(candidate: candidate)
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(candidate.shortcode)
    }
}

struct ComposeCustomEmojiCandidateCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point7) {
            ZStack {
                Circle()
                    .fill(candidate.tint.opacity(0.18))

                ComposeCustomEmojiIcon(candidate: candidate)
            }
            .frame(width: 34, height: 34)

            Text(candidate.shortcode)
                .font(.astrenza(.point14, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 122, alignment: .leading)
        }
        .padding(.horizontal, AstrenzaSpacing.point10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposeCustomEmojiIcon: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        fallback
            .overlay {
                if let imageURL = candidate.imageURL {
                    ComposeCachedEmojiImage(url: imageURL)
                }
            }
    }

    private var fallback: some View {
        Text(candidate.glyph)
            .font(.system(
                size: candidate.glyph.count > 2 ? 12 : 22,
                weight: .bold,
                design: .rounded
            ))
            .foregroundStyle(candidate.tint)
            .minimumScaleFactor(0.65)
            .lineLimit(1)
    }
}

private struct ComposeCachedEmojiImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: url.absoluteString) {
            image = nil
            let loadedImage = try? await NostrImageCache.shared.image(
                for: url,
                maximumPixelSize: NostrImageCache.customEmojiMaximumPixelSize
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}
