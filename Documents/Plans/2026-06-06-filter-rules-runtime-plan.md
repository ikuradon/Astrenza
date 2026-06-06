# Filter Rules Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Ivory-style Filters screen persist user-facing filter options and apply them to the live Home timeline.

**Architecture:** Extend `NostrFilterRuleRecord` instead of adding a parallel settings table, because the UI edits one logical filter rule at a time and Home timeline materialization already accepts `NostrFilterRuleSet`. Store scope and presentation metadata in GRDB, keep existing rows backward-compatible through defaults, and pass only Home-applicable rules into the timeline materializer. Matching counts are computed from cached local events for the selected account as an MVP, with NIP-51 public mute list items still merged into the runtime rule set.

**Tech Stack:** Swift, SwiftUI, Swift Testing, GRDB, XcodeGen, `AstrenzaCore`.

---

## File Structure

- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
  - Add persisted filter presentation and scope enums.
  - Extend `NostrFilterRuleRecord` with `presentation` and `scopes`.
  - Add helpers for `applies(to:)`, `matchingRule(for:timeline:)`, and `matchingCount`.
- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - Add a migration for `presentation` and `scopes_json`.
  - Save/decode the new fields while defaulting old data to warning-masked Home/List/Public scope.
  - Add a cached event matching count query helper.
- Modify `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Add tests for scope-aware matching, persistence defaults, update persistence, and matching count.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
  - Convert UI scope values to/from core scope values.
  - Save `Mask with a Warning` as rule presentation.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
  - Use real matching count values passed by the overview screen.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
  - Populate editor drafts with DB-backed matching counts.
  - Save scope and presentation options into `filter_rules`.
- Modify `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Pass only rules applying to `.home` into `NostrFilterRuleSet`.

## Task 1: Save Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-06-filter-rules-runtime-plan.md`

- [ ] **Step 1: Save this plan**

Save this plan to the file path above.

- [ ] **Step 2: Create goal**

Create this active goal:

```text
Documents/Plans/2026-06-06-filter-rules-runtime-plan.md を実行し、Filters の scope/presentation/duration/matching count を GRDB と Home TL materializer に結線し、検証、commit まで完了する。
```

## Task 2: Add Core Filter Option Tests

**Files:**
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add tests near existing filter rule tests**

Add tests that verify:

```swift
@Test("Nostr filter rules honor timeline scope and presentation")
func filterRulesHonorTimelineScopeAndPresentation() throws {
    let pubkey = String(repeating: "b", count: 64)
    let event = nostrEvent(kind: 1, pubkey: pubkey, content: "hello scoped timeline")
    let homeRule = NostrFilterRuleRecord(
        ruleID: "home",
        accountID: "account",
        kind: .keyword,
        value: "scoped",
        presentation: .maskWithWarning,
        scopes: [.home],
        createdAt: 1,
        updatedAt: 1
    )
    let mentionsRule = NostrFilterRuleRecord(
        ruleID: "mentions",
        accountID: "account",
        kind: .keyword,
        value: "scoped",
        presentation: .hide,
        scopes: [.mentions],
        createdAt: 1,
        updatedAt: 1
    )

    let rules = NostrFilterRuleSet(rules: [mentionsRule, homeRule])
    #expect(rules.match(event: event, timeline: .home, now: 20) == .keyword("scoped"))
    #expect(rules.match(event: event, timeline: .threads, now: 20) == nil)
    #expect(homeRule.presentation == .maskWithWarning)
    #expect(mentionsRule.presentation == .hide)
}
```

Also add tests for DB persistence and matching count:

```swift
@Test("Nostr event store persists filter rule options and counts cached matches")
func eventStorePersistsFilterRuleOptionsAndCountsMatches() throws {
    let store = try NostrEventStore.inMemory()
    let account = String(repeating: "a", count: 64)
    let matching = nostrEvent(kind: 1, pubkey: account, content: "quiet keyword")
    let other = nostrEvent(kind: 1, pubkey: account, content: "ordinary text")
    try store.save(events: [matching, other])

    let rule = NostrFilterRuleRecord(
        ruleID: "rule-1",
        accountID: account,
        kind: .keyword,
        value: "keyword",
        presentation: .hide,
        scopes: [.home, .lists],
        createdAt: 100,
        updatedAt: 100
    )
    try store.saveFilterRule(rule)

    #expect(try store.filterRules(accountID: account) == [rule])
    #expect(try store.filterRuleMatchingCount(accountID: account, rule: rule, timeline: .home, now: 200) == 1)
    #expect(try store.filterRuleMatchingCount(accountID: account, rule: rule, timeline: .mentions, now: 200) == 0)
}
```

- [ ] **Step 2: Run the focused package tests and confirm failure**

Run:

```bash
cd Packages/AstrenzaCore
swift test --filter NostrCorePackageTests
```

Expected: tests fail because `NostrFilterRulePresentation`, `NostrFilterTimelineScope`, and matching count APIs do not exist yet.

## Task 3: Implement Core Model and Store Support

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`

- [ ] **Step 1: Extend filter model**

Add:

```swift
public enum NostrFilterRulePresentation: String, Codable, Equatable, Sendable {
    case maskWithWarning
    case hide
}

public enum NostrFilterTimelineScope: String, Codable, CaseIterable, Equatable, Sendable {
    case home
    case mentions
    case threads
    case lists
    case publicTimelines
}
```

Extend `NostrFilterRuleRecord` with:

```swift
public let presentation: NostrFilterRulePresentation
public let scopes: Set<NostrFilterTimelineScope>
```

Default initializer values:

```swift
presentation: NostrFilterRulePresentation = .maskWithWarning,
scopes: Set<NostrFilterTimelineScope> = [.home, .lists, .publicTimelines]
```

Add scope-aware helpers:

```swift
public func applies(to timeline: NostrFilterTimelineScope) -> Bool {
    scopes.contains(timeline)
}

public func match(event: NostrEvent, timeline: NostrFilterTimelineScope = .home, now: Int) -> NostrFilterMatchReason? {
    matchingRule(for: event, timeline: timeline, now: now).map { matchReason(rule: $0, event: event) }
}

public func matchingRule(for event: NostrEvent, timeline: NostrFilterTimelineScope = .home, now: Int) -> NostrFilterRuleRecord? {
    activeRules(now: now).first { rule in
        rule.applies(to: timeline) && matches(rule: rule, event: event)
    }
}
```

- [ ] **Step 2: Add migration and persistence**

Add migration after `addLocalFiltersAndBookmarks`:

```swift
migrator.registerMigration("addFilterRulePresentationAndScopes") { db in
    try db.alter(table: "filter_rules") { table in
        table.add(column: "presentation", .text).notNull().defaults(to: NostrFilterRulePresentation.maskWithWarning.rawValue)
        table.add(column: "scopes_json", .blob)
    }
}
```

Update save/select/decode to include `presentation` and `scopes_json`.

- [ ] **Step 3: Add matching count helper**

Add to `NostrEventStore`:

```swift
public func filterRuleMatchingCount(
    accountID: String,
    rule: NostrFilterRuleRecord,
    timeline: NostrFilterTimelineScope,
    now: Int = Int(Date().timeIntervalSince1970)
) throws -> Int
```

Implementation reads cached kind:1 events, wraps `rule` in `NostrFilterRuleSet`, and counts scope-aware matches.

- [ ] **Step 4: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test --filter NostrCorePackageTests
```

Expected: package tests pass.

## Task 4: Connect Filters UI to Core Options

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`

- [ ] **Step 1: Bridge UI scopes**

Add conversions between `FilterApplicationScope` and `NostrFilterTimelineScope`.

- [ ] **Step 2: Preserve existing rule options in editor drafts**

When opening an existing rule, populate:

```swift
masksWithWarning: rule.presentation == .maskWithWarning
selectedScopes: Set(rule.scopes.map(FilterApplicationScope.init(coreScope:)))
matchingCount: injected count from the store
```

- [ ] **Step 3: Save UI options to core rules**

When `FilterEditorDraft.rule(accountID:now:)` builds `NostrFilterRuleRecord`, set:

```swift
presentation: masksWithWarning ? .maskWithWarning : .hide
scopes: Set(selectedScopes.map(\.coreScope))
```

- [ ] **Step 4: Compute matching counts before showing editors**

In `NostrListSettingsView`, create drafts through helper methods that call:

```swift
try eventStore.filterRuleMatchingCount(accountID: accountID, rule: draft.rule(accountID: accountID, now: now), timeline: .home, now: now)
```

Fallback to zero on errors and keep `loadError` for visible failures only.

## Task 5: Apply Scope to Home Timeline

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift`

- [ ] **Step 1: Use scope-aware matching in core materializer**

Call:

```swift
filterRules?.match(event: event, timeline: .home, now: now)
```

- [ ] **Step 2: Pass only Home-applicable local and NIP-51 rules to timeline store**

In `filterRuleSet()`, filter persisted rules with:

```swift
rules = rules.filter { $0.applies(to: .home) }
```

NIP-51 public mute rules keep default Home/List/Public scopes.

## Task 6: Final Verification and Commit

**Files:**
- Verify all changed files.

- [ ] **Step 1: Generate project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds.

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
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRuntime-DerivedData -skipMacroValidation test
```

Expected: all app tests pass. Existing SwiftUI runtime warnings may remain.

- [ ] **Step 4: Commit**

Run:

```bash
git add Documents/Plans/2026-06-06-filter-rules-runtime-plan.md Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineMaterializer.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift
git commit -m "Apply persisted filter rule options"
```
