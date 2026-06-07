# Real Account Switcher And Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mock user switcher and Settings account rows with persisted real Nostr accounts, keeping the existing single-account login flow compatible.

**Architecture:** Extend `NostrSessionStore` from a single restored account into a small account registry with a selected account. Add a UI-facing account summary model that can enrich saved `NostrAccount` values with cached kind:0 metadata from `NostrEventStore`, then feed that model into the home user switcher and Settings account section.

**Tech Stack:** SwiftUI, `ObservableObject`, `UserDefaults` Codable persistence, `AstrenzaCore.NostrAccount`, `NostrEventStore.latestReplaceableEvent`, Swift Testing/XCTest via existing `TimelineModelTests`.

---

## Execution Status

- Completed on 2026-06-07.
- Verification: `xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17'`
- Result: PASS, 90 Swift Testing tests passed.

## File Structure

- Modify `Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift`
  - Add persisted account list and selected account ID.
  - Keep `account` and `signer` API so `AstrenzaRootView` and `NostrHomeTimelineStore` continue to work.
  - Add `selectAccount(_:)`, `removeAccount(_:)`, and `accountSummaries(eventStore:)`.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Home/HomeUserSwitcher.swift`
  - Replace hard-coded `User Alpha/User Beta` rows with `NostrAccountSummary` rows.
  - Wire row tap to `sessionStore.selectAccount`.
  - Show Add Account and Settings actions without fake accounts.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
  - Pass current account avatar and account list into `UserSwitchButton` and `UserSwitcherMenu`.
- Modify `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
  - Derive account summaries from `sessionStore` and live `eventStore`.
  - Close floating menus when switching accounts.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelinePresentations.swift`
  - Pass account summaries and session callbacks into `SettingsView`.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
  - Replace mock `ACCOUNTS` rows with real `NostrAccountSummary`.
  - Account detail screen uses actual `npub`, `readOnly`, NIP-05, relays, and filters.
  - Add Sign Out / Remove Account affordance for selected account.
- Test `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Verify session storage persists multiple accounts.
  - Verify selecting/removing accounts updates selected account and preserves compatibility with `account`.
  - Verify account summary prefers cached kind:0 display name/NIP-05 when available.

## Task 1: Session Store Account Registry

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing tests**

Add tests named:

```swift
@Test("Session store persists multiple accounts and restores selected account")
@MainActor
func sessionStorePersistsMultipleAccounts() async throws

@Test("Session store selecting and removing accounts keeps selected account valid")
@MainActor
func sessionStoreSelectsAndRemovesAccounts() async throws
```

Expected behavior:
- Logging in account A then account B leaves `accounts.count == 2`.
- `account` points to B after login.
- A new store with same `UserDefaults` restores both accounts and selected B.
- `selectAccount(A.pubkey)` switches `account` to A.
- Removing selected A switches to another account.
- Removing the final account clears `account`.

- [ ] **Step 2: Implement storage**

Add `@Published private(set) var accounts: [NostrAccount] = []`.

Update storage to persist:

```swift
private struct NostrSessionSnapshot: Codable {
    let accounts: [NostrAccount]
    let selectedPubkey: String?
}
```

Keep backwards compatibility by reading the old `"astrenza.readonly.account"` key if the new snapshot key is missing.

- [ ] **Step 3: Implement mutations**

Implement:

```swift
func selectAccount(_ pubkey: String)
func removeAccount(_ pubkey: String)
private func installAccount(_ account: NostrAccount, signer: (any NostrEventSigning)?)
```

`installAccount` upserts by `pubkey`, selects the account, sets `signer`, and persists.

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaDerivedData -only-testing:AstrenzaTests/TimelineModelTests/sessionStorePersistsMultipleAccounts -only-testing:AstrenzaTests/TimelineModelTests/sessionStoreSelectsAndRemovesAccounts
```

Expected: PASS.

## Task 2: Real Account Summary Model

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add failing test**

Add:

```swift
@Test("Session account summaries prefer cached profile metadata")
@MainActor
func sessionAccountSummariesPreferCachedProfileMetadata() async throws
```

Expected behavior:
- Without kind:0, summary title falls back to account display identifier and abbreviated npub.
- With kind:0 metadata, summary title uses `bestName`, subtitle uses NIP-05, avatar is deterministic from pubkey.

- [ ] **Step 2: Add model**

Add app-layer model:

```swift
struct NostrAccountSummary: Identifiable {
    let id: String
    let account: NostrAccount
    let title: String
    let subtitle: String
    let npub: String
    let avatarStyle: AvatarStyle
    let isSelected: Bool
    let isReadOnly: Bool
}
```

- [ ] **Step 3: Add summary builder**

Implement:

```swift
func accountSummaries(eventStore: NostrEventStore?) -> [NostrAccountSummary]
func accountSummary(for account: NostrAccount, eventStore: NostrEventStore?) -> NostrAccountSummary
```

Use cached kind:0 only; do not fetch network from Settings/UserSwitcher.

- [ ] **Step 4: Run tests**

Run targeted summary test. Expected: PASS.

## Task 3: Home User Switcher Wiring

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeUserSwitcher.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`

- [ ] **Step 1: Update UI contracts**

Change:

```swift
UserSwitchButton(isExpanded:)
UserSwitcherMenu(onSettingsTap:)
```

to accept:

```swift
summary: NostrAccountSummary?
accounts: [NostrAccountSummary]
onSelectAccount: (String) -> Void
onAddAccount: () -> Void
onSettingsTap: () -> Void
```

- [ ] **Step 2: Replace mock rows**

Render `accounts` with `ForEach(accounts)`. Each row calls `onSelectAccount(summary.id)`.

If `accounts` is empty, show a compact row: `"No account"` / `"Login required"`.

- [ ] **Step 3: Wire HomeTimelineView**

Use:

```swift
let accountSummaries = sessionStore?.accountSummaries(eventStore: liveTimelineStore.eventStore)
```

Pass selected and list into `HomeTimelineTopBar`.

- [ ] **Step 4: Build**

Run app build. Expected: PASS.

## Task 4: Settings Account Section Wiring

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelinePresentations.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Update SettingsView init**

Add:

```swift
let accountSummaries: [NostrAccountSummary]
let onSelectAccount: (String) -> Void
let onRemoveAccount: (String) -> Void
let onAddAccount: () -> Void
```

Keep defaults for mock launches.

- [ ] **Step 2: Replace mock ACCOUNTS**

Render `accountSummaries`. The selected account shows a checkmark. `Add Account` opens onboarding placeholder route for now.

- [ ] **Step 3: Update AccountSettingsView**

Use `NostrAccountSummary` instead of separate title/subtitle/avatar props.

Show:
- `Read-only` for `account.readOnly == true`
- `Local signer` for writable local nsec account
- relay and filter destinations scoped by `summary.id`
- destructive `Remove Account` row that calls `onRemoveAccount(summary.id)`

- [ ] **Step 4: Build**

Run app build. Expected: PASS.

## Task 5: Verification And Commit

**Files:**
- All modified files above.

- [ ] **Step 1: Run targeted tests**

```bash
xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaDerivedData -only-testing:AstrenzaTests/TimelineModelTests
```

Expected: all tests pass.

- [ ] **Step 2: Run app build**

```bash
xcodebuild build -project Astrenza.xcodeproj -scheme Astrenza -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/AstrenzaDerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Documents/Plans/2026-06-07-real-account-switcher-and-settings-plan.md Astrenza/Sources/AstrenzaApp/Nostr/NostrSessionStore.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeUserSwitcher.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelineTopChrome.swift Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift Astrenza/Sources/AstrenzaApp/Components/Home/HomeTimelinePresentations.swift Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Wire account switcher to real sessions"
```

## Self-Review

- Spec coverage: covers home user switcher, Settings accounts, account detail, selection, removal, and cached profile display.
- No network fetch from UI: Settings and user switcher use cached `NostrEventStore` only.
- Backwards compatibility: existing single-account restore key remains readable.
- Risk: local signer persistence is not implemented; signing account can be selected during the same session, but only public account information is persisted. Keychain persistence belongs in a separate security-focused plan.
