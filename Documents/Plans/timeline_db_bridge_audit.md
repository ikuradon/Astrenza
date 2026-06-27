# Timeline DB Bridge Audit

Status: docs-only Phase 4 audit
Updated: 2026-06-27
Scope: planning and test-gate record only. This note does not authorize production DB wiring, SQL schema changes, production Home Timeline wiring, real `ResolveCoordinator` implementation, or DB-backed queue execution.

## Context

Astrenza v1 uses `Documents/Specifications/astrenza_nostr_client_development_spec.md` as the canonical source of truth. The supporting DB source-of-truth remains `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` plus `Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql`.

The v1 spec states that v0.2 schema is the current DB baseline and should not be changed for v1.0 unless a spec-backed migration plan, tests, and rollback path exist. This audit therefore treats schema changes as out of scope.

## Current Implementation Summary

`Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift` currently stores immutable raw Nostr events in `events` and related event facts in supporting tables such as `event_tags`, `media_assets`, `link_previews`, relay sync tables, and outbox tables.

Timeline ordering is currently represented by `timeline_entries` and `NostrTimelineEntryRecord`:

- `account_id`
- `timeline_key`
- `event_id`
- `sort_ts`
- `source`
- `inserted_at`
- `gap_before`
- `gap_after`

Home snapshot persistence writes note events and then saves `timeline_entries` keyed by event ID. Query APIs read `timeline_entries` joined to `events` and order by `sort_ts DESC, event_id ASC`.

Current gaps in the implementation are expected at this phase:

- No `feeds` table integration.
- No `feed_items` write path.
- No `feed_read_state` read marker / scroll anchor storage.
- No `feed_render_hints` contract.
- No `resolve_jobs` queue.
- No `timeline_snapshot_diagnostics` DB write path.
- No `pending_new` DB-level visible-query gate.

## v0.2 Target Schema Summary

The v0.2 schema splits timeline state into rebuildable feed materialization, user read state, render hints, delayed resolve jobs, and diagnostics.

`feeds` identifies the account-scoped feed and its type/params.

`feed_items` is the lightweight Timeline index. It is not a completed row model. It owns stable item identity and visible query fields:

- `feed_id`
- `item_key`
- `source_event_id`
- `subject_event_id`
- `reason`
- `actor_pubkey`
- `sort_at`
- `tie_break_id`
- `hidden_reason`
- `collapsed`
- `pending_new`

`feed_read_state` owns user state independently from item rows:

- read marker fields such as `marker_sort_at` and `marker_event_id`
- scroll anchor fields such as `scroll_anchor_item_key`, `scroll_anchor_sort_at`, `scroll_anchor_tie_break_id`, and viewport metadata
- visible fallback fields such as `last_visible_top_id`, `last_visible_bottom_id`, and `restore_fallback_reason`

`feed_render_hints` stores rebuildable per-item render and delayed-resolve hints, including link preview URL, media count, resolve state JSON, and layout contract JSON.

`resolve_jobs` is the persistent delayed resolver queue keyed by job type, target key, and optional `feed_id/item_key`.

`timeline_snapshot_diagnostics` stores local/test diagnostic records for mutation reason, anchor delta, visible item IDs, and read marker mutation.

## Gaps

The main gap is that current Timeline identity is event-centric while v0.2 identity is feed-item-centric.

- Current `timeline_entries.event_id` is effectively the visible item key. v0.2 uses `feed_items(feed_id, item_key)` and allows `source_event_id` and `subject_event_id` to differ for reposts, quotes, replies, mentions, reactions, and future feed reasons.
- Current `timeline_key` is a string scope. v0.2 requires `feeds.id`, `type`, and `params_json` so Home, profile, list, thread, relay, search, and custom feeds have stable schema-level identity.
- Current `source` is not equivalent to v0.2 `reason`. It does not encode enough information for `author`, `reply`, `repost`, `quote`, `mention`, `reaction`, `zap`, `follow`, or `manual`.
- Current visible queries filter deleted/expired events by joining `events`; v0.2 also materializes `hidden_reason`, `collapsed`, and `pending_new` at the feed item level.
- Current read/unread support is app-model centric and legacy Home oriented. It does not persist v0.2 `feed_read_state` marker and scroll-anchor fields for the new `UICollectionView` TimelineEngine.
- Current link preview/media tables are not tied to per-item `feed_render_hints` or `resolve_jobs`, so delayed resolve cannot yet be audited as a DB-backed queue.
- Current diagnostics are DTO/test artifacts; they are not persisted into `timeline_snapshot_diagnostics`.

## No-Schema-Change Decision

No SQL schema change should be made now.

`Documents/Specifications/astrenza_local_db_schema_v0_2.sql` remains the DB source-of-truth. The current task is an audit and planning checkpoint, not a migration. The next implementation slice should prove bridge semantics with adapter/source-model tests before any real `feed_items` write path, dual-write, migration, or DB-backed `ResolveCoordinator` is introduced.

This decision avoids prematurely changing schema while the app still has:

- legacy Home Timeline wiring,
- current `NostrEventStore.timeline_entries` APIs,
- no production `TimelineEngine` Home integration,
- no real `ResolveCoordinator` actor,
- no DB-backed resolve queue execution.

## Bridge Options

### Option 1: Adapter-only contract

Create a read-only bridge model that maps current `timeline_entries + events` rows into v0.2-like draft feed item records. This can be tested without SQL schema changes or production wiring.

Suggested initial mapping:

| Current field | Draft v0.2-like field |
|---|---|
| `timeline_entries.event_id` | `item_key`, `source_event_id`, `subject_event_id` for simple kind:1 notes |
| `timeline_entries.sort_ts` | `sort_at` |
| `timeline_entries.event_id` | `tie_break_id` until a stronger deterministic key is introduced |
| `events.pubkey` | `actor_pubkey` |
| `timeline_entries.source` | provisional `reason`, only when it can be mapped safely |
| current visible query | `hidden_reason IS NULL` and `pending_new = 0` draft query expectation |

This is the recommended next step.

### Option 2: Temporary dual-write

After adapter tests define expected rows, add a scoped dual-write path from the existing `timeline_entries` write flow into v0.2 `feed_items`. This requires a clear migration/rollback plan and should remain out of production Home until parity is proven.

This option is not recommended until adapter-only tests are stable.

### Option 3: One-shot migration/backfill

Backfill current `timeline_entries` into v0.2 `feeds/feed_items/feed_read_state` and retire the old index. This is the riskiest option because feed IDs, item keys, read state, `pending_new`, reasons, and render hints are not yet contract-tested end to end.

This option is not recommended for the next slice.

## Recommended Next Step

Implement a docs/test-only bridge contract slice:

- Add source-model fixtures for current `timeline_entries` rows and related `events`.
- Add expected v0.2-like draft `feed_items` records for simple Home notes.
- Make unsupported mappings explicit for repost/quote/reply/mention until their `subject_event_id` and `reason` contracts are fixture-backed.
- Keep `pending_new = false` for existing visible rows and add a future fixture showing that `pending_new = true` rows must be excluded from visible snapshots until user action or explicit top-of-feed conditions.
- Keep read marker and scroll anchor out of the adapter until `feed_read_state` tests define the update rules.
- Do not create, migrate, or write v0.2 tables in this slice.

## Future Tests That Must Gate DB Bridge Work

- Adapter parity: current `timeline_entries + events` fixtures map to deterministic v0.2-like `feed_items` draft rows with stable `item_key`, `sort_at`, `tie_break_id`, `reason`, and `subject_event_id`.
- Visible query: rows with hidden state or `pending_new = true` are excluded from the visible snapshot by default.
- Read state: launch, sync, EOSE, foreground, and resolve do not advance read marker; only real visibility or explicit user action can advance it.
- Anchor restore: `feed_read_state.scroll_anchor_item_key`, sort key, viewport metadata, and fallback reason preserve the visual anchor independently of read marker.
- Resolve job draft: OGP, media, profile, repost, quote, and reply parent/root resolve jobs attach to `feed_id/item_key` and never remove the source note on failure.
- Diagnostics: default `read_marker_changed` is false, anchor item key and before/after visible IDs are recorded, and diagnostics artifact JSON remains offline and privacy-checked.
- Migration/dual-write: any future dual-write or backfill proves idempotency, rollback, raw event preservation, and no physical deletion of immutable raw events.
