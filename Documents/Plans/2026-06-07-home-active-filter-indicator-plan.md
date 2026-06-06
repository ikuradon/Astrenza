# Home Active Filter Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home timeline に active filter indicator を追加し、現在の Home に効いている local / NIP-51 mute filter の状態を表示し、タップで Filters へ、clear で TL 上だけ一時無効化できるようにする。

**Architecture:** `NostrHomeTimelineStore` が Home に適用する filter rule set を一元的に組み立て、同じ rule set から indicator 用の件数と suspended state を公開する。UI は Home top chrome 直下に小さな Liquid Glass pill として出し、Filters sheet は Settings 全体ではなく account-scoped `NostrListSettingsView` を直接開く。DB の rule は削除せず、clear は current session の Home TL materializer だけを一時的に bypass する。

**Tech Stack:** Swift, SwiftUI, Swift Testing, XcodeGen, `AstrenzaCore`.

---

## File Structure

- Modify `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - Add `TimelineFilterStatus`.
  - Publish `filterStatus`.
  - Add `suspendTimelineFilters()` and `resumeTimelineFilters()`.
  - Use one shared filter rule builder for materialization and indicator counts.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
  - Add `HomeFilterIndicator`.
- Modify `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - Place indicator under the top chrome.
  - Add Filters sheet state and actions.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelinePresentations.swift`
  - Present `NostrListSettingsView` directly from Home.
- Modify `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add app-level tests for filter status and suspend/resume materialization.

## Task 1: Save Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-07-home-active-filter-indicator-plan.md`

- [x] **Step 1: Save this plan**

Save this plan to the path above.

- [x] **Step 2: Create goal**

Create this active goal:

```text
Documents/Plans/2026-06-07-home-active-filter-indicator-plan.md を実行し、Home active filter indicator、Filters 直行 sheet、Home TL の一時 filter clear/resume を実装し、検証、commit まで完了する。
```

## Task 2: Add App Tests

**Files:**
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [x] **Step 1: Add a store status test**

Add a test that creates an in-memory `NostrEventStore`, saves a Home-applicable keyword rule and two notes, starts `NostrHomeTimelineStore`, then verifies:

```swift
#expect(store.filterStatus.activeRuleCount == 1)
#expect(store.filterStatus.warningMatchCount == 1)
#expect(store.filterStatus.hiddenMatchCount == 0)
#expect(store.filterStatus.isSuspended == false)
```

- [x] **Step 2: Add a suspend/resume test**

Add a test that saves a `.hide` keyword rule and two notes. Verify the filtered note is absent first, appears after `suspendTimelineFilters()`, and disappears again after `resumeTimelineFilters()`.

- [x] **Step 3: Run the focused app tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaHomeFilterIndicator-DerivedData -skipMacroValidation test
```

Expected before implementation: compile fails because `filterStatus`, `suspendTimelineFilters`, and `resumeTimelineFilters` do not exist.

## Task 3: Implement Store Filter Status

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`

- [x] **Step 1: Add `TimelineFilterStatus`**

Add an internal Equatable struct with:

```swift
struct TimelineFilterStatus: Equatable {
    var activeRuleCount = 0
    var warningMatchCount = 0
    var hiddenMatchCount = 0
    var isSuspended = false

    var matchedPostCount: Int { warningMatchCount + hiddenMatchCount }
    var isVisible: Bool { activeRuleCount > 0 || isSuspended }
}
```

- [x] **Step 2: Publish status and suspended state**

Add:

```swift
@Published private(set) var filterStatus = TimelineFilterStatus()
private var areTimelineFiltersSuspended = false
```

Add:

```swift
func suspendTimelineFilters()
func resumeTimelineFilters()
```

Both functions re-run `materializeEntries()`.

- [x] **Step 3: Share the rule builder**

Replace ad-hoc `filterRuleSet()` logic with:

```swift
private func homeFilterRules() -> [NostrFilterRuleRecord]
private func homeFilterRuleSet() -> NostrFilterRuleSet?
```

`homeFilterRuleSet()` returns `nil` when `areTimelineFiltersSuspended == true`.

- [x] **Step 4: Update `materializeEntries()` and `materializedPosts(from:)`**

Use `homeFilterRules()` once, pass `nil` to materializers while suspended, and call a helper that counts `.hide` and `.maskWithWarning` matches from cached `noteEvents`.

## Task 4: Add Home Indicator UI

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [x] **Step 1: Add `HomeFilterIndicator`**

Create a compact Liquid Glass pill with:
- `line.3.horizontal.decrease.circle.fill`
- `N filtered` when enabled
- `Filters Off` when suspended
- trailing `xmark.circle.fill` button to suspend
- trailing `arrow.counterclockwise.circle.fill` button to resume

- [x] **Step 2: Place the indicator**

Render it only when:

```swift
visibleTab == .home && !isPostDetailPresented && liveTimelineStore.filterStatus.isVisible
```

Place it under the top chrome, leading aligned, clear of the unread badge.

## Task 5: Wire Filters Sheet

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelinePresentations.swift`

- [x] **Step 1: Add presentation state**

Add `@State private var isFiltersSettingsPresented = false`.

- [x] **Step 2: Add presentation modifier binding**

Extend `homeTimelinePresentations` to accept `isFiltersSettingsPresented`, `accountID`, and `eventStore`, then present:

```swift
NostrListSettingsView(accountID: accountID, eventStore: eventStore)
```

- [x] **Step 3: Indicator tap opens Filters**

Indicator main tap calls `presentFiltersSettings()`.

## Task 6: Verify and Commit

**Files:**
- All modified files above.

- [x] **Step 1: Generate project**

Run:

```bash
xcodegen generate
```

- [x] **Step 2: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test
```

- [x] **Step 3: Run iOS tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaHomeFilterIndicator-DerivedData -skipMacroValidation test
```

- [x] **Step 4: Commit**

Commit message:

```bash
git commit -m "Add home active filter indicator"
```

## Self-Review

- Spec coverage: Home active filter indicator, Filters direct sheet, non-destructive one-tap clear, and resume are covered.
- Placeholder scan: No TBD/TODO placeholders are used.
- Type consistency: `TimelineFilterStatus`, `filterStatus`, `suspendTimelineFilters()`, `resumeTimelineFilters()`, and `isFiltersSettingsPresented` are consistently named across tasks.
