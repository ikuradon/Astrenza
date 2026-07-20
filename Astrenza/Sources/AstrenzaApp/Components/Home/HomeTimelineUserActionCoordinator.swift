import AstrenzaCore
import Foundation

@MainActor
protocol HomeTimelineUserActionHandling: AnyObject {
    func enqueuePublish(
        _ input: NostrPublishInput,
        taggedUserReadRelays: [String],
        signer: any NostrEventSigning,
        reportProgress: @escaping @MainActor @Sendable (
            HomeTimelinePublishStage
        ) -> Void
    ) async throws -> Bool

    func resolveBlossomServers(accountID: String) async -> [URL]

    func muteAuthor(authorPubkey: String)

    func bookmark(eventID: String)
}

extension NostrHomeTimelineStore: HomeTimelineUserActionHandling {}

@MainActor
final class HomeTimelineUserActionCoordinator {
    private let actions: any HomeTimelineUserActionHandling
    private let tagBuilder: ComposePublishTagBuilder
    private let blossomUploadClient: NostrBlossomUploadClient

    init(
        actions: any HomeTimelineUserActionHandling,
        eventStore: NostrEventStore? = nil,
        blossomUploadClient: NostrBlossomUploadClient = .init()
    ) {
        self.actions = actions
        tagBuilder = ComposePublishTagBuilder(eventStore: eventStore)
        self.blossomUploadClient = blossomUploadClient
    }

    func submit(
        _ request: ComposeSubmitRequest,
        accountID: String?,
        signer: (any NostrEventSigning)?,
        onProgress: @escaping @MainActor @Sendable (
            ComposeSubmissionState
        ) -> Void = { _ in }
    ) async -> Bool {
        guard let accountID, let signer else { return false }
        do {
            let uploadedMedia = try await uploadMedia(
                request.media,
                accountID: accountID,
                signer: signer,
                onProgress: onProgress
            )
            let publish = tagBuilder.prepare(
                request,
                uploadedMedia: uploadedMedia,
                authorPubkey: accountID
            )
            let didEnqueue = try await actions.enqueuePublish(
                publish.input,
                taggedUserReadRelays: publish.taggedUserReadRelays,
                signer: signer,
                reportProgress: { stage in
                    onProgress(stage.composeSubmissionState)
                }
            )
            return didEnqueue
        } catch {
            return false
        }
    }

    private func uploadMedia(
        _ media: [ComposeMediaUploadRequest],
        accountID: String,
        signer: any NostrEventSigning,
        onProgress: @escaping @MainActor @Sendable (
            ComposeSubmissionState
        ) -> Void
    ) async throws -> [ComposeUploadedMedia] {
        guard !media.isEmpty else { return [] }
        let servers = await actions.resolveBlossomServers(accountID: accountID)
        guard !servers.isEmpty else {
            throw ComposePublishError.noMediaServer
        }

        var uploaded: [ComposeUploadedMedia] = []
        for item in media {
            onProgress(.uploadingMedia(
                completed: uploaded.count,
                total: media.count
            ))
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: item.localURL)
            }.value
            var lastError: Error?
            var blob: NostrUploadedBlob?
            for server in servers.prefix(4) {
                do {
                    blob = try await blossomUploadClient.upload(
                        data: data,
                        mimeType: item.mimeType,
                        serverURL: server,
                        accountID: accountID,
                        signer: signer
                    )
                    break
                } catch {
                    lastError = error
                }
            }
            guard let blob else {
                throw lastError ?? ComposePublishError.mediaUploadFailed
            }
            uploaded.append(ComposeUploadedMedia(
                url: blob.url,
                mimeType: blob.type ?? item.mimeType,
                width: item.width,
                height: item.height,
                sha256: blob.sha256,
                altText: item.altText
            ))
        }
        onProgress(.uploadingMedia(
            completed: uploaded.count,
            total: media.count
        ))
        return uploaded
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
        case .report, .translate, .copyLink, .shareLink, .viewDetails,
             .quotedRepost:
            break
        }
    }

}

private enum ComposePublishError: Error {
    case noMediaServer
    case mediaUploadFailed
}

private extension HomeTimelinePublishStage {
    var composeSubmissionState: ComposeSubmissionState {
        switch self {
        case .signing: .signing
        case .savingToOutbox: .savingToOutbox
        case .queued(let eventID): .queued(eventID: eventID)
        }
    }
}
