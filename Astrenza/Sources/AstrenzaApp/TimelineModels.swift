import SwiftUI

struct TimelinePost: Identifiable {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let timestamp: String
    let replyCount: Int?
    let boostCount: Int?
    let favoriteCount: Int?
    let isLocked: Bool
    let media: TimelineMedia?
    let context: String?
    let repostedBy: TimelineRepostAttribution?
    let quotedPost: QuotedTimelinePost?
    let replyContext: TimelineReplyContext?
    let replyMention: TimelineReplyMention?
    let contentWarning: TimelineContentWarning?
    let actionState: TimelinePostActionState

    init(
        id: String = UUID().uuidString,
        authorName: String,
        handle: String,
        avatar: AvatarStyle,
        body: String,
        timestamp: String,
        replyCount: Int?,
        boostCount: Int?,
        favoriteCount: Int?,
        isLocked: Bool,
        media: TimelineMedia?,
        context: String?,
        repostedBy: TimelineRepostAttribution? = nil,
        quotedPost: QuotedTimelinePost? = nil,
        replyContext: TimelineReplyContext? = nil,
        replyMention: TimelineReplyMention? = nil,
        contentWarning: TimelineContentWarning? = nil,
        actionState: TimelinePostActionState = .none
    ) {
        let author = TimelineAuthor.resolved(
            displayName: authorName,
            nip05: handle.hasPrefix("@") ? String(handle.dropFirst()) : handle,
            nip05Status: .valid,
            pubkey: TimelineAuthor.mockPubkey(for: authorName)
        )
        self.id = id
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.timestamp = timestamp
        self.replyCount = replyCount
        self.boostCount = boostCount
        self.favoriteCount = favoriteCount
        self.isLocked = isLocked
        self.media = media
        self.context = context
        self.repostedBy = repostedBy
        self.quotedPost = quotedPost
        self.replyContext = replyContext
        self.replyMention = replyMention
        self.contentWarning = contentWarning
        self.actionState = actionState
    }

    init(
        id: String = UUID().uuidString,
        author: TimelineAuthor,
        avatar: AvatarStyle,
        body: String,
        timestamp: String,
        replyCount: Int?,
        boostCount: Int?,
        favoriteCount: Int?,
        isLocked: Bool,
        media: TimelineMedia?,
        context: String?,
        repostedBy: TimelineRepostAttribution? = nil,
        quotedPost: QuotedTimelinePost? = nil,
        replyContext: TimelineReplyContext? = nil,
        replyMention: TimelineReplyMention? = nil,
        contentWarning: TimelineContentWarning? = nil,
        actionState: TimelinePostActionState = .none
    ) {
        self.id = id
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.timestamp = timestamp
        self.replyCount = replyCount
        self.boostCount = boostCount
        self.favoriteCount = favoriteCount
        self.isLocked = isLocked
        self.media = media
        self.context = context
        self.repostedBy = repostedBy
        self.quotedPost = quotedPost
        self.replyContext = replyContext
        self.replyMention = replyMention
        self.contentWarning = contentWarning
        self.actionState = actionState
    }
}

struct TimelineContentWarning {
    let reason: String?

    var displayReason: String {
        guard let reason, !reason.isEmpty else {
            return "The author marked this post as sensitive."
        }

        return reason
    }
}

struct TimelineRepostAttribution {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let timestamp: String
}

struct TimelineReplyContext {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let timestamp: String
    let bodyPreview: String
    let isSelfReply: Bool
}

struct TimelineReplyMention {
    let text: String
    let isExternal: Bool
}

struct MockNostrEvent {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let content: String
    let timestamp: String
    let replyTo: TimelinePost?
    let replyMention: TimelineReplyMention?
    let reposts: Int?
    let reactions: Int?
    let actionState: TimelinePostActionState

    func timelinePost() -> TimelinePost {
        TimelinePost(
            id: id,
            author: author,
            avatar: avatar,
            body: content,
            timestamp: timestamp,
            replyCount: nil,
            boostCount: reposts,
            favoriteCount: reactions,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: replyTo.map(replyContext(for:)),
            replyMention: replyMention,
            actionState: actionState
        )
    }

    private func replyContext(for parent: TimelinePost) -> TimelineReplyContext {
        TimelineReplyContext(
            author: parent.author,
            avatar: parent.avatar,
            timestamp: parent.timestamp,
            bodyPreview: parent.body,
            isSelfReply: author.pubkey == parent.author.pubkey
        )
    }
}

struct QuotedTimelinePost {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let timestamp: String
    let isAvailable: Bool
}

struct TimelineAuthor {
    let displayName: String?
    let nip05: String?
    let nip05Status: NIP05Status
    let pubkey: String
    let isMetadataResolved: Bool

    var primaryText: String {
        guard let displayName, !displayName.isEmpty else {
            return abbreviatedPubkey
        }

        return displayName
    }

    var secondaryText: String {
        guard isMetadataResolved else {
            return "kind:0 pending"
        }

        guard let nip05, !nip05.isEmpty else {
            return abbreviatedPubkey
        }

        return displayableNIP05(nip05)
    }

    var secondarySystemName: String {
        if !isMetadataResolved {
            return "clock"
        }

        switch nip05Status {
        case .valid:
            return "checkmark.seal.fill"
        case .invalid:
            return "exclamationmark.triangle.fill"
        case .unchecked:
            return "questionmark.circle"
        case .absent:
            return "key.horizontal"
        }
    }

    static func resolved(
        displayName: String,
        nip05: String?,
        nip05Status: NIP05Status = .valid,
        pubkey: String
    ) -> TimelineAuthor {
        TimelineAuthor(
            displayName: displayName,
            nip05: nip05,
            nip05Status: nip05 == nil ? .absent : nip05Status,
            pubkey: pubkey,
            isMetadataResolved: true
        )
    }

    static func unresolved(pubkey: String) -> TimelineAuthor {
        TimelineAuthor(displayName: nil, nip05: nil, nip05Status: .absent, pubkey: pubkey, isMetadataResolved: false)
    }

    static func mockPubkey(for seed: String) -> String {
        let suffix = seed.lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .padding(toLength: 8, withPad: "0", startingAt: 0)
        return "npub1\(suffix)8x7k2p9q4m6v0s3n5rjcw"
    }

    private func displayableNIP05(_ identifier: String) -> String {
        guard identifier.hasPrefix("_@") else {
            return identifier
        }

        return String(identifier.dropFirst(2))
    }

    private var abbreviatedPubkey: String {
        guard pubkey.count > 16 else { return pubkey }

        return "\(pubkey.prefix(10))...\(pubkey.suffix(6))"
    }
}

enum NIP05Status {
    case absent
    case unchecked
    case invalid
    case valid
}

struct TimelinePostActionState {
    let didReply: Bool
    let didRepost: Bool
    let didFavorite: Bool
    let didZap: Bool

    static let none = TimelinePostActionState(
        didReply: false,
        didRepost: false,
        didFavorite: false,
        didZap: false
    )
}

struct AvatarStyle {
    let primary: Color
    let secondary: Color
    let symbolName: String
    let pictureState: AvatarPictureState
    let placeholderSeed: String

    init(
        primary: Color,
        secondary: Color,
        symbolName: String,
        pictureState: AvatarPictureState = .resolved,
        placeholderSeed: String = ""
    ) {
        self.primary = primary
        self.secondary = secondary
        self.symbolName = symbolName
        self.pictureState = pictureState
        self.placeholderSeed = placeholderSeed
    }

    func withPlaceholderSeed(_ seed: String) -> AvatarStyle {
        AvatarStyle(
            primary: primary,
            secondary: secondary,
            symbolName: symbolName,
            pictureState: pictureState,
            placeholderSeed: seed
        )
    }
}

enum AvatarPictureState {
    case resolved
    case missing
    case metadataPending
    case failed

    var usesPlaceholder: Bool {
        switch self {
        case .resolved:
            false
        case .missing, .metadataPending, .failed:
            true
        }
    }

    var markerSystemName: String? {
        switch self {
        case .resolved:
            nil
        case .missing:
            "person.crop.circle"
        case .metadataPending:
            "clock"
        case .failed:
            "exclamationmark"
        }
    }
}

enum TimelineMedia {
    case weather
    case gallery([MediaTile])
    case linkPreview(LinkPreview)
    case unresolvedLink(UnresolvedLinkPreview)
}

struct MediaTile: Identifiable {
    let id = UUID()
    let title: String
    let colors: [Color]
    let symbolName: String
}

struct LinkPreview {
    let title: String
    let subtitle: String
    let host: String
}

struct UnresolvedLinkPreview {
    let host: String
    let url: String
}

enum MockTimelineData {
    static var posts: [TimelinePost] {
        store.homeTimeline
    }

    private static let store = MockTimelineStore(basePosts: basePosts)

    private static let basePosts: [TimelinePost] = [
        TimelinePost(
            id: "thread-a-root",
            authorName: "Yuki Sato",
            handle: "@yuki@relay.town",
            avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles"),
            body: "Nostr の relay を切り替えても、既読位置がふわっと戻る体験を最優先にしたい。タイムラインは速さより「迷子にならない」ほうが大事。",
            timestamp: "2m",
            replyCount: nil,
            boostCount: 7,
            favoriteCount: 18,
            isLocked: false,
            media: nil,
            context: nil,
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: true, didZap: false)
        ),
        TimelinePost(
            authorName: "Astral Notes",
            handle: "@astral@nostr.example",
            avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
            body: "Home / Local / Federated ではなく、Nostr では Home / Relays / Lists という切替が気持ちよさそう。Tapbots 的な密度で、relay 状態だけ少し見えるようにする。",
            timestamp: "18m",
            replyCount: 2,
            boostCount: 14,
            favoriteCount: 46,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "NIP-65 Outbox Model",
                subtitle: "Read/write relays を分けて timeline を安定させる設計メモ",
                host: "docs.astrenza.app"
            )),
            context: "Pinned research",
            actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: true)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Taro Relay",
                nip05: "taro@relay.town",
                pubkey: "npub1tarorelay9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .mint, secondary: .blue, symbolName: "arrow.triangle.2.circlepath"),
            body: "週末にリレー構成を少し整理したら、TLの読み込みがだいぶ落ち着いた。read/write を分けて眺めるだけでも体感が変わる。",
            timestamp: "26m",
            replyCount: 1,
            boostCount: 9,
            favoriteCount: 24,
            isLocked: false,
            media: nil,
            context: nil,
            repostedBy: TimelineRepostAttribution(
                author: .resolved(
                    displayName: "Yuki Sato",
                    nip05: "yuki@relay.town",
                    pubkey: "npub1yukirepost9q4m6v0s3n5rjcw"
                ),
                avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles"),
                timestamp: "5m"
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: false, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Kedama",
                nip05: "kedama@foresdon.jp",
                pubkey: "npub1kedamacontentwarning9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .brown, secondary: .yellow, symbolName: "exclamationmark.triangle.fill"),
            body: "シュタゲ0 のアニメを観ています ep.16\nん〜アニメでは多少のフォローは入ってているけど……真帆が紅莉栖に勝てない絶望と、見知った顔の幸せそうな「今」を何度も奪って、それでも目の前で見知った顔が繰り返し繰り返し何度もしんでいく絶望を、同列に語るのは……ちょっと重さが違うんですよねぇ……。",
            timestamp: "31m",
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            contentWarning: TimelineContentWarning(reason: "Steins;Gate 0 episode 16 spoilers")
        ),
        TimelinePost(
            authorName: "Mika",
            handle: "@mika@notes.cafe",
            avatar: AvatarStyle(primary: .orange, secondary: .yellow, symbolName: "cup.and.saucer.fill"),
            body: "今日のテスト端末、外が暑すぎて手から滑りそう。32 度で。",
            timestamp: "35m",
            replyCount: 1,
            boostCount: nil,
            favoriteCount: 9,
            isLocked: false,
            media: .weather,
            context: nil,
            actionState: TimelinePostActionState(didReply: true, didRepost: false, didFavorite: false, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Nozomi",
                nip05: "nozomi@design.pub",
                pubkey: "npub1nozomiquoted9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .pink, secondary: .orange, symbolName: "quote.bubble.fill"),
            body: "Quoted repost は reply thread に混ぜたくないので、本文中の nostr:nevent 参照は q tag として扱うのがよさそう。UIは引用カードとして本文の直下に置く。",
            timestamp: "39m",
            replyCount: 2,
            boostCount: 6,
            favoriteCount: 21,
            isLocked: false,
            media: nil,
            context: "Quoted repost",
            quotedPost: QuotedTimelinePost(
                author: .resolved(
                    displayName: "Ren",
                    nip05: "ren@web.nostr",
                    pubkey: "npub1renquotedsource9q4m6v0s3n5rjcw"
                ),
                avatar: AvatarStyle(
                    primary: .indigo,
                    secondary: .blue,
                    symbolName: "link.circle.fill",
                    pictureState: .missing
                ),
                body: "NIP-18 の q tag は quote repost をreply扱いにしないための手がかりになる。countにも使いやすい。",
                timestamp: "31m",
                isAvailable: true
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Hota",
                nip05: "hota@relay.cafe",
                pubkey: "npub1hotareply9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .blue, secondary: .indigo, symbolName: "person.crop.circle.fill"),
            body: "緊急すぎて上級者モードしか回せてなかった",
            timestamp: "40m",
            replyCount: 1,
            boostCount: 2,
            favoriteCount: 11,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: TimelineReplyContext(
                author: .resolved(
                    displayName: "unarist",
                    nip05: "unarist@relay.maud.io",
                    pubkey: "npub1unaristreplysource9q4m6v0s3n5rjcw"
                ),
                avatar: AvatarStyle(primary: .cyan, secondary: .white, symbolName: "circle.dotted"),
                timestamp: "45m",
                bodyPreview: "あーわかった、ディスクフルだ多分。",
                isSelfReply: false
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: false, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "unarist",
                nip05: "unarist@relay.maud.io",
                pubkey: "npub1unaristreplysource9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .cyan, secondary: .white, symbolName: "circle.dotted"),
            body: "ああ...言われてみればこのマシンならUSBポートにガタが来てても別におかしくないか...さんきゅう...",
            timestamp: "41m",
            replyCount: nil,
            boostCount: nil,
            favoriteCount: 7,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: TimelineReplyContext(
                author: .resolved(
                    displayName: "pikepikeid",
                    nip05: "pikepikeid@relay.tools",
                    pubkey: "npub1pikepikeidreply9q4m6v0s3n5rjcw"
                ),
                avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "wrench.and.screwdriver.fill"),
                timestamp: "43m",
                bodyPreview: "USBの接触も疑ったほうがよさそう",
                isSelfReply: false
            ),
            replyMention: TimelineReplyMention(text: "@pikepikeid", isExternal: true)
        ),
        TimelinePost(
            author: .unresolved(pubkey: "npub1ren9q3z6r4m8x2k0v5c7n1pwaesdftimelinefallback"),
            avatar: AvatarStyle(
                primary: .indigo,
                secondary: .blue,
                symbolName: "link.circle.fill",
                pictureState: .metadataPending
            ),
            body: "OGP が解決できないURLも、カードの高さは固定しておくと復帰位置が安定しそう。",
            timestamp: "42m",
            replyCount: nil,
            boostCount: 4,
            favoriteCount: 17,
            isLocked: false,
            media: .unresolvedLink(UnresolvedLinkPreview(
                host: "unknown.example",
                url: "https://unknown.example/posts/nostr-client-layout"
            )),
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Relay Watch",
                nip05: nil,
                pubkey: "npub1relaywatch9s8d7f6g5h4j3k2l1monitor"
            ),
            avatar: AvatarStyle(
                primary: .green,
                secondary: .mint,
                symbolName: "antenna.radiowaves.left.and.right",
                pictureState: .missing
            ),
            body: "wss://relay.damus.io と wss://nos.lol は catch-up 済み。wss://relay.snort.social は AUTH required。",
            timestamp: "1h",
            replyCount: nil,
            boostCount: 3,
            favoriteCount: 12,
            isLocked: true,
            media: nil,
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Nozomi with an unnecessarily long display name for timeline stress testing",
                nip05: "nozomi.with.a.very.long.nip05.identifier.for.timeline.layout.testing@designers-and-relays.example",
                nip05Status: .unchecked,
                pubkey: "npub1nozomi7k2p9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(
                primary: .pink,
                secondary: .orange,
                symbolName: "camera.fill",
                pictureState: .failed
            ),
            body: "1枚画像は横幅をしっかり使って、本文の余韻を壊さないくらいの角丸にしたい。",
            timestamp: "1h",
            replyCount: 3,
            boostCount: 8,
            favoriteCount: 31,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Dock", colors: [.indigo, .cyan], symbolName: "rectangle.landscape.rotate")
            ]),
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Haru",
                nip05: "_@photo.pub",
                pubkey: "npub1haru7k2p9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .blue, secondary: .teal, symbolName: "camera.aperture"),
            body: "メディア grid は Ivory みたいに角丸を抑えて、余白も詰めると feed の密度が保てる。",
            timestamp: "2h",
            replyCount: 4,
            boostCount: 21,
            favoriteCount: 88,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Relay", colors: [.blue, .purple], symbolName: "network"),
                MediaTile(title: "Key", colors: [.orange, .red], symbolName: "key.fill")
            ]),
            context: nil,
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: false, didZap: true)
        ),
        TimelinePost(
            authorName: "Sora",
            handle: "@sora@relay.art",
            avatar: AvatarStyle(primary: .teal, secondary: .mint, symbolName: "paintbrush.pointed.fill"),
            body: "3枚は上2枚、下1枚。最後の1枚を大きく見せると、投稿の締めが少し強くなる。",
            timestamp: "2h",
            replyCount: 2,
            boostCount: 11,
            favoriteCount: 42,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Sky", colors: [.cyan, .blue], symbolName: "cloud.fill"),
                MediaTile(title: "Relay", colors: [.purple, .indigo], symbolName: "network"),
                MediaTile(title: "Note", colors: [.orange, .yellow], symbolName: "text.bubble.fill")
            ]),
            context: nil
        ),
        TimelinePost(
            authorName: "Luna",
            handle: "@luna@media.nostr",
            avatar: AvatarStyle(primary: .purple, secondary: .blue, symbolName: "sparkles"),
            body: "4枚は2+2で安定。feedの中で一番スキャンしやすい構図かもしれない。",
            timestamp: "2h",
            replyCount: 6,
            boostCount: 19,
            favoriteCount: 67,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Home", colors: [.blue, .purple], symbolName: "house.fill"),
                MediaTile(title: "Keys", colors: [.orange, .red], symbolName: "key.fill"),
                MediaTile(title: "Relay", colors: [.green, .mint], symbolName: "antenna.radiowaves.left.and.right"),
                MediaTile(title: "Post", colors: [.pink, .purple], symbolName: "square.and.pencil")
            ]),
            context: nil
        ),
        TimelinePost(
            authorName: "Mori",
            handle: "@mori@photo.example",
            avatar: AvatarStyle(primary: .green, secondary: .yellow, symbolName: "leaf.fill"),
            body: "5枚以上は4枚gridの最後に +n。隠れている枚数がわかるだけで、見た目の密度が落ち着く。",
            timestamp: "3h",
            replyCount: 4,
            boostCount: 16,
            favoriteCount: 59,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Forest", colors: [.green, .mint], symbolName: "leaf.fill"),
                MediaTile(title: "Night", colors: [.indigo, .black], symbolName: "moon.stars.fill"),
                MediaTile(title: "Sun", colors: [.orange, .yellow], symbolName: "sun.max.fill"),
                MediaTile(title: "Wave", colors: [.cyan, .blue], symbolName: "water.waves"),
                MediaTile(title: "Path", colors: [.brown, .orange], symbolName: "point.topleft.down.curvedto.point.bottomright.up"),
                MediaTile(title: "Key", colors: [.purple, .pink], symbolName: "key.fill")
            ]),
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "Kai",
                nip05: "kai@dev.nostr",
                nip05Status: .invalid,
                pubkey: "npub1differentpubkey9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .gray, secondary: .white, symbolName: "terminal.fill"),
            body: "まずは UI shell。次に timeline store、relay manager、NIP-01 event parser。順番を間違えると、見た目の気持ちよさが後で壊れがち。",
            timestamp: "3h",
            replyCount: nil,
            boostCount: 5,
            favoriteCount: 23,
            isLocked: false,
            media: nil,
            context: nil
        )
    ]

    static func detailReplies(for post: TimelinePost) -> [TimelinePost] {
        store.descendants(of: post)
    }

    static func replyParent(for post: TimelinePost) -> TimelinePost? {
        store.parent(of: post)
    }

    static func replyAncestors(for post: TimelinePost) -> [TimelinePost] {
        store.ancestors(of: post)
    }
}

private struct MockTimelineRecord {
    let post: TimelinePost
    let replyToID: TimelinePost.ID?
    let appearsInHome: Bool
}

private struct MockTimelineStore {
    let records: [MockTimelineRecord]

    init(basePosts: [TimelinePost]) {
        var nextRecords: [MockTimelineRecord] = []

        for post in basePosts {
            if let replyContext = post.replyContext {
                let parentPost = Self.parentPost(from: replyContext, childID: post.id)
                nextRecords.append(MockTimelineRecord(post: parentPost, replyToID: nil, appearsInHome: false))
                nextRecords.append(MockTimelineRecord(post: post, replyToID: parentPost.id, appearsInHome: true))
            } else {
                nextRecords.append(MockTimelineRecord(post: post, replyToID: nil, appearsInHome: true))
            }
        }

        if let featuredThreadRoot = basePosts.first(where: { $0.id == "thread-a-root" }) {
            nextRecords.append(contentsOf: Self.featuredReplyThreadRecords(root: featuredThreadRoot))
        }

        records = nextRecords
    }

    var homeTimeline: [TimelinePost] {
        records
            .filter(\.appearsInHome)
            .map(\.post)
    }

    func replies(to post: TimelinePost) -> [TimelinePost] {
        records
            .filter { $0.replyToID == post.id }
            .map(\.post)
    }

    func parent(of post: TimelinePost) -> TimelinePost? {
        guard let replyToID = records.first(where: { $0.post.id == post.id })?.replyToID else {
            return nil
        }

        return records.first(where: { $0.post.id == replyToID })?.post
    }

    func ancestors(of post: TimelinePost) -> [TimelinePost] {
        var ancestors: [TimelinePost] = []
        var currentPost = post

        while let parentPost = parent(of: currentPost) {
            ancestors.insert(parentPost, at: 0)
            currentPost = parentPost
        }

        return ancestors
    }

    func descendants(of post: TimelinePost) -> [TimelinePost] {
        var descendants: [TimelinePost] = []
        var currentPost = post

        while let childPost = replies(to: currentPost).first {
            descendants.append(childPost)
            currentPost = childPost
        }

        return descendants
    }

    private static func featuredReplyThreadRecords(root: TimelinePost) -> [MockTimelineRecord] {
        let firstReply = MockNostrEvent(
            id: "thread-b-reply",
            author: root.author,
            avatar: root.avatar,
            content: "追記: これ、relay側の遅延だけじゃなくてclient側の復帰処理も絡んでいそう。",
            timestamp: "1m",
            replyTo: root,
            replyMention: TimelineReplyMention(text: "@\(root.author.replyMentionHandle)", isExternal: false),
            reposts: nil,
            reactions: 4,
            actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: false)
        ).timelinePost()

        let secondReply = MockNostrEvent(
            id: "thread-c-reply",
            author: .resolved(
                displayName: "Mika",
                nip05: "mika@notes.cafe",
                pubkey: "npub1mikareplydetail9q4m6v0s3n5rjcw"
            ),
            avatar: AvatarStyle(primary: .orange, secondary: .yellow, symbolName: "cup.and.saucer.fill"),
            content: "このへん、再接続後に既読位置を戻すタイミングを少し遅らせると見た目も安定しそう。",
            timestamp: "6m",
            replyTo: firstReply,
            replyMention: TimelineReplyMention(text: "@\(firstReply.author.replyMentionHandle)", isExternal: true),
            reposts: 1,
            reactions: 9,
            actionState: .none
        ).timelinePost()

        let thirdReply = MockNostrEvent(
            id: "thread-d-reply",
            author: root.author,
            avatar: root.avatar,
            content: "さらにメモ: ツリーは表示用に作るんじゃなくて、event の reply chain から切り出すほうが事故らない。",
            timestamp: "8m",
            replyTo: secondReply,
            replyMention: TimelineReplyMention(text: "@\(secondReply.author.replyMentionHandle)", isExternal: true),
            reposts: nil,
            reactions: 3,
            actionState: .none
        ).timelinePost()

        return [
            MockTimelineRecord(
                post: firstReply,
                replyToID: root.id,
                appearsInHome: false
            ),
            MockTimelineRecord(
                post: secondReply,
                replyToID: firstReply.id,
                appearsInHome: false
            ),
            MockTimelineRecord(
                post: thirdReply,
                replyToID: secondReply.id,
                appearsInHome: false
            )
        ]
    }

    private static func parentPost(from replyContext: TimelineReplyContext, childID: TimelinePost.ID) -> TimelinePost {
        TimelinePost(
            id: "\(childID)-reply-parent",
            author: replyContext.author,
            avatar: replyContext.avatar,
            body: replyContext.bodyPreview,
            timestamp: replyContext.timestamp,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
    }
}

private extension TimelineAuthor {
    var replyMentionHandle: String {
        primaryText
            .filter { !$0.isWhitespace }
            .lowercased()
    }
}
