import CoreGraphics
import Foundation
import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Timeline models")
struct TimelineModelTests {
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
            timestamp: "now",
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
            timestamp: "now",
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
            timestamp: "now",
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
            blurhash: nil,
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
        } else {
            Issue.record("Expected gallery media from persisted asset")
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
            imageURL: nil,
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
        } else {
            Issue.record("Expected resolved link preview media")
        }
    }

    @Test("Nostr materializer merges deleted timeline entries by sort position")
    func nostrMaterializerMergesDeletedTimelineEntries() throws {
        let author = String(repeating: "a", count: 64)
        let newer = timelineEvent(idSeed: "newer", pubkey: author, createdAt: 300, content: "newer")
        let older = timelineEvent(idSeed: "older", pubkey: author, createdAt: 100, content: "older")
        let deleted = NostrDeletedTimelineEntryRecord(
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

    @Test("Unresolved authors display a valid npub-like abbreviated pubkey")
    func unresolvedAuthorDisplay() {
        let author = TimelineAuthor.unresolved(pubkey: TimelineAuthor.mockPubkey(for: "unresolved"))

        #expect(author.primaryText.hasPrefix("npub1"))
        #expect(author.primaryText.contains("..."))
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

    @Test("Timeline viewport resolver restores exact content offset when available")
    func timelineViewportResolverPrefersExactContentOffset() throws {
        let posts = Array(MockTimelineData.posts.prefix(3))
        let anchorPost = try #require(posts.last)
        let snapshot = TimelineLayoutSnapshot(posts: posts, layoutCache: TimelineLayoutCache(), topContentPadding: 72)
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

        #expect(restoredOffset == 512)
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
                timestamp: "\(index)m",
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
        let snapshot = TimelineLayoutSnapshot(posts: posts, layoutCache: cache, topContentPadding: 72)
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

        #expect(persistedCache.measuredHeights.count == 10_000)
        #expect(persistedCache.height(for: posts[9_876]) == 80)
        #expect(restoredOffset == CGFloat(9876 * 80 + 19))
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
