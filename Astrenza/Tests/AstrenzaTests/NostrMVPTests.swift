import CryptoKit
import Foundation
import Testing
import AstrenzaCore
@testable import Astrenza

@Suite("Nostr MVP")
struct NostrMVPTests {
    @Test("Home materializer turns kind:1 events into timeline entries")
    func materializer() throws {
        let pubkey = String(repeating: "d", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "hello nostr")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"display_name":"Reader","nip05":"reader@example.com"}"#
        )

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey]
        )
        let post = try #require(entries.compactMap(\.post).first)

        #expect(post.id == note.id)
        #expect(post.author.primaryText == "Reader")
        #expect(post.author.secondaryText == "reader@example.com")
        #expect(post.body == "hello nostr")
    }

    @Test("kind:0 picture URL is resolved into avatar image URL")
    func metadataPictureMaterializer() throws {
        let pubkey = String(repeating: "e", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "hello image")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"name":"Image User","picture":"https://cdn.example.test/avatar.png"}"#
        )

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey]
        )
        let post = try #require(entries.compactMap(\.post).first)

        #expect(post.avatar.imageURL?.absoluteString == "https://cdn.example.test/avatar.png")
        #expect(post.avatar.pictureState == .resolved)
    }

    @Test("kind:0 invalid picture URL falls back to missing placeholder")
    func metadataInvalidPictureFallback() throws {
        let pubkey = String(repeating: "f", count: 64)
        let note = nostrEvent(kind: 1, pubkey: pubkey, content: "hello fallback")
        let metadata = nostrEvent(
            kind: 0,
            pubkey: pubkey,
            content: #"{"name":"Fallback User","picture":"file:///private/avatar.png"}"#
        )

        let entries = NostrTimelineMaterializer.entries(
            noteEvents: [note],
            metadataEvents: [metadata],
            followedPubkeys: [pubkey]
        )
        let post = try #require(entries.compactMap(\.post).first)

        #expect(post.avatar.imageURL == nil)
        #expect(post.avatar.pictureState == .missing)
    }

    @Test("Nostr image cache stores and reads image data by URL")
    func imageCacheStoresImageData() throws {
        let urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let cache = NostrImageCache(urlCache: urlCache)
        let url = try #require(URL(string: "https://cdn.example.test/avatar.png"))
        let request = cache.request(for: url, cachePolicy: .returnCacheDataElseLoad)
        let response = try #require(URLResponse(url: url, mimeType: "image/png", expectedContentLength: 68, textEncodingName: nil))
        let data = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))

        cache.store(data: data, response: response, for: request)

        #expect(cache.cachedImageData(for: url) == data)
        #expect(cache.cachedImage(for: url) != nil)
    }

    private func nostrEvent(
        kind: Int,
        pubkey: String = String(repeating: "a", count: 64),
        content: String = "",
        tags: [[String]] = []
    ) -> NostrEvent {
        let createdAt = 1_800_000_000
        let canonical = NostrCanonicalJSON.serialize(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        let digest = SHA256Digest.hex(for: canonical)
        return NostrEvent(
            id: digest,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: String(repeating: "1", count: 128)
        )
    }
}

private enum SHA256Digest {
    static func hex(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
