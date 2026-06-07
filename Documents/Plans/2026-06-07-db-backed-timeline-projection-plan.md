# DB-Backed Timeline Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Documents/Research の local-first 方針に合わせ、Home Timeline を `events` 全件 materialize ではなく `timeline_entries` の viewport window から描画する構成へ移行し、live 受信は pending 化してスクロール中のかくつきを抑える。

**Architecture:** `events` は relay 受信直後に正規化保存し、`timeline_entries` は Home 用の表示 index として更新する。SwiftUI に渡す `entries` は DB から読んだ anchor 周辺 window のみ materialize し、forward REQ で受けた新着は最上部表示中だけ即時反映、それ以外は `pendingNewEventIDs` として保持する。

**Tech Stack:** Swift 6, SwiftUI, GRDB, Swift Testing, Maestro mock route.

---

## Research Alignment

- `Documents/Research/tweetbot_ivory_nostr_client_report.md` は、ローカルストアを「ただのキャッシュ」ではなく閲覧モデルそのものとし、Timeline 表示を local-first にする方針を示している。
- 同 Research は「正規化イベントストア + 画面最適化ビューの二層DB」を推奨し、`timeline_entries(account_id, timeline_key, sort_ts)` を描画最適化と last-read 復帰の中核に置いている。
- 現状の `NostrHomeTimelineStore` は `LazyVStack` を使いつつも、`noteEvents` 全体から `entries` 全体を materialize しているため、UI レイヤだけの lazy 化に寄りすぎている。

## File Structure

- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - `timeline_entries` の anchor/window query API と event bulk read API を追加する。
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - window query の順序、anchor 周辺取得、pending 新着件数向け query を検証する。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - `noteEvents` を UI projection window として扱い、runtime 受信を DB 保存 + pending/index 更新に分離する。
  - `pendingNewCount`, `setTimelineAtNewestWindow(_:)`, `applyPendingNewEvents()` を追加する。
  - older/gap backward REQ は `timeline_entries` を更新し、completion 時に projection window を再読込する。
  - kind:0 / reply / repost / quote などの dependency fetch は event store へ保存しつつ、Home Row には勝手に追加しない。
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - scroll offset から「最上部 window 表示中」を Store に伝える。
  - pull-to-refresh 時に pending 新着を visible window へ取り込む。
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - live event がスクロール中に Row 化されず pending になること、最上部では即時反映されること、older/gap で anchor 側が維持されることをテストする。

## Implementation Tasks

### Task 1: Core DB Window Query

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [x] **Step 1: Add failing tests for timeline window queries**

Add tests that create five events with `sort_ts` 500, 400, 300, 200, 100 and assert:

```swift
#expect(try store.timelineEntries(accountID: "account", timelineKey: "home", newerThan: 300, limit: 10).map(\.eventID) == [event500.id, event400.id])
#expect(try store.timelineEntries(accountID: "account", timelineKey: "home", olderThan: 300, limit: 10).map(\.eventID) == [event200.id, event100.id])
#expect(try store.timelineEntries(accountID: "account", timelineKey: "home", aroundEventID: event300.id, leadingLimit: 1, trailingLimit: 2).map(\.eventID) == [event400.id, event300.id, event200.id, event100.id])
```

- [x] **Step 2: Run Core tests and verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: compile failure because the new query APIs do not exist.

- [x] **Step 3: Implement timeline window query APIs**

Add public APIs:

```swift
public func timelineEntries(accountID: String, timelineKey: String, newerThan sortTimestamp: Int, limit: Int) throws -> [NostrTimelineEntryRecord]
public func timelineEntries(accountID: String, timelineKey: String, olderThan sortTimestamp: Int, limit: Int) throws -> [NostrTimelineEntryRecord]
public func timelineEntries(accountID: String, timelineKey: String, aroundEventID eventID: String, leadingLimit: Int, trailingLimit: Int) throws -> [NostrTimelineEntryRecord]
public func events(ids: [String], now: Int = Int(Date().timeIntervalSince1970)) throws -> [NostrEvent]
```

Ordering must always match display order: `sort_ts DESC, event_id ASC`.

- [x] **Step 4: Run Core tests and verify pass**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: pass.

### Task 2: Store Projection Window

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [x] **Step 1: Add failing Store tests for pending live events**

Add tests that:

1. Start a live account with two cached timeline posts.
2. Mark the store as not at newest window with `store.setTimelineAtNewestWindow(false)`.
3. Inject a forward runtime kind:1 event.
4. Assert `pendingNewCount == 1` and `entries` IDs are unchanged.
5. Call `await store.applyPendingNewEvents()`.
6. Assert the new event appears at the top and `pendingNewCount == 0`.

Add a second test that sets `setTimelineAtNewestWindow(true)` before injecting the event and asserts the new event appears immediately.

- [x] **Step 2: Add projection state**

Add state to `NostrHomeTimelineStore`:

```swift
@Published private(set) var pendingNewCount = 0
private var pendingNewEventIDs = Set<String>()
private var isTimelineAtNewestWindow = true
private let projectionWindowLimit = 240
private let projectionAnchorLeadingLimit = 80
private let projectionAnchorTrailingLimit = 160
```

- [x] **Step 3: Add Store APIs**

Add:

```swift
func setTimelineAtNewestWindow(_ isAtNewestWindow: Bool)
func applyPendingNewEvents() async
```

`applyPendingNewEvents()` reloads the newest projection window from `timeline_entries`, clears `pendingNewEventIDs`, updates `pendingNewCount`, materializes, and schedules link preview resolution.

- [x] **Step 4: Add DB projection helpers**

Add helpers:

```swift
private func saveHomeTimelineIndex(events: [NostrEvent], account: NostrAccount, source: String)
private func reloadNewestProjectionWindow(account: NostrAccount)
private func reloadProjectionWindow(account: NostrAccount, around anchorEventID: String?)
private func projectedTimelineEvents(account: NostrAccount, entries: [NostrTimelineEntryRecord]) -> [NostrEvent]
```

The helpers read `timeline_entries` first, then bulk-load events by ID, preserving timeline entry order.

- [x] **Step 5: Change `handleHomeForwardEvent`**

For kind:1 and kind:6:

1. Save event to `events`.
2. Save one `timeline_entries` row.
3. Enqueue backward dependencies.
4. If `isTimelineAtNewestWindow && pendingNewEventIDs.isEmpty`, reload newest projection window and materialize.
5. Otherwise add the event ID to `pendingNewEventIDs` and update `pendingNewCount`.

For kind:5:

1. Save deletion event.
2. Remove deleted IDs from current projection `noteEvents`.
3. Materialize current projection only.

- [x] **Step 6: Change `handleBackwardEvent`**

For kind:0:

1. Save metadata and update `metadataEvents`.
2. Re-materialize current projection.

For kind:1 and kind:6:

1. Save event to `events`.
2. Only save to `timeline_entries` when the matching `PendingBackwardRequest` is older page or gap backfill.
3. Do not append dependency source events directly to Home projection.

- [x] **Step 7: Run App tests and verify pending behavior**

Run:

```bash
xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: App tests pass.

### Task 3: Home UI Top-State Wiring

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [x] **Step 1: Wire scroll offset to Store top-state**

Update `handleTimelineScrollOffset(_:)` or equivalent scroll handler so Home timeline calls:

```swift
liveTimelineStore.setTimelineAtNewestWindow(offset <= 6)
```

Only do this for `selectedTimeline == .home` and a real session account.

- [x] **Step 2: Pull-to-refresh consumes pending first**

Update `refreshVisibleTimeline()`:

```swift
if liveTimelineStore.pendingNewCount > 0 {
    await liveTimelineStore.applyPendingNewEvents()
    return
}
await liveTimelineStore.refreshLatest()
```

- [x] **Step 3: Keep relay runtime alive**

Do not close forward REQ after EOSE. This task must not change `NostrRelayRuntime` subscription lifetime.

### Task 4: Gap and Older Projection Reconciliation

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [x] **Step 1: Add tests for older load projection expansion**

The test should load a two-post projection, trigger older runtime completion with an older event, and assert the older event appears without requiring all historical events to be materialized.

- [x] **Step 2: Add tests for gap backfill projection**

The test should keep the existing gap test expectation:

```swift
#expect(store.entries.compactMap(\.post).map(\.id) == [newer.id, middle.id, older.id])
```

It should also assert resolved gap flags are cleared in `timeline_entries`.

- [x] **Step 3: On older completion, reload projection around prior bottom anchor**

When `PendingBackwardRequest.isOlderPage` completes with events, save those events into `timeline_entries`, then reload projection around the previous bottom post ID so the upper visible side remains stable.

- [x] **Step 4: On gap completion, resolve gap flags and reload around stable side**

For `.newer` gap fill, reload around `gap.olderPostID`.
For `.older` gap fill, reload around `gap.newerPostID`.
This mirrors the UX rule:

- 上方向補完なら下の投稿を固定する。
- 下方向補完なら上の投稿を固定する。

### Task 5: Verification

**Files:**
- Test only unless failures require fixes.

- [x] **Step 1: Run Core SwiftPM tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected: pass.

- [x] **Step 2: Run iOS unit tests**

Run:

```bash
xcodebuild test -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: pass.

- [x] **Step 3: Run simulator build**

Run:

```bash
xcodebuild build -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: build succeeds.

- [x] **Step 4: Manual smoke check**

Open Home TL in mock route and live route if available. Confirm:

- Scrolling does not jump when live events arrive.
- Pull-to-refresh consumes pending new posts.
- GapRow disappears after successful backfill.
- Relay pill still reflects runtime/DB state.

Verification evidence on 2026-06-07:

- Core SwiftPM: `env CLANG_MODULE_CACHE_PATH=/private/tmp/astrenza-clang-module-cache swift test --disable-sandbox --package-path Packages/AstrenzaCore --filter NostrCorePackageTests` passed with 113 tests and 0 failures.
- iOS tests: XcodeBuildMCP `test_sim` passed with 85 tests and 0 failures on iPhone 17.
- Simulator build: XcodeBuildMCP `build_sim` succeeded on iPhone 17.
- Manual smoke: XcodeBuildMCP `build_run_sim` launched mock route with `-AstrenzaMockTimeline`; screenshot captured at `/var/folders/n7/whby92pj2kd85qnv9yl2xhnm0000gn/T/screenshot_optimized_ac6aa26b-efb6-4f0c-994f-074f60f7fee7.jpg`. Live route manual login was not exercised in this sandbox run; live runtime behavior is covered by unit tests.

## Risks and Guardrails

- Do not delete or rewrite unrelated dirty worktree changes.
- Do not close relay forward REQ after EOSE.
- Do not add source dependency events as top-level Home rows unless they are also in `timeline_entries`.
- Keep `LazyVStack`; it remains useful after DB windowing.
- Avoid broad SwiftUI invalidation: normal `EVENT received` must not publish relay status revisions.
- If test expectations conflict with existing mock behavior, preserve mock route by gating live-only behavior on `sessionStore.account != nil`.
