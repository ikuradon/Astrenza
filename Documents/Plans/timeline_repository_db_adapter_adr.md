# TimelineRepository DB Adapter ADR

Status: accepted for future implementation planning
Updated: 2026-06-27
Scope: docs-only ADR and implementation plan. This document does not authorize production DB adapter code, DB write paths, SQL schema changes, DB migrations, production Home Timeline wiring, legacy SwiftUI Timeline changes, a real `ResolveCoordinator` actor, URLSession/WebSocket/relay/media/OGP resolver startup, external telemetry, debug-screen exposure, production diagnostics upload, or GitHub Actions changes.
Follow-up boundary: `Documents/Plans/timeline_repository_adapter_promotion_adr.md` decides that the current test-private SQLite adapter should not be copied into `TimelineEngine`; the first production promotion boundary should be a core/store-owned read-only `TimelineRepositoryStore` boundary.

## Decision Summary

- Schema v0.2 remains unchanged.
- No migration is approved yet.
- The first future real adapter slice will read the existing v0.2 `feed_items` and `feed_read_state` tables only.
- Any future write adapter, feed materialization write path, read marker write path, anchor persistence write path, diagnostics persistence write path, dual-write, backfill, or migration execution requires a separate ADR and test plan.
- The current `timeline_entries` path remains a legacy/bridge source until a real adapter, temporary adapter, or dual-write decision is implemented.
- The immediate next implementation after this ADR is still a narrow `TimelineRepositoryDBAdapter` slice against controlled data, not production Home wiring.
- Diagnostics for this slice must remain offline, redacted, artifact-only where exported, and covered by the diagnostics artifact guard when JSON shape or fixtures change.

## Current State

`Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift` still uses `timeline_entries` for current timeline ordering. It writes `timeline_entries(account_id, timeline_key, event_id, sort_ts, source, inserted_at, gap_before, gap_after)` and reads that table ordered by `sort_ts DESC, event_id ASC`.

The current Phase 4 contracts are source-model and test-only. They define persistence shape and repository boundary expectations, but they are not real DB adapters and they do not prove production Home reads from v0.2 tables.

Current tests/source-model contracts cover:

- `timeline_entries`-like input mapped into v0.2-like feed item drafts.
- feed item draft shape for `item_key`, `source_event_id`, `subject_event_id`, `reason`, `sort_at`, `tie_break_id`, `hidden_reason`, `collapsed`, and `pending_new`.
- repository boundary initial window behavior.
- adapter-to-repository fixture pipeline behavior.
- read-state fallback across scroll anchor, marker, last visible rows, newest row, and empty output.
- read marker and scroll anchor as separate state.
- persistence shape DTOs for feed item and read-state rows.
- DTO-derived drafts matching direct `FixtureTimelineRepositoryBoundary` behavior.

These contracts intentionally do not add GRDB-backed repository code, DB migrations, production runtime wiring, real network work, or real resolver queue execution.

## Future Adapter Responsibilities

The future `TimelineRepositoryDBAdapter` or equivalent must:

- fetch the initial visible window around a requested anchor from `feed_items`;
- decode and preserve `feed_read_state`;
- write and read scroll anchor fields independently from read marker fields;
- preserve read marker vs scroll anchor separation;
- exclude `pending_new` rows by default;
- include pending rows only after explicit user action or another explicit top-of-feed policy;
- exclude rows with `hidden_reason` by default;
- preserve `collapsed` rows as represented rows, not treat them as hidden rows;
- preserve repost/quote rows that are missing their target when they are fallback-capable;
- produce local diagnostics for anchor source, fallback reason, visible item IDs, excluded pending/hidden counts, and read marker mutation attempts;
- never advance read marker during launch, restore, sync, EOSE, foreground, or resolve;
- never start URLSession, WebSocket, relay, media, profile, or OGP work;
- never resolve OGP, media, profile, quote, repost, or reply targets itself.

The adapter is a local persistence boundary. Resolve work stays behind a future `ResolveCoordinator` and `resolve_jobs` queue; production UI wiring stays out of the adapter PR.

## SQL / Query Contract

This section describes query shape only. It is not implementation code and does not change schema.

The adapter should use `feed_items(feed_id, sort_at DESC, tie_break_id ASC)` as the deterministic visible ordering contract. The existing `idx_feed_items_order` index supports this order.

Visible window queries must apply:

- `feed_id` equality;
- `hidden_reason IS NULL`;
- `pending_new = 0` unless the request carries an explicit user-action inclusion policy;
- ordering by `sort_at DESC, tie_break_id ASC`.

`collapsed` is not a visible-query exclusion. It is retained as row/render state.

Initial anchor lookup should prefer:

1. `feed_items.item_key` matching `feed_read_state.scroll_anchor_item_key`;
2. only visible rows, unless a future explicit diagnostics-only query needs to explain a hidden/pending anchor.

If the anchor item exists, the adapter should fetch:

- the newer side before the anchor using the same order contract;
- the anchor row itself;
- the older side after the anchor using the same order contract;
- enough rows on each side to satisfy the requested initial window size deterministically.

Fallback order:

1. anchor item key: `feed_read_state.scroll_anchor_item_key`;
2. scroll anchor event ID: `feed_read_state.scroll_anchor_event_id` matched against `source_event_id` or `subject_event_id`;
3. read marker event ID: `feed_read_state.marker_event_id` matched against `source_event_id` or `subject_event_id`;
4. read marker sort key: `feed_read_state.marker_sort_at`;
5. last visible top or bottom: `feed_read_state.last_visible_top_id`, then `feed_read_state.last_visible_bottom_id`;
6. newest visible row;
7. empty output when no visible rows exist.

`marker_sort_at` fallback should pick the nearest represented visible row under the same deterministic ordering. It must not mutate the marker.

## Transaction / Write Policy

- Anchor saves are independent user-state writes.
- Feed item materialization is separate from read marker writes.
- Read marker updates require explicit visibility or explicit user action.
- Restore diagnostics writes must not mutate read marker.
- `pending_new` DB persistence can happen immediately, but visible snapshot insertion cannot happen until user action or an explicit top-of-feed policy.
- Feed materialization, anchor persistence, diagnostics persistence, and read marker updates should be separately testable transaction boundaries.
- Crash/rollback behavior for anchor saves should be tested before production use if anchor writes become transactional with other user-state writes.

## Adapter Strategy Options

### Option 1: Temporary adapter from `timeline_entries`

Map existing `timeline_entries + events` rows into source-model feed item drafts without changing schema. This is useful for parity checks, but it must not become the final v1 source of truth.

### Option 2: Dual-write `timeline_entries` + `feed_items`

Write the existing legacy index and the v0.2 feed index during a transition. This needs an explicit backfill, idempotency, rollback, and divergence-diagnostics plan before implementation.

### Option 3: Direct migration to `feed_items`

Backfill existing timeline data into v0.2 tables and retire `timeline_entries`. This has the highest blast radius and should wait until adapter parity and rollback behavior are proven.

### Option 4: Direct real adapter against `feed_items`

Implement a read-only adapter against fixture-backed SQLite/GRDB data using existing v0.2 tables. This is the recommended next implementation slice because it tests the real query shape without production Home wiring.

Recommended sequence:

1. Source-model adapter parity.
2. Real read-only adapter against a fixture DB containing `feed_items` and `feed_read_state`.
3. Dual-write/backfill decision record.
4. Migration only if still needed after the adapter and dual-write/backfill decision.

## Future Test Gates

Future real DB adapter work must add or update focused tests for:

- file-backed SQLite/GRDB fixture DB;
- `feed_items` initial window query;
- `feed_read_state` anchor restore;
- `pending_new` excluded by default;
- pending rows included only by explicit user action or explicit top-of-feed policy;
- `hidden_reason` rows excluded by default;
- collapsed rows retained;
- missing-target fallback-capable rows retained;
- `readMarkerChanged == false` during launch/restore/sync/resolve;
- no URLSession, WebSocket, relay, media, profile, or OGP startup;
- no schema change;
- migration file unchanged;
- large-window deterministic ordering;
- duplicate/tie-break behavior;
- anchor item-key fallback to scroll anchor event ID;
- marker event and marker sort fallback behavior;
- last visible top/bottom fallback behavior;
- empty visible result behavior;
- rollback/crash-safe anchor save if anchor writes are introduced.

## Forbidden Scope

A future DB adapter PR still must not:

- add DB write paths, including feed materialization writes, read marker writes, anchor persistence writes, diagnostics persistence writes, `resolve_jobs` writes, dual-write, backfill, or production migration execution;
- wire production Home;
- modify legacy SwiftUI Timeline;
- implement a real `ResolveCoordinator` actor;
- call URLSession, WebSocket, relay startup, media resolver, profile resolver, or OGP resolver APIs;
- introduce external telemetry, production diagnostics upload, raw/private diagnostics material, or debug-screen exposure;
- change SQL schema without a separate migration ADR;
- add a DB migration without a separate migration ADR;
- advance read marker during launch, restore, sync, EOSE, foreground, or resolve;
- use `timeline_entries` as the final v1 source of truth;
- touch GitHub Actions as part of adapter work.

## Open Questions

- Should the next implementation use a temporary adapter from `timeline_entries`, or jump directly to a read-only fixture DB adapter against `feed_items`?
- When should dual-write begin, if at all?
- Should `feed_items` be backfilled from `timeline_entries`, or should the app rebuild feeds from raw events and projections?
- When can `timeline_entries` be retired?
- Should reason values, hidden reasons, and fallback reasons gain DB-level constraints later?
- How much diagnostics data belongs in `timeline_snapshot_diagnostics` versus debug export artifacts?
- Should anchor saves be isolated transactions or bundled with other user-state writes after the first real adapter lands?
