# Home Timeline Unread Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ivory式に、右上Pillを「現在Rowに投影済みだが未読の件数」、Home Tab右下dotを「DB保存済みだが未投影の新着あり」、Home Tab再押下を「現在Rowトップへのジャンプ/元位置復帰」として分離して実働化する。

**Architecture:** `NostrHomeTimelineStore` はDB未投影新着と投影済み未読を別々の状態として公開する。`TimelineFeedView` はviewport内のpost frameから読了境界候補を通知し、`HomeTimelineView` は右上Pill、Tab dot、Home再押下の一時的な戻りanchorを調停する。DB永続のread cursorは後続Phaseに残し、MVPでは表示中セッションでの挙動を安定させる。

**Tech Stack:** SwiftUI, UIKit `UITabBarController`/`UITab`, Swift Testing, XcodeGen, existing GRDB-backed `NostrEventStore`

---

## File Structure

- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
  - `pendingNew*` を `unmaterializedNew*` にrenameする。
  - 投影済み未読件数、dismiss世代、read boundary、viewport relationを管理する。
  - `markMaterializedPostsRead(visiblePostIDs:)` と `dismissUnreadBadge()` を追加する。

- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - 右上Pillを固定値からStoreの `visibleUnreadBadgeCount` に結線する。
  - `TimelineFeedView` からvisible post IDsを受け取り、Storeへ既読候補を通知する。
  - Home Tab再押下時の `returnAnchor` / `restore` 状態を持つ。

- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
  - `HomeUnreadBadge` に `count` を渡す。
  - Tapは「Pill dismiss」として扱う。

- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTabs.swift`
  - `hasUnmaterializedHomeEvents` と `isHomeReturnMode` を受け取り、Home tabのdotと下矢印アイコンを表現する。
  - 選択中Home tab再タップを `onHomeRetap` へ通知する。

- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTypes.swift`
  - Home tab icon helperにreturn modeを表現できる入口を追加する。

- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
  - post frameからviewport内/読了ライン通過post IDsを上位へ通知する。
  - 呼び出し元互換のためcallbackはdefault no-opにする。

- Test: `Astrenza/Tests/AstrenzaTests/HomeTimelineUnreadStateTests.swift`
  - Storeの未投影新着、投影済み未読、dismiss、既読化の状態遷移をSwift Testingで確認する。

---

### Task 1: Store状態をDB未投影新着と投影済み未読に分離する

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/HomeTimelineUnreadStateTests.swift`

- [ ] **Step 1: Write the failing state tests**

Create `Astrenza/Tests/AstrenzaTests/HomeTimelineUnreadStateTests.swift` with tests equivalent to:

```swift
import Testing
@testable import Astrenza

@MainActor
@Suite("Home timeline unread state")
struct HomeTimelineUnreadStateTests {
    @Test("materialized unread count ignores unmaterialized new events")
    func materializedUnreadCountIsSeparateFromUnmaterializedEvents() {
        let store = NostrHomeTimelineStore()

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.testingSetUnmaterializedNewEventIDs(["db-new-1"])

        #expect(store.materializedUnreadCount == 2)
        #expect(store.visibleUnreadBadgeCount == 2)
        #expect(store.unmaterializedNewCount == 1)
    }

    @Test("dismissing badge hides only the current unread generation")
    func unreadBadgeDismissIsGenerationScoped() {
        let store = NostrHomeTimelineStore()

        store.testingSetMaterializedPostIDs(["new-1", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")
        store.dismissUnreadBadge()
        #expect(store.visibleUnreadBadgeCount == 0)

        store.testingSetMaterializedPostIDs(["new-2", "new-1", "old-1"])
        #expect(store.visibleUnreadBadgeCount == 2)
    }

    @Test("marking visible materialized posts read decreases unread count")
    func markVisiblePostsReadDecreasesCount() {
        let store = NostrHomeTimelineStore()

        store.testingSetMaterializedPostIDs(["new-1", "new-2", "old-1"])
        store.testingSetReadBoundary(postID: "old-1")

        store.markMaterializedPostsRead(visiblePostIDs: ["new-1"])
        #expect(store.materializedUnreadCount == 1)

        store.markMaterializedPostsRead(visiblePostIDs: ["new-2"])
        #expect(store.materializedUnreadCount == 0)
    }
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: fail because the testing helpers and unread APIs do not exist.

- [ ] **Step 3: Implement minimal store state**

In `NostrHomeTimelineStore`, rename:

```swift
@Published private(set) var pendingNewCount = 0
private var pendingNewEventIDs = Set<String>()
```

to:

```swift
@Published private(set) var unmaterializedNewCount = 0
private var unmaterializedNewEventIDs = Set<String>()
```

Add:

```swift
@Published private(set) var materializedUnreadCount = 0
@Published private(set) var visibleUnreadBadgeCount = 0

private var materializedPostIDs: [String] = []
private var readPostIDs = Set<String>()
private var unreadBadgeDismissedGeneration: String?
```

Add `recomputeMaterializedUnreadState()` that:

```swift
materializedPostIDs = entries.compactMap(\.post?.id)
let unreadIDs = materializedPostIDs.filter { !readPostIDs.contains($0) }
materializedUnreadCount = unreadIDs.count
let generation = unreadIDs.joined(separator: "|")
visibleUnreadBadgeCount = generation.isEmpty || unreadBadgeDismissedGeneration == generation ? 0 : unreadIDs.count
```

Call it after `materializeEntries()`, `applyPendingNewEvents()`, restore/reset paths, and whenever read state changes.

Add:

```swift
func dismissUnreadBadge()
func markMaterializedPostsRead(visiblePostIDs: [String])
```

For MVP, `markMaterializedPostsRead` inserts visible IDs into `readPostIDs` only if the ID is in `materializedPostIDs`.

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: unread state tests pass.

---

### Task 2: Right-top unread Pillを実数表示にする

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [ ] **Step 1: Update `HomeUnreadBadge` API**

Change:

```swift
struct HomeUnreadBadge: View {
    let onTap: () -> Void
```

to:

```swift
struct HomeUnreadBadge: View {
    let count: Int
    let onTap: () -> Void

    private var displayCount: String {
        count > 999 ? "999+" : "\(count)"
    }
```

Use `displayCount` for text and accessibility label.

- [ ] **Step 2: Connect badge display in `HomeTimelineView`**

Replace fixed rendering:

```swift
HomeUnreadBadge(onTap: dismissFloatingMenus)
```

with:

```swift
if liveTimelineStore.visibleUnreadBadgeCount > 0 {
    HomeUnreadBadge(count: liveTimelineStore.visibleUnreadBadgeCount) {
        liveTimelineStore.dismissUnreadBadge()
        dismissFloatingMenus()
    }
}
```

Expected: right-top badge disappears when there are no materialized unread rows or after tap.

---

### Task 3: Tab dotとHome下矢印復帰をTab wrapperに結線する

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTabs.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTypes.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [ ] **Step 1: Add state inputs to `UIKitTimelineTabView`**

Add properties:

```swift
let hasUnmaterializedHomeEvents: Bool
let isHomeReturnMode: Bool
let onHomeRetap: () -> Void
```

Pass them from `HomeTimelineView`:

```swift
hasUnmaterializedHomeEvents: liveTimelineStore.unmaterializedNewCount > 0,
isHomeReturnMode: homeReturnAnchor != nil,
onHomeRetap: handleHomeTabRetap,
```

- [ ] **Step 2: Update Home icon and dot**

Add helper in `TimelineTab`:

```swift
func systemName(isSelected: Bool, isReturnMode: Bool) -> String {
    if self == .home, isReturnMode {
        return "arrow.down"
    }
    return systemName(isSelected: isSelected)
}
```

In `Coordinator`, update home tab image when props change:

```swift
tabs[.home]?.image = UIImage(
    systemName: TimelineTab.home.systemName(
        isSelected: parent.selectedTab == .home,
        isReturnMode: parent.isHomeReturnMode
    )
)
tabs[.home]?.badgeValue = parent.hasUnmaterializedHomeEvents ? " " : nil
```

This uses a minimal native badge dot. Later visual polish can replace it with a custom overlay if needed.

- [ ] **Step 3: Detect selected Home retap**

In `didSelectTab` / `didSelect`, if previous selected tab was also `.home`, call `parent.onHomeRetap()`. Guard compose as before.

Expected:
- Home tab dot tracks DB-unmaterialized events.
- When return anchor exists, Home icon becomes down arrow.
- Retapping selected Home calls Home-specific handler.

---

### Task 4: Viewportから既読化を通知する

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [ ] **Step 1: Add callback to `TimelineFeedView`**

Add property and initializer default:

```swift
let onReadablePostIDsChanged: ([TimelinePost.ID]) -> Void
```

Default to `{ _ in }` for compatibility.

- [ ] **Step 2: Compute readable IDs from measured frames**

In `handleObservedContentOffset(_:)`, after `saveViewportStateIfPossible()`, compute:

```swift
let readLineY = topContentPadding + 24
let readableIDs = scrollRuntime.postFrames
    .filter { _, frame in frame.minY <= readLineY && frame.maxY > 0 }
    .map(\.key)
onReadablePostIDsChanged(readableIDs)
```

Use the existing frame preference cache; do not add new GeometryReaders.

- [ ] **Step 3: Connect to Store**

In `HomeTimelineView.timelineList`, pass:

```swift
onReadablePostIDsChanged: { ids in
    guard sessionStore.account != nil, selectedTimeline == .home else { return }
    liveTimelineStore.markMaterializedPostsRead(visiblePostIDs: ids)
}
```

Expected: scrolling toward latest over materialized unread rows reduces right-top Pill count.

---

### Task 5: Home Tab top jump / return anchor

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`

- [ ] **Step 1: Add Home return state**

In `HomeTimelineView`:

```swift
@State private var homeReturnAnchor: TimelineViewportState?
@State private var homeScrollCommand: TimelineScrollCommand?
```

Define:

```swift
struct TimelineScrollCommand: Equatable, Identifiable {
    enum Target: Equatable { case top; case viewport(TimelineViewportState) }
    let id = UUID()
    let target: Target
}
```

- [ ] **Step 2: Make `TimelineFeedView` accept scroll command**

Add optional `scrollCommand: TimelineScrollCommand?`.

On change:

```swift
.onChange(of: scrollCommand?.id) { _, _ in
    guard let scrollCommand else { return }
    switch scrollCommand.target {
    case .top:
        if let firstPostID = posts.first?.id {
            scrollPosition.scrollTo(id: firstPostID, anchor: .top)
        } else {
            scrollPosition.scrollTo(y: 0)
        }
    case .viewport(let state):
        scrollPosition.scrollTo(id: state.anchorPostID, anchor: .top)
    }
}
```

- [ ] **Step 3: Implement `handleHomeTabRetap`**

In `HomeTimelineView`:

```swift
func handleHomeTabRetap() {
    guard selectedTab == .home, selectedTimeline == .home else { return }
    if let returnAnchor = homeReturnAnchor {
        homeScrollCommand = TimelineScrollCommand(target: .viewport(returnAnchor))
        homeReturnAnchor = nil
    } else {
        homeReturnAnchor = homeViewportState
        homeScrollCommand = TimelineScrollCommand(target: .top)
    }
}
```

Clear `homeReturnAnchor` when switching timeline, opening detail, or selecting another tab.

Expected: Home tap jumps to current materialized top and changes icon to down arrow; down arrow tap restores saved position.

---

### Task 6: Verification and commit

**Files:**
- All changed files

- [ ] **Step 1: Generate project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds.

- [ ] **Step 2: Run tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: tests pass.

- [ ] **Step 3: Build app**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/superpowers/plans/2026-06-08-home-timeline-unread-pill.md Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTabs.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTypes.swift Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift Astrenza/Tests/AstrenzaTests/HomeTimelineUnreadStateTests.swift
git commit -m "Make home timeline unread pill live"
```

---

## Self-Review

- Spec coverage: Ivory式の右上Pill、Home Tab dot、Home下矢印復帰をそれぞれ独立Taskで実装する。
- Placeholder scan: この計画にTBD/TODO/未定義の実装指示は残していない。
- Type consistency: `unmaterializedNewCount`, `materializedUnreadCount`, `visibleUnreadBadgeCount`, `TimelineScrollCommand` を計画内で一貫して使う。
- Scope: read cursorのDB永続化は後続Phase。今回のMVPは実働表示と操作分離に集中する。
