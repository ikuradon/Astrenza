# Timeline Quote Materialization ADR

Status: accepted for future implementation planning
Updated: 2026-06-28
Scope: docs-only ADR. This document does not authorize production DB adapter code, SQL schema changes, DB migrations, DB write paths, production Home Timeline wiring, legacy SwiftUI Timeline changes, a real `ResolveCoordinator` actor, URLSession/WebSocket/relay/media/OGP resolver startup, or GitHub Actions changes.

## Context

Astrenza v1 uses `Documents/Specifications/astrenza_nostr_client_development_spec.md` as the canonical source of truth. The supporting DB source-of-truth remains `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` plus `Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql`.

The v0.2 schema already supports `feed_items.reason = 'quote'`. It also allows `feed_items.subject_event_id` to be `NULL`, and it has quote-specific delayed hydration surfaces through `feed_render_hints.quote_target_event_id`, `missing_events.reason = 'quote_target'`, and `resolve_jobs.job_type = 'quote_target'`.

The source-model pipeline has historically treated a kind:1 quote as a normal note row with a quote candidate/render relation. The read-only DB adapter slice now proves that persisted `reason = quote` rows with missing `subject_event_id` can round-trip as fallback-capable rows without creating `resolve_jobs` or mutating DB state.

Before promoting any production DB adapter or feed materializer, v1 needs a single policy for when a quote relation becomes its own `feed_items` row and when it remains render state on the source note.

## Decision

`feed_items.reason = quote` is a first-class v1 feed item reason, but it is not the default Home representation for every note that has a `q` tag.

Default Home materialization keeps a quoting kind:1 event as a normal source note row when the source note itself satisfies Home insertion policy. In that case:

- `feed_items.reason` stays `author` or another feed inclusion reason selected by the source note policy;
- `source_event_id` is the quoting note;
- `subject_event_id` is normally the source note itself for that Home row;
- the quote target is represented through `note_relations`, `feed_render_hints.quote_target_event_id`, and delayed quote-target resolve state;
- the source row owns the compact `QuoteCard` fallback/resolved rendering.

`reason = quote` is reserved for feeds where the quote relation itself is the reason the row appears, such as notifications, quote search, future "quotes of this note" views, and specialized profile/relay/custom feeds whose explicit purpose is quote relations.

Production Home must not emit both `note:<source_event_id>` and `quote:<source_event_id>` for the same quoting event. Quote target hydration may update the source row or a first-class quote row by reconfigure-style update, but it must not insert a duplicate source note or synthesize a normal target note row.

`q` tags must not create reply parents. NIP-10 root/reply markers own reply context. Quote relations own `QuoteCard` state and quote-target hydration only.

## Feed-Specific Policy

### Home

Home uses the source note's feed inclusion reason. A followed author's note with a `q` tag is materialized once as `note:<source_event_id>` with `reason = author` unless a separate Home policy explicitly chooses another source-note reason.

The quote target stays a render relation/hint on that source row. If the quote target is missing, the source note remains visible with compact quote fallback. Home must not materialize an additional `quote:<source_event_id>` row for the same source note.

If the quoted target independently satisfies Home insertion policy, it may appear as its own normal `note:<target_event_id>` row. That row is independent feed materialization, not a side effect of quote resolve.

### Notifications

Notifications may use `reason = quote` when the user is notified because another event quoted the user's note or another watched subject. The quoting event is `source_event_id`; the quoted event is `subject_event_id` when known.

If the target event is not yet hydrated but its ID is known, `subject_event_id` should hold that target ID and the row should remain fallback-capable. If the target ID itself is unavailable in legacy or diagnostic input, `subject_event_id == NULL` means unresolved/unavailable subject, not an invalid row.

### Profile Timeline

A normal profile timeline for an author's notes should materialize the quoting note as a source note row and keep the quote target as render state. It should not duplicate the same quoting event as a separate `reason = quote` row.

A specialized profile surface such as "quotes by this profile" or "quotes of this profile's note" may use `reason = quote` because the quote relation is the feed reason.

### Thread Detail

Thread detail follows root/reply policy for the thread tree. A `q` tag inside a thread note renders as `QuoteCard`; it must not create a reply parent, reply root, or inline parent preview.

A future quote reference section attached to thread detail may use `reason = quote` for "quotes of this note" rows, but that section is a specialized quote feed, not the thread tree itself.

### Search/Quote-Of-Note Feed

Search results or a future "quotes of this note" feed may use `reason = quote` when the relation to the quoted target is the reason for inclusion. The `item_key` must identify the quote relation row stably, and `source_event_id` remains the quoting event.

These feeds should dedupe the same quoting event deterministically and must not additionally synthesize a normal `note:<source_event_id>` row unless the feed explicitly has a separate source-note result section.

### Relay/Custom Feed

Relay and custom feeds follow their explicit feed contract. If the feed is a normal event stream, a quote tag remains render state on the source note. If the feed is configured as a quote-relation feed, it may use `reason = quote`.

The materializer must be feed-type aware. The same source event may appear in different feeds with different `item_key` values only when those feeds have different explicit inclusion reasons.

## Persistence Policy

### `source_event_id`

`source_event_id` is always the event that caused the feed row to exist.

For source note rows, it is the note being rendered. For first-class quote rows, it is the quoting event.

### `subject_event_id`

`subject_event_id` is the displayed or related subject for the feed reason when known.

For default Home source note rows, it should remain the source note unless a future source-model contract proves a different subject is required. For first-class quote rows, it is the quoted target when known.

### `item_key` convention

Default Home source note rows use `note:<source_event_id>`.

First-class quote rows use a quote-specific key, normally `quote:<source_event_id>` for a row representing one quoting event. Future quote feeds that can contain multiple quote relations for the same source event must extend the key deterministically, for example with a relation position or target key, before production use.

`item_key` remains the row identity. Resolve state, quote target hydration, profile, OGP, media, and reply parent state must not change identity.

### `reason` mapping

Use `author`, `reply`, `repost`, `mention`, `reaction`, `zap`, `follow`, or `manual` when that is the feed inclusion reason. Use `quote` only when the quote relation itself is the feed inclusion reason.

The materializer must choose one reason per feed row. It must not create parallel Home rows for the same source event just because the event also has a `q` tag.

### Missing Subject Semantics

For `reason = quote`, `subject_event_id == NULL` means the quote subject is unresolved, unavailable, or not representable from the current input. It does not mean the row is invalid, and it must not be coerced to `reply`, `author`, or `note:<source_event_id>`.

If the quoted target ID is known but the target event body is missing, the preferred production representation is to store the target ID in `subject_event_id`, queue/record quote-target hydration through future materializer work, and render compact fallback until resolved.

## UI/Projection Policy

### `QuoteCard` Compact Fallback

Missing quote targets render as compact `QuoteCard` fallback. The source note body remains visible. Failed or unavailable quote target resolve must not remove the source note.

### No Reply Parent Contamination

`q` tags create quote relations only. They must not populate reply parent/root state, `ReplyContextHeader`, or thread tree parentage.

### No Duplicate Target Note Insertion

Resolving a quote target enriches the existing source row or first-class quote row. It must not insert the target as a normal feed row unless that target independently satisfies the feed's materialization policy.

### Delayed Resolve / Reconfigure

Quote target hydration is a delayed resolve path. It must keep `feed_items.item_key` / `TimelineEntryID` stable and update visible rows through reconfigure-style invalidation, not delete/insert replacement.

Quote resolve must not advance read marker, capture a new scroll anchor, block first interactive restore, or start network/relay/media/OGP work from UI code.

## DB Adapter Implications

The read-only adapter must support existing `reason = quote` rows, including rows with `subject_event_id == NULL`. Such rows are represented as quote rows, not normalized into reply or author rows.

The read-only adapter must not materialize new rows, create `resolve_jobs`, write diagnostics, update read marker, or promote missing quote targets into normal note rows.

The future materializer must avoid duplicate Home rows by treating the feed type and inclusion reason as part of the materialization decision. A default Home materializer emits the source note row plus quote render hint, not both a source note row and a first-class quote row for the same source event.

A future write adapter must be feed-type aware before it can write `reason = quote` rows in production. It must keep feed item materialization, read marker updates, anchor persistence, diagnostics persistence, and resolve queue writes as separately testable boundaries.

## Test Gates

Future materializer or production DB adapter promotion must be blocked until focused tests prove:

- a note with a `q` tag in Home emits only one source note row plus quote render hint;
- production Home does not emit both `note:<source_event_id>` and `quote:<source_event_id>` for the same quoting event;
- a quote-of-note feed emits a first-class `reason = quote` row;
- `reason = quote` remains allowed for notifications, quote search, and specialized quote feeds;
- missing quote target with known target ID survives as fallback and later hydration keeps row identity;
- `reason = quote` with `subject_event_id == NULL` round-trips as unresolved/unavailable subject, not an invalid row;
- `q` tag does not create reply parent/root state;
- quote target resolve updates by reconfigure-style path and keeps `TimelineEntryID` / `feed_items.item_key` stable;
- resolving a quote target does not synthesize a duplicate normal target note row;
- `pending_new`, `hidden_reason`, and `collapsed` policies apply identically to first-class quote rows;
- read-only adapter reads quote rows without creating `resolve_jobs`, writing diagnostics, or changing read marker;
- future diagnostics artifacts remain offline/redacted and contain no `nsec`, secret key material, raw event JSON, raw private content, or private relay/account material.

## Forbidden Scope

This ADR does not authorize:

- SQL schema changes;
- DB migrations;
- production DB adapter code;
- DB write paths;
- production Home Timeline wiring;
- legacy SwiftUI Timeline changes;
- real `ResolveCoordinator` actor implementation;
- URLSession, WebSocket, relay, media resolver, profile resolver, or OGP resolver hookup;
- GitHub Actions changes;
- external telemetry, production diagnostics upload, raw/private diagnostics material, or debug-screen exposure.
