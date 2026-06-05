import SwiftUI

struct ComposeCustomEmojiCandidate: Identifiable, Equatable {
    let shortcode: String
    let glyph: String
    let tint: Color

    var id: String { shortcode }

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

struct ComposeCustomEmojiPicker: View {
    let isContinuousInput: Bool
    let onSelect: (ComposeCustomEmojiCandidate) -> Void
    let onReturn: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 30, maximum: 44), spacing: 16), count: 8)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    emojiSection("CUSTOM", values: ComposeCustomEmojiCandidate.customPickerValues)
                    emojiSection("PARTY PARROTS", values: ComposeCustomEmojiCandidate.partyParrotValues)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, isContinuousInput ? 72 : 24)
            }

            if isContinuousInput {
                Button(action: onReturn) {
                    Image(systemName: "return")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 48)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .accessibilityLabel("Finish emoji input")
                .accessibilityIdentifier("compose.emoji.finish")
            }
        }
        .frame(height: 330)
        .background(Color(white: 0.18))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .frame(height: 1)
        }
        .accessibilityLabel("Custom emoji picker")
    }

    private func emojiSection(_ title: String, values: [ComposeCustomEmojiCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
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
}

struct ComposeCustomEmojiGridCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        ZStack {
            Circle()
                .fill(candidate.tint.opacity(candidate.glyph.count > 2 ? 0.12 : 0.18))

            Text(candidate.glyph)
                .font(.system(size: candidate.glyph.count > 2 ? 12 : 26, weight: .bold, design: .rounded))
                .foregroundStyle(candidate.tint)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(candidate.shortcode)
    }
}

struct ComposeCustomEmojiCandidateCell: View {
    let candidate: ComposeCustomEmojiCandidate

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(candidate.tint.opacity(0.18))

                Text(candidate.glyph)
                    .font(.system(size: 22))
            }
            .frame(width: 34, height: 34)

            Text(candidate.shortcode)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 122, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
