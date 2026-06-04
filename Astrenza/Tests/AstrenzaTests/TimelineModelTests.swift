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
}
