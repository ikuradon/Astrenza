# Filter Settings Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the Ivory-style Filters settings implementation out of `SettingsView.swift`, keep current behavior intact, and prepare the codebase for persisted filter options and real matching counts.

**Architecture:** Keep shared settings primitives in `SettingsView.swift` for now, because many existing settings screens depend on them. Move the filter-specific state model, overview screen, editor sheet, and rows into focused files under `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/`. This preserves the current UI behavior while reducing the blast radius for the next schema and matching-count work.

**Tech Stack:** SwiftUI, AstrenzaCore `NostrEventStore`, GRDB-backed `filter_rules`, Swift Testing, XcodeGen.

---

## File Structure

- Create `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
  - Holds `FilterEditorKind`, `FilterApplicationScope`, `FilterCandidateUser`, `FilterEditorDraft`, and filter-specific helper extensions.
- Create `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsRows.swift`
  - Holds `FilterAddButton`, `FilterOverviewRuleRow`, `FilterCandidateUserRow`, `FilterSelectedUserRow`, `FilterToggleLine`, and `FilterScopeToggleRow`.
- Create `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
  - Holds the editor/search sheet for user, keyword, hashtag, and potential spam filters.
- Create `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
  - Holds the `Filters` destination screen previously named `NostrListSettingsView`.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
  - Remove filter-specific types and leave the account settings entry pointing at `NostrListSettingsView`.
  - Keep shared settings primitives and NIP-51 helper rows if they are still used by the extracted filter screen.

## Task 1: Save This Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-06-filter-settings-refactor-execution-plan.md`

- [ ] **Step 1: Save plan**

Save this exact plan to the file above.

- [ ] **Step 2: Create goal**

Create an active goal:

```text
Documents/Plans/2026-06-06-filter-settings-refactor-execution-plan.md を実行し、Filters 設定 UI を focused files に分割、既存挙動維持、検証、commit まで完了する。
```

## Task 2: Extract Filter Models

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Create model file**

Move these definitions from `SettingsView.swift` into `FilterSettingsModels.swift`:

```swift
import AstrenzaCore
import SwiftUI

enum FilterEditorKind: String, Identifiable {
    case user
    case keyword
    case hashtag
    case potentialSpam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "Filter User"
        case .keyword: "Filter Keyword"
        case .hashtag: "Filter Hashtag"
        case .potentialSpam: "Filter Potential Spam"
        }
    }
}
```

Also move `FilterApplicationScope`, `FilterCandidateUser`, `FilterEditorDraft`, `String.trimmingPrefix(_:)`, and `NostrFilterRuleKind.displayTitle`.

- [ ] **Step 2: Remove moved symbols from `SettingsView.swift`**

Delete the moved type and extension declarations from `SettingsView.swift`.

- [ ] **Step 3: Build-check**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRefactor-DerivedData -skipMacroValidation test
```

Expected: build/test succeeds with existing SwiftUI runtime warning only.

## Task 3: Extract Filter Rows

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsRows.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Create rows file**

Move these definitions from `SettingsView.swift` into `FilterSettingsRows.swift`:

```swift
import AstrenzaCore
import SwiftUI

struct FilterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

Also move `FilterOverviewRuleRow`, `FilterCandidateUserRow`, `FilterSelectedUserRow`, `FilterToggleLine`, and `FilterScopeToggleRow`.

- [ ] **Step 2: Remove moved row symbols from `SettingsView.swift`**

Delete the moved view declarations from `SettingsView.swift`.

- [ ] **Step 3: Build-check**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRefactor-DerivedData -skipMacroValidation test
```

Expected: build/test succeeds with existing SwiftUI runtime warning only.

## Task 4: Extract Filter Editor Sheet

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Create sheet file**

Move `FilterEditorSheet` from `SettingsView.swift` into `FilterEditorSheet.swift`:

```swift
import SwiftUI

struct FilterEditorSheet: View {
    @State private var draft: FilterEditorDraft
    @State private var searchText = ""
    let onCancel: () -> Void
    let onSave: (FilterEditorDraft) -> Void

    init(draft: FilterEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (FilterEditorDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }
}
```

Keep its existing body and helper properties unchanged.

- [ ] **Step 2: Remove moved sheet symbol from `SettingsView.swift`**

Delete `FilterEditorSheet` from `SettingsView.swift`.

- [ ] **Step 3: Build-check**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRefactor-DerivedData -skipMacroValidation test
```

Expected: build/test succeeds with existing SwiftUI runtime warning only.

## Task 5: Extract Filters Destination

**Files:**
- Create: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Create destination file**

Move `NostrListSettingsView` from `SettingsView.swift` into `NostrListSettingsView.swift`:

```swift
import AstrenzaCore
import SwiftUI

struct NostrListSettingsView: View {
    let accountID: String?
    let eventStore: NostrEventStore?
}
```

Keep the existing body and private methods unchanged.

- [ ] **Step 2: Remove moved destination from `SettingsView.swift`**

Delete `NostrListSettingsView` from `SettingsView.swift`.

- [ ] **Step 3: Build-check**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRefactor-DerivedData -skipMacroValidation test
```

Expected: build/test succeeds with existing SwiftUI runtime warning only.

## Task 6: Final Verification and Commit

**Files:**
- Verify all files above.

- [ ] **Step 1: Run core tests**

Run:

```bash
swift test
```

from `Packages/AstrenzaCore`.

Expected: all Swift Testing tests pass.

- [ ] **Step 2: Run app tests**

Run:

```bash
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterRefactor-DerivedData -skipMacroValidation test
```

Expected: all app tests pass. The known SwiftUI runtime warning may still appear.

- [ ] **Step 3: Commit**

Run:

```bash
git add Documents/Plans/2026-06-06-filter-settings-refactor-execution-plan.md Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters
git commit -m "Refactor filter settings views"
```

## Deferred Follow-up Plan

After this refactor, create a separate goal for persisted filter options:

- Add DB fields or a companion table for:
  - `mask_with_warning`
  - `applies_home`
  - `applies_mentions`
  - `applies_threads`
  - `applies_lists`
  - `applies_public_timelines`
- Update `NostrFilterRuleRecord` or introduce `NostrFilterPresentationRuleRecord`.
- Add matching-count query APIs against timeline/event materialization.
- Replace mock `matchingCount/totalCount` in `FilterEditorDraft`.

## Self-review

- Spec coverage: Covers the immediate `next` from the previous answer: refactor first, preserve behavior, prepare for schema and matching counts.
- Placeholder scan: No implementation placeholders remain for this goal. Deferred work is explicitly outside this execution.
- Type consistency: Extracted symbols keep their current names so `AccountSettingsView` can keep using `NostrListSettingsView` unchanged.
