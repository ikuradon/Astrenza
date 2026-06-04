import SwiftUI

enum MockTimelineData {
    static var posts: [TimelinePost] {
        store.homeTimeline
    }

    private static let store = MockTimelineStore(basePosts: basePosts)

    private static let basePosts: [TimelinePost] = [
        TimelinePost(
            id: "thread-a-root",
            authorName: "User Alpha",
            handle: "@alpha@mock.example",
            avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles"),
            body: "リレー構成を切り替えても、既読位置が自然に戻る体験を最優先にしたい。タイムラインは速さより迷子にならないことを大事にしたい。",
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
            authorName: "User Beta",
            handle: "@beta@mock.example",
            avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
            body: "Home / Relays / Lists の切り替えを、投稿密度を崩さずに扱いたい。接続状態は少しだけ見えているくらいが気持ちよさそう。",
            timestamp: "18m",
            replyCount: 2,
            boostCount: 14,
            favoriteCount: 46,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "Relay Routing Notes",
                subtitle: "read/write relay を分けて timeline を安定させる設計メモ",
                host: "docs.mock.example",
                url: "https://docs.mock.example/relay-routing"
            )),
            context: nil,
            actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: true)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Gamma",
                nip05: "gamma@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-gamma"),
                isFollowed: false
            ),
            avatar: AvatarStyle(primary: .mint, secondary: .blue, symbolName: "arrow.triangle.2.circlepath"),
            body: "週末に接続先を少し整理したら、TLの読み込みがだいぶ落ち着いた。read/write を分けて眺めるだけでも体感が変わる。",
            timestamp: "26m",
            replyCount: 1,
            boostCount: 9,
            favoriteCount: 24,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "Relay Maintenance Log",
                subtitle: "フォロー外ユーザー由来のRTではOGPだけを保護表示にする",
                host: "logs.mock.example",
                url: "https://logs.mock.example/relay-maintenance"
            )),
            context: nil,
            repostedBy: TimelineRepostAttribution(
                author: .resolved(
                    displayName: "User Alpha",
                    nip05: "alpha@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "user-alpha-repost")
                ),
                avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles"),
                timestamp: "5m"
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: false, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Delta",
                nip05: "delta@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-delta")
            ),
            avatar: AvatarStyle(primary: .brown, secondary: .yellow, symbolName: "exclamationmark.triangle.fill"),
            body: "架空作品の最新話を観ています。\nこの先は展開に触れるので、タイムラインでは本文だけを伏せておきたい。詳細画面では理由がわかるように表示しておく。",
            timestamp: "31m",
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil,
            contentWarning: TimelineContentWarning(reason: "Fictional episode spoilers")
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Zeta",
                nip05: "zeta@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-zeta")
            ),
            avatar: AvatarStyle(primary: .pink, secondary: .orange, symbolName: "quote.bubble.fill"),
            body: "引用投稿は reply thread に混ぜず、本文の直下にカードとして置くと読みやすい。通常の返信とは見え方を分けたい。",
            timestamp: "39m",
            replyCount: 2,
            boostCount: 6,
            favoriteCount: 21,
            isLocked: false,
            media: nil,
            context: nil,
            quotedPost: QuotedTimelinePost(
                author: .resolved(
                    displayName: "User Eta",
                    nip05: "eta@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "user-eta")
                ),
                avatar: AvatarStyle(
                    primary: .indigo,
                    secondary: .blue,
                    symbolName: "link.circle.fill",
                    pictureState: .missing
                ),
                body: "引用参照は返信扱いにしないための手がかりになる。表示上もcount上も別物として扱いたい。",
                timestamp: "31m",
                isAvailable: true
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Theta",
                nip05: "theta@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-theta")
            ),
            avatar: AvatarStyle(primary: .blue, secondary: .indigo, symbolName: "person.crop.circle.fill"),
            body: "急いでいたので設定画面をちゃんと見直せていなかった。",
            timestamp: "40m",
            replyCount: 1,
            boostCount: 2,
            favoriteCount: 11,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: TimelineReplyContext(
                author: .resolved(
                    displayName: "User Iota",
                    nip05: "iota@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "user-iota")
                ),
                avatar: AvatarStyle(primary: .cyan, secondary: .white, symbolName: "circle.dotted"),
                timestamp: "45m",
                bodyPreview: "原因がわかったかもしれない。たぶん保存領域まわりです。",
                isSelfReply: false
            ),
            actionState: TimelinePostActionState(didReply: false, didRepost: true, didFavorite: false, didZap: false)
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Iota",
                nip05: "iota@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-iota")
            ),
            avatar: AvatarStyle(primary: .cyan, secondary: .white, symbolName: "circle.dotted"),
            body: "言われてみれば、この端末なら接続まわりの不調も疑ったほうがよさそう。助かりました。",
            timestamp: "41m",
            replyCount: nil,
            boostCount: nil,
            favoriteCount: 7,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: TimelineReplyContext(
                author: .resolved(
                    displayName: "User Kappa",
                    nip05: "kappa@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "user-kappa")
                ),
                avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "wrench.and.screwdriver.fill"),
                timestamp: "43m",
                bodyPreview: "接続部分の状態も疑ったほうがよさそう。",
                isSelfReply: false
            ),
            replyMention: TimelineReplyMention(text: "@kappa", isExternal: true)
        ),
        TimelinePost(
            author: .unresolved(pubkey: TimelineAuthor.mockPubkey(for: "user-unknown")),
            avatar: AvatarStyle(
                primary: .indigo,
                secondary: .blue,
                symbolName: "link.circle.fill",
                pictureState: .metadataPending
            ),
            body: "リンクプレビューが解決できないURLも、カードの高さは固定しておくと復帰位置が安定しそう。",
            timestamp: "42m",
            replyCount: nil,
            boostCount: 4,
            favoriteCount: 17,
            isLocked: false,
            media: .unresolvedLink(UnresolvedLinkPreview(
                host: "unknown.mock.example",
                url: "https://unknown.mock.example/posts/client-layout"
            )),
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Lambda",
                nip05: nil,
                pubkey: TimelineAuthor.mockPubkey(for: "user-lambda")
            ),
            avatar: AvatarStyle(
                primary: .green,
                secondary: .mint,
                symbolName: "antenna.radiowaves.left.and.right",
                pictureState: .missing
            ),
            body: "wss://relay-a.mock.example と wss://relay-b.mock.example は catch-up 済み。wss://relay-c.mock.example は AUTH required。",
            timestamp: "1h",
            replyCount: nil,
            boostCount: 3,
            favoriteCount: 12,
            isLocked: false,
            media: nil,
            context: nil
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Mu with an unnecessarily long display name for timeline stress testing",
                nip05: "mu.with.a.very.long.nip05.identifier.for.timeline.layout.testing@mock-long-domain.example",
                nip05Status: .unchecked,
                pubkey: TimelineAuthor.mockPubkey(for: "user-mu")
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
                displayName: "User Nu",
                nip05: "_@mock-photo.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-nu")
            ),
            avatar: AvatarStyle(primary: .blue, secondary: .teal, symbolName: "camera.aperture"),
            body: "メディア grid は角丸を抑えて、余白も詰めると feed の密度が保てる。",
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
            authorName: "User Xi",
            handle: "@xi@mock.example",
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
            authorName: "User Omicron",
            handle: "@omicron@mock.example",
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
            authorName: "User Pi",
            handle: "@pi@mock.example",
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
                displayName: "User Rho",
                nip05: "rho@mock.example",
                nip05Status: .invalid,
                pubkey: TimelineAuthor.mockPubkey(for: "user-rho")
            ),
            avatar: AvatarStyle(primary: .gray, secondary: .white, symbolName: "terminal.fill"),
            body: "まずは UI shell。次に timeline store、relay manager、event parser。順番を間違えると、見た目の気持ちよさが後で壊れがち。",
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

        let secondReplyAuthor = TimelineAuthor.resolved(
            displayName: "User Sigma",
            nip05: "sigma@mock.example",
            pubkey: TimelineAuthor.mockPubkey(for: "user-sigma"),
            isFollowed: false
        )
        let secondReplyAvatar = AvatarStyle(primary: .orange, secondary: .yellow, symbolName: "cup.and.saucer.fill")
        let secondReply = TimelinePost(
            id: "thread-c-reply",
            author: secondReplyAuthor,
            avatar: secondReplyAvatar,
            body: "このへん、再接続後に既読位置を戻すタイミングを少し遅らせると見た目も安定しそう。",
            timestamp: "6m",
            replyCount: nil,
            boostCount: 1,
            favoriteCount: 9,
            isLocked: false,
            media: .gallery([
                MediaTile(title: "Trace", colors: [.orange, .yellow], symbolName: "point.topleft.down.curvedto.point.bottomright.up"),
                MediaTile(title: "Relay", colors: [.blue, .purple], symbolName: "network")
            ]),
            context: nil,
            replyContext: TimelineReplyContext(
                author: firstReply.author,
                avatar: firstReply.avatar,
                timestamp: firstReply.timestamp,
                bodyPreview: firstReply.body,
                isSelfReply: secondReplyAuthor.pubkey == firstReply.author.pubkey
            ),
            replyMention: TimelineReplyMention(text: "@\(firstReply.author.replyMentionHandle)", isExternal: true)
        )

        let thirdReply = MockNostrEvent(
            id: "thread-d-reply",
            author: root.author,
            avatar: root.avatar,
            content: "さらにメモ: ツリーは表示用に作るのではなく、event の reply chain から切り出すほうが事故らない。",
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
