import AstrenzaCore
import SwiftUI

struct ComposeCompletion: Equatable {
    let trigger: Character
    let mentionCandidates: [ComposeMentionCandidate]
    let hashtagCandidates: [ComposeHashtagCandidate]
    let customEmojiCandidates: [ComposeCustomEmojiCandidate]

    init(
        trigger: Character,
        mentionCandidates: [ComposeMentionCandidate] = [],
        hashtagCandidates: [ComposeHashtagCandidate] = [],
        customEmojiCandidates: [ComposeCustomEmojiCandidate] = []
    ) {
        self.trigger = trigger
        self.mentionCandidates = mentionCandidates
        self.hashtagCandidates = hashtagCandidates
        self.customEmojiCandidates = customEmojiCandidates
    }
}

struct ComposeCompletionBar: View {
    let completion: ComposeCompletion
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AstrenzaSpacing.point8) {
                if completion.trigger == "@" {
                    if completion.mentionCandidates.isEmpty {
                        Text("Start Typing a User...")
                            .font(.astrenza(.point16, weight: .semibold, design: .rounded))
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
                            .font(.astrenza(.point16, weight: .semibold, design: .rounded))
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
                }
            }
            .padding(.horizontal, AstrenzaSpacing.point4)
        }
        .padding(.horizontal, AstrenzaSpacing.point14)
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
    let insertionText: String

    init(
        id: String,
        displayName: String,
        handle: String,
        avatar: AvatarStyle,
        insertionText: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatar = avatar
        self.insertionText = insertionText ?? "@\(id)"
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
        HStack(spacing: AstrenzaSpacing.point9) {
            AvatarView(style: candidate.avatar, size: 34)

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point2) {
                Text(candidate.displayName)
                    .font(.astrenza(.point14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.handle)
                    .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 138, alignment: .leading)
        }
        .padding(.horizontal, AstrenzaSpacing.point10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
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

struct ComposeSuggestionSnapshot: Equatable {
    let mentions: [ComposeMentionCandidate]
    let hashtags: [ComposeHashtagCandidate]
    let completionEmojis: [ComposeCustomEmojiCandidate]
    let emojiSets: [ComposeCustomEmojiSet]

    static let empty = ComposeSuggestionSnapshot(
        mentions: [],
        hashtags: [],
        completionEmojis: [],
        emojiSets: []
    )

    static let preview = ComposeSuggestionSnapshot(
        mentions: ComposeMentionCandidate.mockValues,
        hashtags: ComposeHashtagCandidate.recentValues,
        completionEmojis: ComposeCustomEmojiCandidate.mockValues,
        emojiSets: ComposeCustomEmojiSet.previewValues
    )

    static func load(
        accountID: String?,
        eventStore: NostrEventStore?
    ) -> ComposeSuggestionSnapshot {
        guard accountID != nil else { return .preview }
        guard let eventStore else { return .empty }
        let source = source(accountID: accountID, eventStore: eventStore)
        return project(
            profiles: source.profiles,
            recentNotes: source.recentNotes,
            emojiListEvent: source.emojiListEvent,
            emojiSetEvents: source.emojiSetEvents
        )
    }

    static func source(
        accountID: String?,
        eventStore: NostrEventStore
    ) -> ComposeSuggestionSource {
        let profiles = (try? eventStore.profileSearchCandidates(
            query: "",
            limit: 100
        )) ?? []
        let recentNotes = (try? eventStore.events(kind: 1, limit: 300)) ?? []
        let emojiListEvent = accountID.flatMap {
            try? eventStore.latestReplaceableEvent(pubkey: $0, kind: 10_030)
        }
        let emojiSetEvents = NostrEmojiSetReference
            .references(in: emojiListEvent)
            .compactMap { reference in
                try? eventStore.latestAddressableEvent(
                    kind: 30_030,
                    pubkey: reference.pubkey,
                    dTag: reference.dTag
                )
            }
        return ComposeSuggestionSource(
            profiles: profiles,
            recentNotes: recentNotes,
            emojiListEvent: emojiListEvent,
            emojiSetEvents: emojiSetEvents
        )
    }

    static func project(
        profiles: [NostrProfileSearchResult],
        recentNotes: [NostrEvent],
        emojiListEvent: NostrEvent? = nil,
        emojiSetEvents: [NostrEvent] = []
    ) -> ComposeSuggestionSnapshot {
        let mentions = profiles.map(mentionCandidate)
        let hashtags = hashtagCandidates(from: recentNotes)
        let recentEmojis = customEmojiCandidates(from: recentNotes)
        let catalog = ComposeEmojiCatalogProjection.project(
            emojiListEvent: emojiListEvent,
            emojiSetEvents: emojiSetEvents
        )
        let catalogEmojis = catalog.flatMap(\.emojis)
        return ComposeSuggestionSnapshot(
            mentions: mentions,
            hashtags: hashtags,
            completionEmojis: deduplicatedEmojis(
                catalogEmojis + recentEmojis
            ),
            emojiSets: catalog.isEmpty && !recentEmojis.isEmpty
                ? [ComposeCustomEmojiSet(
                    id: "cached-recent",
                    title: "RECENT",
                    imageURL: nil,
                    detail: nil,
                    emojis: recentEmojis
                )]
                : catalog
        )
    }

    private static func mentionCandidate(
        _ profile: NostrProfileSearchResult
    ) -> ComposeMentionCandidate {
        let npub = (try? NostrNIP19.publicKey(profile.pubkey)) ?? profile.pubkey
        let displayName = profile.displayName ?? abbreviated(profile.pubkey)
        let handle = profile.nip05.map { "@\($0)" } ?? abbreviated(npub)
        return ComposeMentionCandidate(
            id: profile.pubkey,
            displayName: displayName,
            handle: handle,
            avatar: AvatarStyle(
                primary: .purple,
                secondary: .blue,
                symbolName: "person.crop.circle.fill",
                pictureState: profile.pictureURL == nil ? .missing : .resolved,
                placeholderSeed: profile.pubkey,
                imageURL: profile.pictureURL
            ),
            insertionText: "nostr:\(npub)"
        )
    }

    private static func hashtagCandidates(
        from events: [NostrEvent]
    ) -> [ComposeHashtagCandidate] {
        var observations: [String: (tag: String, count: Int, newest: Int)] = [:]
        for event in events {
            for tag in event.tags where tag.count >= 2 && tag[0] == "t" {
                let value = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let key = value.lowercased()
                let previous = observations[key]
                observations[key] = (
                    tag: previous?.tag ?? "#\(value)",
                    count: (previous?.count ?? 0) + 1,
                    newest: max(previous?.newest ?? event.createdAt, event.createdAt)
                )
            }
        }
        return observations.values
            .sorted {
                $0.newest == $1.newest
                    ? $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
                    : $0.newest > $1.newest
            }
            .prefix(40)
            .map { observation in
                ComposeHashtagCandidate(
                    tag: observation.tag,
                    recency: observation.count == 1
                        ? "Seen in a cached note"
                        : "Seen in \(observation.count) cached notes",
                    isPinned: false
                )
            }
    }

    private static func customEmojiCandidates(
        from events: [NostrEvent]
    ) -> [ComposeCustomEmojiCandidate] {
        var seen = Set<String>()
        var candidates: [ComposeCustomEmojiCandidate] = []
        for event in events.sorted(by: { $0.createdAt > $1.createdAt }) {
            for tag in event.tags where tag.count >= 3 && tag[0] == "emoji" {
                let name = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty,
                      seen.insert(name.lowercased()).inserted,
                      let imageURL = URL(string: tag[2]),
                      let scheme = imageURL.scheme?.lowercased(),
                      scheme == "https" || scheme == "http"
                else { continue }
                candidates.append(ComposeCustomEmojiCandidate(
                    shortcode: ":\(name):",
                    glyph: String(name.prefix(1)).uppercased(),
                    tint: .astrenzaAccent,
                    imageURL: imageURL,
                    emojiSetAddress: tag.count >= 4
                        ? NostrEmojiSetReference.parse(address: tag[3])?.address
                        : nil
                ))
                if candidates.count == 80 { return candidates }
            }
        }
        return candidates
    }

    private static func deduplicatedEmojis(
        _ candidates: [ComposeCustomEmojiCandidate]
    ) -> [ComposeCustomEmojiCandidate] {
        var seen = Set<String>()
        return candidates.filter {
            seen.insert($0.shortcode.lowercased()).inserted
        }
    }

    private static func abbreviated(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(9))…\(value.suffix(7))"
    }
}

struct ComposeSuggestionSource: Sendable {
    let profiles: [NostrProfileSearchResult]
    let recentNotes: [NostrEvent]
    let emojiListEvent: NostrEvent?
    let emojiSetEvents: [NostrEvent]
}

struct ComposeHashtagCandidateCell: View {
    let candidate: ComposeHashtagCandidate

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point8) {
            Image(systemName: candidate.isPinned ? "tag.fill" : "clock.arrow.circlepath")
                .font(.astrenza(.point20, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point1) {
                Text(candidate.tag)
                    .font(.astrenza(.point14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(candidate.recency)
                    .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)
        }
        .padding(.horizontal, AstrenzaSpacing.point10)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point8, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
