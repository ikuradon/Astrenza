# Nostr MVP Completion Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for direct execution, or `superpowers:subagent-driven-development` when splitting independent phases. Keep this file as the source of truth. Update checkboxes only when the phase has been implemented, verified, and committed.

**Goal:** `Documents/Research` の結論と既存の GRDB/Home TL 基盤を前提に、実リレー運用の耐久性、Timeline Row の実データ化、表示用 event の段階投入、永続化強化を Phase ごとに完了する。

**Current baseline:** The latest committed baseline already includes GRDB event storage, Home TL restore, kind:0/NIP-05/NIP-65/kind:3 wiring, NIP-77 gap context, relay sync history partial persistence, persistence regression tests, and partial Timeline tag materialization.

**Completion definition:** Each phase is complete only when:
- implementation is merged into the current working tree
- focused Swift Testing tests pass
- app project generation passes
- simulator test/build passes, unless a phase explicitly documents why it cannot
- a commit is created for that phase

**Verification commands:**

```bash
swift test
xcodegen generate
xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/AstrenzaNostrMVP-DerivedData -skipMacroValidation test
```

Run package-only tests from `Packages/AstrenzaCore` when a phase touches only core. Run full app tests after any app UI/materializer wiring.

---

## Baseline Already Completed

These items are treated as already complete and must not be counted again as new phase completion:

- [x] GRDB-backed `NostrEventStore` for canonical events, tags, relay profiles, sync cursors, timeline entries, timeline state.
- [x] Home TL restoration from DB, including removal of UserDefaults timeline snapshot fallback.
- [x] Real npub read-only onboarding path connected to Home TL.
- [x] NIP-65 relay list resolution and kind:3 follow list resolution.
- [x] kind:0 profile resolution, avatar display/cache, NIP-05 resolution/cache.
- [x] NIP-77 gap/backfill context and gap row replacement behavior.
- [x] Persistence regression coverage for store recreation, bounded timeline restore, 10,000-event restore, and gap anchor preservation.
- [x] Relay sync event history table and partial relay sheet DB wiring.
- [x] Partial Timeline Row materialization for reply shell, quote shell, media URL shell, unresolved link preview, content warning shell, and low-trust collapse.

The remaining phases below intentionally revisit some of those areas where they are still partial.

---

## Phase 8A: NIP-09 Deletion and NIP-40 Expiration Semantics

**Purpose:** Make deletion and expiration behavior correct at the event-store boundary before expanding UI behavior. Research says deletion is a request, not guaranteed erasure; therefore raw events remain stored, while visible queries and materialized timelines respect valid tombstones and expiration.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test if app mapping changes: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [x] Add failing tests:
  - same-author kind:5 deletion marks the target event as hidden from visible timeline queries
  - deletion by a different pubkey is ignored
  - deletion request can be saved in the same batch as its target and still apply
  - raw target event remains queryable by raw/debug API if such API exists
  - NIP-40 `expiration` tag hides an event when `expires_at <= now`
  - non-expired event remains visible when `expires_at > now`
- [x] Apply kind:5 deletion after all events in a save transaction are upserted, so batch order does not matter.
- [x] Only apply tombstones when deletion author matches the target author.
- [x] Insert/update `deletion_tombstones` with deletion event id, target id, author pubkey, and deletion timestamp.
- [x] Set `events.deleted_at` for valid deleted targets, but do not delete the raw row.
- [x] Add a shared visible-event SQL predicate:
  - `deleted_at IS NULL`
  - `expires_at IS NULL OR expires_at > :now`
- [x] Use the predicate in visible timeline queries, reference queries, author/kind queries, profile/detail materializer queries, and Home TL state reconstruction.
- [x] Keep raw/debug fetches intentionally separate from visible fetches.

**Acceptance tests:**
- `swift test` in `Packages/AstrenzaCore`
- full app tests if public query signatures change

**Commit:**
`Apply deletion and expiration semantics`

---

## Phase 8B: Deleted, Sensitive, Reply, Repost, and Quote Rows From Real Events

**Purpose:** Move Timeline Row behavior from mock-shaped state to event-derived state while keeping existing SwiftUI components.

**Files:**
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/TimelineModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelinePostRow.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [x] Materialize valid kind:5 effects as `TimelineFeedEntry.deleted` or a compact deleted row when the deleted event still occupies an expected timeline slot.
- [x] Interpret NIP-36 `content-warning` tags from actual event tags:
  - empty reason: generic sensitive state
  - non-empty reason: overlay reason text
  - author/header remains visible, body/media/OGP are blurred
- [x] Interpret NIP-10 reply markers:
  - root/reply marker tags win when present
  - fallback to positional `e` tags when markers are absent
  - reply marker is not shown for root posts
- [x] Interpret kind:6 repost:
  - show repost attribution from the reposting event
  - [x] use cached target event if available
  - [x] otherwise show a compact missing target placeholder
- [x] Interpret quote references from `q` tags, NIP-19 references in content, or quote-like `e` tags where supported by existing parser.
- [x] Keep relay hints internal; UI should show post author, original post time, and repost/quote actor time, not relay hints.
- [x] Reuse the same row component for Home TL, User Detail, and Post Detail wherever the displayed entity is a timeline post.

**Acceptance tests:**
- timeline model tests for reply root, self-reply, non-self reply mention color state, repost attribution, quote placeholder, deleted row, and content warning blur state
- full app tests

**Commit:**
`Materialize timeline rows from event semantics`

---

## Phase 9: Addressable Heads and NIP-51 Lists

**Purpose:** Add the storage layer for addressable replaceable events and public list/mute/bookmark/search-relay data. This is required for list timelines, mutes, bookmarks, and relay search settings.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrListModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/HomeTimelineView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

**Implementation steps:**

- [x] Add schema:
  - `addressable_heads(kind, pubkey, d_tag, event_id, created_at, updated_at)`
  - `lists(list_id, account_id, kind, pubkey, d_tag, event_id, title, visibility, private_content, created_at, updated_at)`
  - `list_items(list_id, item_key, item_type, value, relay_hint, visibility, position)`
- [x] Update addressable heads for events with kinds `30000...39999`.
- [x] Tie-break addressable replacement by newer `created_at`, then deterministic event id ordering.
- [x] Parse public NIP-51 tags for:
  - `30000` follow sets
  - `30002` relay sets
  - `30003` bookmark sets
  - `10000` mute list
  - `10007` search relays
- [x] Store encrypted private list content raw for now; do not attempt NIP-44 decrypt in this phase.
- [x] Expose DB APIs for list summaries and list items.
- [x] Wire settings/list UI to DB-backed summaries with empty states when no list event is cached.

**Acceptance tests:**
- addressable replacement test
- public list parsing test
- mute/bookmark/search relay list storage test
- full app tests if UI touched

**Commit:**
`Add addressable list storage`

---

## Phase 10A: NIP-92 Media Asset Storage

**Purpose:** Store media metadata from event tags so gallery rendering does not depend on ad-hoc content parsing. Keep gallery height predictable.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrMediaModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineAttachments.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [x] Add schema:
  - `media_assets(asset_id, event_id, url, mime_type, blurhash, width, height, alt, sha256, status, local_path, created_at)`
- [x] Parse NIP-92 `imeta` fields:
  - `url`
  - `m`
  - `dim`
  - `blurhash`
  - `alt`
  - `x` / `ox`
- [x] Extract direct image/video URLs from content only as fallback when no `imeta` is present.
- [x] Materialize `TimelineMedia.gallery` from `media_assets`.
- [x] Keep existing 1-5+ media grid behavior and fixed gallery height.
- [x] Use `alt` as alt text in the full-screen image viewer; do not treat visible embedded text as alt text.

**Acceptance tests:**
- imeta parse test
- content URL fallback test
- gallery tile count/overflow test
- full app tests

**Commit:**
`Persist NIP-92 media assets`

---

## Phase 10B: URL and OGP Materialization

**Purpose:** Make link previews cache-backed and deterministic. Materializer must not synchronously fetch remote OGP while building rows.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrLinkModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineLinkPreview.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [x] Add schema:
  - `link_previews(url, normalized_url, status, title, summary, site_name, image_url, fetched_at, expires_at, error)`
- [x] Extract URLs from event content and store unresolved preview requests.
- [x] Materializer maps:
  - cached resolved preview -> existing OGP card
  - missing/failed preview -> unresolved/tap-to-inspect card
  - low-trust or unknown author media/OGP -> blurred inspect-first card
- [x] Ensure `tap to inspect` reveals before opening In-App Browser.
- [x] Ensure In-App Browser state cannot consume taps behind it.

**Acceptance tests:**
- URL normalization test
- resolved/unresolved/failed preview mapping test
- low-trust preview blur test
- full app tests

**Commit:**
`Materialize link previews from cache`

---

## Phase 11: Persistent Outbox and Publish MVP

**Purpose:** Add a durable write path for posts, replies, and deletion requests. Research recommends partial success and retry visibility because relay publish can succeed on some relays and fail on others.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrOutboxModels.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrPublisher.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [x] Add schema:
  - `outbox_events(local_id, account_id, event_id, event_json, status, created_at, next_retry_at, last_error)`
  - `outbox_relays(local_id, relay_url, status, last_attempt_at, ok_message)`
- [x] Add publisher input models for:
  - new kind:1 post
  - reply with NIP-10 tags
  - deletion request kind:5
- [x] Keep signer boundary abstract so local signing, NIP-46, and mock signing can share the same publish queue.
- [x] Resolve relay destinations from:
  - account write relays from kind:10002
  - tagged users' cached read relays
  - settings fallback relays
- [x] Compose Post button inserts outbox row and optimistic event row.
- [x] Relay `OK` results update per-relay status and aggregate outbox status.
- [x] UI exposes pending/partial/failed state without blocking timeline rendering.

**Acceptance tests:**
- outbox persistence test across store recreation
- relay destination resolution test
- partial success aggregation test
- compose optimistic insert test

**Commit:**
`Add persistent publish outbox`

---

## Phase 12: Relay Runtime Durability, NIP-42, and Sync Cursor Accuracy

**Purpose:** Complete relay runtime persistence so the relay sheet reflects DB-backed history, not only in-memory state. Strengthen cursor updates from actual per-relay fetch results.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayClient.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrHomeTimelineLoader.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrRelayInformation.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelayStatusSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Relay/RelaySettingsView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`

**Implementation steps:**

- [ ] Persist relay runtime summary fields:
  - last connected
  - last EOSE
  - last timeout
  - last error
  - auth required
  - payment required
  - reconnect count
  - timeout count
  - partial failure count
  - average EOSE latency
- [ ] Persist lifecycle history:
  - connected
  - EOSE
  - reconnect
  - timeout
  - closed
  - partial failure
  - auth required
  - payment required
- [ ] Prune lifecycle rows per relay to a bounded count.
- [ ] Parse NIP-42 `AUTH` challenge and store `.authRequired(challenge:)`.
- [ ] Do not auto-sign AUTH until signer/outbox boundary is ready; surface clear state in relay sheet.
- [ ] Update `sync_cursors` per relay from the actual newest/oldest event received from that relay, not from aggregate timeline state.
- [ ] Relay status sheet reads recent runtime history from DB.
- [ ] Relay settings writes per-account relay preferences; publishing NIP-65 changes can be queued after Phase 11.

**Acceptance tests:**
- lifecycle event persistence test
- bounded pruning test
- AUTH challenge parse test
- per-relay cursor update test
- relay sheet DB summary model test where feasible

**Commit:**
`Persist relay runtime state`

---

## Phase 13: Compose Drafts in GRDB

**Purpose:** Move compose drafts out of mock/local transient state into the event store so account switching, sheet close, and app restart behave predictably.

**Files:**
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrDraftModels.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeSheetView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Home/ComposeDraftViews.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: Maestro mock compose flow if present

**Implementation steps:**

- [ ] Add schema:
  - `drafts(draft_id, account_id, kind, parent_event_id, text, content_warning, media_json, updated_at)`
- [ ] Draft count in gear menu reads from DB.
- [ ] Draft list reads from DB and supports edit mode deletion.
- [ ] Closing compose with text/media shows:
  - Ignore Draft
  - Save Draft
  - Cancel
- [ ] Ignore Draft deletes the draft and closes the sheet.
- [ ] Save Draft persists and closes the sheet.
- [ ] Opening a draft restores text, warning reason, media references, and reply context.
- [ ] Drafts are account-scoped.

**Acceptance tests:**
- draft save/load/delete tests
- account-scoped draft test
- compose close behavior UI/model test

**Commit:**
`Persist compose drafts in event store`

---

## Phase 14: Filter, Mute, Bookmark, and Trust UI

**Purpose:** Add the user-visible noise-control layer from Research. This should use NIP-51 where possible and local rules where the protocol has no single universal answer.

**Files:**
- Create: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrFilterRules.swift`
- Modify: `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Nostr/NostrHomeTimelineStore.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Timeline/TimelineFeedView.swift`
- Modify: `Astrenza/Sources/AstrenzaApp/Components/Settings/SettingsView.swift`
- Test: `Packages/AstrenzaCore/Tests/AstrenzaCoreTests/NostrCorePackageTests.swift`
- Test: `Astrenza/Tests/AstrenzaTests/TimelineModelTests.swift`

**Implementation steps:**

- [ ] Add local filter rules model for:
  - muted pubkey
  - muted hashtag
  - keyword
  - regex
  - muted kind
  - relay mute
  - temporary mute expiry
- [ ] Merge local rules with public NIP-51 mute list when cached.
- [ ] Apply filters in materializer as collapsed/hidden states, not by deleting source events.
- [ ] Add active filter indicator with one-tap clear.
- [ ] Add trust handling for media/OGP:
  - followed users show normally
  - non-followed users in reply/repost/quote context blur media/OGP until reveal
  - sensitive state still takes precedence over trust reveal
- [ ] Add bookmark action storage for local bookmark first, then NIP-51 publish after outbox is available.

**Acceptance tests:**
- mute pubkey/hashtag/keyword/regex tests
- trust blur tests
- filter indicator state tests
- bookmark local persistence test

**Commit:**
`Apply Nostr mute and filter rules`

---

## Final Hardening Pass

**Purpose:** Confirm MVP read/write foundations do not regress under realistic local data volume and relay failure modes.

**Implementation steps:**

- [ ] Re-run store recreation tests after all migrations.
- [ ] Re-run 10,000 timeline restore performance test.
- [ ] Re-run gap anchor preservation test after materializer changes.
- [ ] Run a local mock route for Maestro UI tests.
- [ ] Confirm mock route remains separate from real relay route.
- [ ] Confirm `Documents/Research`-derived TODOs are either implemented or explicitly deferred in a backlog file.
- [ ] Commit final cleanup if needed.

**Commit:**
`Harden Nostr MVP persistence and relay flows`

---

## Execution Order

Execute in this order unless a phase becomes blocked by a compile-time dependency:

1. Phase 8A: deletion/expiration semantics
2. Phase 8B: event-derived Timeline Rows
3. Phase 10A: media assets
4. Phase 10B: OGP/link cache
5. Phase 12: relay runtime durability and cursor accuracy
6. Phase 9: addressable heads and NIP-51 lists
7. Phase 11: persistent outbox
8. Phase 13: drafts in GRDB
9. Phase 14: filter/mute/trust UI
10. Final hardening

Reasoning:
- Deletion/expiration must be correct before row materialization, or the UI can confidently render events that should be hidden.
- Media/link materialization is a read-path feature and can land before publishing.
- Relay runtime durability should be completed before outbox grows relay-specific write state.
- NIP-51 lists and filters can use the same addressable/list infrastructure.
- Drafts can land after outbox schema boundaries are known, so compose state and publish state do not collide.
