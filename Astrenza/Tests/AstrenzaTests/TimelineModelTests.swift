import CoreGraphics
import Foundation
import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Timeline models")
struct TimelineModelTests {
    @Test("Session store persists multiple accounts and restores the selected account")
    @MainActor
    func sessionStorePersistsMultipleAccounts() async throws {
        let suiteName = "AstrenzaTests.session.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstPubkey = String(repeating: "a", count: 64)
        let secondPubkey = String(repeating: "b", count: 64)
        let store = NostrSessionStore(defaults: defaults, restoreAccount: false)

        store.loginInput = firstPubkey
        await store.login()
        store.loginInput = secondPubkey
        await store.login()

        #expect(store.accounts.map(\.pubkey) == [secondPubkey, firstPubkey])
        #expect(store.account?.pubkey == secondPubkey)

        store.selectAccount(firstPubkey)

        let restored = NostrSessionStore(defaults: defaults)
        #expect(restored.accounts.map(\.pubkey) == [secondPubkey, firstPubkey])
        #expect(restored.account?.pubkey == firstPubkey)
    }

    @Test("Session store selects and removes persisted accounts")
    @MainActor
    func sessionStoreSelectsAndRemovesAccounts() async throws {
        let suiteName = "AstrenzaTests.session.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstPubkey = String(repeating: "c", count: 64)
        let secondPubkey = String(repeating: "d", count: 64)
        let store = NostrSessionStore(defaults: defaults, restoreAccount: false)

        store.loginInput = firstPubkey
        await store.login()
        store.loginInput = secondPubkey
        await store.login()
        store.selectAccount(firstPubkey)
        store.removeAccount(firstPubkey)

        #expect(store.accounts.map(\.pubkey) == [secondPubkey])
        #expect(store.account?.pubkey == secondPubkey)

        store.removeAccount(secondPubkey)

        #expect(store.accounts.isEmpty)
        #expect(store.account == nil)
    }

    @Test("Session account summaries prefer cached kind 0 profile metadata")
    @MainActor
    func sessionAccountSummariesPreferCachedProfileMetadata() async throws {
        let suiteName = "AstrenzaTests.session.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let pubkey = String(repeating: "e", count: 64)
        let eventStore = try NostrEventStore.inMemory()
        let metadata = timelineEvent(
            idSeed: "account-metadata",
            kind: 0,
            pubkey: pubkey,
            createdAt: 1_800_000_000,
            content: #"{"name":"Fallback","display_name":"User Real","nip05":"_@real.example","picture":"https://real.example/avatar.png"}"#
        )
        try eventStore.save(events: [metadata])

        let store = NostrSessionStore(defaults: defaults, restoreAccount: false)
        store.loginInput = pubkey
        await store.login()

        let summary = try #require(store.accountSummaries(eventStore: eventStore).first)
        #expect(summary.title == "User Real")
        #expect(summary.subtitle == "_@real.example")
        #expect(summary.npub.hasPrefix("npub1"))
        #expect(summary.isSelected)
        #expect(summary.isReadOnly)
        #expect(summary.avatarStyle.imageURL?.absoluteString == "https://real.example/avatar.png")
    }

    @Test("Home timeline keeps mock root posts and excludes hidden reply-chain descendants")
    func homeTimelineShape() throws {
        let posts = MockTimelineData.posts

        #expect(posts.contains { $0.id == "thread-a-root" })
        #expect(posts.contains { $0.id == "thread-b-reply" } == false)
        #expect(posts.count >= 12)
    }

    @Test("Home timeline entries can include relay catch-up gaps")
    func homeTimelineEntriesIncludeGap() throws {
        let entries = MockTimelineData.homeEntries
        let gap = try #require(entries.compactMap { entry -> TimelineGap? in
            guard case .gap(let gap) = entry else { return nil }
            return gap
        }.first)

        #expect(gap.state == .needsBackfill)
        #expect(gap.missingEstimate > 0)
        #expect(gap.backfilledPosts.map(\.id) == [
            "home-gap-filled-relay-window",
            "home-gap-filled-secondary-fetch"
        ])
        #expect(entries.compactMap(\.post).map(\.id) == MockTimelineData.posts.map(\.id))
    }

    @Test("Nostr materializer inserts live gap rows from timeline entry flags")
    func nostrMaterializerInsertsLiveGapRows() throws {
        let author = String(repeating: "a", count: 64)
        let newer = timelineEvent(idSeed: "live-gap-newer", pubkey: author, createdAt: 300, content: "newer")
        let older = timelineEvent(idSeed: "live-gap-older", pubkey: author, createdAt: 100, content: "older")

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [newer, older],
            metadataEvents: [],
            followedPubkeys: [author],
            gaps: [
                NostrFeedGapRecord(
                    feedID: "feed:home:account",
                    feedRevision: 1,
                    newerEventID: newer.id,
                    olderEventID: older.id,
                    state: .unresolved,
                    createdAt: 400,
                    updatedAt: 400
                )
            ],
            relayCount: 3
        )

        #expect(entries.map(\.id) == [newer.id, "gap-\(newer.id)-\(older.id)", older.id])
        guard case .gap(let gap) = entries[1] else {
            Issue.record("Expected live gap row")
            return
        }
        #expect(gap.newerPostID == newer.id)
        #expect(gap.olderPostID == older.id)
        #expect(gap.relayCount == 3)
        #expect(gap.backfilledPosts.isEmpty)
    }

    @Test("Timeline gap fill directions expose distinct labels and icons")
    func timelineGapFillDirectionsExposeDistinctPresentation() {
        #expect(TimelineGapFillDirection.newer.label == "Backfill newer notes")
        #expect(TimelineGapFillDirection.newer.systemName == "chevron.up")
        #expect(TimelineGapFillDirection.older.label == "Backfill older notes")
        #expect(TimelineGapFillDirection.older.systemName == "chevron.down")
    }

    @Test("Nostr materializer splits unresolved gap around inserted events")
    func nostrMaterializerSplitsUnresolvedGapAroundInsertedEvents() throws {
        let author = String(repeating: "a", count: 64)
        let newer = timelineEvent(idSeed: "live-gap-split-newer", pubkey: author, createdAt: 300, content: "newer")
        let middle = timelineEvent(idSeed: "live-gap-split-middle", pubkey: author, createdAt: 200, content: "middle")
        let older = timelineEvent(idSeed: "live-gap-split-older", pubkey: author, createdAt: 100, content: "older")

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [newer, middle, older],
            metadataEvents: [],
            followedPubkeys: [author],
            gaps: [
                NostrFeedGapRecord(
                    feedID: "feed:home:account",
                    feedRevision: 1,
                    newerEventID: newer.id,
                    olderEventID: older.id,
                    state: .unresolved,
                    createdAt: 400,
                    updatedAt: 410
                )
            ],
            relayCount: 2
        )

        #expect(entries.map(\.id) == [
            newer.id,
            "gap-\(newer.id)-\(middle.id)",
            middle.id,
            "gap-\(middle.id)-\(older.id)",
            older.id
        ])
    }

    @Test("Implicit mock post IDs are stable across construction")
    func implicitMockPostIDsAreStable() {
        let author = TimelineAuthor.resolved(
            displayName: "Stable",
            nip05: nil,
            pubkey: TimelineAuthor.mockPubkey(for: "stable-author")
        )
        let first = TimelinePost(
            author: author,
            avatar: AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person"),
            body: "Stable body",
            createdAt: TimelineMockClock.createdAt(relative: "now"),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
        let second = TimelinePost(
            author: author,
            avatar: AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person"),
            body: "Stable body",
            createdAt: TimelineMockClock.createdAt(relative: "now"),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )

        #expect(first.id == second.id)
        #expect(first.id.hasPrefix("mock-"))
    }

    @Test("Mock relative timestamps render from createdAt without stored labels")
    func mockRelativeTimestampsRenderFromCreatedAtWithoutStoredLabels() {
        let createdAt = TimelineMockClock.createdAt(relative: "8m")

        #expect(TimelineTimestampFormatter.relativeText(from: createdAt) == "8m")
    }

    @Test("Relative timestamp updates only when its displayed value changes")
    func relativeTimestampChangeBoundaries() {
        let createdAt = 1_000
        func date(_ delta: TimeInterval) -> Date {
            Date(timeIntervalSince1970: TimeInterval(createdAt) + delta)
        }

        #expect(TimelineTimestampFormatter.relativeText(from: createdAt, now: date(59)) == "59s")
        #expect(TimelineTimestampFormatter.relativeText(from: createdAt, now: date(60)) == "1m")
        #expect(TimelineTimestampFormatter.relativeText(from: createdAt, now: date(3_600)) == "1h")
        #expect(TimelineTimestampFormatter.relativeText(from: createdAt, now: date(86_400)) == "1d")

        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(58.25)
        ) == date(59))
        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(59)
        ) == date(60))
        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(60)
        ) == date(120))
        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(3_599)
        ) == date(3_600))
        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(3_600)
        ) == date(7_200))
        #expect(TimelineTimestampFormatter.nextRelativeTextChangeDate(
            from: createdAt,
            after: date(86_400)
        ) == date(172_800))
    }

    @Test("Reply tree exposes ancestors and descendants from mock store")
    func replyTreeNavigation() throws {
        let root = try #require(MockTimelineData.posts.first { $0.id == "thread-a-root" })
        let descendants = MockTimelineData.detailReplies(for: root)
        let secondReply = try #require(descendants.first { $0.id == "thread-c-reply" })

        #expect(descendants.map(\.id) == ["thread-b-reply", "thread-c-reply", "thread-d-reply"])
        #expect(MockTimelineData.replyAncestors(for: secondReply).map(\.id) == ["thread-a-root", "thread-b-reply"])
        #expect(MockTimelineData.replyParent(for: secondReply)?.id == "thread-b-reply")
    }

    @Test("External reposts and reply-context posts obscure attachments")
    func attachmentProtectionRules() throws {
        let externalRepost = try #require(MockTimelineData.posts.first { $0.author.primaryText == "User Gamma" })
        let plainExternalPost = TimelinePost(
            author: .resolved(
                displayName: "External",
                nip05: "external@mock.example",
                pubkey: TimelineAuthor.mockPubkey(for: "external"),
                isFollowed: false
            ),
            avatar: AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person"),
            body: "Plain external post",
            createdAt: TimelineMockClock.createdAt(relative: "now"),
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: .linkPreview(LinkPreview(
                title: "Preview",
                subtitle: "Subtitle",
                host: "mock.example",
                url: "https://mock.example"
            )),
            context: nil
        )

        #expect(externalRepost.shouldObscureExternalAttachments)
        #expect(plainExternalPost.shouldObscureExternalAttachments == false)
    }

    @Test("Nostr materializer derives media links warnings replies and quotes from event tags")
    func nostrMaterializerUsesEventTags() throws {
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let parent = timelineEvent(
            idSeed: "parent",
            pubkey: parentAuthor,
            createdAt: 100,
            content: "parent body"
        )
        let quoted = timelineEvent(
            idSeed: "quoted",
            pubkey: parentAuthor,
            createdAt: 110,
            content: "quoted body"
        )
        let note = timelineEvent(
            idSeed: "note",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parent.id, "", "reply"],
                ["p", parentAuthor],
                ["q", quoted.id],
                ["content-warning", "spoiler"],
                ["imeta", "url https://cdn.example.test/pic.png"]
            ],
            content: "reply with https://example.test/story and https://cdn.example.test/pic.png"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note, parent, quoted],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == note.id })

        #expect(post.contentWarning?.displayReason == "spoiler")
        #expect(post.replyContext?.bodyPreview == "parent body")
        #expect(post.replyMention?.isExternal == true)
        #expect(post.quotedPost?.body == "quoted body")
        #expect(post.linkSummary?.totalCount == 1)
        if case .gallery(let tiles) = post.media {
            #expect(tiles.count == 1)
            #expect(tiles[0].title == "pic.png")
        } else {
            Issue.record("Expected gallery media from image URL")
        }
    }

    @Test("Nostr materializer prefers persisted media assets with alt text")
    func nostrMaterializerUsesPersistedMediaAssets() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "asset-note",
            pubkey: author,
            createdAt: 120,
            tags: [["imeta", "url https://cdn.example.test/raw.png"]],
            content: "photo https://cdn.example.test/raw.png"
        )
        let asset = NostrMediaAssetRecord(
            assetID: "\(note.id):imeta:0",
            eventID: note.id,
            url: "https://cdn.example.test/alt.png",
            mimeType: "image/png",
            blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            width: 640,
            height: 480,
            alt: "Alt text from imeta",
            sha256: nil,
            status: "unresolved",
            localPath: nil,
            createdAt: 200
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            mediaAssetsByEventID: [note.id: [asset]]
        )
        let post = try #require(posts.first)

        if case .gallery(let tiles) = post.media {
            #expect(tiles.count == 1)
            #expect(tiles[0].title == "Alt text from imeta")
            #expect(tiles[0].altText == "Alt text from imeta")
            #expect(tiles[0].url?.absoluteString == "https://cdn.example.test/alt.png")
            #expect(tiles[0].width == 640)
            #expect(tiles[0].height == 480)
            #expect(tiles[0].blurhash == "LEHV6nWB2yk8pyo0adR*.7kCMdnj")
        } else {
            Issue.record("Expected gallery media from persisted asset")
        }
    }

    @Test("Nostr materializer keeps direct media URL on fallback tiles")
    func nostrMaterializerDirectMediaFallbackKeepsURL() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "direct-media-url",
            pubkey: author,
            createdAt: 120,
            content: "clip https://cdn.example.test/movie.mp4 page https://example.test/article"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first)

        if case .gallery(let tiles) = post.media {
            #expect(tiles.count == 1)
            #expect(tiles[0].url?.absoluteString == "https://cdn.example.test/movie.mp4")
            #expect(tiles[0].symbolName == "play.rectangle")
            #expect(post.linkSummary?.totalCount == 1)
        } else {
            Issue.record("Expected direct media fallback gallery")
        }
    }

    @Test("Nostr materializer maps resolved cached link previews to OGP cards")
    func nostrMaterializerUsesCachedLinkPreview() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "link-note",
            pubkey: author,
            createdAt: 120,
            content: "read https://example.test/article"
        )
        let url = try #require(URL(string: "https://example.test/article"))
        let preview = NostrLinkPreviewRecord(
            url: url.absoluteString,
            normalizedURL: NostrLinkParser.normalizedURLString(url),
            status: "resolved",
            title: "Cached Article",
            summary: "OGP summary",
            siteName: "Example",
            imageURL: "https://example.test/card.png",
            fetchedAt: 100,
            expiresAt: 200,
            error: nil
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            linkPreviewsByNormalizedURL: [preview.normalizedURL: preview]
        )
        let post = try #require(posts.first)

        if case .linkPreview(let card) = post.media {
            #expect(card.title == "Cached Article")
            #expect(card.subtitle == "OGP summary")
            #expect(card.host == "Example")
            #expect(card.imageURL?.absoluteString == "https://example.test/card.png")
            #expect(card.style == .standard)
            #expect(post.body == "read")
            #expect(post.richBody?.tokens.contains { token in
                if case .url = token {
                    return true
                }
                return false
            } == false)
        } else {
            Issue.record("Expected resolved link preview media")
        }
    }

    @Test("Timeline content projection hides promoted OGP and quote references")
    func timelineContentProjectionHidesPromotedReferences() throws {
        let author = String(repeating: "a", count: 64)
        let quotedEventID = String(repeating: "b", count: 64)
        let nevent = try NostrNIP19.encodeEventReference(
            eventID: quotedEventID,
            relays: ["wss://relay.example"],
            author: author,
            kind: 1
        )
        let event = timelineEvent(
            idSeed: "projected-content",
            pubkey: author,
            createdAt: 120,
            content: "read https://example.test/article nostr:\(nevent)"
        )

        let projection = NostrTimelineContentProjection(event: event)

        #expect(projection.linkURLs.map(\.absoluteString) == ["https://example.test/article"])
        #expect(projection.quotedEventID == quotedEventID)
        #expect(projection.richBody.displayText == "read")
        #expect(projection.richBody.tokens.contains { token in
            if case .url = token {
                return true
            }
            return false
        } == false)
        #expect(projection.richBody.tokens.contains { token in
            if case .event = token {
                return true
            }
            return false
        } == false)
    }

    @Test("Nostr materializer resolves inline profile rich content display names")
    func nostrMaterializerResolvesInlineProfileRichContentDisplayNames() throws {
        let author = String(repeating: "a", count: 64)
        let mentioned = String(repeating: "b", count: 64)
        let npub = try NostrNIP19.publicKey(mentioned)
        let note = timelineEvent(
            idSeed: "inline-profile-rich-content",
            pubkey: author,
            createdAt: 120,
            content: "hello nostr:\(npub)"
        )
        let metadata = timelineEvent(
            idSeed: "inline-profile-rich-content-metadata",
            kind: 0,
            pubkey: mentioned,
            createdAt: 130,
            content: #"{"display_name":"User Beta"}"#
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first)

        #expect(post.body == "hello @User Beta")
        #expect(post.richBody?.displayText == "hello @User Beta")
        #expect(post.richBody?.tokens.map { post.richBody?.displayText(for: $0) ?? "" }.joined() == "hello @User Beta")
    }

    @Test("Timeline rich content route keeps relay hints for internal references")
    func timelineRichContentRouteKeepsRelayHintsForInternalReferences() throws {
        let eventID = String(repeating: "c", count: 64)
        let author = String(repeating: "d", count: 64)
        let eventURL = try #require(URL(string: "astrenza://event/\(eventID)?relay=wss%3A%2F%2Frelay.example&author=\(author)&kind=1"))
        let eventRoute = TimelineRichContentRoute(url: eventURL)

        #expect(eventRoute == .event(eventID: eventID, relays: ["wss://relay.example"], author: author, kind: 1))

        let profileURL = try #require(URL(string: "astrenza://profile/\(author)?relay=wss%3A%2F%2Fprofile.example"))
        let profileRoute = TimelineRichContentRoute(url: profileURL)

        #expect(profileRoute == .profile(pubkey: author, relays: ["wss://profile.example"]))
    }

    @Test("Timeline quote projection returns placeholder for uncached quote")
    func timelineQuoteProjectionReturnsPlaceholderForUncachedQuote() throws {
        let author = String(repeating: "a", count: 64)
        let quotedEventID = String(repeating: "b", count: 64)
        let event = timelineEvent(
            idSeed: "quote-projection-placeholder",
            pubkey: author,
            createdAt: 120,
            tags: [["q", quotedEventID]],
            content: "quoted"
        )

        let quotedPost = try #require(NostrTimelineQuoteProjection.quotedPost(
            from: event,
            eventsByID: [:],
            metadataEvents: [],
            nip05Resolutions: [:],
            followedPubkeys: [],
            avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
        ))

        #expect(quotedPost.isAvailable == false)
        #expect(quotedPost.author.pubkey == quotedEventID)
        #expect(quotedPost.body == "Quoted note is not cached yet.")
        #expect(quotedPost.createdAt == nil)
    }

    @Test("Timeline quote projection preserves rich custom emoji")
    func timelineQuoteProjectionPreservesRichCustomEmoji() throws {
        let author = String(repeating: "a", count: 64)
        let quotedAuthor = String(repeating: "b", count: 64)
        let quoted = timelineEvent(
            idSeed: "quote-projection-custom-emoji-source",
            pubkey: quotedAuthor,
            createdAt: 110,
            tags: [["emoji", "astrenza", "https://emoji.example.test/astrenza.png"]],
            content: "hello :astrenza:"
        )
        let event = timelineEvent(
            idSeed: "quote-projection-custom-emoji",
            pubkey: author,
            createdAt: 120,
            tags: [["q", quoted.id]],
            content: "quoted"
        )

        let quotedPost = try #require(NostrTimelineQuoteProjection.quotedPost(
            from: event,
            eventsByID: [quoted.id: quoted],
            metadataEvents: [],
            nip05Resolutions: [:],
            followedPubkeys: [],
            avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
        ))

        #expect(quotedPost.body == "hello :astrenza:")
        #expect(quotedPost.richBody?.tokens.contains { token in
            if case .customEmoji(let shortcode, let url) = token {
                return shortcode == "astrenza" &&
                    url.absoluteString == "https://emoji.example.test/astrenza.png"
            }
            return false
        } == true)
    }

    @Test("Timeline quote projection removes promoted media and OGP URLs")
    func timelineQuoteProjectionRemovesPromotedMediaAndOGPURLs() throws {
        let author = String(repeating: "a", count: 64)
        let quotedAuthor = String(repeating: "b", count: 64)
        let quoted = timelineEvent(
            idSeed: "quote-projection-promoted-links-source",
            pubkey: quotedAuthor,
            createdAt: 110,
            tags: [["imeta", "url https://cdn.example.test/pic.png", "m image/png"]],
            content: "photo https://cdn.example.test/pic.png read https://example.test/page"
        )
        let event = timelineEvent(
            idSeed: "quote-projection-promoted-links",
            pubkey: author,
            createdAt: 120,
            tags: [["q", quoted.id]],
            content: "quoted"
        )

        let quotedPost = try #require(NostrTimelineQuoteProjection.quotedPost(
            from: event,
            eventsByID: [quoted.id: quoted],
            metadataEvents: [],
            nip05Resolutions: [:],
            followedPubkeys: [],
            avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
        ))

        #expect(quotedPost.body == "photo read")
        #expect(quotedPost.richBody?.tokens.contains { token in
            if case .url = token {
                return true
            }
            return false
        } == false)
    }

    @Test("Timeline media projection prefers persisted assets over content attachments")
    func timelineMediaProjectionPrefersPersistedAssets() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "media-projection",
            pubkey: author,
            createdAt: 120,
            content: "look https://cdn.example.test/fallback.jpg"
        )
        let content = NostrTimelineContentProjection(event: note)
        let persisted = NostrMediaAssetRecord(
            assetID: "asset-1",
            eventID: note.id,
            url: "https://cdn.example.test/persisted.mp4",
            mimeType: "video/mp4",
            blurhash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
            width: 1920,
            height: 1080,
            alt: "Persisted media",
            sha256: nil,
            status: "resolved",
            localPath: nil,
            createdAt: 120
        )

        let media = NostrTimelineMediaProjection.media(
            assets: [persisted],
            mediaAttachments: content.mediaAttachments,
            linkURLs: content.linkURLs,
            linkPreviewsByNormalizedURL: [:],
            palette: NostrTimelineAuthorProjection.avatarPalette(for: author)
        )

        if case .gallery(let tiles) = media {
            #expect(tiles.count == 1)
            #expect(tiles[0].url?.absoluteString == "https://cdn.example.test/persisted.mp4")
            #expect(tiles[0].symbolName == "play.rectangle")
            #expect(tiles[0].altText == "Persisted media")
            #expect(tiles[0].width == 1920)
            #expect(tiles[0].height == 1080)
            #expect(tiles[0].blurhash == "LKO2?U%2Tw=w]~RBVZRi};RPxuwH")
        } else {
            Issue.record("Expected persisted media gallery")
        }
    }

    @Test("Timeline media projection defers remote media loading when policy requires tap")
    func timelineMediaProjectionDefersRemoteMediaLoading() throws {
        let author = String(repeating: "b", count: 64)
        let note = timelineEvent(
            idSeed: "media-deferred",
            pubkey: author,
            createdAt: 121,
            content: "look https://cdn.example.test/deferred.jpg"
        )
        let content = NostrTimelineContentProjection(event: note)

        let media = NostrTimelineMediaProjection.media(
            assets: [],
            mediaAttachments: content.mediaAttachments,
            linkURLs: content.linkURLs,
            linkPreviewsByNormalizedURL: [:],
            palette: NostrTimelineAuthorProjection.avatarPalette(for: author),
            policy: .default(networkType: .cellular)
        )

        guard case .gallery(let tiles) = media else {
            Issue.record("Expected deferred media gallery")
            return
        }

        #expect(tiles[0].remoteLoadMode == .tapRequired)
        #expect(media?.allowsAutomaticRemoteMediaLoading == false)
        #expect(media?.allowingRemoteMediaLoading().allowsAutomaticRemoteMediaLoading == true)
    }

    @Test("Timeline media projection keeps OGP card but defers remote preview image loading")
    func timelineMediaProjectionDefersOGPImageLoading() throws {
        let author = String(repeating: "c", count: 64)
        let note = timelineEvent(
            idSeed: "ogp-deferred-image",
            pubkey: author,
            createdAt: 122,
            content: "read https://example.test/page"
        )
        let content = NostrTimelineContentProjection(event: note)
        let preview = NostrLinkPreviewRecord(
            url: "https://example.test/page",
            normalizedURL: "https://example.test/page",
            status: "resolved",
            title: "Example",
            summary: "Summary",
            siteName: "Example",
            imageURL: "https://example.test/card.jpg",
            fetchedAt: 122,
            expiresAt: 222,
            error: nil
        )

        let media = NostrTimelineMediaProjection.media(
            assets: [],
            mediaAttachments: content.mediaAttachments,
            linkURLs: content.linkURLs,
            linkPreviewsByNormalizedURL: [preview.normalizedURL: preview],
            palette: NostrTimelineAuthorProjection.avatarPalette(for: author),
            policy: .default(networkType: .cellular)
        )

        guard case .linkPreview(let linkPreview) = media else {
            Issue.record("Expected link preview card")
            return
        }

        #expect(linkPreview.imageURL?.absoluteString == "https://example.test/card.jpg")
        #expect(linkPreview.remoteImageLoadMode == .tapRequired)
    }

    @Test("Timeline presentation projection collapses low trust and link heavy bodies")
    func timelinePresentationProjectionCollapsesRiskyBodies() throws {
        let links = try [
            #require(URL(string: "https://b.example.test/one")),
            #require(URL(string: "https://a.example.test/two")),
            #require(URL(string: "https://b.example.test/three")),
            #require(URL(string: "https://c.example.test/four")),
            #require(URL(string: "https://d.example.test/five"))
        ]

        #expect(
            NostrTimelinePresentationProjection.bodyPresentation(
                body: "external link",
                linkURLs: [links[0]],
                isFollowed: false
            ).collapseReason == .lowTrustLinks
        )
        #expect(
            NostrTimelinePresentationProjection.bodyPresentation(
                body: "many links",
                linkURLs: links,
                isFollowed: true
            ).collapseReason == .linkHeavy
        )

        let summary = try #require(NostrTimelinePresentationProjection.linkSummary(from: links))
        #expect(summary.totalCount == 5)
        #expect(summary.visibleHosts == [
            "a.example.test",
            "b.example.test",
            "c.example.test",
            "d.example.test"
        ])
        #expect(summary.unresolvedCount == 5)
    }

    @Test("Nostr materializer gives YouTube previews a video card style")
    func nostrMaterializerUsesYouTubeLinkPreviewStyle() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "youtube-note",
            pubkey: author,
            createdAt: 120,
            content: "watch https://youtu.be/abc123"
        )
        let url = try #require(URL(string: "https://youtu.be/abc123"))
        let preview = NostrLinkPreviewRecord(
            url: url.absoluteString,
            normalizedURL: NostrLinkParser.normalizedURLString(url),
            status: "resolved",
            title: "Video Title",
            summary: "Video summary",
            siteName: "YouTube",
            imageURL: "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
            fetchedAt: 100,
            expiresAt: 200,
            error: nil
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            linkPreviewsByNormalizedURL: [preview.normalizedURL: preview]
        )
        let post = try #require(posts.first)

        if case .linkPreview(let card) = post.media {
            #expect(card.style == .youtube)
            #expect(card.imageURL?.absoluteString == "https://i.ytimg.com/vi/abc123/hqdefault.jpg")
        } else {
            Issue.record("Expected YouTube link preview media")
        }
    }

    @Test("Nostr materializer merges deleted timeline entries by sort position")
    func nostrMaterializerMergesDeletedTimelineEntries() throws {
        let author = String(repeating: "a", count: 64)
        let newer = timelineEvent(idSeed: "newer", pubkey: author, createdAt: 300, content: "newer")
        let older = timelineEvent(idSeed: "older", pubkey: author, createdAt: 100, content: "older")
        let deleted = NostrDeletedFeedItemRecord(
            feedID: "feed:home:account",
            feedRevision: 1,
            targetEventID: "deleted-target",
            deletionEventID: "delete-event",
            deletedAt: 210,
            sortTimestamp: 200
        )

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [newer, older],
            metadataEvents: [],
            followedPubkeys: [author],
            deletedEntries: [deleted]
        )

        #expect(entries.map(\.id) == [newer.id, "deleted-deleted-target", older.id])
        guard case .deleted(let deletedEntry) = entries[1] else {
            Issue.record("Expected deleted timeline entry")
            return
        }
        #expect(deletedEntry.id == "deleted-deleted-target")
    }

    @Test("Nostr materializer does not treat root markers as replies")
    func nostrMaterializerIgnoresRootOnlyReplyMarker() throws {
        let author = String(repeating: "a", count: 64)
        let root = timelineEvent(idSeed: "root", pubkey: author, createdAt: 100, content: "root")
        let note = timelineEvent(
            idSeed: "root-marker-note",
            pubkey: author,
            createdAt: 120,
            tags: [["e", root.id, "", "root"]],
            content: "thread root marker only"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note, root],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == note.id })

        #expect(post.replyContext == nil)
        #expect(post.replyMention == nil)
    }

    @Test("Timeline reply projection separates root markers from reply markers")
    func timelineReplyProjectionSeparatesRootAndReplyMarkers() throws {
        let author = String(repeating: "a", count: 64)
        let root = timelineEvent(idSeed: "projection-root", pubkey: author, createdAt: 100, content: "root")
        let rootMarkerOnly = timelineEvent(
            idSeed: "projection-root-marker",
            pubkey: author,
            createdAt: 120,
            tags: [["e", root.id, "", "root"]],
            content: "root marker only"
        )
        let legacyReply = timelineEvent(
            idSeed: "projection-legacy-reply",
            pubkey: author,
            createdAt: 130,
            tags: [["e", root.id]],
            content: "legacy reply"
        )

        #expect(NostrTimelineReplyProjection.replyParentID(from: rootMarkerOnly.tags) == nil)
        #expect(NostrTimelineReplyProjection.replyParentID(from: legacyReply.tags) == root.id)
    }

    @Test("Timeline reply projection builds reply context and external mention")
    func timelineReplyProjectionBuildsContextAndMention() throws {
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let parent = timelineEvent(idSeed: "projection-parent", pubkey: parentAuthor, createdAt: 90, content: "parent preview")
        let reply = timelineEvent(
            idSeed: "projection-reply",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parent.id, "", "reply"],
                ["p", parentAuthor]
            ],
            content: "reply body"
        )
        let projection = NostrTimelineReplyProjection(
            event: reply,
            eventsByID: [parent.id: parent, reply.id: reply],
            author: .resolved(displayName: "Author", nip05: nil, nip05Status: .absent, pubkey: author, isFollowed: true),
            authorForParent: { _ in TimelineAuthor.unresolved(pubkey: parentAuthor) },
            avatarForParent: { _ in AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person") },
            mentionDisplayForPubkey: { _ in nil }
        )

        #expect(projection.replyContext?.bodyPreview == "parent preview")
        #expect(projection.replyContext?.createdAt == parent.createdAt)
        #expect(projection.replyContext?.isSelfReply == false)
        #expect(projection.replyMention?.text == "@\(parentAuthor.prefix(10))")
        #expect(projection.replyMention?.isExternal == true)
    }

    @Test("Timeline reply projection carries rich parent preview content")
    func timelineReplyProjectionCarriesRichParentPreviewContent() throws {
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let parent = timelineEvent(
            idSeed: "reply-rich-parent",
            pubkey: parentAuthor,
            createdAt: 90,
            tags: [["emoji", "spark", "https://emoji.example.test/spark.png"]],
            content: "parent :spark:"
        )
        let reply = timelineEvent(
            idSeed: "reply-rich-child",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parent.id, "", "reply"],
                ["p", parentAuthor]
            ],
            content: "reply body"
        )

        let projection = NostrTimelineReplyProjection(
            event: reply,
            eventsByID: [parent.id: parent, reply.id: reply],
            author: .resolved(displayName: "Author", nip05: nil, nip05Status: .absent, pubkey: author, isFollowed: true),
            authorForParent: { _ in TimelineAuthor.unresolved(pubkey: parentAuthor) },
            avatarForParent: { _ in AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person") },
            mentionDisplayForPubkey: { _ in nil }
        )

        #expect(projection.replyContext?.richContent?.displayText == "parent :spark:")
        #expect(projection.replyContext?.richContent?.tokens.contains { token in
            if case .customEmoji(let shortcode, _) = token {
                return shortcode == "spark"
            }
            return false
        } == true)
    }

    @Test("Nostr materializer resolves reply target author and mention from kind 0")
    func nostrMaterializerResolvesReplyTargetAuthorAndMention() throws {
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let parent = timelineEvent(
            idSeed: "resolved-reply-parent",
            pubkey: parentAuthor,
            createdAt: 90,
            content: "parent preview"
        )
        let reply = timelineEvent(
            idSeed: "resolved-reply",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parent.id, "", "reply"],
                ["p", parentAuthor]
            ],
            content: "reply body"
        )
        let parentMetadata = timelineEvent(
            idSeed: "resolved-reply-parent-metadata",
            kind: 0,
            pubkey: parentAuthor,
            createdAt: 130,
            content: #"{"name":"Parent Display","nip05":"parent.example","picture":"https://example.test/avatar.png"}"#
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [reply, parent],
            metadataEvents: [parentMetadata],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == reply.id })

        #expect(post.replyContext?.author.primaryText == "Parent Display")
        #expect(post.replyContext?.author.secondaryText == "parent.example")
        #expect(post.replyMention?.text == "@Parent Display")
        #expect(post.replyMention?.isExternal == true)
    }

    @Test("Home timeline store single post projection resolves reply mention from cached kind 0")
    @MainActor
    func homeTimelineStoreSinglePostProjectionResolvesReplyMentionFromCachedKind0() throws {
        let eventStore = try NostrEventStore.inMemory()
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let parentID = timelineEventID("single-post-reply-parent")
        let reply = timelineEvent(
            idSeed: "single-post-reply",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parentID, "", "reply"],
                ["p", parentAuthor]
            ],
            content: "reply body"
        )
        let parentMetadata = timelineEvent(
            idSeed: "single-post-reply-parent-metadata",
            kind: 0,
            pubkey: parentAuthor,
            createdAt: 130,
            content: #"{"name":"Parent Display"}"#
        )
        try eventStore.save(events: [reply, parentMetadata])
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [:])),
            eventStore: eventStore,
            relayRuntime: nil
        )

        let post = try #require(store.post(eventID: reply.id))

        #expect(post.replyMention?.text == "@Parent Display")
    }

    @Test("Timeline author projection resolves author avatar timestamp and warning")
    func timelineAuthorProjectionBuildsDisplayBits() throws {
        let pubkey = String(repeating: "c", count: 64)
        let item = NostrHomeTimelineItem(
            id: "author-projection-item",
            pubkey: pubkey,
            displayName: "Projection Author",
            nip05: "author.example",
            nip05Status: NostrNIP05Status.verified,
            isFollowed: true,
            body: "body",
            createdAt: 120,
            avatarPictureState: .resolved,
            avatarImageURL: URL(string: "https://example.test/avatar.png"),
            profileResolutionState: .resolved
        )
        let event = timelineEvent(
            idSeed: "author-projection-warning",
            pubkey: pubkey,
            createdAt: 120,
            tags: [["content-warning", "spoiler"]],
            content: "warning body"
        )

        let author = NostrTimelineAuthorProjection.author(for: item)
        let avatar = NostrTimelineAuthorProjection.avatar(for: item)

        #expect(author.primaryText == "Projection Author")
        #expect(author.secondaryText == "author.example")
        #expect(author.nip05Status == NIP05Status.valid)
        #expect(avatar.pictureState == AvatarPictureState.resolved)
        #expect(avatar.imageURL?.absoluteString == "https://example.test/avatar.png")
        #expect(NostrTimelineAuthorProjection.relativeTimestamp(from: 90, now: 120) == "30s")
        #expect(NostrTimelineAuthorProjection.relativeTimestamp(from: 0, now: 3_600) == "1h")
        #expect(NostrTimelineAuthorProjection.contentWarning(from: event)?.displayReason == "spoiler")
    }

    @Test("Timeline post projection composes quote media reply and presentation")
    func timelinePostProjectionComposesDisplayDependencies() throws {
        let author = String(repeating: "a", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let quotedAuthor = String(repeating: "c", count: 64)
        let parent = timelineEvent(idSeed: "post-projection-parent", pubkey: parentAuthor, createdAt: 90, content: "parent body")
        let quoted = timelineEvent(idSeed: "post-projection-quoted", pubkey: quotedAuthor, createdAt: 95, content: "quoted body")
        let note = timelineEvent(
            idSeed: "post-projection-note",
            pubkey: author,
            createdAt: 120,
            tags: [
                ["e", parent.id, "", "reply"],
                ["p", parentAuthor],
                ["q", quoted.id],
                ["content-warning", "sensitive"]
            ],
            content: "hello https://example.test/card"
        )
        let item = NostrHomeTimelineItem(
            id: note.id,
            pubkey: author,
            displayName: "Projection Poster",
            nip05: nil,
            nip05Status: .absent,
            isFollowed: false,
            body: note.content,
            createdAt: note.createdAt,
            avatarPictureState: .metadataPending,
            avatarImageURL: nil,
            profileResolutionState: .resolved
        )
        let previewURL = try #require(URL(string: "https://example.test/card"))
        let preview = NostrLinkPreviewRecord(
            url: previewURL.absoluteString,
            normalizedURL: NostrLinkParser.normalizedURLString(previewURL),
            status: "resolved",
            title: "Example Card",
            summary: "Card summary",
            siteName: "Example",
            imageURL: "https://example.test/card.png",
            fetchedAt: 100,
            expiresAt: 200,
            error: nil
        )

        let post = NostrTimelinePostProjection.post(
            for: item,
            event: note,
            eventsByID: [
                note.id: note,
                parent.id: parent,
                quoted.id: quoted
            ],
            linkPreviewsByNormalizedURL: [preview.normalizedURL: preview]
        )

        #expect(post.author.primaryText == "Projection Poster")
        #expect(post.createdAt == note.createdAt)
        #expect(post.replyContext?.bodyPreview == "parent body")
        #expect(post.replyContext?.createdAt == parent.createdAt)
        #expect(post.replyMention?.isExternal == true)
        #expect(post.quotedPost?.body == "quoted body")
        #expect(post.quotedPost?.createdAt == quoted.createdAt)
        #expect(post.contentWarning?.displayReason == "sensitive")
        #expect(post.bodyPresentation.collapseReason == .lowTrustLinks)
        #expect(post.linkSummary?.totalCount == 1)
        if case .linkPreview(let card) = post.media {
            #expect(card.title == "Example Card")
            #expect(card.host == "Example")
        } else {
            Issue.record("Expected link preview media")
        }
    }

    @Test("Nostr materializer falls back to unmarked e tags for legacy replies")
    func nostrMaterializerUsesUnmarkedReplyFallback() throws {
        let author = String(repeating: "a", count: 64)
        let parent = timelineEvent(idSeed: "legacy-parent", pubkey: author, createdAt: 100, content: "legacy parent")
        let reply = timelineEvent(
            idSeed: "legacy-reply",
            pubkey: author,
            createdAt: 120,
            tags: [["e", parent.id]],
            content: "legacy reply"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [reply, parent],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == reply.id })

        #expect(post.replyContext?.bodyPreview == "legacy parent")
    }

    @Test("Nostr materializer derives quotes from NIP-19 note references in content")
    func nostrMaterializerUsesNIP19NoteQuoteReferences() throws {
        let author = String(repeating: "a", count: 64)
        let quotedID = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        let quoted = timelineEvent(
            idSeed: "quoted-by-note",
            id: quotedID,
            pubkey: author,
            createdAt: 100,
            content: "quoted from note1"
        )
        let note = timelineEvent(
            idSeed: "note-with-note1-quote",
            pubkey: author,
            createdAt: 120,
            content: "nostr:note1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q7k28gn"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note, quoted],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == note.id })

        #expect(post.quotedPost?.body == "quoted from note1")
        #expect(post.body.isEmpty)
        #expect(post.richBody?.references.isEmpty == true)
        #expect(post.richBody?.tokens.contains { token in
            if case .event = token {
                return true
            }
            return false
        } == false)
    }

    @Test("Nostr materializer treats NIP-10 mention markers as quote-like event references")
    func nostrMaterializerUsesMentionMarkerQuoteFallback() throws {
        let author = String(repeating: "a", count: 64)
        let quoted = timelineEvent(idSeed: "quoted-by-mention", pubkey: author, createdAt: 100, content: "quoted by mention")
        let note = timelineEvent(
            idSeed: "note-with-mention-quote",
            pubkey: author,
            createdAt: 120,
            tags: [["e", quoted.id, "", "mention"]],
            content: "quote-like mention"
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note, quoted],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let post = try #require(posts.first { $0.id == note.id })

        #expect(post.quotedPost?.body == "quoted by mention")
        #expect(post.replyContext == nil)
    }

    @Test("Nostr materializer collapses locally filtered posts without deleting them")
    func nostrMaterializerCollapsesFilteredPosts() throws {
        let author = String(repeating: "a", count: 64)
        let note = timelineEvent(
            idSeed: "filtered-note",
            pubkey: author,
            createdAt: 100,
            content: "this contains noisy text"
        )
        let filterRules = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(
                ruleID: "rule",
                accountID: "account",
                kind: .keyword,
                value: "noisy",
                createdAt: 1,
                updatedAt: 1
            )
        ])

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            filterRules: filterRules,
            now: 100
        )
        let post = try #require(posts.first)

        #expect(post.id == note.id)
        #expect(post.bodyPresentation.collapseReason == .filtered)
    }

    @Test("Nostr materializer hides filtered posts configured as hidden")
    func nostrMaterializerHidesFilteredPosts() throws {
        let author = String(repeating: "a", count: 64)
        let hidden = timelineEvent(
            idSeed: "hidden-filtered-note",
            pubkey: author,
            createdAt: 100,
            content: "this contains noisy text"
        )
        let visible = timelineEvent(
            idSeed: "visible-note",
            pubkey: author,
            createdAt: 90,
            content: "ordinary text"
        )
        let filterRules = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(
                ruleID: "rule",
                accountID: "account",
                kind: .keyword,
                value: "noisy",
                presentation: .hide,
                createdAt: 1,
                updatedAt: 1
            )
        ])

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [hidden, visible],
            metadataEvents: [],
            followedPubkeys: [author],
            filterRules: filterRules,
            now: 100
        )

        #expect(posts.map(\.id) == [visible.id])
    }

    @Test("Nostr materializer collapses posts muted by cached NIP-51 list items")
    func nostrMaterializerCollapsesNIP51MutedPosts() throws {
        let author = String(repeating: "b", count: 64)
        let note = timelineEvent(
            idSeed: "nip51-filtered-note",
            pubkey: author,
            createdAt: 100,
            content: "this author is muted by a public NIP-51 list"
        )
        let listID = "10000:account:"
        let items = [
            NostrListItemRecord(
                listID: listID,
                itemKey: "pubkey:\(author)",
                itemType: "pubkey",
                value: author,
                relayHint: nil,
                visibility: "public",
                position: 0
            )
        ]
        let filterRules = NostrFilterRuleSet(
            rules: NostrFilterRuleSet.publicMuteRules(accountID: "account", items: items, updatedAt: 100)
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            filterRules: filterRules,
            now: 100
        )
        let post = try #require(posts.first)

        #expect(post.id == note.id)
        #expect(post.bodyPresentation.collapseReason == .filtered)
    }

    @Test("Home timeline store exposes active filter status")
    @MainActor
    func homeTimelineStoreExposesActiveFilterStatus() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let matching = timelineEvent(
            idSeed: "status-filtered-note",
            pubkey: account.pubkey,
            createdAt: 200,
            content: "quiet keyword"
        )
        let other = timelineEvent(
            idSeed: "status-visible-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "ordinary text"
        )
        let rule = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: account.pubkey,
            kind: .keyword,
            value: "keyword",
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )

        try eventStore.saveFilterRule(rule)
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [matching, other],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post).map(\.id) == [matching.id, other.id]
        })

        #expect(store.filterStatus.activeRuleCount == 1)
        #expect(store.filterStatus.warningMatchCount == 1)
        #expect(store.filterStatus.hiddenMatchCount == 0)
        #expect(store.filterStatus.isSuspended == false)
        #expect(store.entries.compactMap(\.post).map(\.id) == [matching.id, other.id])
    }

    @Test("Home timeline event ingestor stores event and relay source")
    func homeTimelineEventIngestorStoresEventAndRelaySource() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let event = timelineEvent(
            idSeed: "ingest-note",
            pubkey: String(repeating: "a", count: 64),
            createdAt: 100,
            content: "ingested note"
        )
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore)

        let result = try await ingestor.ingest(event: event, relayURL: "wss://relay.example")

        #expect(result.primaryEventID == event.id)
        #expect(result.embeddedEvent == nil)
        #expect(result.savedEventIDs == [event.id])
        #expect(try eventStore.events(ids: [event.id]).map(\.id) == [event.id])
        #expect(try eventStore.eventSources(eventID: event.id).map(\.relayURL) == ["wss://relay.example"])
    }

    @Test("Home timeline event ingestor stores embedded repost target")
    func homeTimelineEventIngestorStoresEmbeddedRepostTarget() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let reposterSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "44", count: 32))
        let targetSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "45", count: 32))
        let target = try await targetSigner.sign(
            NostrPublishInput.post(content: "original body")
                .unsignedEvent(pubkey: targetSigner.pubkey, createdAt: 90)
        )
        let targetData = try JSONEncoder().encode(target)
        let targetJSON = try #require(String(data: targetData, encoding: .utf8))
        let repost = try await reposterSigner.sign(
            NostrUnsignedEvent(
                pubkey: reposterSigner.pubkey,
                createdAt: 100,
                kind: 6,
                tags: [["e", target.id], ["p", target.pubkey]],
                content: targetJSON
            )
        )
        let ingestor = HomeTimelineEventIngestor(eventStore: eventStore)

        let result = try await ingestor.ingest(event: repost, relayURL: "wss://relay.example")

        #expect(result.primaryEventID == repost.id)
        #expect(result.embeddedEvent?.id == target.id)
        #expect(result.savedEventIDs == [repost.id, target.id])
        #expect(Set(try eventStore.events(ids: [repost.id, target.id]).map(\.id)) == [repost.id, target.id])
        #expect(try eventStore.eventSources(eventID: target.id).map(\.relayURL) == ["wss://relay.example"])
    }

    @Test("Home timeline sync planner builds forward reconnect packet")
    func homeTimelineSyncPlannerBuildsForwardReconnectPacket() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followed = String(repeating: "b", count: 64)
        let planner = HomeTimelineSyncPlanner()

        let packet = planner.forwardPacket(
            account: account,
            followedPubkeys: [followed],
            newestCreatedAt: 1_800_000_100,
            relayURLs: ["wss://relay.example"]
        )

        #expect(packet.strategy == .forward)
        #expect(packet.subscriptionID == NostrHomeForwardREQBuilder.subscriptionID)
        #expect(packet.relayURLs == ["wss://relay.example"])
        #expect(packet.filters == [[
            "kinds": .ints([1, 5, 6]),
            "authors": .strings([followed]),
            "since": .int(1_800_000_090)
        ]])
    }

    @Test("Home timeline sync planner builds older notes packet")
    func homeTimelineSyncPlannerBuildsOlderNotesPacket() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followed = String(repeating: "b", count: 64)
        let planner = HomeTimelineSyncPlanner()

        let packet = planner.olderNotesPacket(
            account: account,
            followedPubkeys: [followed],
            oldestCreatedAt: 200,
            relayURLs: ["wss://relay.example"],
            requestID: "older-test"
        )

        #expect(packet?.strategy == .backward)
        #expect(packet?.groupID == "astrenza-older-notes-older-test")
        #expect(packet?.relayURLs == ["wss://relay.example"])
        #expect(packet?.filters == [[
            "kinds": .ints([1, 5, 6]),
            "authors": .strings([followed]),
            "until": .int(199),
            "limit": .int(100)
        ]])
    }

    @Test("Home timeline sync planner builds gap notes packet")
    func homeTimelineSyncPlannerBuildsGapNotesPacket() {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let newer = timelineEvent(idSeed: "planner-gap-newer", pubkey: account.pubkey, createdAt: 500, content: "newer")
        let older = timelineEvent(idSeed: "planner-gap-older", pubkey: account.pubkey, createdAt: 100, content: "older")
        let planner = HomeTimelineSyncPlanner()

        let packet = planner.gapNotesPacket(
            account: account,
            followedPubkeys: [],
            newerEvent: newer,
            olderEvent: older,
            missingEstimate: 500,
            relayURLs: ["wss://relay.example"],
            requestID: "gap-test"
        )

        #expect(packet?.strategy == .backward)
        #expect(packet?.groupID == "astrenza-gap-notes-gap-test")
        #expect(packet?.filters == [[
            "kinds": .ints([1, 5, 6]),
            "authors": .strings([account.pubkey]),
            "since": .int(101),
            "until": .int(499),
            "limit": .int(250)
        ]])
    }

    @Test("Home timeline sync planner builds dependency packets")
    func homeTimelineSyncPlannerBuildsDependencyPackets() {
        let planner = HomeTimelineSyncPlanner()
        let profilePubkeys = [String(repeating: "b", count: 64), String(repeating: "c", count: 64)]
        let sourceIDs = [String(repeating: "d", count: 64), String(repeating: "e", count: 64)]
        let batch = NostrDependencyFetchBatch(
            profileGroups: [
                NostrDependencyFetchGroup(relayURLs: ["wss://profiles.example"], values: profilePubkeys)
            ],
            sourceGroups: [
                NostrDependencyFetchGroup(relayURLs: ["wss://source.example"], values: sourceIDs)
            ]
        )

        let plan = planner.dependencyPackets(batch: batch, requestID: "deps-test")

        #expect(plan.profilePackets.count == 1)
        #expect(plan.sourcePackets.count == 1)
        #expect(plan.registeredProfilePubkeys == profilePubkeys)
        #expect(plan.registeredSourceEventIDs == sourceIDs)
        #expect(plan.registeredGroupIDs == [
            "astrenza-kind0-deps-test-profile-0",
            "astrenza-source-events-deps-test-source-0"
        ])
        #expect(plan.profilePackets.first?.filters == [[
            "kinds": .ints([0]),
            "authors": .strings(profilePubkeys)
        ]])
        #expect(plan.sourcePackets.first?.filters == [[
            "ids": .strings(sourceIDs)
        ]])
    }

    @Test("Home timeline repository materializes entries from projection")
    func homeTimelineRepositoryMaterializesEntriesFromProjection() throws {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let eventStore = try NostrEventStore.inMemory()
        let note = timelineEvent(
            idSeed: "repository-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "repository body"
        )
        try eventStore.save(events: [note])
        let repository = HomeTimelineRepository(eventStore: eventStore)

        let snapshot = repository.materialize(
            HomeTimelineRenderInput(
                noteEvents: [note],
                feedWindow: nil,
                contextEvents: [],
                metadataEvents: [],
                nip05Resolutions: [:],
                profileResolutionStates: [:],
                followedPubkeys: [account.pubkey],
                resolvedRelayCount: 1,
                filterRules: nil,
                filterStatus: TimelineFilterStatus(),
                timeline: .home,
                policy: .default()
            )
        )

        #expect(snapshot.entries.compactMap(\.post).map(\.id) == [note.id])
        #expect(snapshot.filterStatus == TimelineFilterStatus())
        #expect(snapshot.renderFingerprint.count == snapshot.entries.count)
    }

    @Test("Home timeline render fingerprint covers same-ID visible row changes")
    func homeTimelineRenderFingerprintCoversVisibleFields() {
        let repository = HomeTimelineRepository(eventStore: nil)
        let author = TimelineAuthor.resolved(
            displayName: "Fingerprint",
            nip05: "fingerprint@example.test",
            pubkey: String(repeating: "a", count: 64)
        )
        let avatar = AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person.fill")

        func post(
            isLocked: Bool = false,
            replyMention: TimelineReplyMention? = nil,
            bodyPresentation: TimelineBodyPresentation = .standard
        ) -> TimelinePost {
            TimelinePost(
                id: "same-id",
                author: author,
                avatar: avatar,
                body: "Same canonical body",
                richBody: NostrRichContent(
                    displayText: "Same canonical body",
                    tokens: [.text("Same canonical body")],
                    references: []
                ),
                createdAt: 100,
                replyCount: 1,
                boostCount: 2,
                favoriteCount: 3,
                isLocked: isLocked,
                media: nil,
                context: nil,
                replyMention: replyMention,
                bodyPresentation: bodyPresentation
            )
        }

        let fingerprints = [
            post(),
            post(isLocked: true),
            post(replyMention: TimelineReplyMention(text: "Replying to @someone", isExternal: true)),
            post(bodyPresentation: .collapsed(lineLimit: 2, reason: .filtered))
        ].map { post in
            repository.entriesRenderFingerprint(for: [.post(post)]).first
        }

        #expect(Set(fingerprints).count == fingerprints.count)
    }

    @Test("Routine persistence projection stays bounded to the in-memory 480-event window")
    func homeTimelinePersistenceProjectionStaysBounded() {
        let allowedAuthor = String(repeating: "a", count: 64)
        let excludedAuthor = String(repeating: "b", count: 64)
        let allowedEvents = (0..<600).map { index in
            timelineEvent(
                idSeed: "persistence-bounded-\(index)",
                kind: index.isMultiple(of: 2) ? 1 : 6,
                pubkey: allowedAuthor,
                createdAt: 10_000 - index,
                content: "bounded \(index)"
            )
        }
        let excludedEvents = [
            timelineEvent(
                idSeed: "persistence-excluded-author",
                pubkey: excludedAuthor,
                createdAt: 20_000,
                content: "excluded author"
            ),
            timelineEvent(
                idSeed: "persistence-excluded-kind",
                kind: 7,
                pubkey: allowedAuthor,
                createdAt: 20_001,
                content: "excluded kind"
            )
        ]

        let projection = HomeTimelinePersistenceProjection.boundedEvents(
            from: excludedEvents + Array(allowedEvents.reversed()),
            allowedAuthors: [allowedAuthor]
        )

        #expect(projection.count == HomeTimelinePersistenceProjection.retainedEventLimit)
        #expect(projection.allSatisfy { $0.pubkey == allowedAuthor && ($0.kind == 1 || $0.kind == 6) })
        #expect(projection.map(\.id) == Array(allowedEvents.prefix(480)).map(\.id))
    }

    @Test("Persistence worker keeps relay history single-saved and advances read state")
    func homeTimelinePersistenceWorkerPersistsReadState() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "c", count: 64)
        let feedID = "feed:home:\(accountID)"
        let definition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: accountID,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "persistence-worker-test",
            sortPolicy: "created_at_desc_event_id_asc",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        let snapshot = HomeTimelineFeedPersistenceSnapshot(
            state: NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [accountID],
                noteEvents: [],
                metadataEvents: [],
                hasMoreOlder: true,
                relaySyncEvents: []
            ),
            accountID: accountID,
            definition: definition,
            memberships: [],
            membershipSources: [],
            savedAt: 100,
            windowLimit: 240
        )
        let syncEvent = NostrRelaySyncEventRecord(
            accountID: accountID,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            kind: .eose,
            occurredAt: 101,
            subscriptionID: "persistence-worker",
            eventCount: 0,
            message: "EOSE"
        )
        let worker = HomeTimelinePersistenceWorker(eventStore: eventStore)

        try await worker.saveRelaySyncEvents([syncEvent])
        _ = try await worker.saveFeedSnapshot(snapshot)
        _ = try await worker.saveFeedSnapshot(snapshot)

        let history = try eventStore.relaySyncEvents(
            accountID: accountID,
            timelineKey: "home",
            relayURL: syncEvent.relayURL,
            limit: 10
        )
        #expect(history == [syncEvent])

        let firstBoundary = NostrTimelineEntryCursor(sortTimestamp: 90, eventID: "event-90")
        try await worker.saveReadBoundary(feedID: feedID, boundary: firstBoundary, updatedAt: 102)

        let firstState = try #require(try eventStore.feedReadState(feedID: feedID))
        #expect(firstState.readBoundary == firstBoundary)

        let latestBoundary = NostrTimelineEntryCursor(sortTimestamp: 95, eventID: "event-95")
        try await worker.saveReadBoundary(feedID: feedID, boundary: latestBoundary, updatedAt: 103)

        let stateAfterBoundary = try #require(try eventStore.feedReadState(feedID: feedID))
        #expect(stateAfterBoundary.readBoundary == latestBoundary)
    }

    @Test("Home timeline store restores empty Generic Feed metadata and presentation viewport")
    @MainActor
    func homeTimelineStoreRestoresEmptyGenericFeedMetadata() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followed = String(repeating: "b", count: 64)
        let definition = NostrFeedDefinitionRecord(
            feedID: "feed:home:\(account.pubkey)",
            accountID: account.pubkey,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "empty-app-home",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        let state = NostrHomeTimelineState(
            relays: ["wss://relay.example"],
            followedPubkeys: [followed],
            noteEvents: [],
            metadataEvents: [],
            hasMoreOlder: false
        )
        try eventStore.saveHomeFeedState(
            state,
            accountID: account.pubkey,
            definition: definition,
            memberships: [],
            savedAt: 101
        )
        let suiteName = "HomeTimelineEmptyFeedRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewportStateRestorer = TimelineRestoreStore(defaults: defaults)
        viewportStateRestorer.saveViewportState(TimelineViewportState(
            accountID: account.pubkey,
            timelineKey: "home",
            anchorPostID: "empty-feed-anchor",
            anchorOffset: 18,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 101)
        ))
        let (store, relayClient) = makeGatedHomeStore(
            eventStore: eventStore,
            bootstrapRelays: state.relays,
            viewportStateRestorer: viewportStateRestorer
        )

        store.start(account: account)
        defer { store.cancel() }
        try await relayClient.waitUntilBootstrapFetchStarts()

        #expect(store.entries.isEmpty)
        #expect(store.resolvedRelays == state.relays)
        #expect(store.followedPubkeys == state.followedPubkeys)
        #expect(store.hasMoreOlder == false)
        let viewport = try #require(store.restoredViewportState(
            accountID: account.pubkey,
            timelineKey: "home"
        ))
        #expect(viewport.anchorPostID == "empty-feed-anchor")
        #expect(viewport.anchorOffset == 18)
        await relayClient.releaseBootstrap()
    }

    @Test("Home timeline store restores cached read boundary before relay sync")
    @MainActor
    func homeTimelineStoreRestoresCachedReadBoundaryBeforeRelaySync() async throws {
        let fixture = try makeCachedReadBoundaryStoreFixture()

        fixture.store.start(account: fixture.account)
        defer { fixture.store.cancel() }
        try await fixture.relayClient.waitUntilBootstrapFetchStarts()

        #expect(fixture.store.entries.compactMap(\.post?.id) == fixture.expectedPostIDs)
        #expect(fixture.store.materializedUnreadCount == 1)
        #expect(fixture.store.visibleUnreadBadgeCount == 1)
        await fixture.relayClient.releaseBootstrap()
    }

    @Test("Home timeline store confines legacy timeline restore to migration and creates Generic Feed")
    @MainActor
    func homeTimelineStoreMigratesLegacyTimelineSnapshot() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "c", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let note = timelineEvent(
            idSeed: "legacy-migration-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "legacy migration"
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://legacy.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [note],
                metadataEvents: []
            ),
            accountID: account.pubkey
        )
        #expect(try eventStore.feedDefinition(feedID: "feed:home:\(account.pubkey)") == nil)
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [:]),
                bootstrapRelays: []
            ),
            eventStore: eventStore
        )

        store.start(account: account)
        defer { store.cancel() }
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post?.id) == [note.id]
        })

        #expect(store.entries.compactMap(\.post?.id) == [note.id])
        #expect(try eventStore.feedDefinition(feedID: "feed:home:\(account.pubkey)") != nil)
        #expect(try eventStore.homeFeedState(accountID: account.pubkey)?.noteEvents == [note])
    }

    @Test("Home timeline store restores live gap rows from database timeline entries")
    @MainActor
    func homeTimelineStoreRestoresLiveGapRowsFromDatabaseEntries() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let newer = timelineEvent(idSeed: "store-live-gap-newer", pubkey: account.pubkey, createdAt: 300, content: "newer")
        let older = timelineEvent(idSeed: "store-live-gap-older", pubkey: account.pubkey, createdAt: 100, content: "older")

        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example", "wss://backup.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)
        let expectedIDs = [
            newer.id,
            "gap-\(newer.id)-\(older.id)",
            older.id
        ]
        try #require(await waitForTimelineState {
            store.entries.map(\.id) == expectedIDs
        })

        #expect(store.entries.map(\.id) == expectedIDs)
        guard case .gap(let gap) = store.entries[1] else {
            Issue.record("Expected restored live gap row")
            return
        }
        #expect(gap.relayCount == 2)
    }

    @Test("Home timeline store projects saved restore anchor from database window")
    @MainActor
    func homeTimelineStoreProjectsSavedRestoreAnchorFromDatabaseWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let events = (0..<300).map { index in
            timelineEvent(
                idSeed: "restore-window-\(index)",
                pubkey: account.pubkey,
                createdAt: 10_000 - index,
                content: "restore window \(index)"
            )
        }
        let anchor = events[270]

        try eventStore.save(events: events)
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: Array(events.prefix(10)),
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: events,
            insertedAt: 10_001
        )

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.setRestoreProjectionAnchor(anchor.id)
        store.start(account: account)
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post).contains { $0.id == anchor.id }
        })

        let postIDs = store.entries.compactMap(\.post).map(\.id)
        #expect(postIDs.contains(anchor.id))
        #expect(postIDs.contains(events[0].id) == false)
    }

    @Test("Home timeline store can temporarily suspend and resume filters")
    @MainActor
    func homeTimelineStoreSuspendsAndResumesFilters() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let hidden = timelineEvent(
            idSeed: "suspended-hidden-note",
            pubkey: account.pubkey,
            createdAt: 200,
            content: "quiet keyword"
        )
        let visible = timelineEvent(
            idSeed: "suspended-visible-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "ordinary text"
        )
        let rule = NostrFilterRuleRecord(
            ruleID: "rule-1",
            accountID: account.pubkey,
            kind: .keyword,
            value: "keyword",
            presentation: .hide,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )

        try eventStore.saveFilterRule(rule)
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [hidden, visible],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post).map(\.id) == [visible.id] &&
                store.filterStatus.hiddenMatchCount == 1
        })

        #expect(store.entries.compactMap(\.post).map(\.id) == [visible.id])
        #expect(store.filterStatus.hiddenMatchCount == 1)

        store.suspendTimelineFilters()
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post).map(\.id) == [hidden.id, visible.id] &&
                store.filterStatus.isSuspended
        })

        #expect(store.entries.compactMap(\.post).map(\.id) == [hidden.id, visible.id])
        #expect(store.filterStatus.isSuspended)
        #expect(store.filterStatus.hiddenMatchCount == 0)

        store.resumeTimelineFilters()
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post).map(\.id) == [visible.id] &&
                !store.filterStatus.isSuspended &&
                store.filterStatus.hiddenMatchCount == 1
        })

        #expect(store.entries.compactMap(\.post).map(\.id) == [visible.id])
        #expect(store.filterStatus.isSuspended == false)
        #expect(store.filterStatus.hiddenMatchCount == 1)
    }

    @Test("Home relay pill counts reachable relays from runtime history")
    @MainActor
    func homeRelayPillCountsReachableRelaysFromRuntimeHistory() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "c", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let note = timelineEvent(
            idSeed: "relay-pill-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "relay state"
        )

        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://ok.example", "wss://slow.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [note],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )
        let now = Int(Date().timeIntervalSince1970)
        try eventStore.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: account.pubkey,
                timelineKey: "home",
                relayURL: "wss://ok.example",
                kind: .eose,
                occurredAt: now,
                subscriptionID: "test-ok",
                eventCount: 1,
                message: "EOSE received"
            ),
            NostrRelaySyncEventRecord(
                accountID: account.pubkey,
                timelineKey: "home",
                relayURL: "wss://slow.example",
                kind: .timeout,
                occurredAt: now,
                subscriptionID: "test-slow",
                eventCount: 0,
                message: "timeout"
            )
        ])

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)
        defer { store.cancel() }
        try await waitForRelayStatusCounts(in: store, connected: 1, planned: 2)
    }

    @Test("Home relay pill does not count stale relay history as connected")
    @MainActor
    func homeRelayPillIgnoresStaleReachableHistory() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "d", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let note = timelineEvent(
            idSeed: "stale-relay-pill-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "stale relay state"
        )

        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://old.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [note],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )
        try eventStore.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: account.pubkey,
                timelineKey: "home",
                relayURL: "wss://old.example",
                kind: .connected,
                occurredAt: Int(Date().timeIntervalSince1970) - 600,
                subscriptionID: "old-forward",
                eventCount: 1,
                message: "EVENT received"
            )
        ])

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)
        defer { store.cancel() }
        try #require(await waitForTimelineState {
            store.resolvedRelays == ["wss://old.example"]
        })

        #expect(store.relayStatusCounts.connected == 0)
        #expect(store.relayStatusCounts.planned == 1)
    }

    @Test("Home relay pill lets live runtime state override recent reachable history")
    @MainActor
    func homeRelayPillRuntimeStateOverridesRecentReachableHistory() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let note = timelineEvent(
            idSeed: "live-runtime-relay-pill-note",
            pubkey: account.pubkey,
            createdAt: 100,
            content: "live runtime relay state"
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(maxAttempts: 0, initialDelayMilliseconds: 0, delayStepMilliseconds: 0),
            heartbeatPolicy: .disabled
        )

        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://live.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [note],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )
        try eventStore.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: account.pubkey,
                timelineKey: "home",
                relayURL: "wss://live.example",
                kind: .eose,
                occurredAt: Int(Date().timeIntervalSince1970),
                subscriptionID: "recent-forward",
                eventCount: 1,
                message: "recent EOSE"
            )
        ])
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                    "astrenza-nip65": [],
                    "astrenza-kind3": [],
                    "astrenza-home": []
                ]),
                bootstrapRelays: ["wss://live.example"],
                pageLimit: 20
            ),
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await waitForRelayRuntimeState(in: store, relayURL: "wss://live.example", state: .suspended)
        try await waitForRelayStatusCounts(in: store, connected: 0, planned: 1)
    }

    @Test("Home timeline exposes discovery relays after local cache restoration")
    @MainActor
    func homeTimelineRuntimeExposesProvisionalBootstrapRelaysImmediately() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true,
            discoveryRelays: ["hint.example", "wss://bootstrap.example"]
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(maxAttempts: 0, initialDelayMilliseconds: 0, delayStepMilliseconds: 0),
            heartbeatPolicy: .disabled
        )
        let relayClient = GatedStoreRelayClient(eventsBySubscriptionID: [:])
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: relayClient,
                bootstrapRelays: ["wss://bootstrap.example", "wss://fallback.example"],
                pageLimit: 20
            ),
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        defer { store.cancel() }
        try await relayClient.waitUntilBootstrapFetchStarts()

        #expect(store.resolvedRelays == [
            "wss://hint.example",
            "wss://bootstrap.example",
            "wss://fallback.example"
        ])
        #expect(store.followedPubkeys.isEmpty)
        #expect(store.relayStatusCounts.planned == 3)
        #expect(store.phase == .resolvingRelays)
        await relayClient.releaseBootstrap()
    }

    @Test("Fresh Home runtime waits for kind 10002 and kind 3 before installing forward REQ")
    @MainActor
    func freshHomeRuntimeWaitsForBootstrapBeforeForwardREQ() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followed = String(repeating: "b", count: 64)
        let relayURL = "wss://relay.example"
        let relayClient = GatedStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [timelineEvent(
                idSeed: "gated-nip65",
                kind: 10002,
                pubkey: account.pubkey,
                createdAt: 100,
                tags: [["r", relayURL, "read"]],
                content: ""
            )],
            "astrenza-kind3": [timelineEvent(
                idSeed: "gated-kind3",
                kind: 3,
                pubkey: account.pubkey,
                createdAt: 101,
                tags: [["p", followed]],
                content: ""
            )]
        ])
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: relayClient,
                bootstrapRelays: [relayURL],
                pageLimit: 20
            ),
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await relayClient.waitUntilBootstrapFetchStarts()

        #expect(await connection.sentFrames().allSatisfy { !$0.contains("astrenza-home-forward") })
        #expect(store.followedPubkeys.isEmpty)
        #expect(store.phase == .resolvingRelays)
        #expect(store.activityStatus?.compactLabel == "kind:10002")
        #expect(store.activityStatus?.detail.contains("kind:10002") == true)

        await relayClient.releaseBootstrap()
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)

        let forwardFrame = try #require(await connection.sentFrames().first { $0.contains("astrenza-home-forward") })
        #expect(forwardFrame.contains(followed))
        #expect(!forwardFrame.contains(#""authors":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]"#))
        #expect(store.followedPubkeys == [followed])
    }

    @Test("Fresh Home runtime reports kind 3 resolution before opening Home")
    @MainActor
    func freshHomeRuntimeReportsContactResolution() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "c", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followed = String(repeating: "d", count: 64)
        let relayURL = "wss://relay.example"
        let relayClient = GatedStoreRelayClient(
            eventsBySubscriptionID: [
                "astrenza-nip65": [timelineEvent(
                    idSeed: "gated-stage-nip65",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", relayURL, "read"]],
                    content: ""
                )],
                "astrenza-kind3": [timelineEvent(
                    idSeed: "gated-stage-kind3",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", followed]],
                    content: ""
                )]
            ],
            gatedSubscriptionID: "astrenza-kind3"
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: relayClient,
                bootstrapRelays: [relayURL],
                pageLimit: 20
            ),
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await relayClient.waitUntilBootstrapFetchStarts()

        #expect(store.phase == .resolvingContacts)
        #expect(store.activityStatus?.title == "Resolving contacts")
        #expect(store.activityStatus?.compactLabel == "kind:3")
        #expect(await connection.sentFrames().allSatisfy { !$0.contains("astrenza-home-forward") })

        await relayClient.releaseBootstrap()
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)
        for _ in 0..<100 {
            if store.phase == .loaded { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.phase == .loaded)
        #expect(store.activityStatus == nil)
    }

    @Test("Home timeline releases dependency work when packet relays are unavailable")
    @MainActor
    func homeTimelineReleasesUnavailableRelayDependencyWork() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let store = NostrHomeTimelineStore(
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )
        let definition = NostrFeedDefinitionRecord(
            feedID: homeFeedID(accountID: account.pubkey),
            accountID: account.pubkey,
            kind: "home",
            specificationJSON: Data(#"{"authors":[],"kinds":[1,6]}"#.utf8),
            specificationHash: "unavailable-relay-dependency",
            revision: 1,
            createdAt: 100,
            updatedAt: 100
        )
        let dependencyEventID = String(repeating: "f", count: 64)

        try await relayRuntime.setDefaultRelays(["wss://default.example"])
        await store.testingActivateHomeFeed(
            account: account,
            definition: definition,
            sourceAuthors: [account.pubkey]
        )
        #expect(store.testingEnqueueBackwardDependencies(
            NostrEventDependencies(sourceEventIDs: [dependencyEventID]),
            availableRelayURLs: ["wss://scoped.example"]
        ))
        store.testingFlushBackwardDependencies()

        for _ in 0..<100 {
            guard store.testingHasPendingDependencyWork else { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.testingPendingBackwardRequestCount == 0)
        #expect(store.testingHasPendingDependencyWork == false)
        #expect(await connection.sentFrames().isEmpty)
    }

    @Test("Home relay pill keeps newer cached NIP-65 over stale bootstrap result")
    @MainActor
    func homeRelayPillKeepsNewerCachedNIP65OverStaleBootstrapResult() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "f", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let newerRelayList = timelineEvent(
            idSeed: "newer-cached-nip65",
            kind: 10002,
            pubkey: account.pubkey,
            createdAt: 300,
            tags: [
                ["r", "wss://relay-a.example", "read"],
                ["r", "wss://relay-b.example", "read"],
                ["r", "wss://relay-c.example", "read"]
            ],
            content: ""
        )
        try eventStore.save(events: [newerRelayList])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "stale-bootstrap-nip65",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://old-relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "stale-bootstrap-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 101,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://old-relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(timelineLoader: timelineLoader, eventStore: eventStore)

        store.start(account: account)
        try await waitForRelayStatusCounts(in: store, connected: 0, planned: 3)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.resolvedRelays == [
            "wss://relay-a.example",
            "wss://relay-b.example",
            "wss://relay-c.example"
        ])
        #expect(store.relayStatusCounts.planned == 3)
    }

    @Test("Home timeline loader chooses newest NIP-65 across bootstrap relays")
    func homeTimelineLoaderChoosesNewestNIP65AcrossBootstrapRelays() async throws {
        let account = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let staleRelayList = timelineEvent(
            idSeed: "stale-fast-nip65",
            kind: 10002,
            pubkey: account.pubkey,
            createdAt: 100,
            tags: [["r", "wss://stale.example", "read"]],
            content: ""
        )
        let freshRelayList = timelineEvent(
            idSeed: "fresh-slower-nip65",
            kind: 10002,
            pubkey: account.pubkey,
            createdAt: 300,
            tags: [
                ["r", "wss://relay-a.example", "read"],
                ["r", "wss://relay-b.example", "read"],
                ["r", "wss://relay-c.example", "read"]
            ],
            content: ""
        )
        let contactList = timelineEvent(
            idSeed: "bootstrap-kind3",
            kind: 3,
            pubkey: account.pubkey,
            createdAt: 301,
            tags: [["p", account.pubkey]],
            content: ""
        )
        let loader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(
                eventsByRelayAndSubscriptionID: [
                    "wss://fast.example": [
                        "astrenza-nip65": [staleRelayList],
                        "astrenza-kind3": [contactList],
                        "astrenza-home": []
                    ],
                    "wss://slow.example": [
                        "astrenza-nip65": [freshRelayList],
                        "astrenza-kind3": [contactList],
                        "astrenza-home": []
                    ],
                    "wss://relay-a.example": [
                        "astrenza-kind3": [contactList],
                        "astrenza-home": []
                    ],
                    "wss://relay-b.example": [
                        "astrenza-kind3": [contactList],
                        "astrenza-home": []
                    ],
                    "wss://relay-c.example": [
                        "astrenza-kind3": [contactList],
                        "astrenza-home": []
                    ]
                ]
            ),
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 20
        )

        let state = try await loader.initialState(account: account)

        #expect(state.relayListEvent?.id == freshRelayList.id)
        #expect(state.relays == [
            "wss://relay-a.example",
            "wss://relay-b.example",
            "wss://relay-c.example"
        ])
    }

    @Test("Home timeline keeps newer cached kind 3 over stale bootstrap result")
    @MainActor
    func homeTimelineKeepsNewerCachedKind3OverStaleBootstrapResult() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "f", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let firstFollow = String(repeating: "1", count: 64)
        let secondFollow = String(repeating: "2", count: 64)
        let staleFollow = String(repeating: "3", count: 64)
        let newerContactList = timelineEvent(
            idSeed: "newer-cached-kind3",
            kind: 3,
            pubkey: account.pubkey,
            createdAt: 300,
            tags: [
                ["p", firstFollow],
                ["p", secondFollow]
            ],
            content: ""
        )
        try eventStore.save(events: [newerContactList])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "kind3-stale-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "stale-bootstrap-kind3",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["p", staleFollow]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(timelineLoader: timelineLoader, eventStore: eventStore)

        store.start(account: account)
        try await waitForFollowedPubkeys(in: store, [firstFollow, secondFollow])
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(store.followedPubkeys == [firstFollow, secondFollow])
    }

    @Test("Home timeline treats a newer empty cached kind 3 as unfollow all")
    @MainActor
    func homeTimelineTreatsEmptyCachedKind3AsUnfollowAll() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "9", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let staleFollow = String(repeating: "8", count: 64)
        let emptyContactList = timelineEvent(
            idSeed: "newer-empty-cached-kind3",
            kind: 3,
            pubkey: account.pubkey,
            createdAt: 300,
            tags: [],
            content: ""
        )
        try eventStore.save(events: [emptyContactList])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "empty-kind3-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "stale-nonempty-kind3",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["p", staleFollow]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(timelineLoader: timelineLoader, eventStore: eventStore)

        store.start(account: account)
        for _ in 0..<100 {
            if store.phase == .loaded { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(store.phase == .loaded)
        #expect(store.followedPubkeys.isEmpty)
    }

    @Test("Relay status sheet refresh does not mark NIP-11 HTTP fetches as relay connectivity")
    @MainActor
    func relayStatusSheetRefreshDoesNotPolluteRelaySyncHistory() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "e", count: 64)
        let relayURL = "wss://relay.example"
        let client = FakeRelayInformationClient(result: .success(NostrRelayInformationDocument(
            name: "Relay Example",
            description: "NIP-11 info only",
            pubkey: nil,
            contact: nil,
            supportedNips: [1, 11, 65],
            software: "test-relay",
            version: "1.0",
            limitation: nil
        )))
        let store = RelayStatusSheetStore(
            relayURLs: [relayURL],
            accountID: accountID,
            eventStore: eventStore,
            client: client
        )

        await store.refresh()

        #expect(try eventStore.relaySyncEvents(
            accountID: accountID,
            timelineKey: "home",
            relayURL: relayURL,
            limit: 10
        ).isEmpty)
        #expect(try eventStore.relaySyncSummaries(accountID: accountID, timelineKey: "home").isEmpty)
        let profile = try #require(try eventStore.relayProfile(relayURL: relayURL))
        #expect(profile.information?.name == "Relay Example")
        #expect(store.connectedCount == 0)
        #expect(store.relays.first?.status == .connecting)
    }

    @Test("Relay status sheet keeps live runtime state separate from DB reachability")
    @MainActor
    func relayStatusSheetSeparatesRuntimeStateFromDBReachability() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "f", count: 64)
        let relayURL = "wss://relay.example"
        let store = RelayStatusSheetStore(
            relayURLs: [relayURL],
            relayRuntimeStates: [relayURL: .connected],
            accountID: accountID,
            eventStore: eventStore
        )

        let relay = try #require(store.relays.first)
        #expect(relay.runtimeState == .connected)
        #expect(relay.status == .connecting)
        #expect(store.connectedCount == 0)
        #expect(try eventStore.relaySyncSummaries(accountID: accountID, timelineKey: "home").isEmpty)
    }

    @Test("Relay status sheet updates live runtime state without changing DB reachability")
    @MainActor
    func relayStatusSheetUpdatesRuntimeStateWithoutChangingReachability() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "a1", count: 32)
        let relayURL = "wss://relay.example"
        let store = RelayStatusSheetStore(
            relayURLs: [relayURL],
            relayRuntimeStates: [relayURL: .connected],
            accountID: accountID,
            eventStore: eventStore
        )

        #expect(store.relays.first?.runtimeState == .connected)
        #expect(store.connectedCount == 0)

        store.updateRuntimeStates([relayURL: .retrying])

        #expect(store.relays.first?.runtimeState == .retrying)
        #expect(store.relays.first?.status == .connecting)
        #expect(store.connectedCount == 0)
        #expect(try eventStore.relaySyncSummaries(accountID: accountID, timelineKey: "home").isEmpty)
    }

    @Test("Relay status sheet does not fall back to mock relays while live relays are resolving")
    @MainActor
    func relayStatusSheetKeepsEmptyLiveRelayListOutOfMockMode() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "c1", count: 32)
        let relayURL = "wss://relay.example"
        let store = RelayStatusSheetStore(
            relayURLs: [],
            accountID: accountID,
            eventStore: eventStore
        )

        #expect(store.isLive)
        #expect(store.relays.isEmpty)
        #expect(store.plannedCount == 0)

        store.updateRelayURLs([relayURL])

        let relay = try #require(store.relays.first)
        #expect(store.plannedCount == 1)
        #expect(relay.url == relayURL)
        #expect(relay.displayName == "relay.example")
        #expect(relay.software == "Loading")
        #expect(relay.status == .connecting)
    }

    @Test("Relay status sheet still uses mock relays without a live account")
    @MainActor
    func relayStatusSheetUsesMockRelaysOnlyWithoutLiveAccount() throws {
        let store = RelayStatusSheetStore(
            relayURLs: [],
            accountID: nil,
            eventStore: nil
        )

        #expect(!store.isLive)
        #expect(store.relays.map(\.url) == RelayMockStore.relays.map(\.url))
    }

    @Test("Relay status sheet projects DB lifecycle counters into relay descriptors")
    @MainActor
    func relayStatusSheetProjectsLifecycleCounters() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b1", count: 32)
        let relayURL = "wss://relay.example"
        let now = Int(Date().timeIntervalSince1970)
        try eventStore.saveRelaySyncEvents([
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .reconnect,
                occurredAt: now - 4,
                message: "retrying"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .timeout,
                occurredAt: now - 3,
                message: "heartbeat timeout"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .partialFailure,
                occurredAt: now - 2,
                message: "network lost"
            ),
            NostrRelaySyncEventRecord(
                accountID: accountID,
                timelineKey: "home",
                relayURL: relayURL,
                kind: .eose,
                occurredAt: now - 1,
                eventCount: 0,
                message: "EOSE received"
            )
        ])

        let store = RelayStatusSheetStore(
            relayURLs: [relayURL],
            accountID: accountID,
            eventStore: eventStore
        )

        let lifecycle = try #require(store.relays.first?.lifecycle)
        #expect(lifecycle.reconnects == 1)
        #expect(lifecycle.timeouts == 1)
        #expect(lifecycle.partialFailures == 1)
        #expect(lifecycle.totalProblems == 2)
        #expect(lifecycle.summary.contains("reconnect 1"))
        #expect(lifecycle.summary.contains("timeout 1"))
        #expect(lifecycle.summary.contains("partial 1"))
    }

    @Test("Relay status sheet projects DB traffic counters into diagnostics")
    @MainActor
    func relayStatusSheetProjectsTrafficCounters() throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountID = String(repeating: "b2", count: 32)
        let relayURL = "wss://relay.example"
        let now = 1_717_891_200
        try eventStore.recordRelayTraffic([
            NostrRelayTrafficDelta(
                accountID: accountID,
                relayURL: relayURL,
                occurredAt: now - 10,
                networkType: .wifi,
                syncMode: .ownRelayList,
                receivedBytes: 120,
                sentBytes: 40,
                receivedMessages: 2,
                sentMessages: 1
            ),
            NostrRelayTrafficDelta(
                accountID: accountID,
                relayURL: relayURL,
                occurredAt: now - 7_200,
                networkType: .wifi,
                syncMode: .ownRelayList,
                receivedBytes: 80,
                sentBytes: 10,
                receivedMessages: 1,
                sentMessages: 1
            )
        ])

        let store = RelayStatusSheetStore(
            relayURLs: [relayURL],
            accountID: accountID,
            eventStore: eventStore,
            syncPolicy: NostrSyncPolicy.default(networkType: .wifi),
            sessionStartedAt: now - 60,
            now: { now }
        )

        #expect(store.trafficSummary.session.receivedBytes == 120)
        #expect(store.trafficSummary.session.sentBytes == 40)
        #expect(store.trafficSummary.today.receivedBytes == 200)
        #expect(store.trafficSummary.billingCycle.sentBytes == 50)

        let relay = try #require(store.relays.first)
        #expect(relay.traffic.session.receivedBytes == 120)
        #expect(relay.traffic.today.receivedMessages == 3)
        #expect(relay.receivedBytes == "200 B")
        #expect(relay.sentBytes == "50 B")
    }

    @Test("Sync policy settings persist per account")
    @MainActor
    func syncPolicySettingsPersistPerAccount() throws {
        let suiteName = "AstrenzaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NostrSyncPolicySettingsStore(defaults: defaults)
        let accountA = String(repeating: "c2", count: 32)
        let accountB = String(repeating: "d2", count: 32)
        let policy = NostrSyncPolicy(
            mode: .fullOutbox,
            networkType: .cellular,
            lowPowerMode: false,
            tapToLoadMedia: true,
            queueOGPPreviews: true,
            disableOGPOnCellular: true,
            reduceFullOutboxOnCellular: true
        )

        store.save(policy, accountID: accountA)

        #expect(store.policy(accountID: accountA).mode == .fullOutbox)
        #expect(store.policy(accountID: accountA).networkType == .cellular)
        #expect(store.policy(accountID: accountB).mode == .ownRelayList)
    }

    @Test("Media resolver service settings persist URL token and enabled state")
    func mediaResolverServiceSettingsPersist() throws {
        let suiteName = "AstrenzaTests.media-resolver.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = MediaResolverBearerTokenProbe()
        let store = NostrMediaResolverSettingsStore(defaults: defaults, bearerTokenStore: tokenStore.store)
        let settings = NostrMediaResolverServiceSettings(
            serviceURLString: "https://media.example.test/base",
            bearerToken: "private-token",
            isEnabled: true
        )

        store.save(settings)

        let restored = store.settings()
        #expect(restored == settings)
        #expect(store.configuration().isUsable)
        #expect(store.configuration().bearerToken == "private-token")
        #expect(tokenStore.token == "private-token")
        #expect(defaults.string(forKey: NostrMediaResolverSettingsStore.legacyBearerTokenDefaultsKey) == nil)
        #expect(String(describing: restored).contains("private-token") == false)
        #expect(String(reflecting: restored).contains("private-token") == false)
    }

    @Test("Media resolver service settings migrate legacy UserDefaults token into token store")
    func mediaResolverServiceSettingsMigrateLegacyToken() throws {
        let suiteName = "AstrenzaTests.media-resolver.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-token", forKey: NostrMediaResolverSettingsStore.legacyBearerTokenDefaultsKey)
        let tokenStore = MediaResolverBearerTokenProbe()
        let store = NostrMediaResolverSettingsStore(defaults: defaults, bearerTokenStore: tokenStore.store)

        let settings = store.settings()

        #expect(settings.bearerToken == "legacy-token")
        #expect(tokenStore.token == "legacy-token")
        #expect(defaults.string(forKey: NostrMediaResolverSettingsStore.legacyBearerTokenDefaultsKey) == nil)
    }

    @Test("Home timeline store loads saved sync policy when account starts")
    @MainActor
    func homeTimelineStoreLoadsSavedSyncPolicyOnStart() throws {
        let suiteName = "AstrenzaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policyStore = NostrSyncPolicySettingsStore(defaults: defaults)
        let account = NostrAccount(
            pubkey: String(repeating: "e2", count: 32),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        policyStore.save(NostrSyncPolicy(
            mode: .energySaver,
            networkType: .cellular,
            lowPowerMode: true,
            tapToLoadMedia: true,
            queueOGPPreviews: true,
            disableOGPOnCellular: true,
            reduceFullOutboxOnCellular: true
        ), accountID: account.pubkey)
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [:])),
            eventStore: nil,
            syncPolicySettingsStore: policyStore
        )

        store.start(account: account)
        defer { store.cancel() }

        #expect(store.currentSyncPolicy.mode == .energySaver)
        #expect(store.currentSyncPolicy.networkType == .cellular)
        #expect(store.currentSyncPolicy.lowPowerMode)
    }

    @Test("Home timeline store does not reinstall an unchanged forward subscription")
    @MainActor
    func homeTimelineStoreSkipsUnchangedForwardSubscriptionInstall() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "stable-forward-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "stable-forward-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 101,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)
        store.start(account: account)
        try await Task.sleep(nanoseconds: 200_000_000)

        let sentFrames = await connection.sentFrames()
        let forwardREQCount = sentFrames.filter { frame in
            reqSubscriptionID(from: frame, containing: "astrenza-home-forward") != nil
        }.count
        #expect(forwardREQCount == 1)
    }

    @Test("Home timeline store resets account-scoped projection state on direct account switch")
    @MainActor
    func homeTimelineStoreResetsStateOnDirectAccountSwitch() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let firstAccount = NostrAccount(
            pubkey: String(repeating: "a", count: 64),
            displayIdentifier: "first",
            readOnly: true
        )
        let secondAccount = NostrAccount(
            pubkey: String(repeating: "b", count: 64),
            displayIdentifier: "second",
            readOnly: true
        )
        let firstNote = timelineEvent(
            idSeed: "account-switch-first",
            pubkey: firstAccount.pubkey,
            createdAt: 100,
            content: "first account"
        )
        let secondNote = timelineEvent(
            idSeed: "account-switch-second",
            pubkey: secondAccount.pubkey,
            createdAt: 200,
            content: "second account"
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [firstAccount.pubkey],
                noteEvents: [firstNote],
                metadataEvents: []
            ),
            accountID: firstAccount.pubkey
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: [],
                followedPubkeys: [secondAccount.pubkey],
                noteEvents: [secondNote],
                metadataEvents: []
            ),
            accountID: secondAccount.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: NostrHomeTimelineLoader(
                relayClient: CancellableStoreRelayClient(),
                bootstrapRelays: ["wss://relay.example"]
            ),
            eventStore: eventStore
        )

        store.start(account: firstAccount)
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post?.id) == [firstNote.id]
        })
        #expect(store.entries.compactMap(\.post?.id) == [firstNote.id])

        store.start(account: secondAccount)
        try #require(await waitForTimelineState {
            store.entries.compactMap(\.post?.id) == [secondNote.id]
        })

        #expect(store.account?.pubkey == secondAccount.pubkey)
        #expect(store.followedPubkeys == [secondAccount.pubkey])
        #expect(store.entries.compactMap(\.post?.id) == [secondNote.id])
        #expect(!store.entries.compactMap(\.post?.id).contains(firstNote.id))
        store.cancel()
    }

    @Test("Home timeline initial load uses runtime forward REQ instead of short lived home fetch")
    @MainActor
    func homeTimelineInitialLoadUsesRuntimeForwardREQ() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "e", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-initial-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-initial-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [
                timelineEvent(
                    idSeed: "should-not-use-short-initial",
                    pubkey: account.pubkey,
                    createdAt: 200,
                    content: "short lived initial should be skipped"
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)

        let fetchSubscriptionIDs = try await waitForFetchSubscriptionIDs(
            in: relayClient,
            containing: ["astrenza-nip65", "astrenza-kind3"]
        )
        #expect(fetchSubscriptionIDs.contains("astrenza-nip65"))
        #expect(fetchSubscriptionIDs.contains("astrenza-kind3"))
        #expect(!fetchSubscriptionIDs.contains("astrenza-home"))
        #expect(store.entries.isEmpty)
    }

    @Test("Home timeline store cancel terminates runtime sessions")
    @MainActor
    func homeTimelineStoreCancelTerminatesRuntimeSessions() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "d", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-cancel-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-cancel-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)
        #expect(await relayRuntime.defaultRelayURLs() == ["wss://relay.example"])

        store.cancel()

        for _ in 0..<100 {
            if await connection.closed() {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(await connection.closed())
        #expect(await relayRuntime.defaultRelayURLs().isEmpty)
        #expect(store.relayRuntimeStates.isEmpty)
        #expect(!store.isRelayProcessing)
    }

    @Test("Home timeline refresh keeps the installed runtime forward REQ without resending it")
    @MainActor
    func homeTimelineRefreshKeepsInstalledRuntimeForwardREQ() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "f", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let initialNote = timelineEvent(
            idSeed: "runtime-refresh-initial",
            pubkey: account.pubkey,
            createdAt: 200,
            content: "cached by initial bootstrap"
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-refresh-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-refresh-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [initialNote],
            "astrenza-home-newer": [
                timelineEvent(
                    idSeed: "should-not-use-short-refresh",
                    pubkey: account.pubkey,
                    createdAt: 300,
                    content: "short lived refresh should be skipped"
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await waitForREQFrameCount(in: connection, containing: "astrenza-home-forward", count: 1)
        let requestCountBeforeRefresh = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: "astrenza-home-forward") != nil
        }.count
        store.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        let requestCountAfterRefresh = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: "astrenza-home-forward") != nil
        }.count

        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(requestCountBeforeRefresh == 1)
        #expect(requestCountAfterRefresh == requestCountBeforeRefresh)
        #expect(!fetchSubscriptionIDs.contains("astrenza-home"))
        #expect(!fetchSubscriptionIDs.contains("astrenza-home-newer"))
        #expect(store.entries.compactMap(\.post).map(\.id) == [initialNote.id])
    }

    @Test("Home timeline load older uses runtime backward REQ instead of short lived older fetch")
    @MainActor
    func homeTimelineLoadOlderUsesRuntimeBackwardREQ() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "34", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialNote = try await signer.sign(
            NostrPublishInput.post(content: "initial page")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let olderNote = try await signer.sign(
            NostrPublishInput.post(content: "older page")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-older-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-older-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [initialNote],
            "astrenza-home-older": [
                timelineEvent(
                    idSeed: "should-not-use-short-older",
                    pubkey: account.pubkey,
                    createdAt: 150,
                    content: "short lived older should be skipped"
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        store.loadOlder()
        let olderSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-older-notes")
        #expect(store.isRelayProcessing)
        #expect(store.activityStatus?.compactLabel == "Older")

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: olderSubscriptionID, event: olderNote),
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let profileSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)
        let metadataEvent = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 301,
                kind: 0,
                tags: [],
                content: #"{"name":"Runtime Older"}"#
            )
        )
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: profileSubscriptionID, event: metadataEvent),
            try relayEOSEFrame(subscriptionID: profileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 100_000_000)

        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(!fetchSubscriptionIDs.contains("astrenza-home"))
        #expect(!fetchSubscriptionIDs.contains("astrenza-home-older"))
        #expect(store.entries.compactMap(\.post).map(\.id) == [initialNote.id, olderNote.id])
        try await waitForRelayProcessing(in: store, isProcessing: false)
    }

    @Test("Home timeline runtime older page materializes deletion events from backward REQ")
    @MainActor
    func homeTimelineRuntimeOlderDeletionMaterializesTombstone() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "42", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialNote = try await signer.sign(
            NostrPublishInput.post(content: "initial page")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 400)
        )
        let olderNote = try await signer.sign(
            NostrPublishInput.post(content: "older page before deletion")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let deletionEvent = try await signer.sign(
            NostrPublishInput.delete(eventIDs: [olderNote.id], reason: "remove")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 210)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = GatedStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-older-delete-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-older-delete-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [initialNote]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        try await relayClient.waitUntilBootstrapFetchStarts()
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        store.loadOlder()
        let olderSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-older-notes")

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: olderSubscriptionID, event: olderNote),
            try relayEventFrame(subscriptionID: olderSubscriptionID, event: deletionEvent),
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        _ = try await waitForDeletedFeedItem(
            in: eventStore,
            accountID: account.pubkey,
            targetEventID: olderNote.id
        )
        try await waitForTimelineEntryIDs(
            in: store,
            ids: [initialNote.id, "deleted-\(olderNote.id)"]
        )
        await relayClient.releaseBootstrap()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(store.entries.compactMap(\.post).map(\.id) == [initialNote.id])
        guard case .deleted(let deletedEntry) = try #require(store.entries.last) else {
            Issue.record("Expected deleted timeline entry")
            return
        }
        #expect(deletedEntry.id == "deleted-\(olderNote.id)")
        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(!fetchSubscriptionIDs.contains("astrenza-home-older"))
    }

    @Test("Home timeline gap backfill uses runtime bounded backward REQ")
    @MainActor
    func homeTimelineGapBackfillUsesRuntimeBoundedBackwardREQ() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "43", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let middle = try await signer.sign(
            NostrPublishInput.post(content: "gap filled by runtime")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-gap-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 90,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-gap-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 91,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [newer, older],
            "astrenza-home-older": [
                timelineEvent(
                    idSeed: "should-not-use-short-gap",
                    pubkey: account.pubkey,
                    createdAt: 150,
                    content: "short lived gap should be skipped"
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )

        let didStart = await store.backfillGap(gap, direction: .older)
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-gap-notes")
        let sentFrames = await connection.sentFrames()
        let gapREQFrame = try #require(sentFrames.last { $0.contains(gapSubscriptionID) })
        #expect(didStart)
        #expect(gapREQFrame.contains(#""since":101"#))
        #expect(gapREQFrame.contains(#""until":299"#))
        #expect(gapREQFrame.contains(#""limit":8"#))

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: gapSubscriptionID, event: middle),
            try relayEOSEFrame(subscriptionID: gapSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForTimelinePostIDs(in: store, ids: [newer.id, middle.id, older.id])
        try await waitForHomeFeedGapState(
            in: eventStore,
            accountID: account.pubkey,
            newerEventID: newer.id,
            olderEventID: older.id,
            state: .resolved
        )

        #expect(store.entries.compactMap(\.post).map(\.id) == [newer.id, middle.id, older.id])
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [newer.id, middle.id, older.id])
        #expect(try homeFeedGaps(in: eventStore, accountID: account.pubkey).first?.state == .resolved)
        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(!fetchSubscriptionIDs.contains("astrenza-home-older"))
    }

    @Test("Home timeline gap backfill clears gap flags after empty runtime completion")
    @MainActor
    func homeTimelineGapBackfillClearsFlagsAfterEmptyRuntimeCompletion() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "44", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-gap-empty-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-gap-empty-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [newer, older]
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )

        #expect(await store.backfillGap(gap, direction: .older))
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-gap-notes")
        await connection.appendInboundFrames([try relayEOSEFrame(subscriptionID: gapSubscriptionID)])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForTimelinePostIDs(in: store, ids: [newer.id, older.id])
        try await waitForHomeFeedGapState(
            in: eventStore,
            accountID: account.pubkey,
            newerEventID: newer.id,
            olderEventID: older.id,
            state: .resolved
        )

        #expect(store.entries.map(\.id) == [newer.id, older.id])
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [newer.id, older.id])
        #expect(try homeFeedGaps(in: eventStore, accountID: account.pubkey).first?.state == .resolved)
        #expect(store.hasMoreOlder)
    }

    @Test("Home timeline completed gap backfill uses NIP-77 before resolving")
    @MainActor
    func homeTimelineCompletedGapBackfillUsesNIP77BeforeResolving() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4f", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "negentropy newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let middle = try await signer.sign(
            NostrPublishInput.post(content: "negentropy recovered middle")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "negentropy older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let metadataEvent = timelineEvent(
            idSeed: "runtime-gap-negentropy-author",
            kind: 0,
            pubkey: signer.pubkey,
            createdAt: 301,
            content: #"{"name":"Runtime Gap"}"#
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in
                FakeRelayRuntimeTransport(connection: connection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let relayClient = FakeStoreRelayClient(
            eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-gap-negentropy-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-gap-negentropy-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [newer, older],
                "astrenza-gap-events": [middle]
            ],
            missingEventIDsBySubscriptionID: [
                "astrenza-neg-gap": [middle.id]
            ]
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [metadataEvent],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )

        #expect(await store.backfillGap(gap, direction: .older))
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-gap-notes")
        await connection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: gapSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForRelayProcessing(in: store, isProcessing: false)
        let expectedEntryIDs = [
            newer.id,
            "gap-\(newer.id)-\(middle.id)",
            middle.id,
            "gap-\(middle.id)-\(older.id)",
            older.id
        ]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)

        #expect(store.entries.map(\.id) == expectedEntryIDs)
        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(fetchSubscriptionIDs.contains("astrenza-gap-events"))
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [newer.id, middle.id, older.id])
        let gaps = try homeFeedGaps(in: eventStore, accountID: account.pubkey)
        #expect(gaps.count == 1)
        #expect(gaps.first?.newerEventID == newer.id)
        #expect(gaps.first?.olderEventID == older.id)
        #expect(gaps.first?.state == .unresolved)
    }

    @Test("Home timeline gap backfill keeps gap flags after partial runtime success")
    @MainActor
    func homeTimelineGapBackfillKeepsFlagsAfterPartialRuntimeSuccess() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4a", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let middle = try await signer.sign(
            NostrPublishInput.post(content: "partial relay gap fill")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 200)
        )
        let fastConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let slowConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { relayURL in
                FakeRelayRuntimeTransport(connection: relayURL == "wss://fast.example" ? fastConnection : slowConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 200)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-gap-partial-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [
                            ["r", "wss://fast.example", "read"],
                            ["r", "wss://slow.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-gap-partial-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [newer, older]
            ]),
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://fast.example", "wss://slow.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-home-forward")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-home-forward")
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 2,
            state: .needsBackfill,
            backfilledPosts: []
        )

        #expect(await store.backfillGap(gap, direction: .older))
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-gap-notes")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-gap-notes")

        await fastConnection.appendInboundFrames([
            try relayEventFrame(subscriptionID: gapSubscriptionID, event: middle),
            try relayEOSEFrame(subscriptionID: gapSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        _ = try await waitForRelaySyncEvent(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://slow.example",
            kind: .timeout,
            subscriptionID: gapSubscriptionID
        )
        try await waitForRelayProcessing(in: store, isProcessing: false)
        let expectedEntryIDs = [
            newer.id,
            "gap-\(newer.id)-\(middle.id)",
            middle.id,
            "gap-\(middle.id)-\(older.id)",
            older.id
        ]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)

        #expect(store.entries.map(\.id) == expectedEntryIDs)
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [newer.id, middle.id, older.id])
        let gaps = try homeFeedGaps(in: eventStore, accountID: account.pubkey)
        #expect(gaps.count == 1)
        #expect(gaps.first?.newerEventID == newer.id)
        #expect(gaps.first?.olderEventID == older.id)
        #expect(gaps.first?.state == .unresolved)
    }

    @Test("Home timeline gap backfill keeps original gap after runtime timeout without events")
    @MainActor
    func homeTimelineGapBackfillKeepsOriginalGapAfterRuntimeTimeoutWithoutEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4c", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "timeout newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "timeout older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in
                FakeRelayRuntimeTransport(connection: connection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 200)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-gap-timeout-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-gap-timeout-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [newer, older]
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )

        #expect(await store.backfillGap(gap, direction: .older))
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-gap-notes")
        _ = try await waitForRelaySyncEvent(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://relay.example",
            kind: .timeout,
            subscriptionID: gapSubscriptionID
        )
        try await waitForRelayProcessing(in: store, isProcessing: false)

        let expectedEntryIDs = [
            newer.id,
            "gap-\(newer.id)-\(older.id)",
            older.id
        ]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)
        #expect(store.entries.map(\.id) == expectedEntryIDs)
        let gaps = try homeFeedGaps(in: eventStore, accountID: account.pubkey)
        #expect(gaps.count == 1)
        #expect(gaps.first?.newerEventID == newer.id)
        #expect(gaps.first?.olderEventID == older.id)
        #expect(gaps.first?.state == .requested)
    }

    @Test("Home timeline gap backfill keeps original gap after runtime closed without events")
    @MainActor
    func homeTimelineGapBackfillKeepsOriginalGapAfterRuntimeClosedWithoutEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4d", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let newer = try await signer.sign(
            NostrPublishInput.post(content: "closed newer side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let older = try await signer.sign(
            NostrPublishInput.post(content: "closed older side")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 100)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in
                FakeRelayRuntimeTransport(connection: connection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-gap-closed-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-gap-closed-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [newer, older]
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [newer, older],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        try seedHomeFeedProjection(
            in: eventStore,
            accountID: account.pubkey,
            events: [newer, older],
            gapPairs: [(newer.id, older.id)],
            insertedAt: 400
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let gap = TimelineGap(
            id: "gap-\(newer.id)-\(older.id)",
            newerPostID: newer.id,
            olderPostID: older.id,
            missingEstimate: 8,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )

        #expect(await store.backfillGap(gap, direction: .older))
        let gapSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-gap-notes")
        await connection.appendInboundFrames([
            try relayClosedFrame(subscriptionID: gapSubscriptionID, message: "rate-limited")
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForRelayProcessing(in: store, isProcessing: false)

        let expectedEntryIDs = [
            newer.id,
            "gap-\(newer.id)-\(older.id)",
            older.id
        ]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)
        #expect(store.entries.map(\.id) == expectedEntryIDs)
        let gaps = try homeFeedGaps(in: eventStore, accountID: account.pubkey)
        #expect(gaps.count == 1)
        #expect(gaps.first?.newerEventID == newer.id)
        #expect(gaps.first?.olderEventID == older.id)
        #expect(gaps.first?.state == .requested)
    }

    @Test("Home timeline older partial completion marks boundary gap")
    @MainActor
    func homeTimelineOlderPartialCompletionMarksBoundaryGap() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4b", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialNote = try await signer.sign(
            NostrPublishInput.post(content: "current oldest")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let olderNote = try await signer.sign(
            NostrPublishInput.post(content: "partial older")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 120)
        )
        let fastConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let slowConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { relayURL in
                FakeRelayRuntimeTransport(connection: relayURL == "wss://fast.example" ? fastConnection : slowConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 200)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-older-partial-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [
                            ["r", "wss://fast.example", "read"],
                            ["r", "wss://slow.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-older-partial-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [initialNote]
            ]),
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://fast.example", "wss://slow.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-home-forward")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-home-forward")
        store.loadOlder()
        let olderSubscriptionID = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-older-notes")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-older-notes")

        await fastConnection.appendInboundFrames([
            try relayEventFrame(subscriptionID: olderSubscriptionID, event: olderNote),
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        _ = try await waitForRelaySyncEvent(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://slow.example",
            kind: .timeout,
            subscriptionID: olderSubscriptionID
        )
        try await waitForRelayProcessing(in: store, isProcessing: false)

        let expectedEntryIDs = [
            initialNote.id,
            "gap-\(initialNote.id)-\(olderNote.id)",
            olderNote.id
        ]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)
        #expect(store.entries.map(\.id) == expectedEntryIDs)
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [initialNote.id, olderNote.id])
        let gaps = try homeFeedGaps(in: eventStore, accountID: account.pubkey)
        #expect(gaps.count == 1)
        #expect(gaps.first?.newerEventID == initialNote.id)
        #expect(gaps.first?.olderEventID == olderNote.id)
        #expect(gaps.first?.state == .unresolved)
    }

    @Test("Home timeline older completed page with events does not mark boundary gap")
    @MainActor
    func homeTimelineOlderCompletedPageWithEventsDoesNotMarkBoundaryGap() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4e", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialNote = try await signer.sign(
            NostrPublishInput.post(content: "completed current oldest")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let olderNote = try await signer.sign(
            NostrPublishInput.post(content: "completed older")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 120)
        )
        let metadataEvent = timelineEvent(
            idSeed: "runtime-older-completed-author",
            kind: 0,
            pubkey: signer.pubkey,
            createdAt: 301,
            content: #"{"name":"Runtime Completed"}"#
        )
        let fastConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let slowConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { relayURL in
                FakeRelayRuntimeTransport(connection: relayURL == "wss://fast.example" ? fastConnection : slowConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-older-completed-relays",
                        kind: 10002,
                        pubkey: account.pubkey,
                        createdAt: 90,
                        tags: [
                            ["r", "wss://fast.example", "read"],
                            ["r", "wss://slow.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-older-completed-follows",
                        kind: 3,
                        pubkey: account.pubkey,
                        createdAt: 91,
                        tags: [["p", account.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [initialNote]
            ]),
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://fast.example", "wss://slow.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [metadataEvent],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-home-forward")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-home-forward")
        store.loadOlder()
        let olderSubscriptionID = try await waitForREQSubscriptionID(in: fastConnection, containing: "astrenza-older-notes")
        _ = try await waitForREQSubscriptionID(in: slowConnection, containing: "astrenza-older-notes")

        await fastConnection.appendInboundFrames([
            try relayEventFrame(subscriptionID: olderSubscriptionID, event: olderNote),
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        await slowConnection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        try await relayRuntime.receiveNext(relayURL: "wss://slow.example")
        try await waitForRelayProcessing(in: store, isProcessing: false)

        let expectedEntryIDs = [initialNote.id, olderNote.id]
        try await waitForTimelineEntryIDs(in: store, ids: expectedEntryIDs)
        #expect(store.entries.map(\.id) == expectedEntryIDs)
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [initialNote.id, olderNote.id])
        #expect(try homeFeedGaps(in: eventStore, accountID: account.pubkey).isEmpty)
    }

    @Test("Home timeline runtime older completion without events marks older end")
    @MainActor
    func homeTimelineRuntimeOlderEmptyCompletionMarksEnd() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "35", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialNote = try await signer.sign(
            NostrPublishInput.post(content: "initial only")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let relayClient = FakeStoreRelayClient(eventsBySubscriptionID: [
            "astrenza-nip65": [
                timelineEvent(
                    idSeed: "runtime-older-empty-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", "wss://relay.example", "read"]],
                    content: ""
                )
            ],
            "astrenza-kind3": [
                timelineEvent(
                    idSeed: "runtime-older-empty-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", account.pubkey]],
                    content: ""
                )
            ],
            "astrenza-home": [initialNote],
            "astrenza-home-older": [
                timelineEvent(
                    idSeed: "should-not-use-empty-short-older",
                    pubkey: account.pubkey,
                    createdAt: 150,
                    content: "short lived empty older should be skipped"
                )
            ]
        ])
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [initialNote],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        store.loadOlder()
        let olderSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-older-notes")

        await connection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: olderSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 100_000_000)

        let fetchSubscriptionIDs = await relayClient.fetchSubscriptionIDs()
        #expect(!fetchSubscriptionIDs.contains("astrenza-home-older"))
        #expect(!store.hasMoreOlder)
        #expect(store.entries.compactMap(\.post).map(\.id) == [initialNote.id])
    }

    @Test("Home timeline store persists runtime forward events after EOSE")
    @MainActor
    func homeTimelineStorePersistsRuntimeForwardEventsAfterEOSE() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "31", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let liveEvent = try await signer.sign(
            NostrPublishInput.post(content: "live after eose")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 500)
        )
        let metadataEvent = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 501,
                kind: 0,
                tags: [],
                content: #"{"name":"live-user","display_name":"Live User"}"#
            )
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        let forwardSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: "astrenza-home-forward"
        )
        try await waitForRelayRuntimeState(in: store, relayURL: "wss://relay.example", state: .connected)
        await connection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: forwardSubscriptionID),
            try relayEventFrame(subscriptionID: forwardSubscriptionID, event: liveEvent)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForHomeTimelineRealtime(in: store, isRealtime: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        let revisionAfterEOSE = store.relayStatusRevision
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.relayStatusRevision == revisionAfterEOSE)
        let profileSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: profileSubscriptionID, event: metadataEvent),
            try relayEOSEFrame(subscriptionID: profileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        _ = try await waitForTimelinePost(in: store, id: liveEvent.id) { post in
            post.author.primaryText == "Live User"
        }
        let posts = store.entries.compactMap(\.post)
        #expect(posts.map(\.id) == [liveEvent.id])
        #expect(posts.first?.author.primaryText == "Live User")
        #expect(try eventStore.event(id: liveEvent.id)?.content == "live after eose")
        #expect(try eventStore.event(id: metadataEvent.id)?.kind == 0)
        #expect(try eventStore.eventSources(eventID: liveEvent.id).map(\.relayURL) == ["wss://relay.example"])
        #expect(try eventStore.eventSources(eventID: metadataEvent.id).map(\.relayURL) == ["wss://relay.example"])
        let cursor = try #require(try eventStore.syncCursor(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: "wss://relay.example"
        ))
        #expect(cursor.newestCreatedAt == nil)
        #expect(cursor.oldestCreatedAt == nil)
        #expect(cursor.lastEOSEAt != nil)
        #expect(store.relayStatusCounts.connected == 1)

        let forwardRequestAfterEOSE = try #require(
            try eventStore.feedSyncRequests(feedID: homeFeedID(accountID: account.pubkey)).first {
                $0.subscriptionID == forwardSubscriptionID
            }
        )
        #expect(forwardRequestAfterEOSE.eoseAt != nil)
        #expect(forwardRequestAfterEOSE.endedAt == nil)
        #expect(forwardRequestAfterEOSE.endReason == nil)
        #expect(store.testingActiveFeedSyncRequestCount == 1)
        #expect(store.testingActiveFeedSyncContextCount == 1)

        await connection.appendInboundFrames([
            try relayClosedFrame(
                subscriptionID: forwardSubscriptionID,
                message: "blocked: terminal test close"
            )
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForHomeTimelineRealtime(in: store, isRealtime: false)
        for _ in 0..<100 {
            let request = try eventStore.feedSyncRequests(
                feedID: homeFeedID(accountID: account.pubkey)
            ).first { $0.subscriptionID == forwardSubscriptionID }
            if request?.endReason == .closed {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let closedForwardRequest = try #require(
            try eventStore.feedSyncRequests(feedID: homeFeedID(accountID: account.pubkey)).first {
                $0.subscriptionID == forwardSubscriptionID
            }
        )
        #expect(closedForwardRequest.endReason == .closed)
        #expect(closedForwardRequest.endedAt != nil)
        #expect(store.testingActiveFeedSyncRequestCount == 0)
        #expect(store.testingActiveFeedSyncContextCount == 0)
    }

    @Test("Home timeline store buffers runtime forward events away from newest window")
    @MainActor
    func homeTimelineStoreBuffersRuntimeForwardEventsAwayFromNewestWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "32", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialEvent = timelineEvent(
            idSeed: "buffered-initial",
            pubkey: signer.pubkey,
            createdAt: 400,
            content: "already visible"
        )
        let liveEvent = try await signer.sign(
            NostrPublishInput.post(content: "buffered live")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 500)
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [signer.pubkey],
                noteEvents: [initialEvent],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: liveEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-relays-buffered",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-follows-buffered",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [initialEvent]
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await waitForRelayRuntimeState(in: store, relayURL: "wss://relay.example", state: .connected)
        try await waitForTimelinePostIDs(in: store, ids: [initialEvent.id])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        store.setTimelineAtNewestWindow(false)
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(store.unmaterializedNewCount == 1)
        #expect(store.entries.compactMap(\.post).map(\.id) == [initialEvent.id])
        #expect(try eventStore.event(id: liveEvent.id)?.content == "buffered live")
        #expect(try homeFeedMemberships(in: eventStore, accountID: account.pubkey).map(\.eventID) == [liveEvent.id, initialEvent.id])

        let requestCountBeforeApplying = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: "astrenza-home-forward") != nil
        }.count
        let didApplyPendingNewEvents = await store.applyPendingNewEvents()
        let requestCountAfterApplying = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: "astrenza-home-forward") != nil
        }.count

        #expect(didApplyPendingNewEvents)
        #expect(requestCountAfterApplying == requestCountBeforeApplying)
        try await waitForTimelinePostIDs(
            in: store,
            ids: [liveEvent.id, initialEvent.id]
        )
        #expect(store.unmaterializedNewCount == 0)
        #expect(store.entries.compactMap(\.post).map(\.id) == [liveEvent.id, initialEvent.id])
    }

    @Test("Home timeline store applies runtime forward events immediately at newest window")
    @MainActor
    func homeTimelineStoreAppliesRuntimeForwardEventsAtNewestWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "33", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let initialEvent = timelineEvent(
            idSeed: "immediate-initial",
            pubkey: signer.pubkey,
            createdAt: 400,
            content: "already visible"
        )
        let liveEvent = try await signer.sign(
            NostrPublishInput.post(content: "live visible")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 500)
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [signer.pubkey],
                noteEvents: [initialEvent],
                metadataEvents: [],
                hasMoreOlder: true
            ),
            accountID: account.pubkey
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-relays-immediate",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-follows-immediate",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": [initialEvent]
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        let forwardSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: "astrenza-home-forward"
        )
        try await waitForRelayRuntimeState(in: store, relayURL: "wss://relay.example", state: .connected)
        try await waitForTimelinePostIDs(in: store, ids: [initialEvent.id])
        #expect(!store.isHomeTimelineRealtime)
        await connection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: forwardSubscriptionID),
            try relayEventFrame(subscriptionID: forwardSubscriptionID, event: liveEvent)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForHomeTimelineRealtime(in: store, isRealtime: true)

        store.setTimelineAtNewestWindow(true)
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.unmaterializedNewCount == 0)
        #expect(store.entries.compactMap(\.post).map(\.id) == [liveEvent.id, initialEvent.id])
        #expect(store.realtimeFollowSourceRevision == store.resolvedContentRevision)
    }

    @Test("Home timeline runtime EOSE preserves subscription event window in relay history")
    @MainActor
    func homeTimelineRuntimeEOSEPreservesSubscriptionEventWindow() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "41", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let firstEvent = try await signer.sign(
            NostrPublishInput.post(content: "first live note")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 500)
        )
        let secondEvent = try await signer.sign(
            NostrPublishInput.post(content: "second live note")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 520)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-window-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-window-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        let forwardSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: "astrenza-home-forward"
        )
        #expect(!store.isHomeTimelineRealtime)
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: forwardSubscriptionID, event: firstEvent),
            try relayEventFrame(subscriptionID: forwardSubscriptionID, event: secondEvent),
            try relayEOSEFrame(subscriptionID: forwardSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForHomeTimelineRealtime(in: store, isRealtime: true)
        try await waitForTimelinePostIDs(in: store, ids: [secondEvent.id, firstEvent.id])
        #expect(store.realtimeFollowSourceRevision == nil)

        let eose = try await waitForRelaySyncEvent(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://relay.example",
            kind: .eose,
            subscriptionID: forwardSubscriptionID
        )
        #expect(eose.subscriptionID == forwardSubscriptionID)
        #expect(eose.eventCount == 2)
        #expect(eose.newestCreatedAt == secondEvent.createdAt)
        #expect(eose.oldestCreatedAt == firstEvent.createdAt)

        let summary = try #require(try eventStore.relaySyncSummaries(
            accountID: account.pubkey,
            timelineKey: "home"
        ).first { $0.relayURL == "wss://relay.example" })
        #expect(summary.totalEventCount >= 2)

        let cursor = try #require(try eventStore.syncCursor(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: "wss://relay.example"
        ))
        #expect(cursor.newestCreatedAt == secondEvent.createdAt)
        #expect((cursor.oldestCreatedAt ?? Int.max) <= firstEvent.createdAt)
        #expect(cursor.lastEOSEAt == eose.occurredAt)
    }

    @Test("Home timeline enters realtime only after every forward relay reaches EOSE")
    @MainActor
    func homeTimelineRealtimeWaitsForEveryForwardRelayEOSE() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "42", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let fastConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let slowConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { relayURL in
            FakeRelayRuntimeTransport(
                connection: relayURL.contains("slow") ? slowConnection : fastConnection
            )
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-realtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [
                            ["r", "wss://fast.example", "read"],
                            ["r", "wss://slow.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-realtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://fast.example", "wss://slow.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        let fastSubscriptionID = try await waitForREQSubscriptionID(
            in: fastConnection,
            containing: "astrenza-home-forward"
        )
        let slowSubscriptionID = try await waitForREQSubscriptionID(
            in: slowConnection,
            containing: "astrenza-home-forward"
        )
        #expect(!store.isHomeTimelineRealtime)

        await fastConnection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: fastSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://fast.example")
        #expect(!store.isHomeTimelineRealtime)

        await slowConnection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: slowSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://slow.example")
        try await waitForHomeTimelineRealtime(in: store, isRealtime: true)
    }

    @Test("Home timeline store classifies runtime CLOSED auth and payment states")
    @MainActor
    func homeTimelineStoreClassifiesRuntimeClosedAuthAndPaymentStates() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "32", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let authConnection = FakeRelayRuntimeConnection(inboundFrames: [
            try relayClosedFrame(subscriptionID: "astrenza-home-forward", message: "auth-required: sign in first")
        ])
        let paymentConnection = FakeRelayRuntimeConnection(inboundFrames: [
            try relayClosedFrame(subscriptionID: "astrenza-home-forward", message: "payment-required: paid relay")
        ])
        let relayRuntimeWithTwoRelays = NostrRelayRuntime(transportFactory: { relayURL in
            FakeRelayRuntimeTransport(connection: relayURL.contains("paid") ? paymentConnection : authConnection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "closed-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [
                            ["r", "wss://relay.example", "read"],
                            ["r", "wss://paid.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "closed-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntimeWithTwoRelays
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: authConnection, containing: "astrenza-home-forward")
        _ = try await waitForREQSubscriptionID(in: paymentConnection, containing: "astrenza-home-forward")
        try await relayRuntimeWithTwoRelays.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntimeWithTwoRelays.receiveNext(relayURL: "wss://paid.example")

        let authSummary = try await waitForRelaySummary(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://relay.example",
            kind: .authRequired
        )
        let paymentSummary = try await waitForRelaySummary(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://paid.example",
            kind: .paymentRequired
        )
        #expect(authSummary.lastEventKind == .authRequired)
        #expect(authSummary.authRequiredCount == 1)
        #expect(authSummary.paymentRequiredCount == 0)
        #expect(paymentSummary.lastEventKind == .paymentRequired)
        #expect(paymentSummary.authRequiredCount == 0)
        #expect(paymentSummary.paymentRequiredCount == 1)
    }

    @Test("Home timeline store materializes backward quoted source events")
    @MainActor
    func homeTimelineStoreMaterializesBackwardQuotedSourceEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "33", count: 32))
        let quotedSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "34", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let quotedEvent = try await quotedSigner.sign(
            NostrPublishInput.post(content: "quoted source body")
                .unsignedEvent(pubkey: quotedSigner.pubkey, createdAt: 450)
        )
        let quoteEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "forward quote wrapper",
                tags: [
                    ["q", quotedEvent.id],
                    ["p", quotedSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 500)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: quoteEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "quote-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "quote-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: quotedEvent.id)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: quotedEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let post = try await waitForTimelinePost(in: store, id: quoteEvent.id) { post in
            post.quotedPost?.body == "quoted source body"
        }
        #expect(post.body == "forward quote wrapper")
        #expect(post.quotedPost?.isAvailable == true)
        #expect(post.quotedPost?.body == "quoted source body")
        #expect(try eventStore.event(id: quotedEvent.id)?.content == "quoted source body")
        #expect(try eventStore.eventSources(eventID: quotedEvent.id).map(\.relayURL) == ["wss://relay.example"])
    }

    @Test("Home timeline store persists media and OGP from backward source events")
    @MainActor
    func homeTimelineStorePersistsMediaAndOGPFromBackwardSourceEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "35", count: 32))
        let quotedSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "36", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let sourceURL = try #require(URL(string: "https://example.test/backward-source"))
        let html = """
        <html><head>
        <meta property="og:title" content="Backward Source OGP">
        <meta property="og:description" content="Resolved from a backward fetched quote source">
        <meta property="og:site_name" content="Example">
        </head></html>
        """
        let linkPreviewResolver = NostrLinkPreviewResolver(
            dataLoader: { request in
                #expect(request.url == sourceURL)
                let data = try #require(html.data(using: .utf8))
                return (data, timelineHTTPResponse(url: request.url, statusCode: 200))
            },
            now: { Date(timeIntervalSince1970: 2_000) },
            cacheTTLSeconds: 600
        )
        let quotedEvent = try await quotedSigner.sign(
            NostrPublishInput.post(
                content: "quoted source with media https://example.test/backward-source",
                tags: [
                    [
                        "imeta",
                        "url https://cdn.example.test/backward.webp",
                        "alt backward media alt",
                        "m image/webp"
                    ]
                ]
            )
            .unsignedEvent(pubkey: quotedSigner.pubkey, createdAt: 452)
        )
        let quoteEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "forward quote wrapper",
                tags: [
                    ["q", quotedEvent.id],
                    ["p", quotedSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 502)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: quoteEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "backward-media-ogp-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "backward-media-ogp-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime,
            linkPreviewResolver: linkPreviewResolver
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: quotedEvent.id)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: quotedEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let preview = try await waitForLinkPreview(in: eventStore, url: sourceURL, status: "resolved")

        let mediaAssets = try eventStore.mediaAssets(eventID: quotedEvent.id)
        #expect(mediaAssets.map(\.url) == ["https://cdn.example.test/backward.webp"])
        #expect(mediaAssets.first?.alt == "backward media alt")
        #expect(preview.title == "Backward Source OGP")
        #expect(preview.summary == "Resolved from a backward fetched quote source")
        #expect(try eventStore.eventSources(eventID: quotedEvent.id).map(\.relayURL) == ["wss://relay.example"])
    }

    @Test("Home timeline store sends hinted source fetches only to matching connected relays")
    @MainActor
    func homeTimelineStoreUsesSourceRelayHints() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4a", count: 32))
        let quotedSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4b", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let quotedEvent = try await quotedSigner.sign(
            NostrPublishInput.post(content: "hinted quoted source")
                .unsignedEvent(pubkey: quotedSigner.pubkey, createdAt: 455)
        )
        let quoteEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "quote wrapper with relay hint",
                tags: [
                    ["q", quotedEvent.id, "wss://hinted.example"],
                    ["p", quotedSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 505)
        )
        let hintedConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let otherConnection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(transportFactory: { relayURL in
            FakeRelayRuntimeTransport(connection: relayURL == "wss://hinted.example" ? hintedConnection : otherConnection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "hint-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [
                            ["r", "wss://hinted.example", "read"],
                            ["r", "wss://other.example", "read"]
                        ],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "hint-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://hinted.example", "wss://other.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        let forwardSubscriptionID = try await waitForREQSubscriptionID(
            in: hintedConnection,
            containing: "astrenza-home-forward"
        )
        await hintedConnection.appendInboundFrames([
            try relayEOSEFrame(subscriptionID: forwardSubscriptionID),
            try relayEventFrame(subscriptionID: forwardSubscriptionID, event: quoteEvent)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://hinted.example")
        try await relayRuntime.receiveNext(relayURL: "wss://hinted.example")
        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: hintedConnection, containing: quotedEvent.id)
        try await assertNoREQSubscriptionID(in: otherConnection, containing: quotedEvent.id)

        await hintedConnection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: quotedEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://hinted.example")
        try await relayRuntime.receiveNext(relayURL: "wss://hinted.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let post = try await waitForTimelinePost(in: store, id: quoteEvent.id) { post in
            post.quotedPost?.body == "hinted quoted source"
        }
        #expect(post.quotedPost?.body == "hinted quoted source")
    }

    @Test("Home timeline store uses cached dependencies before backward fetch")
    @MainActor
    func homeTimelineStoreUsesCachedDependenciesBeforeBackwardFetch() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4c", count: 32))
        let quotedSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4d", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let quotedEvent = try await quotedSigner.sign(
            NostrPublishInput.post(content: "cached quoted source")
                .unsignedEvent(pubkey: quotedSigner.pubkey, createdAt: 456)
        )
        let quotedMetadata = try await quotedSigner.sign(
            NostrUnsignedEvent(
                pubkey: quotedSigner.pubkey,
                createdAt: 457,
                kind: 0,
                tags: [],
                content: #"{"name":"cached-quote-author","display_name":"Cached Quote Author"}"#
            )
        )
        let authorMetadata = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 458,
                kind: 0,
                tags: [],
                content: #"{"name":"cached-wrapper-author","display_name":"Cached Wrapper Author"}"#
            )
        )
        let quoteEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "quote wrapper uses cached source",
                tags: [
                    ["q", quotedEvent.id],
                    ["p", quotedSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 506)
        )
        try eventStore.save(events: [quotedEvent, quotedMetadata, authorMetadata])
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: quoteEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "cached-dependency-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "cached-dependency-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )
        let initialRevision = store.resolvedContentRevision

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let post = try await waitForTimelinePost(in: store, id: quoteEvent.id) { post in
            post.quotedPost?.body == "cached quoted source" &&
                post.quotedPost?.author.primaryText == "Cached Quote Author"
        }
        #expect(store.resolvedContentRevision > initialRevision)
        #expect(post.quotedPost?.body == "cached quoted source")
        #expect(post.quotedPost?.author.primaryText == "Cached Quote Author")
        try await assertNoREQSubscriptionID(in: connection, containing: quotedEvent.id)
        try await assertNoREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)
    }

    @Test("Home timeline materializes a cached profile while another dependency remains unresolved")
    @MainActor
    func homeTimelineStoreMaterializesCachedProfileWithPendingDependency() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "6c", count: 32))
        let unresolvedPubkey = String(repeating: "d", count: 64)
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let note = try await signer.sign(
            NostrPublishInput.post(
                content: "cached author with pending mention",
                tags: [["p", unresolvedPubkey]]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 600)
        )
        let pictureURL = "https://cdn.example.test/cached-pending-avatar.png"
        let cachedMetadata = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 601,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Cached Pending Author","picture":"https://cdn.example.test/cached-pending-avatar.png"}"#
            )
        )
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [signer.pubkey],
                noteEvents: [note],
                metadataEvents: []
            ),
            accountID: account.pubkey
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "cached-pending-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "cached-pending-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )
        defer { store.cancel() }

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        let unresolvedPost = try await waitForTimelinePost(in: store, id: note.id) { post in
            post.avatar.imageURL == nil
        }
        #expect(unresolvedPost.avatar.imageURL == nil)

        try eventStore.save(events: [cachedMetadata])
        let unresolvedRevision = store.resolvedContentRevision
        await store.testingEnqueueBackwardDependencies(for: note)

        let resolvedPost = try await waitForTimelinePost(in: store, id: note.id) { post in
            post.author.primaryText == "Cached Pending Author" &&
                post.avatar.imageURL?.absoluteString == pictureURL
        }
        #expect(resolvedPost.author.primaryText == "Cached Pending Author")
        #expect(resolvedPost.avatar.imageURL?.absoluteString == pictureURL)
        #expect(store.resolvedContentRevision > unresolvedRevision)
    }

    @Test("Home timeline store batches burst profile dependency requests")
    @MainActor
    func homeTimelineStoreBatchesBurstProfileDependencyRequests() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4e", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let firstMention = String(repeating: "a", count: 64)
        let secondMention = String(repeating: "b", count: 64)
        let authorMetadata = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 458,
                kind: 0,
                tags: [],
                content: #"{"name":"burst-author","display_name":"Burst Author"}"#
            )
        )
        try eventStore.save(events: [authorMetadata])
        let firstEvent = try await signer.sign(
            NostrPublishInput.post(content: "first burst", tags: [["p", firstMention]])
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 510)
        )
        let secondEvent = try await signer.sign(
            NostrPublishInput.post(content: "second burst", tags: [["p", secondMention]])
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 511)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: firstEvent),
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: secondEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "burst-dependency-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "burst-dependency-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        _ = try await waitForREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)
        try await Task.sleep(nanoseconds: 150_000_000)

        let profileFrames = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: #""kinds":[0]"#) != nil
        }
        #expect(profileFrames.count == 1)
        #expect(profileFrames.first?.contains(firstMention) == true)
        #expect(profileFrames.first?.contains(secondMention) == true)
    }

    @Test("Home timeline store batches burst source dependency requests")
    @MainActor
    func homeTimelineStoreBatchesBurstSourceDependencyRequests() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "4f", count: 32))
        let firstSourceSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "50", count: 32))
        let secondSourceSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "51", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let firstSource = try await firstSourceSigner.sign(
            NostrPublishInput.post(content: "first source")
                .unsignedEvent(pubkey: firstSourceSigner.pubkey, createdAt: 450)
        )
        let secondSource = try await secondSourceSigner.sign(
            NostrPublishInput.post(content: "second source")
                .unsignedEvent(pubkey: secondSourceSigner.pubkey, createdAt: 451)
        )
        let authorMetadata = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 458,
                kind: 0,
                tags: [],
                content: #"{"name":"source-burst-author","display_name":"Source Burst Author"}"#
            )
        )
        let firstSourceMetadata = try await firstSourceSigner.sign(
            NostrUnsignedEvent(
                pubkey: firstSourceSigner.pubkey,
                createdAt: 459,
                kind: 0,
                tags: [],
                content: #"{"name":"first-source","display_name":"First Source"}"#
            )
        )
        let secondSourceMetadata = try await secondSourceSigner.sign(
            NostrUnsignedEvent(
                pubkey: secondSourceSigner.pubkey,
                createdAt: 460,
                kind: 0,
                tags: [],
                content: #"{"name":"second-source","display_name":"Second Source"}"#
            )
        )
        try eventStore.save(events: [authorMetadata, firstSourceMetadata, secondSourceMetadata])
        let firstQuote = try await signer.sign(
            NostrPublishInput.post(
                content: "first quote wrapper",
                tags: [
                    ["q", firstSource.id],
                    ["p", firstSourceSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 520)
        )
        let secondQuote = try await signer.sign(
            NostrPublishInput.post(
                content: "second quote wrapper",
                tags: [
                    ["q", secondSource.id],
                    ["p", secondSourceSigner.pubkey]
                ]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 521)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: firstQuote),
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: secondQuote)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "burst-source-dependency-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "burst-source-dependency-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        _ = try await waitForREQSubscriptionID(in: connection, containing: firstSource.id)
        try await Task.sleep(nanoseconds: 150_000_000)

        let sourceFrames = await connection.sentFrames().filter { frame in
            frame.contains(firstSource.id) || frame.contains(secondSource.id)
        }
        #expect(sourceFrames.count == 1)
        #expect(sourceFrames.first?.contains(firstSource.id) == true)
        #expect(sourceFrames.first?.contains(secondSource.id) == true)
    }

    @Test("Home timeline store materializes backward repost source events")
    @MainActor
    func homeTimelineStoreMaterializesBackwardRepostSourceEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let reposterSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "35", count: 32))
        let targetSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "36", count: 32))
        let account = NostrAccount(pubkey: reposterSigner.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let targetEvent = try await targetSigner.sign(
            NostrPublishInput.post(content: "reposted source body")
                .unsignedEvent(pubkey: targetSigner.pubkey, createdAt: 440)
        )
        let repostEvent = try await reposterSigner.sign(
            NostrUnsignedEvent(
                pubkey: reposterSigner.pubkey,
                createdAt: 520,
                kind: 6,
                tags: [
                    ["e", targetEvent.id],
                    ["p", targetSigner.pubkey]
                ],
                content: ""
            )
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: repostEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "repost-runtime-relays",
                        kind: 10002,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "repost-runtime-follows",
                        kind: 3,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 101,
                        tags: [["p", reposterSigner.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: targetEvent.id)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: targetEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let post = try await waitForTimelinePost(in: store, id: repostEvent.id) { post in
            post.body == "reposted source body"
        }
        #expect(post.body == "reposted source body")
        #expect(post.author.pubkey == targetSigner.pubkey)
        #expect(post.repostedBy?.author.pubkey == reposterSigner.pubkey)
        #expect(try eventStore.event(id: targetEvent.id)?.content == "reposted source body")
    }

    @Test("Home timeline store resolves NIP-05 for runtime profile dependencies")
    @MainActor
    func homeTimelineStoreResolvesNIP05ForRuntimeProfileDependencies() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let authorSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "39", count: 32))
        let mentionedSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3a", count: 32))
        let account = NostrAccount(pubkey: authorSigner.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let note = try await authorSigner.sign(
            NostrUnsignedEvent(
                pubkey: authorSigner.pubkey,
                createdAt: 540,
                kind: 1,
                tags: [["p", mentionedSigner.pubkey]],
                content: "runtime mention profile"
            )
        )
        let mentionedMetadata = try await mentionedSigner.sign(
            NostrUnsignedEvent(
                pubkey: mentionedSigner.pubkey,
                createdAt: 541,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Runtime Mention","nip05":"mention@example.test"}"#
            )
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: note)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "runtime-nip05-relays",
                        kind: 10002,
                        pubkey: authorSigner.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "runtime-nip05-follows",
                        kind: 3,
                        pubkey: authorSigner.pubkey,
                        createdAt: 101,
                        tags: [["p", authorSigner.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            nip05Resolver: FakeNIP05Resolver(resolutions: [
                "mention@example.test": NostrNIP05Resolution(
                    identifier: "mention@example.test",
                    pubkey: mentionedSigner.pubkey,
                    relays: [],
                    status: .verified
                )
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let profileSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: mentionedSigner.pubkey)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: profileSubscriptionID, event: mentionedMetadata),
            try relayEOSEFrame(subscriptionID: profileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let post = try await waitForTimelinePost(in: store, id: note.id) { post in
            post.replyMention == nil && post.body == "runtime mention profile"
        }
        #expect(post.body == "runtime mention profile")
        #expect(try eventStore.latestReplaceableEvent(pubkey: mentionedSigner.pubkey, kind: 0)?.id == mentionedMetadata.id)
        let resolution = try await waitForNIP05Resolution(
            in: eventStore,
            accountID: authorSigner.pubkey,
            pubkey: mentionedSigner.pubkey
        )
        #expect(resolution.status == .verified)
    }

    @Test("Home timeline store renders stale cached profile while refreshing it")
    @MainActor
    func homeTimelineStoreRendersStaleCachedProfileWhileRefreshingIt() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3f", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let staleMetadata = try await signer.sign(
            NostrUnsignedEvent(
                pubkey: signer.pubkey,
                createdAt: 10,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Cached Author"}"#
            )
        )
        let liveEvent = try await signer.sign(
            NostrPublishInput.post(content: "profile stale refresh")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 540)
        )
        try eventStore.save(events: [staleMetadata], receivedAt: 1)
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: liveEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "stale-profile-refresh-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "stale-profile-refresh-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let post = try await waitForTimelinePost(in: store, id: liveEvent.id) { post in
            post.author.primaryText == "Cached Author"
        }
        _ = try await waitForREQSubscriptionID(in: connection, containing: signer.pubkey)

        #expect(post.body == "profile stale refresh")
        #expect(post.author.primaryText == "Cached Author")
    }

    @Test("Home timeline store materializes runtime repost metadata")
    @MainActor
    func homeTimelineStoreMaterializesRuntimeRepostMetadata() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let reposterSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3b", count: 32))
        let targetSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3c", count: 32))
        let account = NostrAccount(pubkey: reposterSigner.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let targetEvent = try await targetSigner.sign(
            NostrPublishInput.post(content: "metadata repost source body")
                .unsignedEvent(pubkey: targetSigner.pubkey, createdAt: 440)
        )
        let repostEvent = try await reposterSigner.sign(
            NostrUnsignedEvent(
                pubkey: reposterSigner.pubkey,
                createdAt: 520,
                kind: 6,
                tags: [
                    ["e", targetEvent.id],
                    ["p", targetSigner.pubkey]
                ],
                content: ""
            )
        )
        let reposterMetadata = try await reposterSigner.sign(
            NostrUnsignedEvent(
                pubkey: reposterSigner.pubkey,
                createdAt: 521,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Runtime Reposter"}"#
            )
        )
        let targetMetadata = try await targetSigner.sign(
            NostrUnsignedEvent(
                pubkey: targetSigner.pubkey,
                createdAt: 522,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Runtime Target"}"#
            )
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: repostEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "repost-metadata-relays",
                        kind: 10002,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "repost-metadata-follows",
                        kind: 3,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 101,
                        tags: [["p", reposterSigner.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: targetEvent.id)
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: targetEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let reposterProfileSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: reposterSigner.pubkey
        )
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: reposterProfileSubscriptionID, event: reposterMetadata),
            try relayEOSEFrame(subscriptionID: reposterProfileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let targetProfileSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: targetSigner.pubkey
        )
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: targetProfileSubscriptionID, event: targetMetadata),
            try relayEOSEFrame(subscriptionID: targetProfileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let post = try await waitForTimelinePost(in: store, id: repostEvent.id) { post in
            post.author.primaryText == "Runtime Target"
                && post.repostedBy?.author.primaryText == "Runtime Reposter"
        }
        #expect(post.body == "metadata repost source body")
        #expect(post.author.primaryText == "Runtime Target")
        #expect(post.repostedBy?.author.primaryText == "Runtime Reposter")
    }

    @Test("Home timeline store materializes embedded repost target events")
    @MainActor
    func homeTimelineStoreMaterializesEmbeddedRepostTargetEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let reposterSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3d", count: 32))
        let targetSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3e", count: 32))
        let account = NostrAccount(pubkey: reposterSigner.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let targetEvent = try await targetSigner.sign(
            NostrPublishInput.post(content: "embedded repost source body")
                .unsignedEvent(pubkey: targetSigner.pubkey, createdAt: 440)
        )
        let targetJSON = String(data: try JSONEncoder().encode(targetEvent), encoding: .utf8) ?? ""
        let repostEvent = try await reposterSigner.sign(
            NostrUnsignedEvent(
                pubkey: reposterSigner.pubkey,
                createdAt: 520,
                kind: 6,
                tags: [
                    ["e", targetEvent.id],
                    ["p", targetSigner.pubkey]
                ],
                content: targetJSON
            )
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: repostEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "embedded-repost-relays",
                        kind: 10002,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "embedded-repost-follows",
                        kind: 3,
                        pubkey: reposterSigner.pubkey,
                        createdAt: 101,
                        tags: [["p", reposterSigner.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")

        let post = try await waitForTimelinePost(in: store, id: repostEvent.id) { post in
            post.body == "embedded repost source body"
        }
        #expect(post.body == "embedded repost source body")
        #expect(try eventStore.event(id: targetEvent.id)?.content == "embedded repost source body")
    }

    @Test("Home timeline store materializes backward reply parent events")
    @MainActor
    func homeTimelineStoreMaterializesBackwardReplyParentEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let replySigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "37", count: 32))
        let parentSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "38", count: 32))
        let account = NostrAccount(pubkey: replySigner.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let rootEvent = try await parentSigner.sign(
            NostrPublishInput.post(content: "root source body")
                .unsignedEvent(pubkey: parentSigner.pubkey, createdAt: 410)
        )
        let parentEvent = try await parentSigner.sign(
            NostrPublishInput.post(content: "parent source body")
                .unsignedEvent(pubkey: parentSigner.pubkey, createdAt: 430)
        )
        let rootReference = NostrReplyReference(
            eventID: rootEvent.id,
            pubkey: parentSigner.pubkey
        )
        let parentReference = NostrReplyReference(
            eventID: parentEvent.id,
            pubkey: parentSigner.pubkey
        )
        let replyEvent = try await replySigner.sign(
            NostrPublishInput.reply(
                content: "runtime reply body",
                root: rootReference,
                parent: parentReference
            )
            .unsignedEvent(pubkey: replySigner.pubkey, createdAt: 530)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: replyEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "reply-runtime-relays",
                        kind: 10002,
                        pubkey: replySigner.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "reply-runtime-follows",
                        kind: 3,
                        pubkey: replySigner.pubkey,
                        createdAt: 101,
                        tags: [["p", replySigner.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let sourceSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: parentEvent.id)

        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: sourceSubscriptionID, event: parentEvent),
            try relayEOSEFrame(subscriptionID: sourceSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let post = try await waitForTimelinePost(in: store, id: replyEvent.id) { post in
            post.replyContext?.bodyPreview == "parent source body"
        }
        #expect(post.body == "runtime reply body")
        #expect(post.replyContext?.bodyPreview == "parent source body")
        #expect(post.replyMention?.isExternal == true)
        #expect(try eventStore.event(id: parentEvent.id)?.content == "parent source body")
    }

    @Test("Profile directory persists runtime backward idle timeouts without blocking Home sync")
    @MainActor
    func homeTimelineStoreRecordsRuntimeBackwardIdleTimeouts() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3b", count: 32))
        let mentionedPubkey = String(repeating: "c", count: 64)
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let liveEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "runtime profile dependency",
                tags: [["p", mentionedPubkey]]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 530)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: liveEvent)
        ])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "timeout-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "timeout-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        _ = try await waitForREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)
        let profileRecord = try await waitForProfileFetchRecord(
            in: eventStore,
            pubkey: mentionedPubkey,
            outcome: .failed
        )
        let history = try eventStore.relaySyncEvents(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            limit: 10
        )

        #expect(profileRecord.lastError == "timeout")
        #expect(profileRecord.nextRetryAt.map { $0 > profileRecord.lastAttemptAt } == true)
        #expect(history.allSatisfy { event in
            event.subscriptionID?.contains(NostrProfileDirectory.groupIDPrefix) != true
        })
    }

    @Test("An arriving kind 0 event republishes the visible timeline row")
    @MainActor
    func homeTimelineStoreRepublishesVisibleRowAfterProfileResolution() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let accountSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "2a", count: 32))
        let authorSigner = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "2b", count: 32))
        let account = NostrAccount(
            pubkey: accountSigner.pubkey,
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let note = try await authorSigner.sign(
            NostrPublishInput.post(content: "profile updates this visible row")
                .unsignedEvent(pubkey: authorSigner.pubkey, createdAt: 530)
        )
        let metadata = try await authorSigner.sign(
            NostrUnsignedEvent(
                pubkey: authorSigner.pubkey,
                createdAt: 531,
                kind: 0,
                tags: [],
                content: #"{"display_name":"Resolved Visible Author"}"#
            )
        )
        let relayURL = "wss://relay.example"
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: note)
        ])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [timelineEvent(
                    idSeed: "visible-profile-relays",
                    kind: 10002,
                    pubkey: account.pubkey,
                    createdAt: 100,
                    tags: [["r", relayURL, "read"]],
                    content: ""
                )],
                "astrenza-kind3": [timelineEvent(
                    idSeed: "visible-profile-follows",
                    kind: 3,
                    pubkey: account.pubkey,
                    createdAt: 101,
                    tags: [["p", authorSigner.pubkey]],
                    content: ""
                )]
            ]),
            bootstrapRelays: [relayURL],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: relayURL)
        try await relayRuntime.receiveNext(relayURL: relayURL)

        let unresolvedPost = try await waitForTimelinePost(in: store, id: note.id) { post in
            post.author.profileResolutionState == .fetching
        }
        #expect(unresolvedPost.author.primaryText != "Resolved Visible Author")
        let unresolvedRevision = store.resolvedContentRevision
        let profileSubscriptionID = try await waitForREQSubscriptionID(
            in: connection,
            containing: #""kinds":[0]"#
        )
        await connection.appendInboundFrames([
            try relayEventFrame(subscriptionID: profileSubscriptionID, event: metadata),
            try relayEOSEFrame(subscriptionID: profileSubscriptionID)
        ])
        try await relayRuntime.receiveNext(relayURL: relayURL)
        try await relayRuntime.receiveNext(relayURL: relayURL)

        let resolvedPost = try await waitForTimelinePost(in: store, id: note.id) { post in
            post.author.primaryText == "Resolved Visible Author"
        }
        #expect(resolvedPost.id == unresolvedPost.id)
        #expect(resolvedPost.author.profileResolutionState == .resolved)
        #expect(store.resolvedContentRevision > unresolvedRevision)
    }

    @Test("Home timeline store clears missing backward profile requests after EOSE")
    @MainActor
    func homeTimelineStoreClearsMissingBackwardProfilesAfterEOSE() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3d", count: 32))
        let missingProfilePubkey = String(repeating: "d", count: 64)
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let firstEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "first event with missing profile",
                tags: [["p", missingProfilePubkey]]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 540)
        )
        let secondEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "second event retries missing profile",
                tags: [["p", missingProfilePubkey]]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 541)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: firstEvent)
        ])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 1_000)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "missing-profile-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "missing-profile-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let firstProfileSubscriptionID = try await waitForREQSubscriptionID(in: connection, containing: #""kinds":[0]"#)
        await connection.appendInboundFrames([try relayEOSEFrame(subscriptionID: firstProfileSubscriptionID)])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForRelayProcessing(in: store, isProcessing: false)

        await connection.appendInboundFrames([try relayEventFrame(subscriptionID: "astrenza-home-forward", event: secondEvent)])
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForREQFrameCount(in: connection, containing: #""kinds":[0]"#, count: 2)

        #expect(!store.isRelayProcessing)
        #expect(store.entries.compactMap(\.post).map(\.id).contains(secondEvent.id))
    }

    @Test("Home timeline store records heartbeat reconnects in relay history")
    @MainActor
    func homeTimelineStoreRecordsHeartbeatReconnects() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3c", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let connection = FakeRelayRuntimeConnection(inboundFrames: [])
        let relayRuntime = NostrRelayRuntime(
            transportFactory: { _ in FakeRelayRuntimeTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy(isEnabled: false, reconnectAfterMisses: 1),
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "heartbeat-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "heartbeat-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.sendHeartbeat(relayURL: "wss://relay.example")
        try await waitForSentFrameCount(in: connection, count: 4)
        _ = try await waitForRelaySummary(
            in: eventStore,
            accountID: account.pubkey,
            relayURL: "wss://relay.example",
            kind: .connected
        )
        let history = try eventStore.relaySyncEvents(
            accountID: account.pubkey,
            timelineKey: "home",
            relayURL: "wss://relay.example",
            limit: 12
        )
        let sent = await connection.sentFrames()

        #expect(store.relayStatusCounts.connected == 1)
        #expect(sent.count >= 4)
        #expect(sent[1].contains(#""ids":["0000000000000000000000000000000000000000000000000000000000000000"]"#))
        #expect(sent[2].contains(#"["CLOSE","astrenza-heartbeat-"#))
        #expect(sent[3].contains("astrenza-home-forward"))
        #expect(history.contains { $0.kind == .timeout && $0.subscriptionID?.hasPrefix("astrenza-heartbeat-") == true })
        #expect(history.contains { $0.kind == .reconnect && $0.message == NostrRelayConnectionState.waitingForRetry.rawValue })
        #expect(history.contains { $0.kind == .reconnect && $0.message == NostrRelayConnectionState.retrying.rawValue })
    }

    @Test("Home timeline store persists runtime media assets and OGP requests")
    @MainActor
    func homeTimelineStorePersistsRuntimeMediaAssetsAndOGPRequests() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "39", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let mediaEvent = try await signer.sign(
            NostrPublishInput.post(
                content: "runtime media https://example.test/story https://cdn.example.test/photo.png",
                tags: [[
                    "imeta",
                    "url https://cdn.example.test/tagged.webp",
                    "m image/webp",
                    "alt tagged media alt"
                ]]
            )
            .unsignedEvent(pubkey: signer.pubkey, createdAt: 540)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: mediaEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "media-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "media-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await waitForTimelinePostIDs(in: store, ids: [mediaEvent.id])

        let post = try #require(store.entries.compactMap(\.post).first { $0.id == mediaEvent.id })
        if case .gallery(let tiles) = post.media {
            #expect(tiles.compactMap { $0.url?.absoluteString } == ["https://cdn.example.test/tagged.webp"])
            #expect(tiles.first?.altText == "tagged media alt")
        } else {
            Issue.record("Expected gallery media from runtime imeta")
        }

        let assets = try eventStore.mediaAssets(eventID: mediaEvent.id)
        #expect(assets.map(\.url) == ["https://cdn.example.test/tagged.webp"])
        let previews = try eventStore.linkPreviews(urls: [
            try #require(URL(string: "https://example.test/story"))
        ])
        let preview = try #require(previews.values.first)
        #expect(preview.status == "unresolved")
    }

    @Test("Home timeline store resolves runtime OGP requests into cached cards")
    @MainActor
    func homeTimelineStoreResolvesRuntimeOGPRequestsIntoCachedCards() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "3a", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let linkEvent = try await signer.sign(
            NostrPublishInput.post(content: "runtime ogp https://example.test/story")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 545)
        )
        let html = """
        <html><head>
        <meta property="og:title" content="Runtime OGP">
        <meta property="og:description" content="Resolved inside Home TL">
        <meta property="og:site_name" content="Example">
        </head></html>
        """
        let linkPreviewResolver = NostrLinkPreviewResolver(
            dataLoader: { request in
                let data = try #require(html.data(using: .utf8))
                return (data, timelineHTTPResponse(url: request.url, statusCode: 200))
            },
            now: { Date(timeIntervalSince1970: 2_000) },
            cacheTTLSeconds: 600
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: linkEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "ogp-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "ogp-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime,
            linkPreviewResolver: linkPreviewResolver
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        let url = try #require(URL(string: "https://example.test/story"))
        let preview = try await waitForLinkPreview(
            in: eventStore,
            url: url,
            status: "resolved"
        )

        let post = try await waitForTimelinePost(
            in: store,
            id: linkEvent.id,
            matching: { post in
                if case .linkPreview = post.media {
                    return true
                }
                return false
            }
        )
        if case .linkPreview(let card) = post.media {
            #expect(card.title == "Runtime OGP")
            #expect(card.subtitle == "Resolved inside Home TL")
            #expect(card.host == "Example")
        } else {
            Issue.record("Expected resolved OGP card")
        }
        #expect(preview.status == "resolved")
    }

    @Test("Home timeline store materializes runtime deletion events")
    @MainActor
    func homeTimelineStoreMaterializesRuntimeDeletionEvents() async throws {
        let eventStore = try NostrEventStore.inMemory()
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "40", count: 32))
        let account = NostrAccount(pubkey: signer.pubkey, displayIdentifier: "npub-test", readOnly: true)
        let noteEvent = try await signer.sign(
            NostrPublishInput.post(content: "runtime note before deletion")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 550)
        )
        let deletionEvent = try await signer.sign(
            NostrPublishInput.delete(eventIDs: [noteEvent.id], reason: "remove")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 560)
        )
        let connection = FakeRelayRuntimeConnection(inboundFrames: [
            #"["EOSE","astrenza-home-forward"]"#,
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: noteEvent),
            try relayEventFrame(subscriptionID: "astrenza-home-forward", event: deletionEvent)
        ])
        let relayRuntime = NostrRelayRuntime(transportFactory: { _ in
            FakeRelayRuntimeTransport(connection: connection)
        }, autoReceive: false)
        let timelineLoader = NostrHomeTimelineLoader(
            relayClient: FakeStoreRelayClient(eventsBySubscriptionID: [
                "astrenza-nip65": [
                    timelineEvent(
                        idSeed: "deletion-runtime-relays",
                        kind: 10002,
                        pubkey: signer.pubkey,
                        createdAt: 100,
                        tags: [["r", "wss://relay.example", "read"]],
                        content: ""
                    )
                ],
                "astrenza-kind3": [
                    timelineEvent(
                        idSeed: "deletion-runtime-follows",
                        kind: 3,
                        pubkey: signer.pubkey,
                        createdAt: 101,
                        tags: [["p", signer.pubkey]],
                        content: ""
                    )
                ],
                "astrenza-home": []
            ]),
            bootstrapRelays: ["wss://relay.example"],
            pageLimit: 20
        )
        let store = NostrHomeTimelineStore(
            timelineLoader: timelineLoader,
            eventStore: eventStore,
            relayRuntime: relayRuntime
        )

        store.start(account: account)
        _ = try await waitForREQSubscriptionID(in: connection, containing: "astrenza-home-forward")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await relayRuntime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.entries.compactMap(\.post).isEmpty)
        guard case .deleted(let deletedEntry) = try #require(store.entries.first) else {
            Issue.record("Expected deleted timeline entry")
            return
        }
        #expect(deletedEntry.id == "deleted-\(noteEvent.id)")
        let deletedRows = try eventStore.deletedFeedItems(
            feedID: homeFeedID(accountID: account.pubkey),
            limit: 10
        )
        #expect(deletedRows.map(\.targetEventID) == [noteEvent.id])
    }

    @Test("Nostr materializer applies list scoped filters only to list timelines")
    func nostrMaterializerAppliesListScopedFiltersOnlyToLists() throws {
        let author = String(repeating: "c", count: 64)
        let note = timelineEvent(
            idSeed: "list-filter-note",
            pubkey: author,
            createdAt: 100,
            content: "quiet list text"
        )
        let filterRules = NostrFilterRuleSet(rules: [
            NostrFilterRuleRecord(
                ruleID: "list-rule",
                accountID: "account",
                kind: .keyword,
                value: "quiet",
                scopes: [.lists],
                createdAt: 1,
                updatedAt: 1
            )
        ])

        let homePosts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            filterRules: filterRules,
            timeline: .home,
            now: 100
        )
        let listPosts = NostrTimelineMaterializer.posts(
            noteEvents: [note],
            metadataEvents: [],
            followedPubkeys: [author],
            filterRules: filterRules,
            timeline: .lists,
            now: 100
        )

        #expect(homePosts.first?.bodyPresentation.collapseReason == nil)
        #expect(listPosts.first?.bodyPresentation.collapseReason == .filtered)
    }

    @Test("Home timeline store builds Lists entries from cached NIP-51 follow and bookmark sets")
    @MainActor
    func homeTimelineStoreBuildsListsEntriesFromCachedNIP51Sets() throws {
        let eventStore = try NostrEventStore.inMemory()
        let account = NostrAccount(
            pubkey: String(repeating: "d", count: 64),
            displayIdentifier: "npub-test",
            readOnly: true
        )
        let followedAuthor = String(repeating: "e", count: 64)
        let followedNote = timelineEvent(
            idSeed: "list-followed-note",
            pubkey: followedAuthor,
            createdAt: 300,
            content: "follow-set cached note"
        )
        let bookmarkedNote = timelineEvent(
            idSeed: "list-bookmarked-note",
            pubkey: account.pubkey,
            createdAt: 200,
            content: "bookmark-set cached note"
        )
        let unrelated = timelineEvent(
            idSeed: "list-unrelated-note",
            pubkey: String(repeating: "f", count: 64),
            createdAt: 400,
            content: "not in a cached list"
        )
        let followSet = timelineEvent(
            idSeed: "follow-set",
            kind: 30_000,
            pubkey: account.pubkey,
            createdAt: 500,
            tags: [
                ["d", "friends"],
                ["title", "Friends"],
                ["p", followedAuthor]
            ],
            content: ""
        )
        let bookmarkSet = timelineEvent(
            idSeed: "bookmark-set",
            kind: 30_003,
            pubkey: account.pubkey,
            createdAt: 450,
            tags: [
                ["d", "reads"],
                ["title", "Reads"],
                ["e", bookmarkedNote.id]
            ],
            content: ""
        )

        try eventStore.save(events: [followedNote, bookmarkedNote, unrelated, followSet, bookmarkSet])
        try eventStore.saveHomeTimelineState(
            NostrHomeTimelineState(
                relays: ["wss://relay.example"],
                followedPubkeys: [account.pubkey],
                noteEvents: [unrelated],
                metadataEvents: [],
                hasMoreOlder: false
            ),
            accountID: account.pubkey
        )

        let store = NostrHomeTimelineStore(eventStore: eventStore)
        store.start(account: account)

        #expect(store.listEntries().compactMap(\.post).map(\.id) == [
            followedNote.id,
            bookmarkedNote.id
        ])
    }

    @Test("Nostr materializer turns kind 6 reposts into attributed timeline posts")
    func nostrMaterializerUsesKind6Reposts() throws {
        let author = String(repeating: "a", count: 64)
        let reposter = String(repeating: "b", count: 64)
        let target = timelineEvent(idSeed: "repost-target", pubkey: author, createdAt: 100, content: "original body")
        let repost = timelineEvent(
            idSeed: "repost-event",
            kind: 6,
            pubkey: reposter,
            createdAt: 300,
            tags: [["e", target.id]],
            content: ""
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [target, repost],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let repostedPost = try #require(posts.first { $0.id == repost.id })

        #expect(posts.map { $0.id }.first == repost.id)
        #expect(repostedPost.body == "original body")
        #expect(repostedPost.author.pubkey == author)
        #expect(repostedPost.repostedBy?.author.pubkey == reposter)
    }

    @Test("Timeline repost projection uses the last event tag as target")
    func timelineRepostProjectionUsesLastEventTagAsTarget() throws {
        let reposter = String(repeating: "b", count: 64)
        let firstTargetID = timelineEventID("first-repost-target")
        let secondTargetID = timelineEventID("second-repost-target")
        let repost = timelineEvent(
            idSeed: "projection-repost-target",
            kind: 6,
            pubkey: reposter,
            createdAt: 300,
            tags: [
                ["e", firstTargetID],
                ["e", secondTargetID]
            ],
            content: ""
        )

        #expect(NostrTimelineRepostProjection.targetID(from: repost) == secondTargetID)
    }

    @Test("Timeline repost projection builds attribution from metadata")
    func timelineRepostProjectionBuildsAttributionFromMetadata() throws {
        let reposter = String(repeating: "b", count: 64)
        let repost = timelineEvent(
            idSeed: "projection-repost-attribution",
            kind: 6,
            pubkey: reposter,
            createdAt: 300,
            tags: [["e", timelineEventID("projection-target")]],
            content: ""
        )
        let metadata = timelineEvent(
            idSeed: "projection-reposter-metadata",
            kind: 0,
            pubkey: reposter,
            createdAt: 250,
            content: #"{"display_name":"Projection Reposter","nip05":"reposter@example.test","picture":"https://example.test/reposter.png"}"#
        )

        let attribution = NostrTimelineRepostProjection.attribution(
            for: repost,
            metadataEvents: [metadata],
            nip05Resolutions: [
                reposter: NostrNIP05Resolution(
                    identifier: "reposter@example.test",
                    pubkey: reposter,
                    relays: [],
                    status: .verified
                )
            ],
            followedPubkeys: [reposter],
            avatarForItem: NostrTimelineAuthorProjection.avatar(for:)
        )

        #expect(attribution.author.primaryText == "Projection Reposter")
        #expect(attribution.author.nip05 == "reposter@example.test")
        #expect(attribution.author.nip05Status == .valid)
        #expect(attribution.author.isFollowed == true)
        #expect(attribution.avatar.imageURL?.absoluteString == "https://example.test/reposter.png")
        #expect(attribution.createdAt == repost.createdAt)
    }

    @Test("Nostr materializer keeps kind 6 reposts visible when the target event is missing")
    func nostrMaterializerUsesKind6MissingTargetPlaceholder() throws {
        let author = String(repeating: "a", count: 64)
        let reposter = String(repeating: "b", count: 64)
        let repost = timelineEvent(
            idSeed: "missing-repost-event",
            kind: 6,
            pubkey: reposter,
            createdAt: 300,
            tags: [
                ["e", timelineEventID("missing-repost-target")],
                ["p", author]
            ],
            content: ""
        )

        let posts = NostrTimelineMaterializer.posts(
            noteEvents: [repost],
            metadataEvents: [],
            followedPubkeys: [author]
        )
        let repostedPost = try #require(posts.first { $0.id == repost.id })

        #expect(repostedPost.body == "Reposted post unavailable")
        #expect(repostedPost.author.pubkey == author)
        #expect(repostedPost.repostedBy?.author.pubkey == reposter)
        #expect(repostedPost.bodyPresentation.timelineLineLimit == 1)
    }

    @Test("_@domain NIP-05 is displayed as domain only")
    func rootNIP05Display() {
        let author = TimelineAuthor.resolved(
            displayName: "User",
            nip05: "_@mock.example",
            pubkey: TimelineAuthor.mockPubkey(for: "root-nip05")
        )

        #expect(author.secondaryText == "mock.example")
    }

    @Test("Filter user direct candidate accepts hex pubkeys")
    func filterUserDirectCandidateAcceptsHexPubkeys() throws {
        let pubkey = String(repeating: "a", count: 64)
        let candidate = try #require(FilterCandidateUser.directCandidate(from: pubkey))

        #expect(candidate.id == pubkey)
        #expect(candidate.nip05 == "Direct pubkey")
    }

    @Test("Filter user direct candidate accepts npub")
    func filterUserDirectCandidateAcceptsNpub() throws {
        let candidate = try #require(FilterCandidateUser.directCandidate(
            from: "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"
        ))

        #expect(candidate.id == "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
        #expect(candidate.nip05 == "Direct npub")
    }

    @Test("Filter user direct candidate rejects unresolved names")
    func filterUserDirectCandidateRejectsUnresolvedNames() {
        #expect(FilterCandidateUser.directCandidate(from: "someone@example.com") == nil)
        #expect(FilterCandidateUser.directCandidate(from: "not a key") == nil)
    }

    @Test("Unresolved authors display a valid npub-like abbreviated pubkey")
    func unresolvedAuthorDisplay() {
        let author = TimelineAuthor.unresolved(pubkey: TimelineAuthor.mockPubkey(for: "unresolved"))

        #expect(author.primaryText.hasPrefix("npub1"))
        #expect(author.primaryText.contains("..."))
        #expect(author.secondaryText == author.primaryText)
        #expect(author.secondarySystemName == "person.crop.circle")
    }

    @Test("Fetching authors keep the existing transient pending presentation")
    func fetchingAuthorDisplay() {
        let author = TimelineAuthor.unresolved(
            pubkey: TimelineAuthor.mockPubkey(for: "fetching"),
            state: .fetching
        )

        #expect(author.secondaryText == "kind:0 pending")
        #expect(author.secondarySystemName == "clock")
    }

    @Test("Timeline layout estimator gives media and long posts more room")
    func timelineLayoutEstimates() throws {
        let posts = MockTimelineData.posts
        let compactPost = try #require(posts.first { $0.id == "thread-a-root" })
        let mediaPost = try #require(posts.first { $0.media?.isFullscreenMedia == true })
        let longPost = try #require(posts.first { $0.bodyPresentation.collapseReason != nil })

        #expect(
            TimelineLayoutEstimator.estimatedHeight(for: mediaPost)
            > TimelineLayoutEstimator.estimatedHeight(for: compactPost)
        )
        #expect(
            TimelineLayoutEstimator.estimatedHeight(for: longPost)
            > TimelineLayoutEstimator.estimatedHeight(for: compactPost)
        )
    }

    @Test("Timeline layout cache prefers measured row heights")
    func timelineLayoutCacheUsesMeasuredHeight() throws {
        let post = try #require(MockTimelineData.posts.first)
        var cache = TimelineLayoutCache()

        cache.merge(measuredFrames: [post.id: CGRect(x: 0, y: 0, width: 390, height: 321)])

        #expect(cache.height(for: post) == 321)
    }

    @Test("Timeline layout cache ignores subpixel height churn and prunes removed posts")
    func timelineLayoutCacheCoalescesMeasurementsAndPrunes() throws {
        let posts = Array(MockTimelineData.posts.prefix(3))
        let firstPost = try #require(posts.first)
        let lastPost = try #require(posts.last)
        var cache = TimelineLayoutCache()

        let didRecordInitialHeight = cache.recordMeasuredHeight(100, for: firstPost.id)
        let didIgnoreSubpixelChange = !cache.recordMeasuredHeight(100.4, for: firstPost.id)
        let didRecordMaterialChange = cache.recordMeasuredHeight(101, for: firstPost.id)
        cache.measuredHeights[lastPost.id] = 240
        cache.prune(keeping: [firstPost.id])

        #expect(didRecordInitialHeight)
        #expect(didIgnoreSubpixelChange)
        #expect(didRecordMaterialChange)
        #expect(cache.measuredHeights == [firstPost.id: 101])
    }

    @Test("Incremental timeline heights match a full snapshot across gaps and deleted rows")
    func timelineLayoutSnapshotAppliesIncrementalHeights() throws {
        let posts = Array(MockTimelineData.posts.prefix(4))
        let firstPost = try #require(posts.first)
        let thirdPost = posts[2]
        let gap = TimelineGap(
            id: "incremental-height-gap",
            newerPostID: posts[0].id,
            olderPostID: posts[1].id,
            missingEstimate: 2,
            relayCount: 1,
            state: .needsBackfill,
            backfilledPosts: []
        )
        let entries: [TimelineFeedEntry] = [
            .post(posts[0]),
            .gap(gap),
            .post(posts[1]),
            .deleted(TimelineDeletedEntry(id: "incremental-deleted")),
            .post(posts[2]),
            .post(posts[3])
        ]
        var cache = TimelineLayoutCache(measuredHeights: [
            posts[0].id: 100,
            posts[1].id: 120,
            posts[2].id: 140,
            posts[3].id: 160
        ])
        var incrementalSnapshot = TimelineLayoutSnapshot(
            entries: entries,
            layoutCache: cache,
            topContentPadding: 72
        )

        let didRecordFirstHeight = incrementalSnapshot.recordMeasuredHeight(180, for: firstPost.id)
        let didUpdateFirstHeight = incrementalSnapshot.recordMeasuredHeight(210, for: firstPost.id)
        let didRecordThirdHeight = incrementalSnapshot.recordMeasuredHeight(260, for: thirdPost.id)
        #expect(didRecordFirstHeight)
        #expect(didUpdateFirstHeight)
        #expect(didRecordThirdHeight)
        cache.measuredHeights[firstPost.id] = 210
        cache.measuredHeights[thirdPost.id] = 260
        let rebuiltSnapshot = TimelineLayoutSnapshot(
            entries: entries,
            layoutCache: cache,
            topContentPadding: 72
        )

        for post in posts {
            #expect(incrementalSnapshot.offset(for: post.id) == rebuiltSnapshot.offset(for: post.id))
        }
        for contentOffset: CGFloat in [0, 80, 220, 360, 520, 760, 1_000] {
            #expect(
                incrementalSnapshot.anchor(at: contentOffset, anchorLineY: 72) ==
                    rebuiltSnapshot.anchor(at: contentOffset, anchorLineY: 72)
            )
        }
    }

    @Test("Timeline attachment layout never starts from a one-point width")
    func timelineAttachmentLayoutUsesStableFallbackWidth() {
        #expect(TimelineAttachmentLayoutMetrics.availableWidth(for: nil) == 320)
        #expect(TimelineAttachmentLayoutMetrics.availableWidth(for: 0) == 320)
        #expect(TimelineAttachmentLayoutMetrics.availableWidth(for: .infinity) == 320)
        #expect(TimelineAttachmentLayoutMetrics.availableWidth(for: 287) == 287)
    }

    @Test("Home viewport restore protection does not treat the temporary top as newest")
    func homeViewportRestoreProtectionBlocksTemporaryTopFollowing() {
        #expect(!HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: 0,
            isRestoreProtected: true,
            isDetachedFromLiveEdge: false
        ))
        #expect(!HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: true,
            isDetachedFromLiveEdge: false
        ))
        #expect(HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: 0,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: false
        ))
        #expect(!HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: false,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: false
        ))
        #expect(HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: false
        ))
    }

    @Test("Home restored window remains detached after viewport writes unlock")
    func homeRestoredWindowDoesNotFollowNewestAfterRestoreCompletes() {
        #expect(!HomeTimelineViewportRestorePolicy.isAtNewestWindow(
            offset: 0,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: true
        ))
        #expect(!HomeTimelineViewportRestorePolicy.followsRealtimeEntries(
            isRealtime: true,
            isAtNewestWindow: true,
            isRestoreProtected: false,
            isDetachedFromLiveEdge: true
        ))
    }

    @Test("Feed blocks viewport writes while waiting for or applying restore")
    func timelineFeedBlocksViewportWritesUntilRestoreCompletes() {
        #expect(!TimelineFeedViewportRestorePolicy.canSaveViewport(
            isRestoreProtected: true,
            didRestoreViewport: false,
            isRestoringViewport: false
        ))
        #expect(!TimelineFeedViewportRestorePolicy.canSaveViewport(
            isRestoreProtected: true,
            didRestoreViewport: true,
            isRestoringViewport: true
        ))
        #expect(TimelineFeedViewportRestorePolicy.canSaveViewport(
            isRestoreProtected: true,
            didRestoreViewport: true,
            isRestoringViewport: false
        ))
        #expect(!TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: true,
            isPullRefreshProtected: false,
            isRestoreProtected: true,
            didRestoreViewport: false,
            isRestoringViewport: false
        ))
        #expect(!TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: true,
            isPullRefreshProtected: false,
            isRestoreProtected: true,
            didRestoreViewport: true,
            isRestoringViewport: true
        ))
        #expect(!TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: false,
            isPullRefreshProtected: false,
            isRestoreProtected: false,
            didRestoreViewport: true,
            isRestoringViewport: false
        ))
        #expect(!TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: true,
            isPullRefreshProtected: true,
            isRestoreProtected: false,
            didRestoreViewport: true,
            isRestoringViewport: false
        ))
        #expect(TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: true,
            isPullRefreshProtected: false,
            isRestoreProtected: true,
            didRestoreViewport: true,
            isRestoringViewport: false
        ))
        #expect(TimelineFeedViewportRestorePolicy.canFollowRealtimeEntries(
            isRealtimeEnabled: true,
            isPullRefreshProtected: false,
            isRestoreProtected: false,
            didRestoreViewport: false,
            isRestoringViewport: false
        ))
    }

    @Test("Timeline viewport resolver converts anchor offset into content offset")
    func timelineViewportResolverUsesAnchorOffset() throws {
        let posts = Array(MockTimelineData.posts.prefix(3))
        let anchorPost = try #require(posts.last)
        var cache = TimelineLayoutCache()
        cache.merge(measuredFrames: [
            posts[0].id: CGRect(x: 0, y: 0, width: 390, height: 120),
            posts[1].id: CGRect(x: 0, y: 120, width: 390, height: 180),
            anchorPost.id: CGRect(x: 0, y: 300, width: 390, height: 220)
        ])
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: anchorPost.id,
            anchorOffset: 24,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let restoredOffset = TimelineViewportResolver.restoredContentOffsetY(
            posts: posts,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        )

        #expect(restoredOffset == 324)
    }

    @Test("Timeline viewport resolver includes gap height in entry snapshots")
    func timelineViewportResolverIncludesGapHeight() throws {
        let posts = Array(MockTimelineData.posts.prefix(3))
        let anchorPost = try #require(posts.last)
        let gap = TimelineGap(
            id: "test-gap",
            newerPostID: posts[0].id,
            olderPostID: posts[1].id,
            missingEstimate: 10,
            relayCount: 3,
            state: .needsBackfill,
            backfilledPosts: []
        )
        let entries: [TimelineFeedEntry] = [
            .post(posts[0]),
            .gap(gap),
            .post(posts[1]),
            .post(anchorPost)
        ]
        var cache = TimelineLayoutCache()
        cache.merge(measuredFrames: [
            posts[0].id: CGRect(x: 0, y: 0, width: 390, height: 120),
            posts[1].id: CGRect(x: 0, y: 120, width: 390, height: 180),
            anchorPost.id: CGRect(x: 0, y: 300, width: 390, height: 220)
        ])
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: anchorPost.id,
            anchorOffset: 24,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let restoredOffset = TimelineViewportResolver.restoredContentOffsetY(
            entries: entries,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        )

        #expect(restoredOffset == 398)
    }

    @Test("Timeline gap replacement estimates positive inserted height delta")
    func timelineGapReplacementDelta() throws {
        let gap = try #require(MockTimelineData.homeEntries.compactMap { entry -> TimelineGap? in
            guard case .gap(let gap) = entry else { return nil }
            return gap
        }.first)
        let delta = TimelineLayoutEstimator.estimatedReplacementDelta(
            for: gap,
            layoutCache: TimelineLayoutCache()
        )

        #expect(delta > 0)
    }

    @Test("Timeline gap upward fill keeps lower anchor visually fixed")
    func timelineGapUpwardFillKeepsLowerAnchor() throws {
        let posts = Array(MockTimelineData.posts.prefix(4))
        let newerPost = try #require(posts.first)
        let lowerAnchor = try #require(posts.last)
        let insertedPosts = Array(posts.dropFirst().dropLast())
        let gap = TimelineGap(
            id: "upward-gap",
            newerPostID: newerPost.id,
            olderPostID: lowerAnchor.id,
            missingEstimate: insertedPosts.count,
            relayCount: 2,
            state: .needsBackfill,
            backfilledPosts: insertedPosts
        )
        var cache = TimelineLayoutCache()
        cache.measuredHeights = [
            newerPost.id: 100,
            insertedPosts[0].id: 90,
            insertedPosts[1].id: 110,
            lowerAnchor.id: 120
        ]
        let beforeEntries: [TimelineFeedEntry] = [
            .post(newerPost),
            .gap(gap),
            .post(lowerAnchor)
        ]
        let afterEntries: [TimelineFeedEntry] = [
            .post(newerPost),
            .post(insertedPosts[0]),
            .post(insertedPosts[1]),
            .post(lowerAnchor)
        ]
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: lowerAnchor.id,
            anchorOffset: 0,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let beforeOffset = try #require(TimelineViewportResolver.restoredContentOffsetY(
            entries: beforeEntries,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))
        let afterOffset = try #require(TimelineViewportResolver.restoredContentOffsetY(
            entries: afterEntries,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        #expect(afterOffset - beforeOffset == TimelineLayoutEstimator.estimatedReplacementDelta(for: gap, layoutCache: cache))
    }

    @Test("Timeline prepended refresh entries keep current anchor visually fixed")
    func timelinePrependedRefreshEntriesKeepCurrentAnchor() throws {
        let posts = Array(MockTimelineData.posts.prefix(4))
        let firstNewPost = try #require(posts.first)
        let secondNewPost = posts[1]
        let anchorPost = posts[2]
        let olderPost = try #require(posts.last)
        var cache = TimelineLayoutCache()
        cache.measuredHeights = [
            firstNewPost.id: 80,
            secondNewPost.id: 100,
            anchorPost.id: 120,
            olderPost.id: 140
        ]
        let afterEntries: [TimelineFeedEntry] = [
            .post(firstNewPost),
            .post(secondNewPost),
            .post(anchorPost),
            .post(olderPost)
        ]
        let anchor = TimelineViewportAnchor(postID: anchorPost.id, offset: 20)

        let preservedOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: afterEntries,
            anchor: anchor,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        #expect(preservedOffset == 200)
    }

    @Test("Pull refresh keeps its original anchor through prepend and row remeasurement")
    func pullRefreshKeepsOriginalAnchorThroughPrependAndRemeasurement() throws {
        let posts = Array(MockTimelineData.posts.prefix(4))
        let firstNewPost = try #require(posts.first)
        let secondNewPost = posts[1]
        let anchorPost = posts[2]
        let olderPost = try #require(posts.last)
        let oldEntries: [TimelineFeedEntry] = [
            .post(anchorPost),
            .post(olderPost)
        ]
        let newEntries: [TimelineFeedEntry] = [
            .post(firstNewPost),
            .post(secondNewPost),
            .post(anchorPost),
            .post(olderPost)
        ]
        let anchor = TimelineViewportAnchor(postID: anchorPost.id, offset: 0)

        #expect(TimelinePullRefreshAnchorPolicy.prependedAnchor(
            anchor,
            oldIDs: oldEntries.map(\.id),
            newIDs: newEntries.map(\.id)
        ) == anchor)
        #expect(TimelineContentHeightAnchorPlanner.insertedPostIDsAffectingAnchor(
            oldEntries: oldEntries,
            newEntries: newEntries,
            anchorPostID: anchor.postID
        ) == [firstNewPost.id, secondNewPost.id])

        var estimatedCache = TimelineLayoutCache(measuredHeights: [
            firstNewPost.id: 80,
            secondNewPost.id: 100,
            anchorPost.id: 120,
            olderPost.id: 140
        ])
        let estimatedOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: newEntries,
            anchor: anchor,
            layoutCache: estimatedCache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        estimatedCache.measuredHeights[firstNewPost.id] = 130
        estimatedCache.measuredHeights[secondNewPost.id] = 70
        let correctedOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: newEntries,
            anchor: anchor,
            layoutCache: estimatedCache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        #expect(estimatedOffset == 180)
        #expect(correctedOffset == 200)
    }

    @Test("Timeline same-ID row remeasurement preserves the downstream anchor")
    func timelineSameIDRowRemeasurementPreservesDownstreamAnchor() throws {
        let avatar = AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person.fill")
        func post(id: String, body: String) -> TimelinePost {
            TimelinePost(
                id: id,
                authorName: "Anchor Test",
                handle: "anchor@example.test",
                avatar: avatar,
                body: body,
                createdAt: 100,
                replyCount: 0,
                boostCount: 0,
                favoriteCount: 0,
                isLocked: false,
                media: nil,
                context: nil
            )
        }

        let oldChangingPost = post(id: "changing-post", body: "Short body")
        let newChangingPost = post(
            id: "changing-post",
            body: "A much longer body that resolves without changing the row identity."
        )
        let anchorPost = post(id: "anchor-post", body: "Anchor body")
        let oldEntries: [TimelineFeedEntry] = [.post(oldChangingPost), .post(anchorPost)]
        let newEntries: [TimelineFeedEntry] = [.post(newChangingPost), .post(anchorPost)]
        let anchor = TimelineViewportAnchor(postID: anchorPost.id, offset: 20)

        let changedPostIDs = TimelineContentHeightAnchorPlanner.changedPostIDs(
            oldEntries: oldEntries,
            newEntries: newEntries
        )
        #expect(changedPostIDs == [oldChangingPost.id])
        #expect(TimelineContentHeightAnchorPlanner.changedPostIDsAffectingAnchor(
            entries: newEntries,
            changedPostIDs: changedPostIDs,
            anchorPostID: anchor.postID
        ) == [oldChangingPost.id])

        var cache = TimelineLayoutCache(measuredHeights: [
            oldChangingPost.id: 100,
            anchorPost.id: 120
        ])
        let beforeOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: oldEntries,
            anchor: anchor,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        let didInvalidateChangedPost = cache.invalidate(postIDs: changedPostIDs)
        #expect(didInvalidateChangedPost)
        #expect(cache.measuredHeights[oldChangingPost.id] == nil)
        #expect(cache.measuredHeights[anchorPost.id] == 120)
        let didRecordRemeasuredHeight = cache.recordMeasuredHeight(300, for: newChangingPost.id)
        #expect(didRecordRemeasuredHeight)

        let afterOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: newEntries,
            anchor: anchor,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))
        let remeasuredSnapshot = TimelineLayoutSnapshot(
            entries: newEntries,
            layoutCache: cache,
            topContentPadding: 72
        )

        #expect(afterOffset == beforeOffset + 200)
        #expect(remeasuredSnapshot.anchor(at: afterOffset, anchorLineY: 72) == anchor)
    }

    @Test("Timeline prepend plus common row remeasurement preserves the downstream anchor")
    func timelinePrependPlusCommonRowRemeasurementPreservesDownstreamAnchor() throws {
        let avatar = AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person.fill")
        func post(id: String, body: String) -> TimelinePost {
            TimelinePost(
                id: id,
                authorName: "Anchor Test",
                handle: "anchor@example.test",
                avatar: avatar,
                body: body,
                createdAt: 100,
                replyCount: 0,
                boostCount: 0,
                favoriteCount: 0,
                isLocked: false,
                media: nil,
                context: nil
            )
        }

        let prependedPost = post(id: "prepended-post", body: "New post")
        let oldChangingPost = post(id: "changing-post", body: "Short body")
        let newChangingPost = post(
            id: oldChangingPost.id,
            body: "A much longer body arriving in the same revision as the prepend."
        )
        let anchorPost = post(id: "anchor-post", body: "Anchor body")
        let oldEntries: [TimelineFeedEntry] = [.post(oldChangingPost), .post(anchorPost)]
        let newEntries: [TimelineFeedEntry] = [
            .post(prependedPost),
            .post(newChangingPost),
            .post(anchorPost)
        ]
        let anchor = TimelineViewportAnchor(postID: anchorPost.id, offset: 20)
        let changedPostIDs = TimelineContentHeightAnchorPlanner.changedCommonPostIDsAffectingAnchor(
            oldEntries: oldEntries,
            newEntries: newEntries,
            anchorPostID: anchor.postID
        )
        #expect(changedPostIDs == [oldChangingPost.id])

        var cache = TimelineLayoutCache(measuredHeights: [
            prependedPost.id: 80,
            oldChangingPost.id: 100,
            anchorPost.id: 120
        ])
        let beforeOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            entries: oldEntries,
            anchor: anchor,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        let didInvalidateChangedPost = cache.invalidate(postIDs: changedPostIDs)
        #expect(didInvalidateChangedPost)
        var newSnapshot = TimelineLayoutSnapshot(
            entries: newEntries,
            layoutCache: cache,
            topContentPadding: 72
        )
        let didRecordRemeasuredHeight = newSnapshot.recordMeasuredHeight(300, for: newChangingPost.id)
        #expect(didRecordRemeasuredHeight)
        let afterOffset = try #require(TimelineViewportResolver.contentOffsetPreservingAnchor(
            snapshot: newSnapshot,
            anchor: anchor,
            anchorLineY: 72
        ))

        #expect(afterOffset == beforeOffset + 80 + 200)
        #expect(newSnapshot.anchor(at: afterOffset, anchorLineY: 72) == anchor)
    }

    @Test("Timeline gap downward fill keeps upper anchor visually fixed")
    func timelineGapDownwardFillKeepsUpperAnchor() throws {
        let posts = Array(MockTimelineData.posts.prefix(4))
        let upperAnchor = try #require(posts.first)
        let insertedPosts = Array(posts.dropFirst().dropLast())
        let olderPost = try #require(posts.last)
        let gap = TimelineGap(
            id: "downward-gap",
            newerPostID: upperAnchor.id,
            olderPostID: olderPost.id,
            missingEstimate: insertedPosts.count,
            relayCount: 2,
            state: .needsBackfill,
            backfilledPosts: insertedPosts
        )
        var cache = TimelineLayoutCache()
        cache.measuredHeights = [
            upperAnchor.id: 100,
            insertedPosts[0].id: 90,
            insertedPosts[1].id: 110,
            olderPost.id: 120
        ]
        let beforeEntries: [TimelineFeedEntry] = [
            .post(upperAnchor),
            .gap(gap),
            .post(olderPost)
        ]
        let afterEntries: [TimelineFeedEntry] = [
            .post(upperAnchor),
            .post(insertedPosts[0]),
            .post(insertedPosts[1]),
            .post(olderPost)
        ]
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: upperAnchor.id,
            anchorOffset: 12,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let beforeOffset = try #require(TimelineViewportResolver.restoredContentOffsetY(
            entries: beforeEntries,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))
        let afterOffset = try #require(TimelineViewportResolver.restoredContentOffsetY(
            entries: afterEntries,
            state: state,
            layoutCache: cache,
            topContentPadding: 72,
            anchorLineY: 72
        ))

        #expect(afterOffset == beforeOffset)
    }

    @Test("Timeline viewport resolver prefers anchor over stale content offset")
    func timelineViewportResolverPrefersAnchorOverStaleContentOffset() throws {
        let posts = Array(MockTimelineData.posts.prefix(3))
        let anchorPost = try #require(posts.last)
        var cache = TimelineLayoutCache()
        cache.merge(measuredFrames: [
            posts[0].id: CGRect(x: 0, y: 0, width: 390, height: 120),
            posts[1].id: CGRect(x: 0, y: 120, width: 390, height: 180),
            anchorPost.id: CGRect(x: 0, y: 300, width: 390, height: 220)
        ])
        let snapshot = TimelineLayoutSnapshot(posts: posts, layoutCache: cache, topContentPadding: 72)
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: anchorPost.id,
            anchorOffset: 24,
            contentOffset: 512,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let restoredOffset = TimelineViewportResolver.restoredContentOffsetY(
            snapshot: snapshot,
            state: state,
            anchorLineY: 72
        )

        #expect(restoredOffset == 324)
    }

    @Test("Timeline viewport resolver handles persisted large timelines by snapshot offset")
    func timelineViewportResolverHandlesPersistedLargeTimeline() throws {
        let posts = (0..<10_000).map { index in
            TimelinePost(
                id: "large-\(index)",
                author: .resolved(
                    displayName: "User \(index)",
                    nip05: nil,
                    pubkey: TimelineAuthor.mockPubkey(for: "large-\(index)")
                ),
                avatar: AvatarStyle(primary: .blue, secondary: .purple, symbolName: "person"),
                body: "Large timeline row \(index)",
                createdAt: TimelineMockClock.createdAt(relative: "\(index)m"),
                replyCount: nil,
                boostCount: nil,
                favoriteCount: nil,
                isLocked: false,
                media: nil,
                context: nil
            )
        }
        var cache = TimelineLayoutCache()
        cache.measuredHeights = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, CGFloat(80)) })
        let suiteName = "TimelineRestoreStoreLargeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TimelineRestoreStore(defaults: defaults)
        store.saveLayoutCache(cache, accountID: "account-a", timelineKey: "home")
        let persistedCache = store.layoutCache(accountID: "account-a", timelineKey: "home")
        var snapshot = TimelineLayoutSnapshot(posts: posts, layoutCache: cache, topContentPadding: 72)
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: "large-9876",
            anchorOffset: 19,
            contentOffset: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let restoredOffset = TimelineViewportResolver.restoredContentOffsetY(
            snapshot: snapshot,
            state: state,
            anchorLineY: 72
        )
        let didApplyMeasuredHeight = snapshot.recordMeasuredHeight(180, for: "large-0")
        let shiftedOffset = TimelineViewportResolver.restoredContentOffsetY(
            snapshot: snapshot,
            state: state,
            anchorLineY: 72
        )

        #expect(persistedCache.measuredHeights.count == 10_000)
        #expect(persistedCache.height(for: posts[9_876]) == 80)
        #expect(restoredOffset == CGFloat(9876 * 80 + 19))
        #expect(didApplyMeasuredHeight)
        #expect(shiftedOffset == restoredOffset.map { $0 + 100 })
        #expect(snapshot.anchor(at: shiftedOffset ?? 0, anchorLineY: 72) == TimelineViewportAnchor(
            postID: state.anchorPostID,
            offset: state.anchorOffset
        ))
    }

    @Test("Timeline restore store persists viewport state per timeline key")
    func timelineRestoreStorePersistsViewport() throws {
        let suiteName = "TimelineRestoreStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = TimelineRestoreStore(defaults: defaults)
        let state = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: "thread-a-root",
            anchorOffset: 14,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        store.saveViewportState(state)

        #expect(store.viewportState(accountID: "account-a", timelineKey: "home") == state)
        #expect(store.viewportState(accountID: "account-a", timelineKey: "lists") == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Timeline restore store coalesces pending writes and flushes only the latest values")
    @MainActor
    func timelineRestoreStoreDebouncesLatestValues() throws {
        let suiteName = "TimelineRestoreStoreDebounceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TimelineRestoreStore(defaults: defaults)
        let firstState = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: "first",
            anchorOffset: 10,
            contentOffset: 120,
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )
        let latestState = TimelineViewportState(
            accountID: "account-a",
            timelineKey: "home",
            anchorPostID: "latest",
            anchorOffset: 20,
            contentOffset: 240,
            updatedAt: Date(timeIntervalSince1970: 1_801)
        )
        let firstCache = TimelineLayoutCache(measuredHeights: ["first": 100])
        let latestCache = TimelineLayoutCache(measuredHeights: ["latest": 220])

        store.scheduleViewportStateSave(firstState, delay: 0.02)
        store.scheduleViewportStateSave(latestState, delay: 0.02)
        store.scheduleLayoutCacheSave(firstCache, accountID: "account-a", timelineKey: "home", delay: 0.02)
        store.scheduleLayoutCacheSave(latestCache, accountID: "account-a", timelineKey: "home", delay: 0.02)

        #expect(store.viewportState(accountID: "account-a", timelineKey: "home") == nil)
        #expect(store.latestViewportState(accountID: "account-a", timelineKey: "home") == latestState)
        #expect(store.layoutCache(accountID: "account-a", timelineKey: "home").measuredHeights.isEmpty)

        store.flushPendingSaves()

        #expect(store.viewportState(accountID: "account-a", timelineKey: "home") == latestState)
        #expect(store.layoutCache(accountID: "account-a", timelineKey: "home") == latestCache)
    }

    @Test("Unread persistence advances only across a contiguous read suffix")
    func unreadBoundaryDoesNotSkipUnreadHoles() {
        var state = HomeTimelineUnreadState()
        state.replaceMaterializedPostIDs(["old"])
        state.replaceMaterializedPostIDs(["new-1", "new-2", "old"])

        state.markVisiblePostsRead(["new-1"])
        #expect(state.readBoundaryPostID == "old")

        state.markVisiblePostsRead(["new-2"])
        #expect(state.readBoundaryPostID == "new-1")
    }
}

@MainActor
private func makeGatedHomeStore(
    eventStore: NostrEventStore,
    bootstrapRelays: [String],
    viewportStateRestorer: any HomeTimelineViewportStateRestoring =
        TimelineRestoreStore()
) -> (store: NostrHomeTimelineStore, relayClient: GatedStoreRelayClient) {
    let relayClient = GatedStoreRelayClient(eventsBySubscriptionID: [:])
    let store = NostrHomeTimelineStore(
        timelineLoader: NostrHomeTimelineLoader(
            relayClient: relayClient,
            bootstrapRelays: bootstrapRelays
        ),
        eventStore: eventStore,
        viewportStateRestorer: viewportStateRestorer
    )
    return (store, relayClient)
}

private struct CachedReadBoundaryStoreFixture {
    let account: NostrAccount
    let store: NostrHomeTimelineStore
    let relayClient: GatedStoreRelayClient
    let expectedPostIDs: [String]
}

@MainActor
private func makeCachedReadBoundaryStoreFixture() throws -> CachedReadBoundaryStoreFixture {
    let eventStore = try NostrEventStore.inMemory()
    let account = NostrAccount(
        pubkey: String(repeating: "d", count: 64),
        displayIdentifier: "npub-cached-read-boundary",
        readOnly: true
    )
    let newest = timelineEvent(
        idSeed: "cached-read-newest", pubkey: account.pubkey, createdAt: 300, content: "newest"
    )
    let boundary = timelineEvent(
        idSeed: "cached-read-boundary", pubkey: account.pubkey, createdAt: 200, content: "boundary"
    )
    let oldest = timelineEvent(
        idSeed: "cached-read-oldest", pubkey: account.pubkey, createdAt: 100, content: "oldest"
    )
    let events = [newest, boundary, oldest]
    let relays = ["wss://relay.example"]
    try saveCachedReadBoundaryFeed(
        events: events,
        boundary: boundary,
        relays: relays,
        account: account,
        eventStore: eventStore
    )
    let (store, relayClient) = makeGatedHomeStore(
        eventStore: eventStore,
        bootstrapRelays: relays
    )
    return CachedReadBoundaryStoreFixture(
        account: account,
        store: store,
        relayClient: relayClient,
        expectedPostIDs: events.map(\.id)
    )
}

private func saveCachedReadBoundaryFeed(
    events: [NostrEvent],
    boundary: NostrEvent,
    relays: [String],
    account: NostrAccount,
    eventStore: NostrEventStore
) throws {
    let plan = try #require(HomeFeedProjectionBuilder.definitionPlan(
        accountID: account.pubkey,
        followedPubkeys: [account.pubkey],
        existingDefinition: nil,
        now: 301
    ))
    try eventStore.saveHomeFeedState(
        NostrHomeTimelineState(
            relays: relays,
            followedPubkeys: [account.pubkey],
            noteEvents: events,
            metadataEvents: []
        ),
        accountID: account.pubkey,
        definition: plan.definition,
        memberships: HomeFeedProjectionBuilder.memberships(
            events: events,
            feedID: plan.definition.feedID,
            feedRevision: plan.definition.revision,
            reason: "test",
            insertedAt: 301
        ),
        readState: NostrFeedReadStateRecord(
            feedID: plan.definition.feedID,
            readBoundary: NostrTimelineEntryCursor(
                sortTimestamp: boundary.createdAt,
                eventID: boundary.id
            ),
            updatedAt: 301
        ),
        savedAt: 301
    )
}

@MainActor
private func waitForTimelineState(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ predicate: @escaping @MainActor () -> Bool
) async throws -> Bool {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    while !predicate() {
        guard DispatchTime.now().uptimeNanoseconds - startedAt < timeoutNanoseconds else {
            return false
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

private func timelineEvent(
    idSeed: String,
    id: String? = nil,
    kind: Int = 1,
    pubkey: String,
    createdAt: Int,
    tags: [[String]] = [],
    content: String
) -> NostrEvent {
    NostrEvent(
        id: id ?? timelineEventID(idSeed),
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: String(repeating: "0", count: 128)
    )
}

private func timelineEventID(_ seed: String) -> String {
    let hex = seed.utf8.map { String(format: "%02x", $0) }.joined()
    return String((hex + String(repeating: "0", count: 64)).prefix(64))
}

private struct TimelineTestHomeFeedSpecification: Codable {
    let authors: [String]
    let kinds: [Int]
}

private func homeFeedID(accountID: String) -> String {
    "feed:home:\(accountID)"
}

private func seedHomeFeedProjection(
    in eventStore: NostrEventStore,
    accountID: String,
    events: [NostrEvent],
    sourceAuthors: [String]? = nil,
    gapPairs: [(newerEventID: String, olderEventID: String)] = [],
    insertedAt: Int
) throws {
    let authors = (sourceAuthors ?? [accountID]).sorted()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let specificationJSON = try encoder.encode(
        TimelineTestHomeFeedSpecification(authors: authors, kinds: [1, 6])
    )
    let specificationHash = stableHomeFeedSpecificationHash(specificationJSON)
    let feedID = homeFeedID(accountID: accountID)
    let existingDefinition = try eventStore.feedDefinition(feedID: feedID)
    let definition: NostrFeedDefinitionRecord
    if let existingDefinition,
       existingDefinition.specificationHash == specificationHash {
        definition = existingDefinition
    } else {
        definition = NostrFeedDefinitionRecord(
            feedID: feedID,
            accountID: accountID,
            kind: "home",
            specificationJSON: specificationJSON,
            specificationHash: specificationHash,
            sortPolicy: "created_at_desc_event_id_asc",
            revision: (existingDefinition?.revision ?? 0) + 1,
            createdAt: existingDefinition?.createdAt ?? insertedAt,
            updatedAt: insertedAt
        )
    }

    let projectionEvents = events.filter { event in
        (event.kind == 1 || event.kind == 6) && authors.contains(event.pubkey)
    }
    try eventStore.save(events: projectionEvents, receivedAt: insertedAt)
    let memberships = projectionEvents.map { event in
        NostrFeedMembershipRecord(
            feedID: feedID,
            eventID: event.id,
            subjectEventID: event.kind == 6
                ? event.tags.last(where: { $0.count >= 2 && $0[0] == "e" })?[1]
                : nil,
            sortTimestamp: event.createdAt,
            reason: "test-seed",
            insertedAt: insertedAt,
            feedRevision: definition.revision
        )
    }
    let sources = projectionEvents.flatMap { event in
        [
            NostrFeedMembershipSourceRecord(
                feedID: feedID,
                eventID: event.id,
                sourceType: "author",
                sourceID: event.pubkey,
                insertedAt: insertedAt,
                feedRevision: definition.revision
            ),
            NostrFeedMembershipSourceRecord(
                feedID: feedID,
                eventID: event.id,
                sourceType: "ingest",
                sourceID: "test-seed",
                insertedAt: insertedAt,
                feedRevision: definition.revision
            )
        ]
    }
    let gaps = gapPairs.map { pair in
        NostrFeedGapRecord(
            feedID: feedID,
            feedRevision: definition.revision,
            newerEventID: pair.newerEventID,
            olderEventID: pair.olderEventID,
            state: .unresolved,
            createdAt: insertedAt,
            updatedAt: insertedAt
        )
    }
    try eventStore.replaceFeedProjection(
        definition,
        memberships: memberships,
        sources: sources,
        gaps: gaps
    )
}

private func stableHomeFeedSpecificationHash(_ data: Data) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

private func homeFeedMemberships(
    in eventStore: NostrEventStore,
    accountID: String,
    limit: Int = 100
) throws -> [NostrFeedMembershipRecord] {
    try eventStore.feedMemberships(
        feedID: homeFeedID(accountID: accountID),
        limit: limit
    )
}

private func homeFeedGaps(
    in eventStore: NostrEventStore,
    accountID: String
) throws -> [NostrFeedGapRecord] {
    try eventStore.feedGaps(
        feedID: homeFeedID(accountID: accountID),
        includeResolved: true
    )
}

private func relayEventFrame(subscriptionID: String, event: NostrEvent) throws -> String {
    let eventData = try JSONEncoder().encode(event)
    let eventObject = try JSONSerialization.jsonObject(with: eventData)
    let frameData = try JSONSerialization.data(withJSONObject: ["EVENT", subscriptionID, eventObject], options: [.sortedKeys])
    return String(data: frameData, encoding: .utf8) ?? "[]"
}

private func relayEOSEFrame(subscriptionID: String) throws -> String {
    let frameData = try JSONSerialization.data(withJSONObject: ["EOSE", subscriptionID], options: [.sortedKeys])
    return String(data: frameData, encoding: .utf8) ?? "[]"
}

private func relayClosedFrame(subscriptionID: String, message: String) throws -> String {
    let frameData = try JSONSerialization.data(withJSONObject: ["CLOSED", subscriptionID, message], options: [.sortedKeys])
    return String(data: frameData, encoding: .utf8) ?? "[]"
}

private func timelineHTTPResponse(url: URL?, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url ?? URL(string: "https://example.test")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private func reqSubscriptionID(from frame: String, containing needle: String) -> String? {
    guard let data = frame.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
          array.count >= 2,
          array.first as? String == "REQ"
    else { return nil }

    if frame.contains(needle) {
        return array[1] as? String
    }

    let filters = array.dropFirst(2).compactMap { $0 as? [String: Any] }
    let matchesNeedle = filters.contains { filter in
        guard needle.contains(#""kinds":[0]"#),
              let kinds = filter["kinds"] as? [Int]
        else { return false }
        return kinds.contains(0)
    }
    guard matchesNeedle else { return nil }

    return array[1] as? String
}

private func waitForREQSubscriptionID(
    in connection: FakeRelayRuntimeConnection,
    containing needle: String,
    attempts: Int = 100
) async throws -> String {
    for _ in 0..<attempts {
        if let subscriptionID = await connection.sentFrames().compactMap({ frame in
            reqSubscriptionID(from: frame, containing: needle)
        }).last {
            return subscriptionID
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    let sentFrames = await connection.sentFrames()
    return try #require(
        nil as String?,
        "REQ containing \(needle) was not sent. Frames: \(sentFrames)"
    )
}

private func assertNoREQSubscriptionID(
    in connection: FakeRelayRuntimeConnection,
    containing needle: String
) async throws {
    try await Task.sleep(nanoseconds: 100_000_000)
    let subscriptionID = await connection.sentFrames().compactMap { frame in
        reqSubscriptionID(from: frame, containing: needle)
    }.last
    #expect(subscriptionID == nil)
}

private func waitForFetchSubscriptionIDs(
    in relayClient: FakeStoreRelayClient,
    containing expectedSubscriptionIDs: Set<String>,
    attempts: Int = 100
) async throws -> [String] {
    for _ in 0..<attempts {
        let subscriptionIDs = await relayClient.fetchSubscriptionIDs()
        if expectedSubscriptionIDs.isSubset(of: Set(subscriptionIDs)) {
            return subscriptionIDs
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return await relayClient.fetchSubscriptionIDs()
}

@MainActor
private func waitForTimelinePostIDs(
    in store: NostrHomeTimelineStore,
    ids: [String],
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.entries.compactMap(\.post).map(\.id) == ids {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(store.entries.compactMap(\.post).map(\.id) == ids)
}

@MainActor
private func waitForTimelineEntryIDs(
    in store: NostrHomeTimelineStore,
    ids: [String],
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.entries.map(\.id) == ids {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(store.entries.map(\.id) == ids)
}

@MainActor
private func waitForHomeFeedGapState(
    in eventStore: NostrEventStore,
    accountID: String,
    newerEventID: String,
    olderEventID: String,
    state: NostrFeedGapState,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        let gap = try homeFeedGaps(in: eventStore, accountID: accountID).first { gap in
            gap.newerEventID == newerEventID && gap.olderEventID == olderEventID
        }
        if gap?.state == state {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    let gap = try homeFeedGaps(in: eventStore, accountID: accountID).first { gap in
        gap.newerEventID == newerEventID && gap.olderEventID == olderEventID
    }
    #expect(gap?.state == state)
}

private func waitForDeletedFeedItem(
    in eventStore: NostrEventStore,
    accountID: String,
    targetEventID: String,
    attempts: Int = 100
) async throws -> NostrDeletedFeedItemRecord {
    let feedID = "feed:home:\(accountID)"
    for _ in 0..<attempts {
        if let definition = try eventStore.feedDefinition(feedID: feedID),
           let deletedItem = try eventStore.deletedFeedItems(
               feedID: feedID,
               revision: definition.revision,
               limit: 100
           ).first(where: { $0.targetEventID == targetEventID }) {
            return deletedItem
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    let definition = try #require(try eventStore.feedDefinition(feedID: feedID))
    return try #require(try eventStore.deletedFeedItems(
        feedID: feedID,
        revision: definition.revision,
        limit: 100
    ).first(where: { $0.targetEventID == targetEventID }))
}

private func waitForSentFrameCount(
    in connection: FakeRelayRuntimeConnection,
    count: Int,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if await connection.sentFrames().count >= count {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(await connection.sentFrames().count >= count)
}

private func waitForREQFrameCount(
    in connection: FakeRelayRuntimeConnection,
    containing needle: String,
    count: Int,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        let matchingCount = await connection.sentFrames().filter { frame in
            reqSubscriptionID(from: frame, containing: needle) != nil
        }.count
        if matchingCount >= count {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    let matchingCount = await connection.sentFrames().filter { frame in
        reqSubscriptionID(from: frame, containing: needle) != nil
    }.count
    #expect(matchingCount >= count)
}

@MainActor
private func waitForRelayProcessing(
    in store: NostrHomeTimelineStore,
    isProcessing: Bool,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.isRelayProcessing == isProcessing {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(store.isRelayProcessing == isProcessing)
}

@MainActor
private func waitForRelayStatusCounts(
    in store: NostrHomeTimelineStore,
    connected: Int,
    planned: Int,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        let counts = store.relayStatusCounts
        if counts.connected == connected && counts.planned == planned {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    let counts = store.relayStatusCounts
    #expect(counts.connected == connected)
    #expect(counts.planned == planned)
}

@MainActor
private func waitForFollowedPubkeys(
    in store: NostrHomeTimelineStore,
    _ expected: [String],
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.followedPubkeys == expected {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(store.followedPubkeys == expected)
}

@MainActor
private func waitForRelayRuntimeState(
    in store: NostrHomeTimelineStore,
    relayURL: String,
    state: NostrRelayConnectionState,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.relayRuntimeStates[relayURL] == state {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(store.relayRuntimeStates[relayURL] == state)
}

@MainActor
private func waitForHomeTimelineRealtime(
    in store: NostrHomeTimelineStore,
    isRealtime: Bool,
    attempts: Int = 100
) async throws {
    for _ in 0..<attempts {
        if store.isHomeTimelineRealtime == isRealtime {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(store.isHomeTimelineRealtime == isRealtime)
}

@MainActor
private func waitForLinkPreview(
    in store: NostrEventStore,
    url: URL,
    status: String,
    attempts: Int = 100
) async throws -> NostrLinkPreviewRecord {
    for _ in 0..<attempts {
        if let preview = try store.linkPreviews(urls: [url]).values.first,
           preview.status == status {
            return preview
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(try store.linkPreviews(urls: [url]).values.first)
}

@MainActor
private func waitForNIP05Resolution(
    in store: NostrEventStore,
    accountID: String,
    pubkey: String,
    attempts: Int = 100
) async throws -> NostrNIP05Resolution {
    for _ in 0..<attempts {
        if let resolution = try store.homeFeedState(accountID: accountID)?
            .nip05Resolutions[pubkey] {
            return resolution
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(try store.homeFeedState(accountID: accountID)?.nip05Resolutions[pubkey])
}

@MainActor
private func waitForTimelinePost(
    in store: NostrHomeTimelineStore,
    id: String,
    matching predicate: (TimelinePost) -> Bool,
    attempts: Int = 100
) async throws -> TimelinePost {
    for _ in 0..<attempts {
        if let post = store.entries.compactMap(\.post).first(where: { $0.id == id && predicate($0) }) {
            return post
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(store.entries.compactMap(\.post).first { $0.id == id })
}

@MainActor
private func waitForRelaySummary(
    in store: NostrEventStore,
    accountID: String,
    timelineKey: String = "home",
    relayURL: String,
    kind: NostrRelaySyncEventKind,
    attempts: Int = 100
) async throws -> NostrRelaySyncSummaryRecord {
    for _ in 0..<attempts {
        if let summary = try store.relaySyncSummaries(accountID: accountID, timelineKey: timelineKey)
            .first(where: { $0.relayURL == relayURL }),
           summary.lastEventKind == kind {
            return summary
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(
        try store.relaySyncSummaries(accountID: accountID, timelineKey: timelineKey)
            .first(where: { $0.relayURL == relayURL })
    )
}

@MainActor
private func waitForProfileFetchRecord(
    in store: NostrEventStore,
    pubkey: String,
    outcome: NostrProfileFetchOutcome,
    attempts: Int = 100
) async throws -> NostrProfileFetchRecord {
    for _ in 0..<attempts {
        if let record = try store.profileFetchRecords(pubkeys: [pubkey]).first,
           record.outcome == outcome {
            return record
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(try store.profileFetchRecords(pubkeys: [pubkey]).first)
}

@MainActor
private func waitForRelaySyncEvent(
    in store: NostrEventStore,
    accountID: String,
    timelineKey: String = "home",
    relayURL: String,
    kind: NostrRelaySyncEventKind,
    subscriptionID: String?,
    attempts: Int = 100
) async throws -> NostrRelaySyncEventRecord {
    for _ in 0..<attempts {
        if let event = try store.relaySyncEvents(
            accountID: accountID,
            timelineKey: timelineKey,
            relayURL: relayURL,
            limit: 20
        ).first(where: { event in
            event.kind == kind && event.subscriptionID == subscriptionID
        }) {
            return event
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    return try #require(
        try store.relaySyncEvents(
            accountID: accountID,
            timelineKey: timelineKey,
            relayURL: relayURL,
            limit: 20
        ).first(where: { event in
            event.kind == kind && event.subscriptionID == subscriptionID
        })
    )
}

private actor GatedStoreRelayClient: NostrRelayFetching {
    private let eventsBySubscriptionID: [String: [NostrEvent]]
    private let gatedSubscriptionID: String
    private var fetchCalls: [String] = []
    private var isBootstrapReleased = false
    private var bootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        eventsBySubscriptionID: [String: [NostrEvent]],
        gatedSubscriptionID: String = "astrenza-nip65"
    ) {
        self.eventsBySubscriptionID = eventsBySubscriptionID
        self.gatedSubscriptionID = gatedSubscriptionID
    }

    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        fetchCalls.append(request.subscriptionID)
        if request.subscriptionID == gatedSubscriptionID, !isBootstrapReleased {
            await withCheckedContinuation { continuation in
                if isBootstrapReleased {
                    continuation.resume()
                } else {
                    bootstrapWaiters.append(continuation)
                }
            }
        }
        return eventsBySubscriptionID[request.subscriptionID] ?? []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }

    func waitUntilBootstrapFetchStarts() async throws {
        for _ in 0..<100 {
            if fetchCalls.contains(gatedSubscriptionID) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("\(gatedSubscriptionID) bootstrap fetch did not start")
    }

    func releaseBootstrap() {
        isBootstrapReleased = true
        let waiters = bootstrapWaiters
        bootstrapWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func fetchSubscriptionIDs() -> [String] {
        fetchCalls
    }
}

private actor CancellableStoreRelayClient: NostrRelayFetching {
    func fetch(
        relayURL: String,
        request: NostrRelayRequest
    ) async throws -> [NostrEvent] {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        []
    }
}

private actor FakeStoreRelayClient: NostrRelayFetching {
    private let eventsBySubscriptionID: [String: [NostrEvent]]
    private let eventsByRelayAndSubscriptionID: [String: [String: [NostrEvent]]]
    private let missingEventIDsBySubscriptionID: [String: [String]]
    private var fetchCalls: [String] = []

    init(
        eventsBySubscriptionID: [String: [NostrEvent]],
        missingEventIDsBySubscriptionID: [String: [String]] = [:]
    ) {
        self.eventsBySubscriptionID = eventsBySubscriptionID
        self.missingEventIDsBySubscriptionID = missingEventIDsBySubscriptionID
        eventsByRelayAndSubscriptionID = [:]
    }

    init(
        eventsByRelayAndSubscriptionID: [String: [String: [NostrEvent]]],
        missingEventIDsBySubscriptionID: [String: [String]] = [:]
    ) {
        eventsBySubscriptionID = [:]
        self.eventsByRelayAndSubscriptionID = eventsByRelayAndSubscriptionID
        self.missingEventIDsBySubscriptionID = missingEventIDsBySubscriptionID
    }

    func fetch(relayURL: String, request: NostrRelayRequest) async throws -> [NostrEvent] {
        fetchCalls.append(request.subscriptionID)
        if let relayEvents = eventsByRelayAndSubscriptionID[relayURL]?[request.subscriptionID] {
            return relayEvents
        }
        return eventsBySubscriptionID[request.subscriptionID] ?? []
    }

    func fetchMissingEventIDs(
        relayURL: String,
        filter: NostrRelayFilter,
        localEvents: [NostrEvent],
        subscriptionID: String
    ) async throws -> [String] {
        missingEventIDsBySubscriptionID[subscriptionID] ?? []
    }

    func fetchSubscriptionIDs() -> [String] {
        fetchCalls
    }
}

private final class MediaResolverBearerTokenProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    var store: NostrMediaResolverBearerTokenStore {
        NostrMediaResolverBearerTokenStore(
            token: { [weak self] in
                self?.token ?? ""
            },
            save: { [weak self] token in
                self?.save(token)
            }
        )
    }

    var token: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    private func save(_ token: String) {
        lock.lock()
        value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
    }
}

private struct FakeNIP05Resolver: NostrNIP05Resolving {
    let resolutions: [String: NostrNIP05Resolution]

    func resolve(identifier: String, expectedPubkey: String?) async -> NostrNIP05Resolution {
        if let resolution = resolutions[identifier] {
            if let expectedPubkey, let pubkey = resolution.pubkey, pubkey != expectedPubkey {
                return NostrNIP05Resolution(
                    identifier: resolution.identifier,
                    pubkey: pubkey,
                    relays: resolution.relays,
                    status: .invalid,
                    resolvedAt: resolution.resolvedAt
                )
            }
            return resolution
        }

        return NostrNIP05Resolution(
            identifier: identifier,
            pubkey: nil,
            relays: [],
            status: .failed
        )
    }
}

private struct FakeRelayInformationClient: NostrRelayInformationFetching {
    let result: Result<NostrRelayInformationDocument, Error>

    func information(for relayURL: String) async throws -> NostrRelayInformationDocument {
        try result.get()
    }
}

private actor FakeRelayRuntimeTransport: NostrRelayTransport {
    private let connection: FakeRelayRuntimeConnection

    init(connection: FakeRelayRuntimeConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        connection
    }
}

private actor FakeRelayRuntimeConnection: NostrRelayTransportConnection {
    private var inboundFrames: [String]
    private var outboundFrames: [String] = []
    private var isClosed = false

    init(inboundFrames: [String]) {
        self.inboundFrames = inboundFrames
    }

    func send(_ textFrame: String) async throws {
        outboundFrames.append(textFrame)
    }

    func receive() async throws -> String {
        guard !inboundFrames.isEmpty else {
            throw NostrRelayClientError.timeout
        }
        return inboundFrames.removeFirst()
    }

    func appendInboundFrames(_ frames: [String]) {
        inboundFrames.append(contentsOf: frames)
    }

    func close() async {
        isClosed = true
    }

    func sentFrames() -> [String] {
        outboundFrames
    }

    func closed() -> Bool {
        isClosed
    }
}
