# DB-backed Lists Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home timeline の `Lists` tab を mock data から cached NIP-51 list data 由来の timeline に切り替え、MVP で follow set と bookmark set の cached events を表示できるようにする。

**Architecture:** `NostrEventStore` の既存 `lists` / `list_items` API を source of truth にする。`NostrHomeTimelineStore` は account-scoped cached lists から対象 kind:1 event を集めて既存 `NostrTimelineMaterializer` へ渡す。UI はまず aggregate Lists timeline として表示し、個別 list selector / publish / private decrypt は後続に残す。

**Tech Stack:** Swift, SwiftUI, Swift Testing, GRDB, XcodeGen, `AstrenzaCore`.

---

## File Structure

- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
  - Add timeline scope parameter so list rows can use `.lists` filter scopes instead of hard-coded `.home`.
- Modify `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Add `listEntries()` for aggregate cached NIP-51 list timeline.
  - Add helpers to collect follow-set authors and bookmark event IDs.
  - Reuse existing materialization metadata/media/OGP helpers.
- Modify `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - Use `liveTimelineStore.listEntries()` when `selectedTimeline == .lists`.
  - Refresh older behavior remains Home-only.
- Modify `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add tests for list-scope filter materialization and DB-backed Lists entries.
- Modify `Documents/Plans/2026-06-06-nostr-mvp-completion-execution-plan.md`
  - Mark the Lists tab DB-backed step as partially complete.

## Task 1: Save Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-07-db-backed-lists-tab-plan.md`

- [x] **Step 1: Save this plan**

Save this plan to the path above.

- [x] **Step 2: Create goal**

Create this active goal:

```text
Documents/Plans/2026-06-07-db-backed-lists-tab-plan.md を実行し、Lists tab を cached NIP-51 follow/bookmark list 由来の DB-backed timeline に結線し、検証、commit まで完了する。
```

## Task 2: Add Tests

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [x] **Step 1: Add list-scope filter test**

Add a materializer test that creates a keyword rule scoped only to `.lists`. Verify the post is not filtered when materializing `.home`, but is collapsed when materializing `.lists`.

- [x] **Step 2: Add DB-backed Lists tab test**

Add a `@MainActor` test that:
- creates an in-memory `NostrEventStore`
- saves an account
- saves a kind `30000` follow set containing author A
- saves a kind `30003` bookmark set containing event B
- saves note events for author A and event B
- starts `NostrHomeTimelineStore`
- verifies `store.listEntries().compactMap(\.post).map(\.id)` contains both list-derived posts in descending time order

## Task 3: Add Timeline Scope to Materializer

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`

- [x] **Step 1: Update core materializer signature**

Add:

```swift
timeline: NostrFilterTimelineScope = .home
```

to `NostrHomeTimelineMaterializer.items(...)`.

- [x] **Step 2: Use timeline in filter matching**

Replace hard-coded:

```swift
filterRules?.matchDetail(event: event, timeline: .home, now: now)
```

with the passed `timeline`.

- [x] **Step 3: Thread app materializer scope**

Add:

```swift
timeline: NostrFilterTimelineScope = .home
```

to `NostrTimelineMaterializer.posts(...)` and `entries(...)`, and pass it to `NostrHomeTimelineMaterializer.items(...)`.

## Task 4: Implement DB-backed Lists Entries

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`

- [x] **Step 1: Add public `listEntries()`**

Add:

```swift
func listEntries(limit: Int = 500) -> [TimelineFeedEntry]
```

It returns `[]` when no account or event store exists.

- [x] **Step 2: Collect list events**

Use cached `listSummaries(accountID:)` and `listItems(listID:)`.

Include:
- `kind == 30_000`, item type `pubkey`: fetch cached kind:1 events by authors
- `kind == 30_003` and `kind == 10_003`, item type `event`: fetch cached kind:1 events by event id

Deduplicate by event id and sort via existing materializer.

- [x] **Step 3: Materialize with list scope**

Call `NostrTimelineMaterializer.entries(... timeline: .lists ...)`.

Use list-applicable `filterRules` rather than Home-only rules.

## Task 5: Wire Home Lists Tab

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [x] **Step 1: Replace live Lists mock path**

For logged-in accounts:

```swift
case .lists:
    let listEntries = liveTimelineStore.listEntries()
    return listEntries.isEmpty ? MockTimelineData.entries(for: .lists) : listEntries
```

Keep mock fallback so the UI is not blank when no cached list exists yet.

- [x] **Step 2: Keep refresh/load older Home-only**

No behavior change for refresh and pagination in this phase.

## Task 6: Update Parent Plan and Verify

**Files:**
- Modify: `Documents/Plans/2026-06-06-nostr-mvp-completion-execution-plan.md`

- [x] **Step 1: Update Phase 9 note**

Add a note that Lists tab now reads cached follow/bookmark NIP-51 entries in aggregate, while individual list selection remains deferred.

- [x] **Step 2: Generate project**

Run:

```bash
xcodegen generate
```

- [x] **Step 3: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test
```

- [x] **Step 4: Run iOS tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaDBBackedLists-DerivedData -skipMacroValidation test
```

- [x] **Step 5: Commit**

Commit message:

```bash
git commit -m "Back lists tab with cached NIP-51 entries"
```

## Self-Review

- Spec coverage: DB-backed aggregate Lists tab, follow set events, bookmark events, list-scope filters, parent plan update, and tests are covered.
- Placeholder scan: No TBD/TODO placeholders are used.
- Type consistency: `listEntries`, `timeline`, `.lists`, `NostrListSummary`, and `NostrListItemRecord` names match existing code.
