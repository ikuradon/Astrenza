# Research-Based Nostr MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Documents/Research` の結論に沿って、現在の GRDB 正規化ストアを実 Nostr MVP の読み書き体験へ拡張する。

**Architecture:** 既存の `NostrEventStore` を canonical event store とし、UI 用の `TimelinePost` は materializer で生成する。Research が推奨する「正規化 event store + timeline_entries + relay_profiles + sync_cursors + outbox/list/media/draft」の二層構成へ段階的に寄せる。

**Tech Stack:** SwiftUI, Swift Testing, GRDB, SQLite, URLSessionWebSocketTask, xcodegen, XcodeBuildMCP, Maestro mock route.

---

## 現状

実装済み:
- `events`, `event_tags`, `replaceable_heads`, `timeline_entries`, `sync_cursors`, `relay_profiles`, `event_sources`, `deletion_tombstones`, `timeline_state`
- 実 npub read-only login
- NIP-65 relay list 解決
- kind:3 follow list 解決
- kind:0 自動解決と画像キャッシュ
- NIP-05 解決とキャッシュ
- NIP-77 を含む gap/backfill 文脈
- Home TL の DB 保存/復元
- Detail/Profile の DB query 化
- UserDefaults timeline snapshot 撤去

未実装または mock 寄り:
- `addressable_heads`
- `outbox_events`
- `drafts`
- `lists`, `list_items`
- `media_assets`
- NIP-09 tombstone の実 UI 反映
- NIP-40 expiration の非表示処理
- NIP-36 content warning の実 tag 解釈
- NIP-92 `imeta` media materialize
- URL/OGP の実 resolver/cache
- NIP-51 list/mute/bookmark/search relay
- NIP-42 AUTH を含む relay reconnect/failover
- 投稿/返信/リアクション/削除の publish outbox
- リレーごとの実通信結果に基づく `sync_cursors` 更新
- EOSE / reconnect / timeout / partial failure の履歴保存
- リレー状態シートの DB 履歴表示
- reply / repost / quote / deleted / sensitive / media / OGP の実 tag materialize
- アプリ再起動相当の store 再生成テスト
- 10,000件 timeline の復元性能テスト
- Gap補完後の anchor 維持テスト

## 方針

1. Home TL を最優先に保つ。
2. UI は既存 mock component を再利用し、mock data ではなく event tags から materialize する。
3. 各 Phase は Swift Testing -> xcodegen -> Simulator test -> commit の順で閉じる。
4. P0 は「読める、戻れる、欠けが説明できる、誤表示しない」まで。
5. 投稿系は outbox を先に作り、relay 送信は retry/partial success 前提で実装する。
6. 大きな機能追加の前に、永続化・復元・大量TL・Gap anchor の回帰テストを先に置く。

## Phase 7.5: Persistence Regression Harness

**目的:** これ以降の relay/history/materialize 変更で位置復元や大量TLが壊れないよう、Research が重視する永続化テストを先に固定する。

**Files:**
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineRestoreModels.swift` if needed

- [ ] **Step 1: Add store recreation test**

Use a temporary SQLite file, create `NostrEventStore`, save `NostrHomeTimelineState`, release the instance, create a second `NostrEventStore` from the same file, and verify:
- relays are restored
- followed pubkeys are restored from kind:3
- kind:10002 relay list is restored
- timeline event order is restored

- [ ] **Step 2: Add 10,000 timeline restore test**

Save 10,000 kind:1 events and timeline entries, then restore with a bounded limit. Verify:
- restore returns newest-first order
- restore does not need to load all events when limit is small
- test stays deterministic and suitable for CI

- [ ] **Step 3: Add Gap anchor preservation test**

Use existing `TimelineViewportResolver` / `TimelineGapReplacement` model tests to verify:
- upward fill keeps the lower post visually fixed
- downward fill keeps the upper post visually fixed
- inserted gap height delta is included in restored offset

- [ ] **Step 4: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Add persistence regression coverage"`

## Phase 8: Event Interpretation Hardening

**目的:** Research の競合解決原則を DB と materializer に反映し、reply / repost / quote / deleted / sensitive の第一段を mock ではなく実イベントから表示する。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineDeletedRow.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add tests for deletion and expiration**

Add tests that save a kind:1 note, a kind:5 deletion event by the same pubkey, and an expiration-tagged event. Expected behavior:
- deleted event appears as `TimelineFeedEntry.deleted`
- deletion by another pubkey is ignored
- expired event is excluded from Home TL materialization

Run: `swift test` in `Packages/AstrenzaCore`
Expected: FAIL before implementation.

- [ ] **Step 2: Implement tombstone application**

Add store API that reads valid `deletion_tombstones` and marks target events as `deleted_at`, only when deletion author matches target author.

- [ ] **Step 3: Filter expired events**

Ensure `timelineEvents`, `events(kind:authors:)`, and `eventsReferencing` exclude events where `expires_at <= now`, while keeping raw rows for audit/debug.

- [ ] **Step 4: Materialize NIP-36**

Parse `["content-warning"]` and `["content-warning", reason]` tags into `TimelineContentWarning`.

- [ ] **Step 5: Materialize reply/repost/quote shell**

Parse:
- NIP-10 root/reply markers into reply context
- kind:6 repost into `TimelineRepostAttribution` when referenced event is cached
- kind:1 quote tags or quoted event references into `QuotedTimelinePost` when cached

If referenced event is missing, keep the current post visible and expose a muted missing-context placeholder.

- [ ] **Step 6: Refactor conversion boundary**

Keep `TimelinePost` as the UI model, but move event-tag interpretation into a focused materializer API so `HomeTimelineStore`, `PostDetailView`, and `UserDetailView` do not duplicate tag parsing.

- [ ] **Step 7: Verify and commit**

Run:
- `swift test` in `Packages/AstrenzaCore`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Apply deletion expiration and content warning semantics"`

## Phase 9: Addressable Events and NIP-51 Lists

**目的:** Research が重要視する list/filter/mute の土台を作り、Home の Lists tab を mock から DB 由来へ移す。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrListModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTypes.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add schema**

Add:
- `addressable_heads(kind, pubkey, d_tag, event_id, created_at, updated_at)`
- `lists(list_id, account_id, kind, pubkey, d_tag, event_id, title, visibility, updated_at)`
- `list_items(list_id, item_key, item_type, value, relay_hint, visibility, position)`

- [ ] **Step 2: Add addressable head tests**

Save two kind:30000 events with same `(kind, pubkey, d)` and verify newest wins, tie breaks by lower event id.

- [ ] **Step 3: Parse NIP-51 public items**

Support at minimum:
- kind `30000` follow sets
- kind `30001` generic sets if needed later
- kind `30002` relay sets
- kind `30003` bookmark sets
- kind `10000` mute list
- kind `10007` search relays

Private encrypted content is stored raw for now; do not decrypt in this Phase.

- [ ] **Step 4: Wire Lists tab**

For live account:
- show saved NIP-51 follow/bookmark list names
- selecting a list uses `timeline_entries` or event query filtered by list pubkeys/bookmarks
- empty state explains that list events are not cached yet

- [ ] **Step 5: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Add addressable list storage"`

## Phase 10: Media and Link Materialization

**目的:** Timeline Row の media/OGP を実イベントから生成し、NIP-92 `imeta` と URL 抽出を DB/cache に載せる。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkExtractor.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineAttachments.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add media asset schema**

Add `media_assets(asset_id, event_id, url, mime_type, blurhash, width, height, alt, sha256, status, local_path, created_at)`.

- [ ] **Step 2: Parse NIP-92 imeta**

Map `imeta` tags to `TimelineMedia.gallery` tiles:
- `url`
- `m`
- `dim`
- `blurhash`
- `alt`
- `x` or `ox` hash if present

- [ ] **Step 3: Extract URLs for unresolved OGP**

For content URLs without `imeta`, produce existing unresolved link preview UI first. Do not fetch external OGP in this Phase unless cache API already exists.

- [ ] **Step 4: Add OGP cache boundary**

Introduce a small cache model for resolved/unresolved OGP:
- resolved preview maps to existing `LinkPreview`
- unresolved preview maps to existing `UnresolvedLinkPreview`
- failed or untrusted URL can use the existing tap-to-inspect flow

- [ ] **Step 5: Keep row height predictable**

All live media galleries should use the same fixed gallery height policy already chosen in mock UI.

- [ ] **Step 6: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Materialize media and links from Nostr events"`

## Phase 11: Outbox and Publish MVP

**目的:** 投稿/返信/削除を relay へ送るための永続 outbox を作る。Research の「部分成功UI」「retry queue」を先に成立させる。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrOutboxModels.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrPublisher.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add outbox schema**

Add:
- `outbox_events(local_id, account_id, event_id, event_json, status, created_at, next_retry_at, last_error)`
- `outbox_relays(local_id, relay_url, status, last_attempt_at, ok_message)`

- [ ] **Step 2: Build unsigned-to-signed pipeline boundary**

Define publisher inputs for:
- new post
- reply with NIP-10 tags
- deletion request kind:5

Signer can be local/mock initially, but API must allow NIP-46 later.

- [ ] **Step 3: Resolve relay destinations**

Use:
- author write relays from kind:10002
- tagged users' read relays if cached
- manual fallback relays from settings

- [ ] **Step 4: Wire Compose Post button**

Post button writes to outbox, immediately inserts optimistic event into DB/timeline, and shows partial/pending status.

- [ ] **Step 5: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Add persistent publish outbox"`

## Phase 12: Relay Manager Durability

**目的:** Relay status sheet/settings を live DB 状態へ寄せ、NIP-11/42/65 と reconnect/failover を説明可能にする。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayClient.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayInformation.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelayStatusSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelaySettingsView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Persist relay runtime stats**

Extend `relay_profiles` or add `relay_runtime_stats` for:
- last connected
- last EOSE
- last error
- auth required
- payment required
- reconnect count
- average EOSE latency
- timeout count
- partial failure count
- last partial failure reason

- [ ] **Step 2: Handle NIP-42 AUTH state**

Parse `AUTH` challenge and expose a `.authRequired(challenge:)` state. Signing/sending AUTH can remain behind publisher/signer boundary if local signing is not ready.

- [ ] **Step 3: Persist lifecycle events**

Store relay lifecycle events for:
- EOSE
- reconnect
- timeout
- partial failure
- auth required
- payment required

Keep this bounded by pruning old rows per relay, so the sheet can show recent history without unbounded growth.

- [ ] **Step 4: Update sync cursors per relay**

Write newest/oldest cursor per relay from actual fetched results rather than timeline aggregate only.

- [ ] **Step 5: Wire sheets**

Relay status sheet reads DB state; settings sheet edits per-account relay preferences and queues NIP-65 publish through outbox when publishing is available.

- [ ] **Step 6: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Persist relay runtime state"`

## Phase 13: Drafts and Compose Persistence

**目的:** 現在の `@AppStorage` mock draft を GRDB の `drafts` に移し、投稿 outbox と分離する。

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrDraftModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeDraftViews.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: Maestro compose flow if present

- [ ] **Step 1: Add draft schema**

Add `drafts(draft_id, account_id, kind, parent_event_id, text, content_warning, media_json, updated_at)`.

- [ ] **Step 2: Move draft list to DB**

Compose gear menu should show `Drafts (n)` from DB.

- [ ] **Step 3: Save/ignore close behavior**

Close sheet with text/media should offer:
- Ignore Draft
- Save Draft
- Cancel

After Ignore/Save, sheet closes.

- [ ] **Step 4: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`
- Maestro mock compose flow

Commit:
`git commit -m "Persist compose drafts in event store"`

## Phase 14: Filters, Mutes, and Trust UI

**目的:** Tapbots/Ivory 的なノイズ制御を NIP-51 と local rules で成立させる。

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Implement local filter engine**

Support:
- muted pubkey
- muted hashtag
- keyword
- regex
- muted kind
- relay mute
- temporary mute expiry

- [ ] **Step 2: Apply filters in materializer**

Materializer should produce hidden/collapsed state rather than deleting records blindly, so active filter state can be explained.

- [ ] **Step 3: Add active filter UI**

When a timeline is filtered, show compact active filter indicator with one-tap clear.

- [ ] **Step 4: Verify and commit**

Run:
- `swift test`
- `xcodegen generate`
- `test_sim`

Commit:
`git commit -m "Apply Nostr mute and filter rules"`

## Later Backlog

P1:
- NIP-46 remote signing
- NIP-49 encrypted key export/import
- NIP-17/44/59 DM
- NIP-57 Zap and NIP-47 wallet connect
- notification/push proxy with coarse payload only

P2:
- NIP-50 search with relay capability detection
- Blossom/NIP-B7 upload
- Tablet/Desktop multi-column
- OpenTelemetry/Sentry style observability
- strfry/nostr-rs-relay integration matrix

## Verification Rule

Each Phase must end with:

```bash
swift test
xcodegen generate
```

Then run XcodeBuildMCP simulator tests:

```text
test_sim(progress: true)
```

Commit only after all checks pass.

## Suggested Execution Order

Recommended next goal:

1. Phase 7.5
2. Phase 12
3. Phase 8
4. Phase 10

Reason: persistence coverage should land before behavior changes; then relay durability gives live operation history; then Timeline Row moves from mock-shaped data to real event tags.
