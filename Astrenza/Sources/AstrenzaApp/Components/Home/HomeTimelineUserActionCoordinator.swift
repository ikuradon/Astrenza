import AstrenzaCore

@MainActor
protocol HomeTimelineUserActionHandling: AnyObject {
    func enqueuePublish(
        _ input: NostrPublishInput,
        signer: any NostrEventSigning
    ) async throws

    func muteAuthor(authorPubkey: String)

    func bookmark(eventID: String)
}

extension NostrHomeTimelineStore: HomeTimelineUserActionHandling {}

@MainActor
final class HomeTimelineUserActionCoordinator {
    private let actions: any HomeTimelineUserActionHandling

    init(actions: any HomeTimelineUserActionHandling) {
        self.actions = actions
    }

    func submit(
        _ request: ComposeSubmitRequest,
        signer: (any NostrEventSigning)?
    ) async -> Bool {
        guard let signer else { return false }
        do {
            try await actions.enqueuePublish(
                publishInput(for: request),
                signer: signer
            )
            return true
        } catch {
            return false
        }
    }

    func perform(
        _ choice: PostActionChoice,
        on post: TimelinePost
    ) {
        switch choice {
        case .mute:
            actions.muteAuthor(authorPubkey: post.author.pubkey)
        case .bookmark:
            actions.bookmark(eventID: post.id)
        case .report, .translate, .copyLink, .shareLink, .viewDetails:
            break
        }
    }

    private func publishInput(
        for request: ComposeSubmitRequest
    ) -> NostrPublishInput {
        var tags: [[String]] = []
        if request.isSensitive {
            tags.append(["content-warning", request.sensitiveReason])
        }

        switch request.mode {
        case .post, .reply:
            return .post(content: request.text, tags: tags)
        }
    }
}
