# Home Gap UI Lifecycle NIP-77 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home TL の GapRow 表示確認、Gap lifecycle 回帰テスト、NIP-77 による Gap 補完検証を 1-2-3 の順で実装する。

**Architecture:** Gap の永続状態は `timeline_entries.gap_before/gap_after` を単一の真実として扱い、表示層は `TimelineGap` projection に寄せる。通常の backward REQ が EOSE completed でも、window 内の set reconciliation が必要な場面では NIP-77 を追加で実行し、missing IDs があれば event fetch と materialize を行ってから Gap 解消可否を決める。

**Tech Stack:** Swift, Swift Testing, GRDB, SwiftUI timeline projection, NIP-01 REQ/EOSE, NIP-77 Negentropy mock relay client.

---

## File Structure

- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - GapRow の表示方向 projection と Gap lifecycle の regression tests を追加する。
  - `FakeStoreRelayClient` に NIP-77 missing ID と ids fetch のテスト用応答を足す。
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - gap backfill completed 時に NIP-77 reconciliation を挟む。
  - missing IDs があれば event を取得して DB/TL に保存し、Gap は partial と同じく保持する。
  - missing IDs がなければ従来通り `markGapResolved` で解消する。
- Test only if needed: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrEventStoreTests.swift`
  - 前回実装済みの Gap flag persistence は触らない。今回の検証で regression が見つかった場合だけ追加する。

## Task 1: GapRow UI Projection を固定する

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write the failing/pinning tests**

Add tests that pin:
- `.newer` and `.older` use distinct labels and icons.
- An unresolved `newer -> older` gap is split into `newer -> inserted` and `inserted -> older` when an event is materialized between the two boundary posts.

- [ ] **Step 2: Run tests to verify behavior**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected:
- The new tests pass if existing projection is already correct.
- If they fail, failure must point to `TimelineGapFillDirection` labels/icons or materializer projection order.

- [ ] **Step 3: Implement minimal correction if needed**

If the tests fail, update only the projection label/icon or the materializer gap projection path needed by the failure.

- [ ] **Step 4: Commit**

```bash
git add Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Cover home gap UI projection"
```

## Task 2: Gap Lifecycle の残り回帰テストを追加する

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write lifecycle tests**

Add tests that pin:
- Gap backfill `.timedOut` with no inserted events keeps the original GapRow.
- Gap backfill `.closed` with no inserted events keeps the original GapRow.
- Older page `.completed` with received older events does not create a boundary GapRow.

- [ ] **Step 2: Run tests to verify behavior**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected:
- The tests pass if previous partial/timeout preservation is complete.
- Any failure must be fixed in `NostrHomeTimelineStore.handleBackwardCompletion`.

- [ ] **Step 3: Implement minimal correction if needed**

If a test fails:
- Do not resolve gaps unless completion status is `.completed`.
- Do not mark older boundary gaps for `.completed`.
- Keep `.partial`, `.timedOut`, and `.closed` as unknown windows.

- [ ] **Step 4: Commit**

```bash
git add Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift
git commit -m "Cover home gap lifecycle states"
```

## Task 3: Gap Backfill Completed に NIP-77 検証を挟む

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`

- [ ] **Step 1: Write the failing NIP-77 test**

Create a test where:
- TL has `newer` and `older` posts with a GapRow between them.
- Runtime gap backfill returns only EOSE/completed and no events.
- Fake NIP-77 returns a missing `middle` event ID for the same window.
- Fake ids fetch returns the `middle` event.
- Expected result is `newer`, GapRow, `middle`, GapRow, `older`; the original Gap is not treated as fully resolved.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected:
- FAIL because runtime gap completion currently resolves the Gap after EOSE without consulting NIP-77.

- [ ] **Step 3: Implement minimal NIP-77 reconciliation**

In `NostrHomeTimelineStore.handleBackwardCompletion`:
- For `.gap` requests with `.completed`, call a helper before `markGapResolved`.
- The helper builds a `NostrRelayFilter` for the gap window and current follow authors.
- It asks `timelineLoader.relayClient.fetchMissingEventIDs`.
- If missing IDs are empty, return `false` and allow `markGapResolved`.
- If missing IDs exist, fetch those events by ids from relays, save/materialize them, reload around the current anchor, and return `true` so the existing Gap is preserved/split.

- [ ] **Step 4: Run targeted test to verify it passes**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected:
- PASS.

- [ ] **Step 5: Commit**

```bash
git add Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift
git commit -m "Verify gap backfills with NIP-77"
```

## Task 4: Full Verification

**Files:**
- No planned source changes.

- [ ] **Step 1: Run core package tests**

```bash
swift test --disable-sandbox --package-path Packages/AstrenzaCore
```

Expected:
- PASS.

- [ ] **Step 2: Run app tests**

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected:
- PASS.

- [ ] **Step 3: Commit final stabilization if needed**

Only if verification requires a small fix:

```bash
git add Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift
git commit -m "Stabilize gap reconciliation tests"
```

## Assumptions

- Timestamp distance alone is not a Gap signal.
- NIP-77 in this step is used as an additional verification pass for completed gap windows, not as a replacement for live relay subscriptions.
- The runtime WebSocket session remains long-lived; this task does not introduce open/close churn for the normal Home TL subscription.
- Missing IDs fetched by NIP-77 are materialized into the existing timeline entry pipeline so Row components do not need a separate mock path.
