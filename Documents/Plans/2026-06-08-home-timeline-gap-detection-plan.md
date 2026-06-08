# Home Timeline Gap Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home TLで実通信由来の抜けを `GapRow` として検出・保持し、partial/timeout時にGapが消えないようにする。

**Architecture:** `timeline_entries.gap_before/gap_after` をGap表示の唯一のソースにし、実通信のolder/gap backward request completionから境界Gapを明示的にDBへ記録する。Gap解消はcompleted completion時だけに限定し、partial/timeout/closedでは未確定intervalとしてGapを残す。

**Tech Stack:** Swift, Swift Testing, GRDB-backed `NostrEventStore`, SwiftUI Home Timeline projection.

---

### Task 1: Preserve Timeline Gap Flags

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add failing Core tests**

Add tests that verify:

- `saveTimelineEntries` does not clear existing `gapAfter` / `gapBefore` when an existing row is saved again with default false flags.
- `markTimelineGap(accountID:timelineKey:newerEventID:olderEventID:)` sets `gapAfter` on the newer entry and `gapBefore` on the older entry.
- `markTimelineGapResolved` clears both sides.

- [ ] **Step 2: Run Core tests and confirm RED**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: fail because `markTimelineGap` does not exist and/or gap flags are overwritten.

- [ ] **Step 3: Implement Core persistence behavior**

Update `saveTimelineEntries` conflict handling so existing true gap flags are preserved unless the incoming row explicitly sets the flag true. Add `markTimelineGap` as the inverse operation of `markTimelineGapResolved`.

- [ ] **Step 4: Run Core tests and confirm GREEN**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter NostrCorePackageTests
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Preserve timeline gap flags"
```

### Task 2: Detect Runtime Partial Gaps

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing App tests**

Add tests that verify:

- Partial gap backfill with a middle event keeps the interval marked as unresolved and displays split GapRows around the inserted event.
- Timed-out or closed gap backfill without middle events leaves the original GapRow visible.
- Older page partial completion marks a boundary Gap between the prior bottom post and the newest newly received older post.
- Older page completed completion does not add a boundary Gap.

- [ ] **Step 2: Run App tests and confirm RED**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected: fail because received backward timeline event IDs and older anchors are not tracked, and partial completions do not mark unresolved boundaries.

- [ ] **Step 3: Track backward timeline IDs and older anchors**

Extend `PendingBackwardRequest` with `receivedTimelineEventIDs: [String]` and `olderAnchorPostID: String?`. Store `olderAnchorPostID` when creating older page requests and append kind:1/kind:6 IDs when they are received for older or gap requests.

- [ ] **Step 4: Change gap completion semantics**

Only call `markGapResolved` for gap requests when `completion.status == .completed`. For `.partial`, `.timedOut`, and `.closed`, keep existing Gap flags. Reload the projection around the stable anchor after timeline events or terminal completion so the visible GapRows update.

- [ ] **Step 5: Mark older partial boundaries**

When an older page request finishes with `.partial`, `.timedOut`, or `.closed` and received timeline events exist, mark a Gap between `olderAnchorPostID` and the newest received older event. Do not mark a boundary for `.completed`.

- [ ] **Step 6: Run App tests and confirm GREEN**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Detect partial timeline gaps"
```

### Task 3: Final Verification

**Files:**
- No code changes unless verification reveals a regression.

- [ ] **Step 1: Run Core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected: pass.

- [ ] **Step 2: Run App tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected: pass.

- [ ] **Step 3: Commit final stabilization if needed**

Only if verification requires follow-up edits:

```bash
git add <changed files>
git commit -m "Stabilize home gap detection"
```

## Assumptions

- timestamp差だけではGap扱いしない。
- v1ではNIP-77の完全なset reconciliation結果まではGap検出条件に含めない。
- partial/timeout/closedは未確定intervalとしてGapRowを残す。
- completed EOSEは該当fetch windowを補完済みとしてGapを解消する。
- DB schema migrationは不要。既存 `gap_before/gap_after` カラムを使う。
