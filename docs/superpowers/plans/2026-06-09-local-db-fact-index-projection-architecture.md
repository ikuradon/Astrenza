# Astrenza Local DB Fact/Index Projection Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Astrenza toward a local-first Nostr persistence architecture where GRDB/SQLite stores canonical facts and lightweight timeline indexes, while app-layer projection builds `TimelinePost` and other display models on demand.

**Architecture:** Keep GRDB/SQLite as the primary device-local database. Persist normalized Nostr facts (`events`, `event_tags`, heads, relations, deletion tombstones, media/link metadata, relay state) and prunable timeline membership/index rows (`timeline_entries`), but never persist completed UI row DTOs such as `TimelinePost`. Build display models through explicit app-layer projection services with coalesced refresh and bounded observation.

**Tech Stack:** Swift, SwiftUI, GRDB, Swift Testing, XCTest UI target, Maestro mock route tests where applicable, local file media cache, optional future SQLite FTS5 sidecar.

---

## Source Documents

- `Documents/Research/astrenza_local_db_report.md`
- `Documents/Research/tweetbot_ivory_nostr_client_report.md`
- `Documents/Research/tweetbot_ivory_nostr_client_research.md`
- `Documents/Reference/nips/01.md`
- `Documents/Reference/nips/09.md`
- `Documents/Reference/nips/40.md`

## Current High-Level Findings

- `GRDB + SQLite` remains the primary local store.
- `TimelinePost` is an app/view model and must not become the database source of truth.
- `timeline_entries` remains necessary for Home/Mentions/List timeline stability, but it is a prunable membership/index table, not a projection table.
- `kind:5` is a deletion request fact. It should persist as an event and tombstone, then projection should turn affected target rows into `Deleted` rows.
- DB writes and timeline row insertion must remain separate: relay ingestion stores events immediately, while timeline membership is updated only for live-top mode or explicit user actions.
- Observation should watch lightweight row IDs/counts/generation markers, not full display models.

## File Structure and Responsibilities

### Existing files to preserve and gradually reshape

- `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - Owns GRDB schema, migrations, canonical event persistence, tags, heads, timeline index, deletion tombstones, media/link metadata, and query APIs.
  - Must not know `TimelinePost`.

- `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrCore.swift`
  - Owns Nostr event/value models and pure parsing helpers.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMaterializer.swift`
  - Current app-layer projection/materialization entry.
  - Target direction: rename or wrap into `NostrTimelineProjection` without DB persistence semantics.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelinePostProjection.swift`
  - Builds `TimelinePost` from app-layer input facts.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineAuthorProjection.swift`
  - Builds author display from profile/NIP-05 facts.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineContentProjection.swift`
  - Builds rich content from raw event content/tags/media/link facts.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Owns Home runtime state, relay ingestion orchestration, projection windows, unread/live behavior, gap fills, and coalesced projection refresh.
  - Target direction: separate store/query/projection responsibilities into smaller units without behavior loss.

- `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineRepository.swift`
  - Current bridge from `NostrEventStore` query APIs to timeline projection.
  - Target direction: become `HomeTimelineProjectionRepository` or equivalent.

- `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
  - Owns UI display models such as `TimelinePost`, `TimelineFeedEntry`, `TimelineDeletedEntry`.
  - These stay app-layer only.

- `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Existing app-level tests for timeline materialization/projection/runtime.

- `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Existing core tests for persistence and parsing.

### New files to create when tasks require them

- `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md`
  - One-time architecture audit produced by Task 1.

- `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrTimelineIndexPolicy.swift`
  - Pure retention/pruning policy for timeline index entries.

- `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventRelationModels.swift`
  - Relation record types if relation storage outgrows `NostrEventStore.swift`.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineProjection.swift`
  - App-layer projection facade replacing the misleading "materializer" naming.

- `Astrenza/Sources/AstrenzaApp/Nostr/NostrProjectionRefreshCoordinator.swift`
  - Coalesces fact updates into bounded UI projection refreshes.

## Target Data Model

### Canonical facts in SQLite

- `events`
  - `event_id`, `pubkey`, `kind`, `created_at`, `content`, `received_at`, `deleted_at`, `expires_at`, `raw_json`.

- `event_tags`
  - `event_id`, `pos`, `tag_name`, `tag_value`, `tail_json`.

- `replaceable_heads`
  - `(pubkey, kind)` latest event by NIP-01 replacement rules.

- `addressable_heads`
  - `(kind, pubkey, d_tag)` latest event by NIP-01 replacement rules.

- `deletion_tombstones`
  - Deletion request facts from valid kind:5 events.
  - Must keep enough data to avoid resurrecting pruned/deleted events.

- `timeline_entries`
  - `account_id`, `timeline_key`, `event_id`, `sort_ts`, `source`, `inserted_at`, `gap_before`, `gap_after`.
  - This is a timeline membership/index table, not a display projection table.

- `media_assets`
  - URL and media metadata. File bodies stay in file cache.

- `link_previews`
  - OGP/oEmbed metadata. Image bodies stay in file cache.

- `relay_state`, `sync_cursors`, `network_counters`
  - Runtime facts and history for relay health, request outcome, and byte counting.

### App-only projection models

- `TimelinePost`
- `QuotedTimelinePost`
- `TimelineReplyContext`
- `TimelineFeedEntry`
- `PostDetailModel` or equivalent detail projection output
- `UserProfile`

These must not be inserted into SQLite as completed display rows.

## Dependency Rules

Allowed:

```text
Network -> Ingest -> Store -> Projection -> Runtime Store -> SwiftUI
```

Forbidden:

```text
Store -> TimelinePost
Store -> SwiftUI display strings
Projection -> direct relay fetch
SwiftUI View -> direct SQL query
timeline_entries -> display DTO source of truth
```

## Phase 0: Baseline Safety and Audit

### Task 1: Produce architecture audit

**Files:**
- Create: `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md`

- [ ] **Step 1: Map persistent facts and display projections**

Run:

```bash
rg -n "CREATE TABLE|create\\(table:|TimelinePost|NostrTimelineMaterializer|timeline_entries|deletion_tombstones|media_assets|link_previews|replaceable_heads|addressable_heads" Packages/AstrenzaCore/Sources/AstrenzaCore Astrenza/Sources/AstrenzaApp -S
```

Expected: output identifying `NostrEventStore.swift`, `NostrTimelineMaterializer.swift`, projection files, and UI model files.

- [ ] **Step 2: Write the audit document**

Create `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md` with this structure:

```markdown
# Local DB Projection Architecture Audit

## Persistent Fact Tables

List each SQLite table and whether it is canonical fact, lightweight index, cache metadata, runtime state, or draft/outbox state.

## App Projection Types

List each `TimelinePost`/`TimelineFeedEntry` producer and whether it writes to DB.

## Risky Couplings

List any code path where display concerns leak into store APIs.

## Safe Existing Behavior

List behavior that must not regress: gap rows, deleted rows, live unread behavior, pull-to-refresh anchor behavior, post detail navigation, media gallery layout.

## Migration Order

List Phase 1 through Phase 8 from this implementation plan.
```

- [ ] **Step 3: Commit the audit**

Run:

```bash
git add Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md
git commit -m "Document local DB projection audit"
```

Expected: commit succeeds.

### Task 2: Establish baseline test command set

**Files:**
- Modify: none

- [ ] **Step 1: Run core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected: all core package tests pass.

- [ ] **Step 2: Run app tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected: all targeted app tests pass.

- [ ] **Step 3: Record baseline**

Append a short baseline section to `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md`:

```markdown
## Baseline Test Result

- Core: PASS or failure summary with date.
- App: PASS or failure summary with date.
```

- [ ] **Step 4: Commit baseline update**

Run:

```bash
git add Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md
git commit -m "Record local DB projection baseline"
```

Expected: commit succeeds.

## Phase 1: Make Timeline Index Semantics Explicit

### Task 3: Rename concepts in tests and docs before code rename

**Files:**
- Modify: `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md`
- Modify: test names in `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
- Modify: test names in `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Update test display names only**

Replace misleading test display names that say "materializer persists projection" or equivalent with wording that says:

```swift
@Test("Timeline projection builds rows from timeline index flags")
```

and:

```swift
@Test("Timeline index preserves gap flags on upsert")
```

Do not change production code in this task.

- [ ] **Step 2: Run focused tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter Timeline
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: tests pass because only names changed.

- [ ] **Step 3: Commit terminology cleanup**

Run:

```bash
git add Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md
git commit -m "Clarify timeline index terminology"
```

Expected: commit succeeds.

### Task 4: Add TimelineIndex retention policy model

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrTimelineIndexPolicy.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing retention tests**

Add Swift Testing cases:

```swift
@Test("Timeline index policy keeps anchor gap and recent entries")
func timelineIndexPolicyKeepsProtectedEntries() {
    let policy = NostrTimelineIndexPolicy(
        recentLimit: 3,
        anchorRadius: 1,
        retainedAgeSeconds: 60
    )
    let entries = [
        NostrTimelineIndexCandidate(eventID: "newest", sortTimestamp: 500, insertedAt: 500, gapBefore: false, gapAfter: false),
        NostrTimelineIndexCandidate(eventID: "gap-newer", sortTimestamp: 400, insertedAt: 400, gapBefore: false, gapAfter: true),
        NostrTimelineIndexCandidate(eventID: "anchor", sortTimestamp: 300, insertedAt: 300, gapBefore: false, gapAfter: false),
        NostrTimelineIndexCandidate(eventID: "gap-older", sortTimestamp: 200, insertedAt: 200, gapBefore: true, gapAfter: false),
        NostrTimelineIndexCandidate(eventID: "old", sortTimestamp: 100, insertedAt: 100, gapBefore: false, gapAfter: false)
    ]

    let retained = policy.retainedEventIDs(
        from: entries,
        anchorEventID: "anchor",
        now: 520
    )

    #expect(retained.contains("newest"))
    #expect(retained.contains("gap-newer"))
    #expect(retained.contains("anchor"))
    #expect(retained.contains("gap-older"))
    #expect(!retained.contains("old"))
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter TimelineIndexPolicy
```

Expected: FAIL because `NostrTimelineIndexPolicy` does not exist.

- [ ] **Step 3: Implement policy model**

Create `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrTimelineIndexPolicy.swift`:

```swift
import Foundation

public struct NostrTimelineIndexCandidate: Equatable, Sendable {
    public let eventID: String
    public let sortTimestamp: Int
    public let insertedAt: Int
    public let gapBefore: Bool
    public let gapAfter: Bool

    public init(
        eventID: String,
        sortTimestamp: Int,
        insertedAt: Int,
        gapBefore: Bool,
        gapAfter: Bool
    ) {
        self.eventID = eventID
        self.sortTimestamp = sortTimestamp
        self.insertedAt = insertedAt
        self.gapBefore = gapBefore
        self.gapAfter = gapAfter
    }
}

public struct NostrTimelineIndexPolicy: Equatable, Sendable {
    public let recentLimit: Int
    public let anchorRadius: Int
    public let retainedAgeSeconds: Int

    public init(recentLimit: Int, anchorRadius: Int, retainedAgeSeconds: Int) {
        self.recentLimit = max(0, recentLimit)
        self.anchorRadius = max(0, anchorRadius)
        self.retainedAgeSeconds = max(0, retainedAgeSeconds)
    }

    public func retainedEventIDs(
        from entries: [NostrTimelineIndexCandidate],
        anchorEventID: String?,
        now: Int
    ) -> Set<String> {
        let sorted = entries.sorted {
            if $0.sortTimestamp == $1.sortTimestamp {
                return $0.eventID < $1.eventID
            }
            return $0.sortTimestamp > $1.sortTimestamp
        }

        var retained = Set(sorted.prefix(recentLimit).map(\\.eventID))
        for entry in sorted where entry.gapBefore || entry.gapAfter {
            retained.insert(entry.eventID)
        }
        for entry in sorted where now - entry.insertedAt <= retainedAgeSeconds {
            retained.insert(entry.eventID)
        }

        if let anchorEventID,
           let anchorIndex = sorted.firstIndex(where: { $0.eventID == anchorEventID }) {
            let lowerBound = max(0, anchorIndex - anchorRadius)
            let upperBound = min(sorted.count - 1, anchorIndex + anchorRadius)
            for index in lowerBound...upperBound {
                retained.insert(sorted[index].eventID)
            }
        }

        return retained
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter TimelineIndexPolicy
```

Expected: PASS.

- [ ] **Step 5: Commit policy**

Run:

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrTimelineIndexPolicy.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Add timeline index retention policy"
```

Expected: commit succeeds.

## Phase 2: Core Timeline Index Pruning

### Task 5: Add event store API to prune timeline index entries

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing pruning tests**

Add tests that save five timeline entries and then prune with a policy.

Expected behavior:

```text
- recent entries are kept
- gap_before/gap_after entries are kept
- anchor radius entries are kept
- old unprotected entries are deleted
- events table rows remain untouched
```

Test assertion shape:

```swift
let remaining = try store.timelineEntries(accountID: "account", timelineKey: "home", limit: 10).map(\\.eventID)
#expect(remaining.contains("anchor"))
#expect(remaining.contains("gap-newer"))
#expect(!remaining.contains("old-unprotected"))
#expect(try store.event(id: "old-unprotected") != nil)
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter PrunesTimelineIndex
```

Expected: FAIL because pruning API does not exist.

- [ ] **Step 3: Implement API**

Add to `NostrEventStore`:

```swift
public func pruneTimelineEntries(
    accountID: String,
    timelineKey: String,
    policy: NostrTimelineIndexPolicy,
    anchorEventID: String?,
    now: Int = Int(Date().timeIntervalSince1970)
) throws -> Int
```

Implementation:

```text
1. Read all candidate entries for account/timeline.
2. Convert records to `NostrTimelineIndexCandidate`.
3. Ask policy for retained IDs.
4. Delete rows not in retained IDs.
5. Return deleted count.
6. Never delete from `events`.
```

- [ ] **Step 4: Run core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter PrunesTimelineIndex
swift test --package-path Packages/AstrenzaCore
```

Expected: PASS.

- [ ] **Step 5: Commit pruning API**

Run:

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Prune timeline index entries safely"
```

Expected: commit succeeds.

## Phase 3: Deletion Tombstone Finalization

### Task 6: Support pending kind:5 deletion requests

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing pending deletion test**

Test:

```swift
@Test("Nostr event store applies pending same-author deletion after target arrives")
func eventStoreAppliesPendingDeletionAfterTargetArrives() throws {
    let store = try temporaryEventStore()
    let author = "author-pubkey"
    let target = nostrEvent(kind: 1, pubkey: author, createdAt: 100, content: "delete later")
    let deletion = nostrEvent(kind: 5, pubkey: author, createdAt: 120, content: "remove", tags: [["e", target.id]])

    try store.save(events: [deletion])
    #expect(try store.event(id: target.id) == nil)

    try store.save(events: [target])
    let reloaded = try #require(store.event(id: target.id))
    #expect(reloaded.deletedAt == deletion.createdAt)
}
```

- [ ] **Step 2: Run failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter PendingDeletion
```

Expected: FAIL.

- [ ] **Step 3: Implement pending tombstone support**

Implementation rules:

```text
- Persist kind:5 events even if targets are missing.
- Store pending `e` deletion targets in `deletion_tombstones` or a new compatible table.
- When a target event is later saved, check pending tombstone author_pubkey == target.pubkey.
- Apply `events.deleted_at`.
- Ignore deletion requests from different authors.
```

- [ ] **Step 4: Run deletion tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter Deletion
```

Expected: PASS.

- [ ] **Step 5: Commit pending deletion support**

Run:

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Apply pending deletion tombstones"
```

Expected: commit succeeds.

### Task 7: Add addressable `a` tag deletion representation

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Write failing address deletion test**

Test behavior:

```text
- kind:5 with `["a", "30023:<pubkey>:<d>"]` stores an address deletion tombstone.
- matching addressable events by same pubkey and created_at <= deletion.created_at are marked deleted.
- newer versions after deletion.created_at remain visible.
```

- [ ] **Step 2: Run failure**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter AddressableDeletion
```

Expected: FAIL.

- [ ] **Step 3: Implement address tombstones**

Implementation:

```text
- Extend tombstone storage with target_kind, target_pubkey, target_d_tag, target_type.
- Preserve existing event-id tombstone reads.
- Apply to addressable events on save.
- Do not break existing `deletedTimelineEntries`.
```

- [ ] **Step 4: Run core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected: PASS.

- [ ] **Step 5: Commit address deletion support**

Run:

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Support addressable deletion tombstones"
```

Expected: commit succeeds.

## Phase 4: App Projection Renaming and Boundaries

### Task 8: Introduce `NostrTimelineProjection` facade

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineProjection.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineMaterializer.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add app-level tests for facade parity**

Add a test that calls both current materializer and new projection facade with identical input and expects identical `TimelineFeedEntry` IDs.

Expected new API:

```swift
let entries = NostrTimelineProjection.entries(...)
```

- [ ] **Step 2: Run failure**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: FAIL because facade does not exist.

- [ ] **Step 3: Implement facade**

Create `NostrTimelineProjection.swift`:

```swift
import Foundation
import AstrenzaCore

enum NostrTimelineProjection {
    static func entries(
        noteEvents: [NostrEvent],
        contextEvents: [NostrEvent] = [],
        metadataEvents: [NostrEvent],
        nip05Resolutions: [String: NostrNIP05Resolution] = [:],
        followedPubkeys: Set<String>,
        mediaAssetsByEventID: [String: [NostrMediaAssetRecord]] = [:],
        linkPreviewsByNormalizedURL: [String: NostrLinkPreviewRecord] = [:],
        filterRules: NostrFilterRuleSet? = nil,
        deletedEntries: [NostrDeletedTimelineEntryRecord] = [],
        timelineEntries: [NostrTimelineEntryRecord] = [],
        relayCount: Int = 1,
        timeline: NostrFilterTimelineScope = .home,
        policy: NostrSyncPolicy = .default(networkType: .unknown, lowPowerMode: false)
    ) -> [TimelineFeedEntry] {
        NostrTimelineMaterializer.entries(
            noteEvents: noteEvents,
            contextEvents: contextEvents,
            metadataEvents: metadataEvents,
            nip05Resolutions: nip05Resolutions,
            followedPubkeys: followedPubkeys,
            mediaAssetsByEventID: mediaAssetsByEventID,
            linkPreviewsByNormalizedURL: linkPreviewsByNormalizedURL,
            filterRules: filterRules,
            deletedEntries: deletedEntries,
            timelineEntries: timelineEntries,
            relayCount: relayCount,
            timeline: timeline,
            policy: policy
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit facade**

Run:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrTimelineProjection.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Introduce timeline projection facade"
```

Expected: commit succeeds.

### Task 9: Move call sites from materializer to projection facade

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineRepository.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Replace app call sites**

Replace direct calls:

```swift
NostrTimelineMaterializer.entries(...)
NostrTimelineMaterializer.posts(...)
```

with projection facade calls where possible:

```swift
NostrTimelineProjection.entries(...)
```

Keep lower-level pure helpers only if they are still app-only and do not imply DB persistence.

- [ ] **Step 2: Run focused app tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 3: Commit call-site migration**

Run:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/HomeTimelineRepository.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Route timeline rows through projection facade"
```

Expected: commit succeeds.

## Phase 5: Projection Refresh Coalescing

### Task 10: Introduce projection refresh coordinator

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Nostr/NostrProjectionRefreshCoordinator.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Test behavior:

```text
- First schedule creates one refresh.
- Multiple schedules before execution coalesce into one refresh.
- Immediate schedules can force refresh.
- Cancelling prevents pending refresh.
```

- [ ] **Step 2: Implement coordinator**

Create a small `@MainActor` type that stores a pending `Task<Void, Never>?` and calls a supplied closure after a delay.

Signature:

```swift
@MainActor
final class NostrProjectionRefreshCoordinator {
    init(delayNanoseconds: UInt64)
    func schedule(_ operation: @escaping @MainActor () -> Void)
    func flush(_ operation: @escaping @MainActor () -> Void)
    func cancel()
}
```

- [ ] **Step 3: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 4: Commit coordinator**

Run:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrProjectionRefreshCoordinator.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Coalesce timeline projection refreshes"
```

Expected: commit succeeds.

### Task 11: Use coordinator for delayed fact refreshes

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Replace ad-hoc projection delay task**

Replace local `materializeTask` scheduling with `NostrProjectionRefreshCoordinator`.

Rules:

```text
- kind:0/NIP-05/media/link-preview/repost-target/reply-target updates schedule coalesced refresh.
- pull-to-refresh/home tap/gap fill completion can flush immediately.
- visible row ID window remains stable unless timeline_entries changed.
```

- [ ] **Step 2: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 3: Commit refresh coordinator integration**

Run:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Integrate coalesced projection refresh"
```

Expected: commit succeeds.

## Phase 6: Timeline Membership vs Event Ingestion

### Task 12: Add tests for DB-save without timeline membership insertion

**Files:**
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`

- [ ] **Step 1: Write failing tests**

Add tests for these cases:

```text
- When user is not at newest window, relay event save does not insert into timeline_entries immediately.
- unmaterialized count increases.
- Pull-to-refresh inserts selected new events into timeline_entries.
- Home top live mode inserts immediately without scroll jump.
```

- [ ] **Step 2: Implement missing separation**

Ensure:

```text
save(events:) always stores facts.
timeline_entries insertion happens only through explicit timeline index update paths.
```

- [ ] **Step 3: Run app tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 4: Commit membership separation**

Run:

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Separate event ingestion from timeline membership"
```

Expected: commit succeeds.

## Phase 7: Search and Media Sidecar Boundaries

### Task 13: Document and enforce media/link metadata boundary

**Files:**
- Modify: `Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add tests that media/OGP updates only refresh projection**

Test behavior:

```text
- media_assets update changes projected media view.
- timeline_entries rows do not change.
- link_previews update changes projected OGP.
- timeline_entries rows do not change.
```

- [ ] **Step 2: Fix any coupling found**

If media/link update paths insert or reorder timeline entries, move that behavior to projection refresh only.

- [ ] **Step 3: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: PASS.

- [ ] **Step 4: Commit metadata boundary**

Run:

```bash
git add Documents/Plans/2026-06-09-local-db-projection-architecture-audit.md Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Astrenza/Sources/AstrenzaApp/Nostr
git commit -m "Keep media and link metadata out of timeline membership"
```

Expected: commit succeeds.

## Phase 8: Benchmark Harness

### Task 14: Add local DB timeline benchmark fixtures

**Files:**
- Create or modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Optional create: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrTimelineBenchmarkFixtures.swift`

- [ ] **Step 1: Add benchmark-like correctness tests**

Add tests that seed:

```text
- 10,000 kind:1 events
- event_tags for reply and hashtags
- timeline_entries for home
- deletion tombstones for a subset
```

Assertions:

```text
- restore window around anchor returns stable count
- timeline index pruning deletes only unprotected rows
- deleted entries remain projected as deleted records
```

- [ ] **Step 2: Run core tests**

Run:

```bash
swift test --package-path Packages/AstrenzaCore --filter Timeline
```

Expected: PASS within acceptable local runtime.

- [ ] **Step 3: Commit benchmark fixtures**

Run:

```bash
git add Packages/AstrenzaCore/Tests/AstrenzaCoreTests
git commit -m "Add timeline persistence benchmark fixtures"
```

Expected: commit succeeds.

## Phase 9: Final Verification

### Task 15: Run full verification

**Files:**
- Modify: none unless fixes are required

- [ ] **Step 1: Run core test suite**

Run:

```bash
swift test --package-path Packages/AstrenzaCore
```

Expected: PASS.

- [ ] **Step 2: Run app test suite**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests
```

Expected: PASS.

- [ ] **Step 3: Build app**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit final stabilization if required**

Only if verification fixes were needed:

```bash
git add <changed-files>
git commit -m "Stabilize local DB projection architecture"
```

Expected: commit succeeds or no commit needed.

## Phase 10: Deferred Follow-Ups

These are not part of the first implementation pass.

- SQLite FTS5 sidecar `search.sqlite`.
- SQLCipher/full DB encryption evaluation.
- `VACUUM INTO`/checkpoint maintenance scheduling.
- nostrdb/LMDB sidecar benchmark.
- Global search or external social graph services.
- Android/KMP SQLDelight migration.

## Self-Review

- Spec coverage: Covers GRDB primary store, facts/indexes, app-layer projection, `timeline_entries`, pruning, kind:5, media/link metadata, observation/coalescing, and benchmarks.
- Placeholder scan: No `TBD`, `TODO`, or unspecified "write tests" steps remain. Each task names files, behavior, commands, and expected result.
- Type consistency: Uses existing `NostrTimelineEntryRecord`, `NostrDeletedTimelineEntryRecord`, `TimelinePost`, `TimelineFeedEntry`, `NostrTimelineMaterializer`, and proposed `NostrTimelineProjection` consistently.
- Scope check: This is large but phased. Each phase can be validated and committed independently.
