import SwiftUI

struct ComposeCompletion: Equatable {
    let trigger: Character
    let values: [String]

    var mentionCandidates: [ComposeMentionCandidate] {
        guard trigger == "@" else { return [] }
        return ComposeMentionCandidate.mockValues.filter { values.contains($0.insertionText) }
    }

    var hashtagCandidates: [ComposeHashtagCandidate] {
        guard trigger == "#" else { return [] }
        return ComposeHashtagCandidate.recentValues.filter { values.contains($0.tag) }
    }

    var customEmojiCandidates: [ComposeCustomEmojiCandidate] {
        guard trigger == ":" else { return [] }
        return ComposeCustomEmojiCandidate.mockValues.filter { values.contains($0.shortcode) }
    }
}

struct ComposeCompletionBar: View {
    let completion: ComposeCompletion
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if completion.trigger == "@" {
                    if completion.mentionCandidates.isEmpty {
                        Text("Start Typing a User...")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(completion.mentionCandidates.prefix(6)) { candidate in
                            Button {
                                onSelect(candidate.insertionText)
                            } label: {
                                ComposeMentionCandidateCell(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if completion.trigger == "#" {
                    ForEach(completion.hashtagCandidates.prefix(6)) { candidate in
                        Button {
                            onSelect(candidate.tag)
                        } label: {
                            ComposeHashtagCandidateCell(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                } else if completion.trigger == ":" {
                    if completion.customEmojiCandidates.isEmpty {
                        Text("Start Typing a Shortcode...")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(completion.customEmojiCandidates.prefix(8)) { candidate in
                            Button {
                                onSelect(candidate.shortcode)
                            } label: {
                                ComposeCustomEmojiCandidateCell(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ForEach(completion.values.prefix(6), id: \.self) { value in
                        Button {
                            onSelect(value)
                        } label: {
                            Text(value)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(Color.black.opacity(0.28))
        .accessibilityLabel("Input suggestions")
    }
}

struct ComposeMentionCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let handle: String
    let avatar: AvatarStyle

    var insertionText: String {
        "@\(id)"
    }

    var searchText: String {
        "\(displayName) \(handle) \(insertionText)".lowercased()
    }

    static func == (lhs: ComposeMentionCandidate, rhs: ComposeMentionCandidate) -> Bool {
        lhs.id == rhs.id
    }

    static let mockValues: [ComposeMentionCandidate] = [
        ComposeMentionCandidate(
            id: "ivory",
            displayName: "Ivory by Tapbots",
            handle: "@ivory@tapbots.social",
            avatar: AvatarStyle(primary: .indigo, secondary: .purple, symbolName: "quote.bubble.fill")
        ),
        ComposeMentionCandidate(
            id: "aureoleark",
            displayName: "User Beta",
            handle: "@aureoleark@mock.example",
            avatar: AvatarStyle(primary: .cyan, secondary: .blue, symbolName: "person.crop.circle.fill")
        ),
        ComposeMentionCandidate(
            id: "thunder",
            displayName: "User Gamma",
            handle: "@thunder@mock.example",
            avatar: AvatarStyle(primary: .blue, secondary: .indigo, symbolName: "cloud.bolt.fill")
        )
    ]
}

struct ComposeMentionCandidateCell: View {
    let candidate: ComposeMentionCandidate

    var body: some View {
        HStack(spacing: 9) {
            AvatarView(style: candidate.avatar, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.handle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 138, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct ComposeHashtagCandidate: Identifiable, Equatable {
    let tag: String
    let recency: String
    let isPinned: Bool

    var id: String { tag }

    static let recentValues: [ComposeHashtagCandidate] = [
        ComposeHashtagCandidate(tag: "#fedeloper", recency: "Used 6 years ago", isPinned: true),
        ComposeHashtagCandidate(tag: "#EJUG", recency: "Used recently", isPinned: false),
        ComposeHashtagCandidate(tag: "#degoogle", recency: "Used once in 7 days", isPinned: false),
        ComposeHashtagCandidate(tag: "#nostr", recency: "Used recently", isPinned: false),
        ComposeHashtagCandidate(tag: "#timeline", recency: "Used last week", isPinned: false),
        ComposeHashtagCandidate(tag: "#relay", recency: "Used last week", isPinned: false)
    ]
}

struct ComposeHashtagCandidateCell: View {
    let candidate: ComposeHashtagCandidate

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: candidate.isPinned ? "tag.fill" : "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.tag)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.recency)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
