# NIP-51 Filter and Bookmark UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cached NIP-51 mute-list data, local mute rules, and local bookmark actions should affect the real Home TL without deleting source events.

**Architecture:** Keep protocol/data projection in `AstrenzaCore`, account-scoped side effects in `NostrHomeTimelineStore`, and UI action routing in `TimelineFeedView`/`HomeTimelineView`. NIP-51 public mute list items are projected into transient `NostrFilterRuleRecord`s and merged with persisted local rules at materialization time; local bookmark/mute menu actions write to GRDB and then re-materialize the Home TL.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, GRDB-backed `NostrEventStore`, existing `TimelineFeedView` floating menu and settings UI.

---

## Files

- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
  - Add public NIP-51 mute-list projection helper.
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Add tests for NIP-51 public mute item projection.
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Merge local rules with cached NIP-51 mute list.
  - Add `muteAuthor(of:)`, `bookmark(_:)`, and `isBookmarked(_:)`.
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
  - Add callback for `PostActionChoice`.
  - Route Bookmark and Mute choices to parent instead of no-op.
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - Handle post action callbacks for Home TL and profile TL.
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
  - Surface local filter/bookmark counts beside cached NIP-51 list data.
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add app-side materializer test for cached NIP-51 mute projection.

---

## Phase 1: Project NIP-51 Public Mute Items Into Filter Rules

- [x] **Step 1: Add Core test**

Add this test to `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`:

```swift
@Test("NIP-51 public mute items project into filter rules")
func nip51MuteItemsProjectIntoFilterRules() throws {
    let listID = "10000:account:"
    let items = [
        NostrListItemRecord(listID: listID, itemKey: "pubkey:pub", itemType: "pubkey", value: "pub", relayHint: nil, visibility: "public", position: 0),
        NostrListItemRecord(listID: listID, itemKey: "hashtag:nostr", itemType: "hashtag", value: "nostr", relayHint: nil, visibility: "public", position: 1),
        NostrListItemRecord(listID: listID, itemKey: "word:noise", itemType: "word", value: "noise", relayHint: nil, visibility: "public", position: 2),
        NostrListItemRecord(listID: listID, itemKey: "event:ignored", itemType: "event", value: "ignored", relayHint: nil, visibility: "public", position: 3)
    ]

    let rules = NostrFilterRuleSet.publicMuteRules(accountID: "account", items: items, updatedAt: 123)

    #expect(rules.map(\.kind) == [.mutedPubkey, .mutedHashtag, .keyword])
    #expect(rules.map(\.value) == ["pub", "nostr", "noise"])
    #expect(rules.allSatisfy { $0.accountID == "account" && $0.createdAt == 123 && $0.updatedAt == 123 })
}
```

- [x] **Step 2: Run Core test and confirm failure**

Run:

```bash
swift test --filter "NIP-51 public mute items project into filter rules"
```

Expected: FAIL because `NostrFilterRuleSet.publicMuteRules` does not exist.

- [x] **Step 3: Implement projection helper**

Add to `NostrFilterRuleSet` in `NostrFilterRules.swift`:

```swift
public static func publicMuteRules(
    accountID: String,
    items: [NostrListItemRecord],
    updatedAt: Int
) -> [NostrFilterRuleRecord] {
    items.compactMap { item in
        guard let kind = filterKind(forNIP51ItemType: item.itemType) else { return nil }
        return NostrFilterRuleRecord(
            ruleID: "nip51:\(item.listID):\(item.itemKey)",
            accountID: accountID,
            kind: kind,
            value: item.value,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}

private static func filterKind(forNIP51ItemType itemType: String) -> NostrFilterRuleKind? {
    switch itemType {
    case "pubkey":
        .mutedPubkey
    case "hashtag":
        .mutedHashtag
    case "word":
        .keyword
    default:
        nil
    }
}
```

- [x] **Step 4: Run Core package tests**

Run:

```bash
swift test
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift
git commit -m "Project NIP-51 mute lists into filters"
```

---

## Phase 2: Merge Cached NIP-51 Mutes and Add Store Actions

- [x] **Step 1: Add app test**

Add a test to `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift` that creates a `kind:10000` mute list, uses `NostrFilterRuleSet.publicMuteRules`, passes the rule set to `NostrTimelineMaterializer.posts`, and expects the muted author post to remain present with `.filtered` collapse reason.

- [x] **Step 2: Implement store helper**

Update `NostrHomeTimelineStore.filterRuleSet()` so it:

1. loads local `eventStore.filterRules(accountID:)`
2. loads cached `eventStore.listSummaries(accountID:)`
3. filters summaries where `kind == 10_000`
4. loads `eventStore.listItems(listID:)`
5. appends `NostrFilterRuleSet.publicMuteRules(accountID:items:updatedAt:)`
6. returns `nil` only when the merged array is empty

- [x] **Step 3: Add local action methods**

Add these `@MainActor` methods to `NostrHomeTimelineStore`:

```swift
func muteAuthor(of post: TimelinePost)
func bookmark(_ post: TimelinePost)
func isBookmarked(_ post: TimelinePost) -> Bool
```

`muteAuthor(of:)` should write a local `.mutedPubkey` rule for `post.author.pubkey`, then call `materializeEntries()`.

`bookmark(_:)` should write `NostrLocalBookmarkRecord(accountID:eventID:createdAt:)`.

`isBookmarked(_:)` should read local bookmarks for the account and check the post id.

- [x] **Step 4: Run app tests**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaNIP51Filter-DerivedData -skipMacroValidation test
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Merge cached NIP-51 mutes into home filters"
```

---

## Phase 3: Wire Row Menu Actions

- [ ] **Step 1: Extend `TimelineFeedView` callbacks**

Add:

```swift
let onPostActionChoice: (TimelinePost, PostActionChoice) -> Void
```

to both initializers, with a default `{ _, _ in }` for the post-array convenience initializer if needed.

- [ ] **Step 2: Route menu choice**

In `handlePostActionChoice(_:postID:)`, for `.mute` and `.bookmark`, find the post by id, close menus, and call `onPostActionChoice(post, choice)`.

- [ ] **Step 3: Wire Home and Profile timelines**

In `HomeTimelineView`, pass callbacks:

```swift
onPostActionChoice: handlePostActionChoice
```

for Home TL, and a matching callback for profile/detail timeline contexts that at least supports bookmark and mute through `liveTimelineStore`.

- [ ] **Step 4: Add minimal behavior methods**

Add to `HomeTimelineView`:

```swift
func handlePostActionChoice(_ post: TimelinePost, choice: PostActionChoice)
```

Switch:
- `.mute`: `liveTimelineStore.muteAuthor(of: post)`
- `.bookmark`: `liveTimelineStore.bookmark(post)`
- `.viewDetails`: existing open behavior remains in `TimelineFeedView`
- others remain no-op for now

- [ ] **Step 5: Run app tests and commit**

Run the same `xcodegen generate` and `xcodebuild ... test` command from Phase 2.

Commit:

```bash
git add Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift
git commit -m "Wire timeline menu mute and bookmark actions"
```

---

## Phase 4: Settings Counts and Final Verification

- [ ] **Step 1: Extend settings reload**

In `NostrListSettingsView`, add local state:

```swift
@State private var localFilterCount = 0
@State private var localBookmarkCount = 0
```

Load counts from:

```swift
localFilterCount = try eventStore.filterRules(accountID: accountID).count
localBookmarkCount = try eventStore.localBookmarks(accountID: accountID).count
```

- [ ] **Step 2: Add local state section**

Before `NIP-51 LISTS`, add `LOCAL RULES` section with two `NostrListEmptyRow`-style rows or a compact row showing local filter and bookmark counts.

- [ ] **Step 3: Update backlog**

Update `Documents/Plans/2026-06-06-nostr-mvp-deferred-backlog.md`:

- mark NIP-51 public mute projection as completed
- mark local bookmark action storage as connected from row menu
- leave active filter indicator and NIP-51 bookmark publish deferred

- [ ] **Step 4: Final verification**

Run:

```bash
swift test
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaNIP51Filter-DerivedData -skipMacroValidation test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift Documents/Plans/2026-06-06-nip51-filter-bookmark-ui-execution-plan.md Documents/Plans/2026-06-06-nostr-mvp-deferred-backlog.md
git commit -m "Show local filter and bookmark state in settings"
```

---

## Completion Checklist

- [ ] NIP-51 public mute `p`/`t`/`word` items become filter rules.
- [ ] Cached NIP-51 mutes and local filter rules both affect Home TL materialization.
- [ ] Row gear menu Bookmark writes local bookmark state.
- [ ] Row gear menu Mute writes local muted-pubkey state and refreshes Home TL.
- [ ] Settings shows both cached NIP-51 list data and local filter/bookmark counts.
- [ ] Core and app tests pass.
