# URL Attachment Classifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 投稿 `content` と NIP-92 `imeta` から抽出した URL を、Media / OGP / unsupported に一貫分類する Core 基盤を作り、既存の DB 保存・Timeline Row materialize に結線する。

**Architecture:** `NostrContentAttachmentClassifier` を `AstrenzaCore` に追加し、URL 抽出、direct media 拡張子判定、`imeta` 優先、OGP 候補抽出を一箇所に集約する。HEAD / Range GET や将来の imgproxy/cardyb 風外部 API は `NostrURLMetadataResolver` interface と分類モデルだけ先に定義し、MVP では既存の local OGP resolver と direct media 判定へ結線する。

**Tech Stack:** Swift, Swift Testing, GRDB-backed `NostrEventStore`, SwiftUI Timeline materializer, existing `NostrLinkPreviewResolver`.

---

## Research Decisions

- `Documents/Research/tweetbot_ivory_nostr_client_report.md` は、表示側では NIP-92 `imeta` を優先し、メディア主系は Blossom/NIP-B7、互換として NIP-96、ローカルストアは閲覧モデルそのものとして扱う方針を示している。
- MVP では外部 URL metadata/proxy API を必須にしない。理由は運用・privacy・キャッシュ設計の追加負荷が大きく、まず local-first DB と分類一貫性を直す方が Row mock 削減に効くため。
- ただし将来の外部 API は必要になる可能性が高い。リンク先へ端末から直接アクセスすると IP/User-Agent が漏れ、OGP 解決や画像最適化も端末ごとに重複するため、`NostrURLMetadataResolver` 抽象で差し替え可能にする。
- HEAD は `Content-Type` / `Content-Length` の軽量検査には有効だが、HEAD 非対応、誤った MIME、redirect、`application/octet-stream`、anti-bot に弱い。将来実装時は HEAD 失敗時に小さな Range GET fallback を使う。
- 今回は DB migration で `url_metadata` を増やさず、既存 `media_assets` / `link_previews` へ統一 classifier の結果を流す。次段階で `url_metadata` table と proxy result cache を追加する。

## File Structure

- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrContentAttachmentClassifier.swift`
  - `NostrExtractedURL`, `NostrClassifiedAttachment`, `NostrURLAttachmentKind`, `NostrURLMetadataResolver` を定義。
  - `attachments(from:)`, `mediaURLs(from:)`, `linkPreviewURLs(from:)` を提供。
  - `imeta` は media として優先し、content の同一 normalized URL を重複排除する。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
  - direct media extension/MIME 判定を classifier に委譲。
  - `mediaAssets(from:)` は classifier の media 結果を使う。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift`
  - `webURLs(in:)` は classifier の content URL parser と同じ trim/normalize 方針へ寄せる。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - `upsertLinkPreviewRequests` は classifier の `linkPreviewURLs(from:)` を使う。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Row materializer の `urls(from:)` / `isImageURL` 分岐を classifier へ寄せる。
  - content direct media fallback でも `MediaTile.url` を保持する。
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - classifier, media store, OGP request の Core tests を追加。
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Row materializer が direct video/image と OGP を classifier と同じ基準で扱うことを追加。

---

### Task 1: Core Classifier

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrContentAttachmentClassifier.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing classifier tests**

Add tests to `NostrCorePackageTests.swift`:

```swift
@Test("Nostr attachment classifier prioritizes NIP-92 imeta and dedupes content URLs")
func attachmentClassifierPrioritizesIMeta() throws {
    let event = nostrEvent(
        kind: 1,
        content: "photo https://cdn.example.test/photo.png read https://example.test/article",
        tags: [["imeta", "url https://cdn.example.test/photo.png", "m image/png", "dim 1200x800", "alt preview"]]
    )

    let attachments = NostrContentAttachmentClassifier.attachments(from: event)

    #expect(attachments.map(\.url.absoluteString) == [
        "https://cdn.example.test/photo.png",
        "https://example.test/article"
    ])
    #expect(attachments[0].kind == .media)
    #expect(attachments[0].source == .imeta(position: 0))
    #expect(attachments[0].mimeType == "image/png")
    #expect(attachments[0].width == 1200)
    #expect(attachments[0].height == 800)
    #expect(attachments[0].alt == "preview")
    #expect(attachments[1].kind == .linkPreview)
    #expect(attachments[1].source == .content(position: 1))
}

@Test("Nostr attachment classifier treats direct videos as media")
func attachmentClassifierTreatsDirectVideosAsMedia() throws {
    let event = nostrEvent(
        kind: 1,
        content: "clip https://video.example.test/movie.mp4 page https://example.test/watch"
    )

    let attachments = NostrContentAttachmentClassifier.attachments(from: event)

    #expect(attachments.map(\.kind) == [.media, .linkPreview])
    #expect(attachments[0].mimeType == "video/mp4")
    #expect(NostrContentAttachmentClassifier.mediaURLs(from: event).map(\.absoluteString) == [
        "https://video.example.test/movie.mp4"
    ])
    #expect(NostrContentAttachmentClassifier.linkPreviewURLs(from: event).map(\.absoluteString) == [
        "https://example.test/watch"
    ])
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests/attachmentClassifier
```

Expected: compile failure because `NostrContentAttachmentClassifier` does not exist.

- [ ] **Step 3: Implement classifier**

Create `NostrContentAttachmentClassifier.swift` with:

```swift
import Foundation

public enum NostrURLAttachmentKind: String, Codable, Sendable {
    case media
    case linkPreview
    case unsupported
}

public enum NostrURLAttachmentSource: Equatable, Sendable {
    case imeta(position: Int)
    case content(position: Int)
}

public struct NostrClassifiedAttachment: Equatable, Sendable {
    public let url: URL
    public let normalizedURL: String
    public let kind: NostrURLAttachmentKind
    public let source: NostrURLAttachmentSource
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let blurhash: String?
    public let alt: String?
    public let sha256: String?
}

public struct NostrURLMetadata: Equatable, Sendable {
    public let url: URL
    public let normalizedURL: String
    public let contentType: String?
    public let contentLength: Int?
    public let width: Int?
    public let height: Int?
    public let title: String?
    public let summary: String?
    public let siteName: String?
    public let imageURL: String?
}

public protocol NostrURLMetadataResolver: Sendable {
    func resolve(url: URL) async -> NostrURLMetadata
}

public enum NostrContentAttachmentClassifier {
    public static func attachments(from event: NostrEvent) -> [NostrClassifiedAttachment] {
        var seen = Set<String>()
        var output: [NostrClassifiedAttachment] = []

        for (position, tag) in event.tags.enumerated() {
            guard let attachment = attachment(fromIMetaTag: tag, position: position),
                  seen.insert(attachment.normalizedURL).inserted
            else { continue }
            output.append(attachment)
        }

        for (position, url) in webURLsWithPositions(in: event.content) {
            let normalized = NostrLinkParser.normalizedURLString(url)
            guard seen.insert(normalized).inserted else { continue }
            output.append(NostrClassifiedAttachment(
                url: url,
                normalizedURL: normalized,
                kind: isDirectMediaURL(url) ? .media : .linkPreview,
                source: .content(position: position),
                mimeType: mimeType(from: url),
                width: nil,
                height: nil,
                blurhash: nil,
                alt: nil,
                sha256: nil
            ))
        }

        return output
    }

    public static func mediaURLs(from event: NostrEvent) -> [URL] {
        attachments(from: event).filter { $0.kind == .media }.map(\.url)
    }

    public static func linkPreviewURLs(from event: NostrEvent) -> [URL] {
        attachments(from: event).filter { $0.kind == .linkPreview }.map(\.url)
    }

    public static func webURLs(in content: String) -> [URL] {
        webURLsWithPositions(in: content).map(\.url)
    }

    public static func isDirectMediaURL(_ url: URL) -> Bool {
        mimeType(from: url)?.hasPrefix("image/") == true || mimeType(from: url)?.hasPrefix("video/") == true
    }

    public static func mimeType(from url: URL) -> String? {
        let path = url.path.lowercased()
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return "image/jpeg" }
        if path.hasSuffix(".png") { return "image/png" }
        if path.hasSuffix(".gif") { return "image/gif" }
        if path.hasSuffix(".webp") { return "image/webp" }
        if path.hasSuffix(".heic") { return "image/heic" }
        if path.hasSuffix(".avif") { return "image/avif" }
        if path.hasSuffix(".mp4") { return "video/mp4" }
        if path.hasSuffix(".mov") { return "video/quicktime" }
        if path.hasSuffix(".m4v") { return "video/x-m4v" }
        if path.hasSuffix(".webm") { return "video/webm" }
        return nil
    }
}
```

The implementation also needs private helpers for `webURLsWithPositions`, `attachment(fromIMetaTag:)`, `fieldName`, `fieldValue`, and `parseDimensions`.

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests/attachmentClassifier
```

Expected: PASS.

---

### Task 2: Persist Media / OGP Requests Through Classifier

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add failing persistence tests**

Add:

```swift
@Test("Nostr event store treats direct video URLs as media not OGP")
func eventStoreDirectVideoIsMediaNotPreview() throws {
    let store = try NostrEventStore.inMemory()
    let event = nostrEvent(
        kind: 1,
        content: "clip https://cdn.example.test/movie.mp4 page https://example.test/article"
    )

    try store.save(events: [event])

    #expect(try store.mediaAssets(eventID: event.id).map(\.url) == ["https://cdn.example.test/movie.mp4"])
    let previews = try store.linkPreviews(urls: [
        try #require(URL(string: "https://cdn.example.test/movie.mp4")),
        try #require(URL(string: "https://example.test/article"))
    ])
    #expect(previews.keys.sorted() == ["https://example.test/article"])
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests/eventStoreDirectVideoIsMediaNotPreview
```

Expected: FAIL or current behavior mismatch if `.mp4` is not consistently excluded from OGP in all paths.

- [ ] **Step 3: Wire persistence to classifier**

Implementation requirements:

- `NostrLinkParser.webURLs(in:)` returns `NostrContentAttachmentClassifier.webURLs(in:)`.
- `NostrMediaParser.isDirectMediaURL(_:)` delegates to `NostrContentAttachmentClassifier.isDirectMediaURL(_:)`.
- `NostrMediaParser.mediaAssets(from:createdAt:)` builds assets from `NostrContentAttachmentClassifier.attachments(from:) where kind == .media`.
- `NostrEventStore.upsertLinkPreviewRequests` iterates `NostrContentAttachmentClassifier.linkPreviewURLs(from: event)`.

- [ ] **Step 4: Run Core media/link tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: PASS.

---

### Task 3: Timeline Materializer Uses Classifier

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing materializer test**

Add:

```swift
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
    } else {
        Issue.record("Expected direct media fallback gallery")
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AstrenzaTests/TimelineModelTests/nostrMaterializerDirectMediaFallbackKeepsURL
```

Expected: FAIL because fallback tiles currently drop `url` and Row-side classifier does not include video.

- [ ] **Step 3: Wire materializer to classifier**

Implementation requirements:

- Replace private `urls(from:)` and `isImageURL(_:)` logic with `NostrContentAttachmentClassifier.attachments(from:)`.
- Build `imageURLs`/`mediaURLs` from classified `.media` attachments, not local suffix logic.
- Build `linkURLs` from classified `.linkPreview` attachments.
- In fallback direct media tiles, set `url: attachment.url`.
- Use `symbolName: "play.rectangle"` when MIME starts with `video/`; otherwise `photo`.

- [ ] **Step 4: Run targeted Timeline test**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

---

### Task 4: Verification and Commit

**Files:**
- All modified files.

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git -c core.fsmonitor=false diff --check
```

Expected: no output.

- [ ] **Step 2: Run full Core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: PASS.

- [ ] **Step 3: Run full iOS tests**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-07-url-attachment-classifier.md \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrContentAttachmentClassifier.swift \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift \
  Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift \
  Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift \
  Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Unify URL attachment classification"
```

Expected: one commit with classifier, wiring, tests, and this plan.

---

## Follow-Up Plan

- Add `url_metadata` table with classification cache, HEAD result, Range GET fallback result, dimensions, TTL, and proxy URL fields.
- Add `LocalURLMetadataResolver` that performs HEAD and small Range GET fallback.
- Add `ProxyURLMetadataResolver` for a future Astrenza metadata API backed by imgproxy/Cloudflare Images and cardyb-like OGP crawling.
- Render OGP `imageURL` using the same media image loader/proxy path.
- Render real remote media images instead of gradient placeholder tiles.

