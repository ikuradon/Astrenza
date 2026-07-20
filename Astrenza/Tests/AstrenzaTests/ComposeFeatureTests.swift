import AstrenzaCore
import Foundation
import Testing
import UIKit
@testable import Astrenza

@Suite("Compose feature")
@MainActor
struct ComposeFeatureTests {
    @Test("Reply context keeps root, parent, recipients, and relay hint")
    func replyContextKeepsProtocolReferences() throws {
        let store = try NostrEventStore.inMemory()
        let rootID = String(repeating: "1", count: 64)
        let parentAuthor = String(repeating: "b", count: 64)
        let participant = String(repeating: "c", count: 64)
        let target = event(
            pubkey: parentAuthor,
            createdAt: 100,
            tags: [
                ["e", rootID, "wss://root.example", "root"],
                ["p", participant]
            ],
            content: "target"
        )
        try store.save(events: [target])
        try store.recordEventSources(
            eventIDs: [target.id],
            relayURL: "wss://parent.example"
        )
        let post = TimelinePost(
            id: target.id,
            authorName: "Parent",
            handle: "parent@example.com",
            avatar: AvatarStyle(primary: .purple, secondary: .blue, symbolName: "person"),
            body: target.content,
            createdAt: target.createdAt,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )

        let context = ComposeContextFactory.reply(to: post, eventStore: store)
        guard case .reply(let reply) = context else {
            Issue.record("Expected reply context")
            return
        }
        #expect(reply.root.eventID == rootID)
        #expect(reply.root.relayHint == "wss://root.example")
        #expect(reply.parent.eventID == target.id)
        #expect(reply.parent.relayHint == "wss://parent.example")
        #expect(reply.parent.pubkey == parentAuthor)
        #expect(reply.recipientPubkeys == [parentAuthor, participant].sorted())
    }

    @Test("Tag builder emits NIP-10, hashtags, emoji, imeta, and recipient relays")
    func tagBuilderBuildsCompletePublishInput() throws {
        let store = try NostrEventStore.inMemory()
        let mentionedPubkey = String(repeating: "d", count: 64)
        try store.save(events: [event(
            pubkey: mentionedPubkey,
            createdAt: 200,
            kind: 10_002,
            tags: [["r", "wss://read.example", "read"]],
            content: ""
        )])
        let npub = try NostrNIP19.publicKey(mentionedPubkey)
        let reference = ComposeEventReference(
            eventID: String(repeating: "2", count: 64),
            relayHint: "wss://parent.example",
            pubkey: String(repeating: "e", count: 64)
        )
        let request = ComposeSubmitRequest(
            context: .reply(ComposeReplyContext(
                root: reference,
                parent: reference,
                recipientPubkeys: [reference.pubkey!]
            )),
            text: "Hello #Nostr nostr:\(npub) :wave:",
            isSensitive: true,
            sensitiveReason: "spoiler",
            customEmojis: [.init(
                shortcode: "wave",
                url: "https://emoji.example/wave.png"
            )],
            media: []
        )
        let media = ComposeUploadedMedia(
            url: try #require(URL(string: "https://media.example/blob.jpg")),
            mimeType: "image/jpeg",
            width: 800,
            height: 600,
            sha256: String(repeating: "f", count: 64),
            altText: "A test image"
        )

        let prepared = ComposePublishTagBuilder(eventStore: store).prepare(
            request,
            uploadedMedia: [media]
        )
        guard case .reply(let content, let root, let parent, let tags) = prepared.input else {
            Issue.record("Expected reply publish input")
            return
        }
        #expect(root.eventID == reference.eventID)
        #expect(parent.eventID == reference.eventID)
        #expect(content.contains(media.url.absoluteString))
        #expect(tags.contains(["content-warning", "spoiler"]))
        #expect(tags.contains(["t", "Nostr"]))
        #expect(tags.contains(["p", mentionedPubkey]))
        #expect(tags.filter { $0.count >= 2 && $0[0] == "p" && $0[1] == reference.pubkey }.count == 1)
        #expect(tags.contains(["emoji", "wave", "https://emoji.example/wave.png"]))
        #expect(tags.contains { tag in
            tag.first == "imeta"
                && tag.contains("url https://media.example/blob.jpg")
                && tag.contains("dim 800x600")
                && tag.contains("alt A test image")
        })
        #expect(prepared.taggedUserReadRelays.contains("wss://read.example"))
    }

    @Test("Media-only compose is submit-capable and prevents reentrant submit")
    func mediaOnlyComposePreventsReentrantSubmit() async throws {
        let feature = ComposeFeatureModel(
            context: .post,
            isSubmitAvailable: true
        )
        feature.selectedMediaItems = [ComposeSelectedMedia(
            image: UIImage(),
            localURL: URL(fileURLWithPath: "/tmp/compose.jpg"),
            altText: nil
        )]
        #expect(feature.canSubmit)

        let gate = ComposeSubmitGate()
        let first = Task { @MainActor in
            await feature.submit { _, progress in
                progress(.signing)
                await gate.wait()
                progress(.queued(eventID: "event"))
                return true
            }
        }
        await Task.yield()
        #expect(!feature.canSubmit)
        let second = await feature.submit { _, _ in true }
        #expect(!second)
        await gate.resume()
        #expect(await first.value)
        #expect(feature.submissionState == .queued(eventID: "event"))
    }

    @Test("Draft v2 restores context, tags, and durable media metadata")
    func draftV2RoundTripsAllComposeState() throws {
        let store = try NostrEventStore.inMemory()
        let reference = NostrDraftEventReference(
            eventID: String(repeating: "3", count: 64),
            relayHint: "wss://relay.example",
            pubkey: String(repeating: "a", count: 64)
        )
        let draft = NostrDraftRecord(
            draftID: "draft",
            accountID: "account",
            context: .quote(target: reference),
            text: "caption",
            tags: [["emoji", "wave", "https://emoji.example/wave.png"]],
            media: [NostrDraftMediaReference(
                id: UUID().uuidString,
                kind: "photo",
                localPath: "/tmp/durable.jpg",
                mimeType: "image/jpeg",
                width: 1200,
                height: 800,
                altText: "description"
            )],
            updatedAt: 100
        )

        try store.saveDraft(draft)

        let otherAccountDraft = NostrDraftRecord(
            draftID: draft.draftID,
            accountID: "other-account",
            context: .post,
            text: "independent",
            updatedAt: 101
        )
        try store.saveDraft(otherAccountDraft)

        #expect(try store.drafts(accountID: "account") == [draft])
        #expect(try store.drafts(accountID: "other-account") == [otherAccountDraft])
    }

    private func event(
        pubkey: String,
        createdAt: Int,
        kind: Int = 1,
        tags: [[String]],
        content: String
    ) -> NostrEvent {
        let unsigned = NostrUnsignedEvent(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        return NostrEvent(
            id: unsigned.eventID,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "0", count: 128)
        )
    }
}

private actor ComposeSubmitGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
