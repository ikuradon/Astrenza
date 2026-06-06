# Filter Matching Posts and Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make filter rules observable and visibly effective by adding Matching Posts inspection, hide-vs-warning timeline behavior, and duration persistence.

**Architecture:** Keep `filter_rules` as the source of truth. Use existing `expires_at` for duration, the existing `presentation` column for hide versus warning, and cached kind:1 events for Matching Posts inspection. Keep UI changes scoped to the extracted Filters settings files and keep Home timeline behavior in the existing Nostr materializer path.

**Tech Stack:** Swift, SwiftUI, Swift Testing, GRDB, XcodeGen, `AstrenzaCore`.

---

## File Structure

- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
  - Add `NostrFilterMatch` to carry both rule and reason.
  - Add `matchDetail(event:timeline:now:)`.
- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
  - Hide `.hide` filtered posts before they become `NostrHomeTimelineItem`.
  - Keep `.maskWithWarning` posts visible with `filterMatch`.
- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - Add `filterRuleMatchingEvents(...)` for Matching Posts.
  - Make `filterRuleMatchingCount(...)` reuse that query.
- Modify `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Add tests for `.hide` filtering and matching event retrieval.
- Modify `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add app-level materializer test proving `.hide` removes the post and `.maskWithWarning` collapses it.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
  - Add `FilterDuration`.
  - Add `duration` to `FilterEditorDraft` and persist it through `expiresAt`.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
  - Replace static Duration text with a selectable menu.
  - Make Matching Posts row tappable.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
  - Load matching post rows before presenting the sheet.
  - Show a Matching Posts sheet.
- Create `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterMatchingPostsSheet.swift`
  - Simple cached matching-post inspector.

## Task 1: Save Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-07-filter-matching-posts-and-presentation-plan.md`

- [ ] **Step 1: Save this plan**

Save this plan to the path above.

- [ ] **Step 2: Create goal**

Create this active goal:

```text
Documents/Plans/2026-06-07-filter-matching-posts-and-presentation-plan.md を実行し、Matching Posts 表示、hide/maskWithWarning の TL 挙動、Duration 保存を実装し、検証、commit まで完了する。
```

## Task 2: Add Core Tests

**Files:**
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add matching detail and hidden item tests**

Add tests near existing filter tests:

```swift
@Test("Nostr filter rules expose matching rule details")
func filterRulesExposeMatchingRuleDetails() throws {
    let event = nostrEvent(kind: 1, content: "quiet keyword")
    let rule = NostrFilterRuleRecord(
        ruleID: "rule-1",
        accountID: "account",
        kind: .keyword,
        value: "keyword",
        presentation: .hide,
        scopes: [.home],
        createdAt: 1,
        updatedAt: 1
    )
    let match = try #require(NostrFilterRuleSet(rules: [rule]).matchDetail(event: event, timeline: .home, now: 2))
    #expect(match.rule.ruleID == "rule-1")
    #expect(match.rule.presentation == .hide)
    #expect(match.reason == .keyword("keyword"))
}

@Test("Home materializer omits hidden filtered items")
func homeMaterializerOmitsHiddenFilteredItems() throws {
    let author = String(repeating: "a", count: 64)
    let hidden = nostrEvent(kind: 1, pubkey: author, content: "hide this keyword")
    let visible = nostrEvent(kind: 1, pubkey: author, content: "keep this")
    let rules = NostrFilterRuleSet(rules: [
        NostrFilterRuleRecord(
            ruleID: "hide",
            accountID: "account",
            kind: .keyword,
            value: "keyword",
            presentation: .hide,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )
    ])

    let items = NostrHomeTimelineMaterializer.items(
        noteEvents: [hidden, visible],
        metadataEvents: [],
        followedPubkeys: [author],
        filterRules: rules,
        now: 2
    )

    #expect(items.map(\.id) == [visible.id])
}
```

Also add a store test:

```swift
@Test("Nostr event store returns cached filter matching events")
func eventStoreReturnsCachedFilterMatchingEvents() throws {
    let store = try NostrEventStore.inMemory()
    let account = String(repeating: "a", count: 64)
    let first = nostrEvent(kind: 1, pubkey: account, createdAt: 200, content: "quiet keyword")
    let second = nostrEvent(kind: 1, pubkey: account, createdAt: 100, content: "ordinary")
    try store.save(events: [first, second])
    let rule = NostrFilterRuleRecord(
        ruleID: "rule-1",
        accountID: account,
        kind: .keyword,
        value: "keyword",
        presentation: .maskWithWarning,
        scopes: [.home],
        createdAt: 1,
        updatedAt: 1
    )

    #expect(try store.filterRuleMatchingEvents(accountID: account, rule: rule, timeline: .home, now: 300).map(\.id) == [first.id])
    #expect(try store.filterRuleMatchingCount(accountID: account, rule: rule, timeline: .home, now: 300) == 1)
}
```

- [ ] **Step 2: Run focused tests and confirm failure**

Run:

```bash
cd Packages/AstrenzaCore
swift test --filter NostrCorePackageTests
```

Expected: fail because `matchDetail` and `filterRuleMatchingEvents` are not implemented yet.

## Task 3: Implement Core Matching Details and Hide Presentation

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`

- [ ] **Step 1: Add `NostrFilterMatch`**

Add:

```swift
public struct NostrFilterMatch: Equatable, Sendable {
    public let rule: NostrFilterRuleRecord
    public let reason: NostrFilterMatchReason
}
```

Add:

```swift
public func matchDetail(event: NostrEvent, timeline: NostrFilterTimelineScope = .home, now: Int) -> NostrFilterMatch?
```

It should return both the matching rule and reason.

- [ ] **Step 2: Hide `.hide` in home materializer**

In `NostrHomeTimelineMaterializer.items`, if `matchDetail(...).rule.presentation == .hide`, return no item for that event. If it is `.maskWithWarning`, pass `match.reason` to the item.

- [ ] **Step 3: Add matching events store API**

Add:

```swift
public func filterRuleMatchingEvents(
    accountID: String,
    rule: NostrFilterRuleRecord,
    timeline: NostrFilterTimelineScope,
    limit: Int = 10_000,
    now: Int = Int(Date().timeIntervalSince1970)
) throws -> [NostrEvent]
```

Use cached `events(kind: 1, limit: limit, now: now)`, `NostrFilterRuleSet(rules: [rule])`, and `matchingRule`.

- [ ] **Step 4: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test --filter NostrCorePackageTests
```

Expected: focused package tests pass.

## Task 4: Add App Materializer Test

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add hide presentation test**

Add near filtered materializer tests:

```swift
@Test("Nostr materializer hides posts when filter presentation is hide")
func nostrMaterializerHidesFilteredPosts() throws {
    let author = String(repeating: "a", count: 64)
    let hidden = timelineEvent(idSeed: "hidden-note", pubkey: author, createdAt: 100, content: "hide noisy text")
    let visible = timelineEvent(idSeed: "visible-note", pubkey: author, createdAt: 90, content: "plain text")
    let filterRules = NostrFilterRuleSet(rules: [
        NostrFilterRuleRecord(
            ruleID: "rule",
            accountID: "account",
            kind: .keyword,
            value: "noisy",
            presentation: .hide,
            scopes: [.home],
            createdAt: 1,
            updatedAt: 1
        )
    ])

    let posts = NostrTimelineMaterializer.posts(
        noteEvents: [hidden, visible],
        metadataEvents: [],
        followedPubkeys: [author],
        filterRules: filterRules,
        now: 100
    )

    #expect(posts.map(\.id) == [visible.id])
}
```

- [ ] **Step 2: Run app test target after core implementation**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterPresentation-DerivedData -skipMacroValidation test
```

Expected: app tests pass.

## Task 5: Add Duration and Matching Posts UI

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
- Create: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterMatchingPostsSheet.swift`

- [ ] **Step 1: Add `FilterDuration`**

Add enum cases:

```swift
enum FilterDuration: String, CaseIterable, Identifiable {
    case forever = "Forever"
    case oneDay = "24 Hours"
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"
}
```

Add helpers for `expiresAt(from:)` and `init(rule:now:)`.

- [ ] **Step 2: Add duration to `FilterEditorDraft`**

Add:

```swift
var duration: FilterDuration
```

When saving, set:

```swift
expiresAt: duration.expiresAt(from: now)
```

- [ ] **Step 3: Replace Duration text with `Menu`**

In `FilterEditorSheet`, replace static `Text("Forever")` with a `Menu` listing `FilterDuration.allCases`.

- [ ] **Step 4: Make Matching Posts row tappable**

Add `onShowMatchingPosts: (FilterEditorDraft) -> Void` to `FilterEditorSheet`, and wrap the row in a `Button`.

- [ ] **Step 5: Add matching posts sheet**

Create a sheet that displays event content, abbreviated pubkey, and relative created-at text for `FilterMatchingPostRow`.

- [ ] **Step 6: Load matching posts from `NostrListSettingsView`**

When the editor asks to show matching posts, call `eventStore.filterRuleMatchingEvents`, then present the sheet.

## Task 6: Final Verification and Commit

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run `xcodegen generate`**

Expected: success.

- [ ] **Step 2: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test
```

Expected: all package tests pass.

- [ ] **Step 3: Run app tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterPresentation-DerivedData -skipMacroValidation test
```

Expected: all app tests pass. Existing SwiftUI runtime warnings may remain.

- [ ] **Step 4: Commit**

Run:

```bash
git add Documents/Plans/2026-06-07-filter-matching-posts-and-presentation-plan.md Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterMatchingPostsSheet.swift
git commit -m "Show matching posts for filters"
```
