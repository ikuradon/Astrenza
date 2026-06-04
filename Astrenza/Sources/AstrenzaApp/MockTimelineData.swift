import SwiftUI

enum MockTimelineData {
    static var posts: [TimelinePost] {
        store.homeTimeline
    }

    static let selfProfile = UserProfile(
        id: "profile-self",
        author: .resolved(
            displayName: "User Alpha",
            nip05: "_@mock.example",
            pubkey: TimelineAuthor.mockPubkey(for: "user-alpha-profile")
        ),
        avatar: AvatarStyle(primary: .cyan, secondary: .indigo, symbolName: "sparkles"),
        banner: ProfileBannerStyle(colors: [.cyan, .indigo, .purple], symbolName: "network"),
        bio: "Nostr client の読み心地を整えています。relay、timeline、gesture、Liquid Glass。",
        isCurrentUser: true,
        isFollowed: true,
        followerCount: 558,
        followingCount: 2_139,
        postCount: 13_034,
        relayCount: 7,
        latestFollowers: [
            AvatarStyle(primary: .pink, secondary: .orange, symbolName: "quote.bubble.fill"),
            AvatarStyle(primary: .purple, secondary: .blue, symbolName: "sparkles"),
            AvatarStyle(primary: .green, secondary: .mint, symbolName: "antenna.radiowaves.left.and.right"),
            AvatarStyle(primary: .orange, secondary: .yellow, symbolName: "cup.and.saucer.fill"),
            AvatarStyle(primary: .blue, secondary: .teal, symbolName: "camera.aperture"),
            AvatarStyle(primary: .gray, secondary: .white, symbolName: "terminal.fill"),
            AvatarStyle(primary: .mint, secondary: .blue, symbolName: "arrow.triangle.2.circlepath")
        ],
        featuredHashtags: [
            UserFeaturedHashtag(tag: "#nostrclient", lastUsed: "Used 2 days ago", count: 42),
            UserFeaturedHashtag(tag: "#timeline", lastUsed: "Used 1 week ago", count: 18)
        ]
    )

    static var selfProfilePosts: [TimelinePost] {
        [
            TimelinePost(
                id: "profile-self-note-1",
                author: selfProfile.author,
                avatar: selfProfile.avatar,
                body: "Profile画面は、kind:0 と NIP-05 の状態が一目でわかるくらいがちょうどいい。細かいrelay hintは奥に置く。",
                timestamp: "8m",
                replyCount: 2,
                boostCount: 6,
                favoriteCount: 18,
                isLocked: false,
                media: nil,
                context: nil,
                actionState: TimelinePostActionState(didReply: false, didRepost: false, didFavorite: true, didZap: false)
            ),
            TimelinePost(
                id: "profile-self-note-2",
                author: selfProfile.author,
                avatar: selfProfile.avatar,
                body: "Featured Hashtags はNIPの専用機能ではなく、投稿やlistから集計したクライアント側の見せ方として扱うのが自然そう。",
                timestamp: "31m",
                replyCount: nil,
                boostCount: 3,
                favoriteCount: 14,
                isLocked: false,
                media: .linkPreview(LinkPreview(
                    title: "Profile Surface Notes",
                    subtitle: "kind:0, follow list, relay metadata, count query をプロフィール表示へ落とし込む",
                    host: "design.mock.example",
                    url: "https://design.mock.example/profile-surface"
                )),
                context: nil
            ),
            TimelinePost(
                id: "profile-self-reply-1",
                author: selfProfile.author,
                avatar: selfProfile.avatar,
                body: "返信込みのタブでは、会話文脈をTLと同じComponentで見せたい。",
                timestamp: "1h",
                replyCount: 1,
                boostCount: nil,
                favoriteCount: 7,
                isLocked: false,
                media: nil,
                context: nil,
                replyContext: TimelineReplyContext(
                    author: .resolved(
                        displayName: "User Beta",
                        nip05: "beta@mock.example",
                        pubkey: TimelineAuthor.mockPubkey(for: "profile-reply-parent")
                    ),
                    avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
                    timestamp: "1h",
                    bodyPreview: "プロフィールの投稿一覧もTLと同じ触り心地にしたい。",
                    isSelfReply: false
                ),
                replyMention: TimelineReplyMention(text: "@beta", isExternal: true)
            ),
            TimelinePost(
                id: "profile-self-boost-1",
                author: .resolved(
                    displayName: "User Sigma",
                    nip05: "sigma@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "profile-boost-source"),
                    isFollowed: false
                ),
                avatar: AvatarStyle(primary: .orange, secondary: .yellow, symbolName: "cup.and.saucer.fill"),
                body: "User Detailのヘッダーは大きく、投稿行はいつもの密度。ここが揃うとアプリ全体の手触りがかなり安定する。",
                timestamp: "2h",
                replyCount: nil,
                boostCount: 9,
                favoriteCount: 24,
                isLocked: false,
                media: nil,
                context: nil,
                repostedBy: TimelineRepostAttribution(
                    author: selfProfile.author,
                    avatar: selfProfile.avatar,
                    timestamp: "48m"
                )
            )
        ]
    }

    static func profile(for post: TimelinePost) -> UserProfile {
        if post.author.pubkey == selfProfile.author.pubkey {
            return selfProfile
        }

        let score = profileScore(for: post.author.pubkey)

        return UserProfile(
            id: "profile-\(post.author.pubkey)",
            author: post.author,
            avatar: post.avatar,
            banner: ProfileBannerStyle(
                colors: [
                    post.avatar.primary.opacity(0.92),
                    post.avatar.secondary.opacity(0.88),
                    Color.astrenzaAccent.opacity(0.72)
                ],
                symbolName: post.avatar.symbolName
            ),
            bio: "\(post.author.primaryText) のmock profile。kind:0、NIP-05、follow stateをTLと同じComponentから確認するための表示です。",
            isCurrentUser: false,
            isFollowed: post.author.isFollowed,
            followerCount: 180 + score % 9_000,
            followingCount: 24 + score % 1_200,
            postCount: 400 + score % 24_000,
            relayCount: 3 + score % 9,
            latestFollowers: followerAvatars(for: post.avatar),
            featuredHashtags: [
                UserFeaturedHashtag(tag: "#mockprofile", lastUsed: "Used 3 days ago", count: 12 + score % 40),
                UserFeaturedHashtag(tag: "#nostr", lastUsed: "Used 2 weeks ago", count: 8 + score % 22)
            ]
        )
    }

    static func profilePosts(for profile: UserProfile) -> [TimelinePost] {
        if profile.id == selfProfile.id {
            return selfProfilePosts
        }

        let relatedPosts = posts.filter { $0.author.pubkey == profile.author.pubkey }

        return relatedPosts + [
            TimelinePost(
                id: "\(profile.id)-mock-note-1",
                author: profile.author,
                avatar: profile.avatar,
                body: "プロフィールから見た投稿一覧のmock。TLからアバターをタップした時も、同じRowの見た目とジェスチャで動くようにしている。",
                timestamp: "18m",
                replyCount: 1,
                boostCount: 4,
                favoriteCount: 16,
                isLocked: false,
                media: nil,
                context: nil
            ),
            TimelinePost(
                id: "\(profile.id)-mock-reply-1",
                author: profile.author,
                avatar: profile.avatar,
                body: "返信込みタブでは、親投稿の文脈だけ軽く添えて密度を落とさない。",
                timestamp: "47m",
                replyCount: nil,
                boostCount: 1,
                favoriteCount: 9,
                isLocked: false,
                media: nil,
                context: nil,
                replyContext: TimelineReplyContext(
                    author: selfProfile.author,
                    avatar: selfProfile.avatar,
                    timestamp: "51m",
                    bodyPreview: "プロフィール内でもTLと同じ返信Componentを使いたい。",
                    isSelfReply: false
                ),
                replyMention: TimelineReplyMention(text: "@alpha", isExternal: true)
            )
        ]
    }

    private static let store = MockTimelineStore(basePosts: basePosts)

    private static func profileScore(for seed: String) -> Int {
        seed.unicodeScalars.reduce(0) { result, scalar in
            abs(result &* 31 &+ Int(scalar.value))
        }
    }

    private static func followerAvatars(for avatar: AvatarStyle) -> [AvatarStyle] {
        [
            avatar,
            AvatarStyle(primary: .pink, secondary: .orange, symbolName: "quote.bubble.fill"),
            AvatarStyle(primary: .purple, secondary: .blue, symbolName: "sparkles"),
            AvatarStyle(primary: .green, secondary: .mint, symbolName: "antenna.radiowaves.left.and.right"),
            AvatarStyle(primary: .blue, secondary: .teal, symbolName: "camera.aperture")
        ]
    }

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
            authorName: "User Longform",
            handle: "@longform@mock.example",
            avatar: AvatarStyle(primary: .green, secondary: .cyan, symbolName: "text.alignleft"),
            body: """
            TL上で長文を全部表示すると、読み進めるリズムと復帰位置の安定性が同時に壊れやすい。
            なので本文そのものは受け止めつつ、Homeでは一定行数で折りたたむ。
            Detailに入れば全文を読めるので、投稿者の意図を削るわけではない。
            重要なのは、折りたたみが検閲っぽく見えないこと。
            そのため警告色ではなく、本文の続きがあることだけを小さく示す。
            画像やOGPがある投稿でも高さ推定を崩さないように、本文・添付・アクションの各ブロックをそれぞれ固定ルールにしておく。
            長文投稿は悪ではないけれど、TLではほかの投稿と同じ呼吸で並んでいてほしい。
            ここから先はDetailで読めばいい、という導線が自然に見えるかを確認するためのモックです。
            """,
            timestamp: "21m",
            replyCount: 3,
            boostCount: 8,
            favoriteCount: 29,
            isLocked: false,
            media: nil,
            context: nil,
            bodyPresentation: .collapsed(lineLimit: 8, reason: .longText)
        ),
        TimelinePost(
            authorName: "User Linkset",
            handle: "@linkset@mock.example",
            avatar: AvatarStyle(primary: .teal, secondary: .blue, symbolName: "link"),
            body: """
            調査メモをまとめた。docs.mock.example/research/relay-routing と docs.mock.example/research/local-cache、あと design.mock.example/timeline/height-estimates。関連: notes.mock.example/a/b/c, mirror.mock.example/thread/2048, archive.mock.example/client-notes。
            """,
            timestamp: "23m",
            replyCount: 1,
            boostCount: 4,
            favoriteCount: 16,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "Timeline Height Estimates",
                subtitle: "長文とURL大量投稿でも復帰位置を安定させるための表示ルール",
                host: "design.mock.example",
                url: "https://design.mock.example/timeline/height-estimates"
            )),
            context: nil,
            bodyPresentation: .collapsed(lineLimit: 3, reason: .linkHeavy),
            linkSummary: TimelineLinkSummary(
                totalCount: 12,
                visibleHosts: ["docs.mock.example", "design.mock.example", "notes.mock.example"],
                unresolvedCount: 2
            )
        ),
        TimelinePost(
            author: .resolved(
                displayName: "User Outside",
                nip05: "outside@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "user-outside-links"),
                isFollowed: false
            ),
            avatar: AvatarStyle(primary: .orange, secondary: .red, symbolName: "eye.slash.fill"),
            body: "フォロー外ユーザーの返信ツリー経由で入ってきたURL多めの投稿。short.mock/a short.mock/b short.mock/c short.mock/d unknown.mock.example/free-offer unknown.mock.example/more。",
            timestamp: "24m",
            replyCount: nil,
            boostCount: 2,
            favoriteCount: 5,
            isLocked: false,
            media: .unresolvedLink(UnresolvedLinkPreview(
                host: "unknown.mock.example",
                url: "https://unknown.mock.example/free-offer"
            )),
            context: nil,
            replyContext: TimelineReplyContext(
                author: .resolved(
                    displayName: "User Beta",
                    nip05: "beta@mock.example",
                    pubkey: TimelineAuthor.mockPubkey(for: "user-beta")
                ),
                avatar: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
                timestamp: "18m",
                bodyPreview: "Home / Relays / Lists の切り替えを、投稿密度を崩さずに扱いたい。",
                isSelfReply: false
            ),
            bodyPresentation: .collapsed(lineLimit: 4, reason: .lowTrustLinks),
            linkSummary: TimelineLinkSummary(
                totalCount: 9,
                visibleHosts: ["short.mock", "unknown.mock.example"],
                unresolvedCount: 6
            )
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
