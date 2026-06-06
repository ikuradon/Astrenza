# Ivory-style Filters Settings Execution Plan

Date: 2026-06-06

## Goal

Implement an Ivory-like Filters settings flow for Astrenza's per-account Nostr settings, backed by the existing GRDB `filter_rules` table. The flow should cover the screenshots' structure:

- `Filters` overview with `USERS`, `KEYWORDS`, `HASHTAGS`, and `CUSTOM`
- `Add User`, `Add Keyword`, `Add Hashtag`
- `Filter User`, `Filter Keyword`, `Filter Hashtag`, and `Filter Potential Spam` editor sheets
- `Mask with a Warning`, application scope toggles, duration display, and matching-post count affordances
- User search/selection mock UI for the add-user path
- Saved local filters should be reflected in the overview and used by the existing home timeline materialization path

## Placement

Keep the entry under:

- Settings
- Account
- `Muting / Filters`

Rationale: Nostr filters, NIP-51 lists, mutes, bookmarks, and relay/account state are identity scoped. The root settings can route to an account-specific page, but filter editing belongs inside the selected account settings.

## Phase 1: Persistence Completion

Files:

- `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

Tasks:

- Add `deleteFilterRule(accountID:ruleID:)`.
- Preserve existing `saveFilterRule` upsert behavior for enable/disable updates.
- Add a Swift Testing test that verifies:
  - filters are account scoped
  - saving the same `ruleID` updates `isEnabled`
  - deleting a rule only deletes from the matching account

Verification:

- `swift test` from `Packages/AstrenzaCore`

Commit:

- Commit Phase 1 separately.

## Phase 2: Ivory-style Filters Overview

File:

- `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

Tasks:

- Replace the top of `NostrListSettingsView` with a `Filters` overview:
  - `USERS`: existing local `.mutedPubkey` rules plus `Add User`
  - `KEYWORDS`: existing local `.keyword` rules plus `Add Keyword`
  - `HASHTAGS`: existing local `.mutedHashtag` rules plus `Add Hashtag`
  - `CUSTOM`: `Potential Spam` row with `Enabled`/`Disabled`
- Keep `NIP-51 LISTS` below the local filter UI so cached remote lists remain inspectable.
- Rename destination title to `Filters`.
- Keep no-live-account empty state for account-scoped behavior.

Verification:

- `xcodegen generate`
- `xcodebuild ... test`

Commit:

- Commit Phase 2 separately.

## Phase 3: Editor Sheets and Save Flow

File:

- `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`

Tasks:

- Add editor sheet model:
  - `FilterEditorDraft`
  - `FilterEditorKind`
  - `FilterApplicationScope`
  - `FilterCandidateUser`
- Implement sheets:
  - `Filter Keyword`
  - `Filter Hashtag`
  - `Filter User`
  - `Filter Potential Spam`
- User flow:
  - Add User opens search UI first.
  - Selecting a candidate switches into the user detail editor.
  - Candidate row shows avatar, display name, npub, and NIP-05-like display.
- Save flow:
  - Keyword -> `.keyword`
  - Hashtag -> `.mutedHashtag`
  - User -> `.mutedPubkey`
  - Potential Spam -> `.regex` built-in rule
- Editor affordances:
  - `Mask with a Warning` toggle is represented in UI for now.
  - `Apply To` toggles are represented in UI for now.
  - `Duration` is `Forever`, stored as `expiresAt == nil`.
  - `Matching Posts` shows a mock/current-count affordance until timeline-side query counts are introduced.
- Dismiss and reload after successful save.

Verification:

- `xcodegen generate`
- `xcodebuild ... test`

Commit:

- Commit Phase 3 separately.

## Phase 4: Polish and Regression Pass

Tasks:

- Ensure no regressions to existing settings navigation.
- Ensure local filters are still merged into timeline materialization through `NostrHomeTimelineStore`.
- Ensure disabled Potential Spam does not affect the timeline unless enabled and saved.
- Run full verification.

Verification:

- `swift test` from `Packages/AstrenzaCore`
- `xcodegen generate`
- `xcodebuild ... test`

Commit:

- Commit Phase 4 if any polish changes are required.

## Out of Scope for This Goal

- Real user search over relays
- Real matching-post count query UI
- Persisting per-filter application scopes
- Persisting "mask with warning" separately from "hide/collapse"
- NIP-51 private encrypted list editing/publishing
- Cross-device sync of local-only filters

These need either new schema or signer-backed NIP-51 write support and should be handled as a later goal.
