import AstrenzaCore
import Foundation
import Testing
@testable import Astrenza

@Suite("Home timeline user action coordinator")
@MainActor
struct HomeTimelineUserActionCoordinatorTests {
    @Test("Live compose suggestions never fall back to preview data")
    func liveComposeSuggestionsFailClosed() {
        #expect(
            ComposeSuggestionSnapshot.load(
                accountID: String(repeating: "a", count: 64),
                eventStore: nil
            ) == .empty
        )
        #expect(
            ComposeSuggestionSnapshot.load(
                accountID: nil,
                eventStore: nil
            ) == .preview
        )
    }

    @Test("Compose suggestions project cached profiles, hashtags, and emoji")
    func composeSuggestionsProjectCachedEvents() throws {
        let pubkey = String(repeating: "a", count: 64)
        let snapshot = ComposeSuggestionSnapshot.project(
            profiles: [NostrProfileSearchResult(
                pubkey: pubkey,
                displayName: "Astrenza User",
                nip05: "user@example.com",
                pictureURL: URL(string: "https://example.com/avatar.png"),
                updatedAt: 100
            )],
            recentNotes: [
                NostrEvent(
                    id: String(repeating: "1", count: 64),
                    pubkey: pubkey,
                    createdAt: 200,
                    kind: 1,
                    tags: [
                        ["t", "nostr"],
                        ["emoji", "astrenza", "https://example.com/astrenza.png"]
                    ],
                    content: "#nostr :astrenza:",
                    sig: String(repeating: "0", count: 128)
                ),
                NostrEvent(
                    id: String(repeating: "2", count: 64),
                    pubkey: pubkey,
                    createdAt: 100,
                    kind: 1,
                    tags: [["t", "NOSTR"]],
                    content: "#NOSTR",
                    sig: String(repeating: "0", count: 128)
                )
            ]
        )

        #expect(snapshot.mentions.map(\.id) == [pubkey])
        #expect(snapshot.mentions[0].insertionText.hasPrefix("nostr:npub1"))
        #expect(snapshot.hashtags.map(\.tag) == ["#nostr"])
        #expect(snapshot.hashtags[0].recency == "Seen in 2 cached notes")
        #expect(snapshot.completionEmojis.map(\.shortcode) == [":astrenza:"])
        #expect(
            snapshot.completionEmojis[0].imageURL?.absoluteString ==
                "https://example.com/astrenza.png"
        )
        #expect(!snapshot.mentions.contains { $0.handle.contains("mock") })
    }

    @Test("Submit requires a signer before publishing")
    func submitRequiresSigner() async {
        let actions = UserActionHandlerSpy()
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)

        let didSubmit = await coordinator.submit(
            request(mode: .post, text: "unsigned"),
            accountID: Self.accountID,
            signer: nil
        )

        #expect(!didSubmit)
        #expect(actions.publishInputs.isEmpty)
    }

    @Test("Submit preserves post, reply, and content-warning mapping")
    func submitMapsComposeRequests() async {
        let actions = UserActionHandlerSpy()
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)
        let signer = UserActionSigner()

        let didSubmitPost = await coordinator.submit(
            request(mode: .post, text: "plain"),
            accountID: Self.accountID,
            signer: signer
        )
        let didSubmitReply = await coordinator.submit(
            request(
                mode: .reply,
                text: "sensitive",
                isSensitive: true,
                sensitiveReason: "spoiler"
            ),
            accountID: Self.accountID,
            signer: signer
        )

        #expect(didSubmitPost)
        #expect(didSubmitReply)
        #expect(actions.publishInputs == [
            .post(content: "plain", tags: []),
            .reply(
                content: "sensitive",
                root: Self.replyReference.nostrReference,
                parent: Self.replyReference.nostrReference,
                tags: [["content-warning", "spoiler"]]
            )
        ])
    }

    @Test("Submit preserves selected custom emoji tags")
    func submitMapsCustomEmojiTags() async {
        let actions = UserActionHandlerSpy()
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)
        let request = ComposeSubmitRequest(
            context: .post,
            text: "hello :astrenza:",
            isSensitive: false,
            sensitiveReason: "",
            customEmojis: [ComposeCustomEmojiReference(
                shortcode: "astrenza",
                url: "https://emoji.example/astrenza.png"
            )],
            media: []
        )

        #expect(await coordinator.submit(
            request,
            accountID: Self.accountID,
            signer: UserActionSigner()
        ))
        #expect(actions.publishInputs == [
            .post(
                content: "hello :astrenza:",
                tags: [["emoji", "astrenza", "https://emoji.example/astrenza.png"]]
            )
        ])
    }

    @Test("Submit converts publisher errors into failure")
    func submitHandlesPublisherFailure() async {
        let actions = UserActionHandlerSpy()
        actions.shouldFailPublish = true
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)

        let didSubmit = await coordinator.submit(
            request(mode: .post, text: "failure"),
            accountID: Self.accountID,
            signer: UserActionSigner()
        )

        #expect(!didSubmit)
        #expect(actions.publishInputs == [
            .post(content: "failure", tags: [])
        ])
    }

    @Test("Post menu maps only mute and bookmark to domain actions")
    func postMenuMapsImplementedActions() throws {
        let post = try #require(MockTimelineData.posts.first)
        let actions = UserActionHandlerSpy()
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)

        for choice in PostActionChoice.allCases {
            coordinator.perform(choice, on: post)
        }

        #expect(actions.localMutations == [
            .muteAuthor(post.author.pubkey),
            .bookmark(post.id)
        ])
    }

    private func request(
        mode: ComposeSheetMode,
        text: String,
        isSensitive: Bool = false,
        sensitiveReason: String = ""
    ) -> ComposeSubmitRequest {
        ComposeSubmitRequest(
            context: mode == .reply
                ? .reply(ComposeReplyContext(
                    root: Self.replyReference,
                    parent: Self.replyReference,
                    recipientPubkeys: []
                ))
                : .post,
            text: text,
            isSensitive: isSensitive,
            sensitiveReason: sensitiveReason,
            customEmojis: [],
            media: []
        )
    }

    private static let accountID = String(repeating: "a", count: 64)
    private static let replyReference = ComposeEventReference(
        eventID: String(repeating: "1", count: 64),
        relayHint: "wss://relay.example",
        pubkey: String(repeating: "b", count: 64)
    )
}

@MainActor
private final class UserActionHandlerSpy: HomeTimelineUserActionHandling {
    enum Failure: Error {
        case publish
    }

    enum LocalMutation: Equatable {
        case muteAuthor(String)
        case bookmark(String)
    }

    var shouldFailPublish = false
    private(set) var publishInputs: [NostrPublishInput] = []
    private(set) var localMutations: [LocalMutation] = []

    func enqueuePublish(
        _ input: NostrPublishInput,
        taggedUserReadRelays: [String],
        signer: any NostrEventSigning,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void
    ) async throws -> Bool {
        _ = (signer, taggedUserReadRelays)
        publishInputs.append(input)
        reportProgress(.queued(eventID: "test-event"))
        if shouldFailPublish {
            throw Failure.publish
        }
        return true
    }

    func resolveBlossomServers(accountID: String) async -> [URL] {
        _ = accountID
        return []
    }

    func muteAuthor(authorPubkey: String) {
        localMutations.append(.muteAuthor(authorPubkey))
    }

    func bookmark(eventID: String) {
        localMutations.append(.bookmark(eventID))
    }
}

private extension ComposeEventReference {
    var nostrReference: NostrReplyReference {
        NostrReplyReference(
            eventID: eventID,
            relayHint: relayHint,
            pubkey: pubkey
        )
    }
}

private struct UserActionSigner: NostrEventSigning {
    enum Failure: Error {
        case unused
    }

    func sign(_ unsignedEvent: NostrUnsignedEvent) async throws -> NostrEvent {
        throw Failure.unused
    }
}
