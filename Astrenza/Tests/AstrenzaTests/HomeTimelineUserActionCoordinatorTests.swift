import AstrenzaCore
import Testing
@testable import Astrenza

@Suite("Home timeline user action coordinator")
@MainActor
struct HomeTimelineUserActionCoordinatorTests {
    @Test("Submit requires a signer before publishing")
    func submitRequiresSigner() async {
        let actions = UserActionHandlerSpy()
        let coordinator = HomeTimelineUserActionCoordinator(actions: actions)

        let didSubmit = await coordinator.submit(
            request(mode: .post, text: "unsigned"),
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
            signer: signer
        )
        let didSubmitReply = await coordinator.submit(
            request(
                mode: .reply,
                text: "sensitive",
                isSensitive: true,
                sensitiveReason: "spoiler"
            ),
            signer: signer
        )

        #expect(didSubmitPost)
        #expect(didSubmitReply)
        #expect(actions.publishInputs == [
            .post(content: "plain", tags: []),
            .post(
                content: "sensitive",
                tags: [["content-warning", "spoiler"]]
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
            mode: mode,
            text: text,
            isSensitive: isSensitive,
            sensitiveReason: sensitiveReason
        )
    }
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
        signer: any NostrEventSigning
    ) async throws {
        publishInputs.append(input)
        if shouldFailPublish {
            throw Failure.publish
        }
    }

    func muteAuthor(authorPubkey: String) {
        localMutations.append(.muteAuthor(authorPubkey))
    }

    func bookmark(eventID: String) {
        localMutations.append(.bookmark(eventID))
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
