# Nostr Dependency Fetch Queue and TTL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Documents/Research/*.md の local-first / 正規イベントストア / profile cache / relay status / timeline index 分離方針に沿って、Home TL の遅延依存取得を明示的なキューにし、DB/メモリ解決に stale 判定を導入する。

**Architecture:** `kind:1` など immutable event はTTLで消さず、DBに保存済みなら即表示する。`kind:0` / NIP-05 / OGP / relay info のような更新可能・補助データは、DBから即表示しつつ stale 判定で再取得キューへ積む。HomeTL store内に埋まっている `pendingProfilePubkeys` / `pendingSourceEventIDs` / relay hint grouping を `NostrDependencyFetchQueue` に切り出し、UIはキューの状態だけを見る。

**Tech Stack:** Swift 6.1, Swift Testing, GRDB, SwiftUI, URLSessionWebSocketTask, Nostr NIP-01/05/10/11/65/92.

---

## Researchからの実装判断

- `Documents/Research/tweetbot_ivory_nostr_client_report.md` は「ローカルストアはただのキャッシュではなく閲覧モデル」と明記しているため、表示はDB優先にする。
- 推奨スキーマは `events`, `replaceable_heads`, `timeline_entries`, `relay_profiles`, `sync_cursors` を分けるため、TTLはevent削除ではなく `stale_after` / `last_attempted_at` / `expires_at` として扱う。
- `kind:0`, `kind:3`, `kind:10002` は replaceable head 管理。古いheadも一旦表示し、裏で再取得する。
- Repost / Reply先などの source event は immutable なので、存在すればTTL不要。未取得・失敗だけ短い negative TTL/backoff を持つ。
- NIP-11 relay info と OGP は外部状態なのでTTLあり。すでに `relay_profiles` と `link_previews.expires_at` があるため既存DBに寄せる。

## File Structure

- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrDependencyFetchQueue.swift`
  - profile/source依存をrelay hintごとに集約し、stale判定とduplicate suppressionを担う純粋Swift型。
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrNIP05Resolver.swift`
  - NIP-05 cacheにTTLを導入し、login時は既存どおりcacheなし運用可能にする。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - 既存の `bufferedProfilePubkeysByRelay` / `bufferedSourceEventIDsByRelay` / stale判定をqueue型へ接続する。
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - queueとNIP-05 cache TTLの単体テストを追加する。
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - HomeTLがstale kind:0を表示しつつ再取得する回帰テストを追加する。

## Task 1: DependencyFetchQueue core

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrDependencyFetchQueue.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that enqueue profile/source dependencies, dedupe them, group by relay hints, and allow stale profile revalidation while keeping immutable source events cache-hit.

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: FAIL because `NostrDependencyFetchQueue` does not exist.

- [ ] **Step 3: Implement queue**

Create `NostrDependencyFetchQueue` with:

- `public struct NostrDependencyFetchPolicy`
- `public struct NostrDependencyFetchSnapshot`
- `public struct NostrDependencyFetchBatch`
- `public mutating func enqueue(...)`
- `public mutating func drain()`
- `public mutating func finish(...)`

Rules:

- profile is missing when no cached event exists.
- profile is stale when `now - receivedAt >= profileStaleAfterSeconds`.
- source event is missing only when no cached event exists.
- source event is not revalidated by TTL because event IDs are immutable.
- failed/missing entries are suppressed until `retryAfterSeconds`.

- [ ] **Step 4: Run package test**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: PASS.

## Task 2: NIP-05 TTL

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrNIP05Resolver.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for:

- verified cache is reused before TTL.
- stale verified cache is refreshed after TTL.
- failed cache uses shorter TTL.
- `cache: nil` still never caches login resolution.

- [ ] **Step 2: Implement TTL**

Add `NostrNIP05CachePolicy`:

- `verifiedTTLSeconds = 24 * 60 * 60`
- `failureTTLSeconds = 15 * 60`

Change cache lookup so expired entries return nil.

- [ ] **Step 3: Run package test**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: PASS.

## Task 3: HomeTL queue wiring

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing regression test**

Add a HomeTL test that:

- saves stale `kind:0` metadata to DB first.
- receives a new note referencing that pubkey.
- immediately renders with stale metadata.
- also emits a runtime backward `kind:0` REQ for refresh.

- [ ] **Step 2: Replace embedded buffering with queue**

Replace local `bufferedProfilePubkeysByRelay` / `bufferedSourceEventIDsByRelay` with `NostrDependencyFetchQueue`.

Use these rules:

- cached stale profile: keep displaying, enqueue refresh.
- cached fresh profile: display and do not enqueue.
- cached source event: do not enqueue.
- missing source event: enqueue.
- no runtime/relays: skip enqueue.

- [ ] **Step 3: Run targeted app tests**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

## Task 4: Full verification

**Files:**
- All touched files.

- [ ] **Step 1: Run formatting sanity**

Run:

```bash
git -c core.fsmonitor=false diff --check
```

Expected: no output.

- [ ] **Step 2: Run full iOS test**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: TEST SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-06-07-nostr-dependency-fetch-ttl.md Packages/AstrenzaCore/Sources/AstrenzaCore/NostrDependencyFetchQueue.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrNIP05Resolver.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Add dependency fetch queue stale policy"
```

## Self-Review

- Spec coverage: Research再読、計画保存、ゴール設定、実装/結線、TTL検討、キュー処理化を含む。
- Placeholder scan: TBD/TODOなし。
- Type consistency: queue型名とstore接続名は `NostrDependencyFetchQueue` に統一する。
