# Rich Row Content Materialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first rich content materialization layer for timeline rows so media URLs, OGP URLs, Nostr references, custom emoji, and fallback clickable links are interpreted consistently from event JSON content and tags.

**Architecture:** Keep `NostrContentAttachmentClassifier` responsible for URL media/OGP classification, and add a separate `NostrRichContentParser` for visible row tokens. The parser emits UI-independent tokens; the app materializer stores those tokens on `TimelinePost`, while SwiftUI row rendering decides navigation through injected callbacks.

**Tech Stack:** Swift 6, Swift Testing, GRDB-backed AstrenzaCore models, SwiftUI timeline rows, existing `NostrNIP19`, `NostrContentAttachmentClassifier`, `NostrTimelineMaterializer`.

---

## Research Alignment

- `Documents/Research/tweetbot_ivory_nostr_client_report.md` recommends separating normalized event storage from timeline materialization; rich row parsing belongs in materialization, not raw view code.
- The same report treats NIP-92 media as the primary inline media path; URLs promoted to gallery media should be hidden from plain body text to avoid duplicate presentation.
- URL handling and deep links are P0 in `tweetbot_ivory_nostr_client_research.md`; URLs that are not promoted to media/OGP cards must remain clickable.
- NIP-30 custom emoji is listed as open backlog, but NIP-30 itself says kind:1 content should be emojified when matching `emoji` tags exist. Implementing the token parser now keeps the row pipeline ready without needing full remote emoji set sync.
- `event_tags(tag_name, tag_value)` are important for `#e/#p/#a` resolution; NIP-19 `npub/nprofile/nevent/naddr` references should become dependency hints and clickable tokens.

## File Responsibilities

- Create `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRichContentParser.swift`
  - Defines `NostrRichContent`, `NostrRichContentToken`, `NostrRichContentReference`, custom emoji parsing, NIP-19 token extraction, media URL removal, and clickable fallback URL tokenization.
- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift`
  - Extend `NostrNIP19` with TLV decoding for `nprofile`, `nevent`, and `naddr`.
- Modify `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Add tests for NIP-19 TLV decoding, media URL removal, OGP fallback clickable URL retention, `npub/nprofile` profile mention tokens, `nevent` event reference tokens, and NIP-30 custom emoji tokens.
- Modify `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
  - Add optional `richBody: NostrRichContent?` to `TimelinePost` while preserving all existing initializers.
- Modify `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Use `NostrRichContentParser.parse(event:attachments:promotedLinkURLs:)` while materializing posts; pass rich content into `TimelinePost`; use rich display text for body presentation length decisions.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineReplyContextView.swift`
  - Add a rich body renderer that supports inline text/custom emoji fallback, clickable web URLs, and clickable Nostr profile/event references.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRow.swift`
  - Render `post.richBody` when available and add callbacks for opening profile references and event references.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Timeline/PostDetailView.swift`
  - Use rich body display text initially, then rich renderer when callbacks are available.
- Modify `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add tests proving materializer removes promoted media URL from body, keeps non-promoted URL available, removes quoted NIP-19 note/nevent references when a quote card exists, and emits profile mention tokens.

## Task 1: NIP-19 TLV Decode

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add failing tests**

Add tests that decode the NIP-19 examples from `Documents/Reference/nips/19.md` and a locally encoded `nevent` test fixture. Expected behavior:

```swift
@Test("NIP-19 nprofile decodes TLV pubkey and relay hints")
func nip19NProfileDecodesTLV() throws {
    let profile = try NostrNIP19.profileReference(
        from: "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
    )
    #expect(profile.pubkey == "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
    #expect(profile.relays == ["wss://r.x.com", "wss://djbas.sadkb.com"])
}

@Test("NIP-19 nevent decodes TLV event id author kind and relay hints")
func nip19NEventDecodesTLV() throws {
    let eventID = String(repeating: "a", count: 64)
    let author = String(repeating: "b", count: 64)
    let encoded = try NostrNIP19.encodeEventReference(
        eventID: eventID,
        relays: ["wss://relay.example"],
        author: author,
        kind: 1
    )
    let decoded = try NostrNIP19.eventReference(from: encoded)
    #expect(decoded.eventID == eventID)
    #expect(decoded.relays == ["wss://relay.example"])
    #expect(decoded.author == author)
    #expect(decoded.kind == 1)
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter "NIP-19"
```

Expected: fails because `profileReference`, `eventReference`, and `encodeEventReference` do not exist.

- [ ] **Step 3: Implement TLV support**

Add public structs:

```swift
public struct NostrNIP19ProfileReference: Equatable, Sendable {
    public let pubkey: String
    public let relays: [String]
}

public struct NostrNIP19EventReference: Equatable, Sendable {
    public let eventID: String
    public let relays: [String]
    public let author: String?
    public let kind: Int?
}
```

Implement:

```swift
public static func profileReference(from input: String) throws -> NostrNIP19ProfileReference
public static func eventReference(from input: String) throws -> NostrNIP19EventReference
public static func encodeEventReference(eventID: String, relays: [String], author: String?, kind: Int?) throws -> String
```

Decode TLV by stripping optional `nostr:`, Bech32 decoding, iterating type-length-value records, ignoring unknown types, and validating type `0` length for `nprofile`/`nevent` as 32 bytes. Encode helper is test-only useful but public is acceptable because it can later support share sheets.

- [ ] **Step 4: Run tests and confirm pass**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter "NIP-19"
```

Expected: all NIP-19 tests pass.

## Task 2: Core Rich Content Parser

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRichContentParser.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add failing parser tests**

Add tests:

```swift
@Test("Rich content removes promoted media URLs but keeps fallback clickable URLs")
func richContentRemovesMediaAndKeepsClickableURLs() throws {
    let event = nostrEvent(
        kind: 1,
        content: "photo https://cdn.example.test/pic.png read https://example.test/page",
        tags: [["imeta", "url https://cdn.example.test/pic.png", "m image/png", "alt image alt"]]
    )
    let attachments = NostrContentAttachmentClassifier.attachments(from: event)
    let rich = NostrRichContentParser.parse(event: event, attachments: attachments, promotedLinkURLs: [])
    #expect(rich.displayText == "photo read https://example.test/page")
    #expect(rich.tokens.contains(.url(url: try #require(URL(string: "https://example.test/page")))))
    #expect(rich.tokens.contains { token in
        if case .url(let url) = token { return url.absoluteString == "https://cdn.example.test/pic.png" }
        return false
    } == false)
}

@Test("Rich content turns tagged custom emoji shortcode into token")
func richContentParsesCustomEmoji() throws {
    let event = nostrEvent(
        kind: 1,
        content: "hello :astrenza:",
        tags: [["emoji", "astrenza", "https://emoji.example.test/astrenza.png"]]
    )
    let rich = NostrRichContentParser.parse(event: event, attachments: [], promotedLinkURLs: [])
    #expect(rich.tokens.contains(.customEmoji(shortcode: "astrenza", url: try #require(URL(string: "https://emoji.example.test/astrenza.png")))))
}
```

- [ ] **Step 2: Implement parser types**

Create:

```swift
public struct NostrRichContent: Equatable, Sendable {
    public let displayText: String
    public let tokens: [NostrRichContentToken]
    public let references: [NostrRichContentReference]
}

public enum NostrRichContentToken: Equatable, Sendable {
    case text(String)
    case url(url: URL)
    case profile(pubkey: String, relays: [String], display: String)
    case event(eventID: String, relays: [String], author: String?, kind: Int?, display: String)
    case customEmoji(shortcode: String, url: URL)
}

public enum NostrRichContentReference: Equatable, Sendable {
    case profile(pubkey: String, relays: [String])
    case event(eventID: String, relays: [String], author: String?, kind: Int?)
}
```

Parser rules:

- Split on whitespace for MVP to match existing URL parser.
- Remove tokens whose normalized URL is a `.media` attachment.
- Remove tokens whose normalized URL is in `promotedLinkURLs`.
- Keep non-promoted linkPreview/unsupported URLs as `.url`.
- Convert `npub`/`nostr:npub` to `.profile`.
- Convert `nprofile`/`nostr:nprofile` to `.profile`.
- Convert `note`/`nostr:note` and `nevent`/`nostr:nevent` to `.event`.
- Convert `:shortcode:` to `.customEmoji` only when an `emoji` tag exists.
- Unknown/invalid tokens remain `.text`.

- [ ] **Step 3: Run parser tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter "Rich content"
```

Expected: parser tests pass.

## Task 3: Timeline Materializer Integration

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing app tests**

Add tests:

```swift
@Test("Nostr materializer removes promoted media URL from rich body")
func nostrMaterializerRemovesPromotedMediaURLFromRichBody() throws {
    let author = String(repeating: "a", count: 64)
    let note = timelineEvent(
        idSeed: "rich-media",
        pubkey: author,
        createdAt: 120,
        content: "photo https://cdn.example.test/pic.png read https://example.test/page",
        tags: [["imeta", "url https://cdn.example.test/pic.png", "m image/png"]]
    )
    let post = try #require(NostrTimelineMaterializer.posts(noteEvents: [note], metadataEvents: [], followedPubkeys: [author]).first)
    #expect(post.body == "photo read https://example.test/page")
    #expect(post.richBody?.tokens.contains { token in
        if case .url(let url) = token { return url.absoluteString == "https://example.test/page" }
        return false
    } == true)
}
```

- [ ] **Step 2: Add `richBody` to TimelinePost**

Add `let richBody: NostrRichContent?` to `TimelinePost`, defaulting to `nil` in both initializers.

- [ ] **Step 3: Materialize rich body**

In `NostrTimelineMaterializer.post(...)`:

```swift
let promotedLinkURLs = mediaPromotedLinkURLs(...)
let richBody = event.map {
    NostrRichContentParser.parse(event: $0, attachments: attachments, promotedLinkURLs: promotedLinkURLs)
}
let body = richBody?.displayText ?? item.body
```

Use `body` for `TimelinePost.body` and `bodyPresentation`.

- [ ] **Step 4: Run TimelineModelTests**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: all TimelineModelTests pass.

## Task 4: Row Rendering Hooks

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineReplyContextView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRow.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [ ] **Step 1: Add `TimelineRichBodyText`**

Render tokens in a compact horizontal wrapping fallback. For MVP, use a `Text` backed by `AttributedString` with `.link` attributes:

- `.url` links to original URL.
- `.profile` links to `astrenza://profile/<pubkey>`.
- `.event` links to `astrenza://event/<eventID>`.
- `.customEmoji` renders as `:shortcode:` text until inline image layout is added.

- [ ] **Step 2: Use rich body in row**

In `TimelinePostRow.textContent`, render `TimelineRichBodyText(richBody:)` when `post.richBody != nil`. Attach an `OpenURLAction` that routes external URLs to `onOpenURL`, profile URLs to `onOpenProfilePubkey`, and event URLs to `onOpenEventID`.

- [ ] **Step 3: Thread callbacks through feed/home**

Add callbacks:

```swift
let onOpenProfilePubkey: (String) -> Void
let onOpenEventID: (String) -> Void
```

For profile, open User Detail using the existing user detail route. For event, open Post Detail if cached; otherwise no-op for MVP.

## Task 5: Verification and Commit

**Files:**
- All changed files.

- [ ] **Step 1: Run diff check**

```bash
git -c core.fsmonitor=false diff --check
```

- [ ] **Step 2: Run Core tests**

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

- [ ] **Step 3: Run iOS tests**

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-rich-row-content-materialization.md \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift \
  Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRichContentParser.swift \
  Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift \
  Astrenza/Sources/AstrenzaApp/TimelineModels.swift \
  Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift \
  Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineReplyContextView.swift \
  Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRow.swift \
  Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift \
  Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift \
  Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Materialize rich timeline row content"
```

---

## Self-Review

- Spec coverage: media URL removal, OGP fallback clickable URL retention, NIP-19 `npub/nprofile/nevent`, custom emoji, and Research-aligned materialization separation are covered.
- Placeholder scan: No TODO/TBD placeholders remain; Task 4 intentionally limits inline custom emoji image rendering to shortcode text because the goal is parser and clickable routing foundation.
- Type consistency: `NostrRichContent` and `NostrRichContentToken` are defined in Task 2 and referenced by app model/rendering tasks.
