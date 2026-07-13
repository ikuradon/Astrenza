# Local DB Projection Architecture Audit

## Purpose

This audit records the current Astrenza local persistence/projection shape before the local DB fact/index projection architecture migration begins.

Target direction:

- Keep GRDB/SQLite as the device-local primary store.
- Store canonical Nostr facts and lightweight timeline indexes in SQLite.
- Keep completed display models such as `TimelinePost` app-only.
- Treat `timeline_entries` as prunable timeline membership/index, not a persisted projection.
- Treat kind:5 as deletion facts and tombstones, not normal timeline posts.

## Persistent Fact Tables

The current store lives primarily in `Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift`.

### Canonical or fact-like tables

- `events`
  - Stores raw Nostr event facts with key columns such as `event_id`, `pubkey`, `kind`, `created_at`, `content`, `received_at`, `deleted_at`, `expires_at`, and `raw_json`.
  - This is the main source of truth for event bodies.

- `event_tags`
  - Stores event tags for lookup and reconstruction.
  - This is the source for `e`, `p`, `a`, `t`, `emoji`, `imeta`, `k`, and other tag-derived facts.

- `replaceable_heads`
  - Stores the current accepted head for replaceable events such as kind:0, kind:3, and kind:10002.
  - This decouples NIP-01 replacement logic from timeline row projection.

- `addressable_heads`
  - Stores the current accepted head for addressable events keyed by kind/pubkey/d-tag.

- `deletion_tombstones`
  - Stores valid deletion facts derived from kind:5 requests.
  - Current behavior updates `events.deleted_at` when a same-author target event is available.
  - Future work should support pending targets and addressable `a` tag deletion.

- `media_assets`
  - Stores media metadata and cache state.
  - Media file bodies should remain in the file cache, not in SQLite.

- `link_previews`
  - Stores OGP/oEmbed metadata and resolution status.
  - Preview images should remain in the file cache.

### Timeline index table

- `timeline_entries`
  - Stores `account_id`, `timeline_key`, `event_id`, `sort_ts`, `source`, `inserted_at`, `gap_before`, and `gap_after`.
  - This is required for Home/Mentions/List timeline stability, restore anchors, GapRows, and controlled insertion.
  - This is not a completed row projection table.
  - It must be prunable by retention policy.

### Runtime/account/outbox state

- `sync_cursors`
  - Stores account/timeline/relay cursor state.

- Relay state/history/counters
  - Existing relay state and network counter tables are part of local runtime facts.

- `accounts`, `drafts`, `outbox_events`, filters/lists/bookmark settings
  - Local app state and outgoing workflow persistence.

## App Projection Types

Projection currently lives in app-layer files under `Astrenza/Sources/AstrenzaApp/Nostr`.

- `NostrTimelineMaterializer`
  - Builds `TimelineFeedEntry` and `TimelinePost` values from facts.
  - Despite the name, this is app-layer projection and should not imply DB persistence of completed rows.
  - Future work should introduce `NostrTimelineProjection` as the public facade and route call sites through it.

- `NostrTimelinePostProjection`
  - Builds `TimelinePost` from `NostrHomeTimelineItem`, content facts, media facts, link preview facts, author facts, reply facts, and quote facts.

- `NostrTimelineAuthorProjection`
  - Builds author display state from metadata and NIP-05 resolution facts.

- `NostrTimelineContentProjection`
  - Parses rich content, URLs, custom emoji, media/OGP promotion, and quoted references from event content/tags.

- `NostrTimelineMediaProjection`
  - Builds media display models from media facts and policy.

- `NostrTimelineQuoteProjection`
  - Builds quoted post display models from quoted target events and author/content facts.

- `NostrTimelineReplyProjection`
  - Builds reply context and reply mention display from tags and related events.

## Risky Couplings

- `NostrTimelineMaterializer` naming suggests persisted materialization even though it currently acts as app-layer projection.
- `NostrHomeTimelineStore` owns many responsibilities at once:
  - relay/runtime event handling,
  - timeline index insertion,
  - projection window loading,
  - projection scheduling,
  - unread/live behavior,
  - detail/profile helpers.
- Projection refresh scheduling is currently embedded in `NostrHomeTimelineStore`; future work should use a focused coordinator.
- `timeline_entries` can grow forever unless retention and pruning are implemented.
- kind:5 handling currently applies deletion only when the target event is already known; pending deletion and `a` tag deletion are future work.
- `media_assets` are currently extracted during event fact save, while `link_previews` can be resolved asynchronously later. The async path must only update projection input facts and must not insert, remove, or reorder `timeline_entries`.

## Safe Existing Behavior

Do not regress these behaviors while migrating:

- `saveTimelineEntries` preserves existing `gap_before` and `gap_after` flags.
- Gap backfill keeps partial/timeout gaps until explicitly resolved.
- Deleted timeline rows are synthesized from `deletedTimelineEntries`.
- Same-author kind:5 deletion hides or replaces target timeline rows.
- Repost/quote/reply targets can arrive after the original row and should update projection.
- Media and OGP metadata updates should update row projection without changing timeline membership.
- Live relay events can be saved to DB without immediately moving the visible timeline unless the user is at the newest window/live mode.
- Pull-to-refresh and Home tab actions should control when new stored events become timeline entries.
- Timeline restore should use a stable anchor and avoid visible scroll thrash at launch.

## Migration Order

1. Preserve this plan and audit as the baseline.
2. Add a pure `NostrTimelineIndexPolicy`.
3. Add `NostrEventStore.pruneTimelineEntries`.
4. Complete kind:5 tombstone handling with pending event and `a` target support.
5. Introduce `NostrTimelineProjection` as an app-layer facade.
6. Move timeline row building call sites to the projection facade.
7. Add projection refresh coalescing.
8. Separate event ingestion from timeline membership insertion more explicitly.
9. Keep media/link metadata updates as projection refresh triggers, not timeline membership mutations.
10. Add 10k/100k timeline persistence benchmark-like tests.

## Open Questions

- Whether `timeline_entries` should eventually be renamed in code to `timeline_index_entries` or left as-is with stronger docs.
- Whether relation facts should remain extracted on demand from `event_tags` or move into an explicit `event_relations` table.
- Whether FTS5 should be a separate `search.sqlite` sidecar in the first pass or deferred until after projection boundaries are stable.
- Whether `deletion_tombstones` should be migrated in place or replaced with a generalized `deletion_targets` table.

## Baseline Test Result

Date: 2026-06-09

- Core: PASS. `swift test --package-path Packages/AstrenzaCore` passed 154 Swift Testing tests. The sandboxed first run failed because SwiftPM could not write to the user-level Swift/Clang cache; the same command passed when run with cache access.
- App: PASS. `xcodebuild -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AstrenzaTests` passed 152 tests.
- Notes: The app test log includes WebSocket handshake error logs for external relay URLs used by tests, but the test session finished with `** TEST SUCCEEDED **`.
