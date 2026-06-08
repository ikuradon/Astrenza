# RichContent Connection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RichContent の profile/event/hashtag/custom emoji/URL/引用/返信プレビューを、表示・遅延取得・画面遷移に接続する。

**Architecture:** Core の `NostrRichContentParser` は token 化の責務を維持し、App 側 projection で metadata/event cache を使った表示名解決を追加する。本文中の RichContent references は `NostrEventDependencies` に取り込み、runtime backward/profile dependency fetch に流す。UI では `astrenza://profile`, `astrenza://event`, `astrenza://hashtag` を明示的に処理し、既存 `NavigationStack` に乗せる。

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, GRDB-backed `NostrEventStore`, `AstrenzaCore`, Xcode iOS Simulator.

---

## Scope

対象は直前に列挙した 1-10:

1. `nostr:npub` / `nostr:nprofile` の表示名解決
2. `RichContent.references` の dependency fetch 接続
3. inline `nostr:note/nevent` tap の対象投稿遷移
4. `nprofile` / `nevent` relay hints の保持
5. hashtag tap の接続点
6. `#[0]` tag-index mention の profile/event token 化
7. URL trailing punctuation の保持
8. ReplyContext preview の richContent 化
9. QuotedPostCard 内 richContent tap の接続
10. Quote 内 media/OGP URL の本文除去

## Files

- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRichContentParser.swift`
  - `NostrRichContent` に表示 override と token display helper を追加
  - `#[n]` tag-index mention parse と URL trailing punctuation restore を追加
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayRuntimeModels.swift`
  - `NostrEventDependencies.extract(from:)` に RichContent references を取り込む
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineContentProjection.swift`
  - rich body を projection 後に解決できる補助を使う
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelinePostProjection.swift`
  - profile display map / event display map を作り、`NostrRichContent` に適用
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineQuoteProjection.swift`
  - quote 内も `NostrTimelineContentProjection` を使って media/OGP/quote URL を除去
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineReplyProjection.swift`
  - reply parent preview に richContent を持たせる
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
  - `TimelineReplyContext.richContent` を追加
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineReplyContextView.swift`
  - token 表示 helper と richContent link URL helper を使う
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostContentView.swift`
  - quoted card に rich URL handler を渡す
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRowSupplementaryViews.swift`
  - `QuotedPostCard` 内 rich body に `openURL` handler を通す
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRow.swift`
  - profile/event/hashtag URL routing を修正
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/PostDetailView.swift`
  - profile/event/hashtag URL routing を修正
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

## Tasks

### Task 1: Core RichContent display override and parser edge cases

- [ ] Add failing tests:
  - valid profile tokens can render with display names
  - URL trailing punctuation remains visible after URL token
  - `#[0]` resolves to profile/event references from tags
- [ ] Run:
  - `swift test --package-path Packages/AstrenzaCore --filter RichContent`
  - Expected: new tests fail.
- [ ] Implement:
  - `NostrRichContent.displayText(for:)`
  - `NostrRichContent.resolving(profileDisplayNamesByPubkey:eventDisplayTextByID:)`
  - URL branch appends trailing punctuation
  - tag-index mention parser maps `#[n]` to `p/e/q/a` tag token where possible
- [ ] Run:
  - `swift test --package-path Packages/AstrenzaCore --filter RichContent`
  - Expected: pass.

### Task 2: RichContent references into dependency extraction

- [ ] Add failing Core tests:
  - content `nostr:npub...` adds profile pubkey dependency
  - content `nostr:nevent...` adds source event dependency and relay hints
- [ ] Run:
  - `swift test --package-path Packages/AstrenzaCore --filter NostrEventDependencies`
  - Expected: new tests fail.
- [ ] Implement:
  - `NostrEventDependencies.extract(from:)` parses `NostrRichContentParser.parse(event:)`
  - `.profile` references append profile pubkeys/hints
  - `.event` references append source event IDs/hints
- [ ] Run:
  - `swift test --package-path Packages/AstrenzaCore --filter NostrEventDependencies`
  - Expected: pass.

### Task 3: App projection display names for inline profiles/events

- [ ] Add failing App tests:
  - materialized post body renders `nostr:npub...` as `@Display Name`
  - UI rich body token display helper also uses `@Display Name`
  - fallback remains `@npub:<hex prefix>`
- [ ] Run:
  - `xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests`
  - Expected: new tests fail.
- [ ] Implement:
  - `NostrTimelinePostProjection` resolves profile display names from metadata/nip05/follow state
  - `NostrTimelineQuoteProjection` applies the same display map
  - UI uses `richContent.displayText(for:)` instead of `token.displayText`
- [ ] Run the same App test command.
  - Expected: pass.

### Task 4: Inline profile/event/hashtag routing

- [ ] Add failing App tests for route helpers if possible; otherwise add focused model-level tests for placeholder posts:
  - event URL opens placeholder with `id == eventID`
  - profile URL opens placeholder profile with `author.pubkey == pubkey`
  - hashtag URL returns handled without browser fallback
- [ ] Implement:
  - Row `astrenza://event/<id>` opens `TimelinePost(id: id, ...)`
  - Detail `astrenza://event/<id>` opens the same placeholder
  - Hashtag handler switches to a contained action (`.handled`) and leaves future Explore binding point
  - Rich link URLs preserve relay hints in query for `nprofile/nevent`
- [ ] Run `xcodebuild ... -only-testing:AstrenzaTests/TimelineModelTests`.

### Task 5: Quoted card rich interactions and quote content cleanup

- [ ] Add failing App tests:
  - quote body removes promoted media URL
  - quote body removes promoted OGP URL
  - quote body keeps custom emoji token
- [ ] Implement:
  - `NostrTimelineQuoteProjection` uses `NostrTimelineContentProjection(event:)`
  - `QuotedPostCard` receives `onOpenRichURL`
  - `TimelinePostContentView` forwards rich URL handler into quoted card
- [ ] Run `xcodebuild ... -only-testing:AstrenzaTests/TimelineModelTests`.

### Task 6: ReplyContext rich preview

- [ ] Add failing App test:
  - reply context parent content with custom emoji or profile ref carries `richContent`
- [ ] Implement:
  - `TimelineReplyContext` adds optional `richContent`
  - `NostrTimelineReplyProjection` parses parent content
  - Existing mock/default initializers keep `nil` by default
- [ ] Run `xcodebuild ... -only-testing:AstrenzaTests/TimelineModelTests`.

### Task 7: Final verification

- [ ] Run Core:
  - `swift test --package-path Packages/AstrenzaCore`
- [ ] Run App:
  - `xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests`
- [ ] Run:
  - `git diff --check`
- [ ] Summarize remaining intentional limitations:
  - hashtag Explore screen is still future UI, but handler no longer leaks to browser
  - relay hints are preserved in links and dependency extraction; explicit UI fetch with hint may be deepened later

## Expected Behavior

- `nostr:npub... test nostr:nprofile...` renders as `@Name test @Name2` when metadata exists, otherwise keeps a stable npub fallback.
- RichContent references cause profile/source dependency fetches, so inline users/events can resolve after receive.
- Tapping inline profiles opens User Detail.
- Tapping inline events opens the referenced Post Detail if cached, or a placeholder detail route if still pending.
- Hashtags are clickable and handled without opening an invalid browser URL.
- Custom emoji remains image-backed.
- Quote cards and reply previews stop leaking promoted media/OGP URLs into text.
