# Filter User Real Profile Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mock-only Filter User picker with cached Nostr profile candidates while keeping direct pubkey/npub/NIP-05 entry useful.

**Architecture:** Keep profile lookup in `AstrenzaCore` because cached kind:0 events live in `NostrEventStore`. Keep Settings-specific row state in `FilterSettingsModels`, and keep the sheet dumb: it receives prepared candidates and falls back to direct input candidates when cache has not caught up. Do not introduce network fetch here; NIP-05 network resolution remains a later async flow.

**Tech Stack:** Swift, SwiftUI, Swift Testing, GRDB, XcodeGen, `AstrenzaCore`.

---

## File Structure

- Modify `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
  - Add `NostrProfileSearchResult`.
  - Add `profileSearchCandidates(query:limit:now:)`.
- Modify `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
  - Add tests for cached kind:0 profile search and malformed metadata tolerance.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
  - Add `FilterCandidateUser.init(profile:)`.
  - Add `FilterCandidateUser.directCandidate(from:)`.
  - Stop hard-coding selected existing muted users as `"Muted User"` when a richer candidate is available.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
  - Accept real `candidateUsers`.
  - Show real candidates first.
  - Allow exact pubkey/npub/NIP-05 direct candidate rows.
- Modify `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`
  - Load candidates from `eventStore.profileSearchCandidates`.
  - Pass candidates into `FilterEditorSheet`.
  - Build existing muted user drafts from cached profiles when available.
- Modify `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`
  - Add lightweight tests for `FilterCandidateUser` direct candidate behavior.

## Task 1: Save Plan and Set Goal

**Files:**
- Create: `Documents/Plans/2026-06-07-filter-user-real-profile-picker-plan.md`

- [ ] **Step 1: Save this plan**

Save this plan to the path above.

- [ ] **Step 2: Create goal**

Create this active goal:

```text
Documents/Plans/2026-06-07-filter-user-real-profile-picker-plan.md を実行し、Filter User picker を cached kind:0 profile / direct pubkey / npub / NIP-05 候補に結線し、検証、commit まで完了する。
```

## Task 2: Add Core Cached Profile Search Tests

**Files:**
- Modify: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

- [ ] **Step 1: Add cached profile search test**

Add a test near `eventStoreProfileEventsByAuthor`:

```swift
@Test("Nostr event store searches cached profile metadata candidates")
func eventStoreSearchesCachedProfileCandidates() throws {
    let store = try NostrEventStore.inMemory()
    let alpha = String(repeating: "a", count: 64)
    let beta = String(repeating: "b", count: 64)
    let alphaMetadata = #"{"display_name":"User Alpha","name":"alpha","nip05":"alpha@mock.example","picture":"https://example.com/a.png"}"#
    let betaMetadata = #"{"name":"Beta Relay","nip05":"relay@mock.example"}"#

    try store.save(events: [
        nostrEvent(kind: 0, pubkey: alpha, createdAt: 100, content: alphaMetadata),
        nostrEvent(kind: 0, pubkey: beta, createdAt: 200, content: betaMetadata)
    ])

    let alphaResults = try store.profileSearchCandidates(query: "alpha", limit: 10)
    #expect(alphaResults.map(\.pubkey) == [alpha])
    #expect(alphaResults.first?.displayName == "User Alpha")
    #expect(alphaResults.first?.nip05 == "alpha@mock.example")
    #expect(alphaResults.first?.pictureURL?.absoluteString == "https://example.com/a.png")

    let relayResults = try store.profileSearchCandidates(query: "relay", limit: 10)
    #expect(relayResults.map(\.pubkey) == [beta])
}
```

- [ ] **Step 2: Add malformed metadata tolerance test**

Add:

```swift
@Test("Nostr event store profile search skips malformed metadata")
func eventStoreProfileSearchSkipsMalformedMetadata() throws {
    let store = try NostrEventStore.inMemory()
    let broken = String(repeating: "c", count: 64)
    let valid = String(repeating: "d", count: 64)

    try store.save(events: [
        nostrEvent(kind: 0, pubkey: broken, createdAt: 100, content: "{"),
        nostrEvent(kind: 0, pubkey: valid, createdAt: 120, content: #"{"name":"Valid User"}"#)
    ])

    let results = try store.profileSearchCandidates(query: "valid", limit: 10)
    #expect(results.map(\.pubkey) == [valid])
}
```

## Task 3: Implement Core Profile Search

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`

- [ ] **Step 1: Add result model**

Add near other public records:

```swift
public struct NostrProfileSearchResult: Equatable, Sendable {
    public let pubkey: String
    public let displayName: String?
    public let nip05: String?
    public let pictureURL: URL?
    public let updatedAt: Int
}
```

- [ ] **Step 2: Add search method**

Add:

```swift
public func profileSearchCandidates(query: String, limit: Int = 20, now: Int = Int(Date().timeIntervalSince1970)) throws -> [NostrProfileSearchResult]
```

Implementation rules:
- Query latest cached kind:0 replaceable heads via `replaceable_heads`.
- Decode `NostrProfileMetadata`.
- Match query against display name, `nip05`, pubkey, and abbreviated names case-insensitively.
- Empty query returns the most recently updated cached profiles.
- Sort by `updatedAt DESC`, then `pubkey ASC`.
- Return at most `limit`.

- [ ] **Step 3: Run package tests**

Run:

```bash
cd Packages/AstrenzaCore
swift test
```

Expected: package tests pass.

## Task 4: Add App Candidate Model Helpers

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift`
- Modify: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

- [ ] **Step 1: Add `FilterCandidateUser` helpers**

Add helpers:

```swift
init(profile: NostrProfileSearchResult) {
    id = profile.pubkey
    displayName = profile.displayName ?? "Unknown User"
    npub = profile.pubkey.abbreviatedMiddle
    nip05 = profile.nip05 ?? "NIP-05 not cached"
    avatar = AvatarStyle(seed: profile.pubkey)
}

static func directCandidate(from input: String) -> FilterCandidateUser? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if NostrHex.isLowercaseHex(trimmed, byteCount: 32) {
        return FilterCandidateUser(id: trimmed, displayName: "Pubkey", npub: trimmed.abbreviatedMiddle, nip05: "Direct pubkey", avatar: AvatarStyle(seed: trimmed))
    }
    if let pubkey = try? NostrNIP19.publicKeyHex(from: trimmed) {
        return FilterCandidateUser(id: pubkey, displayName: "Nostr User", npub: trimmed.abbreviatedMiddle, nip05: "Direct npub", avatar: AvatarStyle(seed: pubkey))
    }
    if NostrNIP05Address.parse(trimmed) != nil {
        return FilterCandidateUser(id: trimmed.lowercased(), displayName: trimmed, npub: "Resolve NIP-05 later", nip05: trimmed.lowercased(), avatar: AvatarStyle(primary: .purple, secondary: .indigo, symbolName: "checkmark.seal"))
    }
    return nil
}
```

Adjust exact code for the existing `AvatarStyle` initializer names.

- [ ] **Step 2: Add direct candidate tests**

Add tests proving hex pubkey and npub become candidates, and random text does not.

## Task 5: Wire Real Candidates Into Filter Editor

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift`

- [ ] **Step 1: Pass real candidates to sheet**

Update `FilterEditorSheet` initializer to accept:

```swift
candidateUsers: [FilterCandidateUser]
```

Use these candidates in `filteredCandidates`.

- [ ] **Step 2: Add direct input candidate**

When `searchText` is non-empty and `FilterCandidateUser.directCandidate(from: searchText)` returns a candidate that is not already in the result list, append it as a selectable row.

- [ ] **Step 3: Load candidates in `NostrListSettingsView`**

Add:

```swift
private func candidateUsers(query: String = "") -> [FilterCandidateUser]
```

For now use empty query in the sheet and filter locally as the user types. Load from:

```swift
try eventStore.profileSearchCandidates(query: query, limit: 50)
```

Map results with `FilterCandidateUser(profile:)`. Fall back to `FilterCandidateUser.mockCandidates` only when no live account/store exists or cache is empty.

- [ ] **Step 4: Improve existing muted user draft**

When opening an existing muted pubkey rule, look up a cached candidate by pubkey and pass that into the draft so the editor does not show `"Muted User"` unnecessarily.

## Task 6: Verification and Commit

**Files:**
- All modified files above.

- [ ] **Step 1: Regenerate project**

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

- [ ] **Step 3: Run iOS tests**

Run:

```bash
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaFilterUserPicker-DerivedData -skipMacroValidation test
```

Expected: app tests pass. Existing SwiftUI runtime warning may still appear.

- [ ] **Step 4: Commit**

Run:

```bash
git add Documents/Plans/2026-06-07-filter-user-real-profile-picker-plan.md Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterSettingsModels.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/FilterEditorSheet.swift Astrenza/Sources/AstrenzaApp/Components/Settings/Filters/NostrListSettingsView.swift Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift
git commit -m "Use cached profiles in filter user picker"
```

Expected: commit succeeds.
