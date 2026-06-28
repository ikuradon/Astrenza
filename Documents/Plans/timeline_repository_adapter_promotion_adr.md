# TimelineRepository Adapter Promotion ADR

Status: accepted for next Phase 4 slice
Updated: 2026-06-28
Scope: docs-only promotion boundary decision. This document does not authorize production DB adapter code, DB write paths, SQL schema changes, DB migrations, production Home Timeline wiring, legacy SwiftUI Timeline changes, a real `ResolveCoordinator` actor, URLSession/WebSocket/relay/media/OGP resolver startup, external telemetry, or GitHub Actions changes.

## 1. Status

Accepted for the next Phase 4 planning slice.

This is a docs-only ADR. It decides the promotion boundary for the future read-only `TimelineRepository` DB adapter, but it does not promote the current test-private adapter into production source.

## 2. Context

The current read-only DB adapter exists only inside `Astrenza/Tests/AstrenzaTests/TimelineRepositoryDBAdapterReadOnlyTests.swift`. It is a private SQLite fixture adapter that proves query behavior against controlled test tables. Fixture setup owns all `CREATE TABLE`, `INSERT`, malformed-row setup, and audit counts; the adapter path opens SQLite with `SQLITE_OPEN_READONLY` and performs query-only reads.

The existing source-model contracts are strong enough to define the next boundary. Current tests cover `feed_items` / `feed_read_state` reads, SQL-level visible filtering, deterministic ordering, anchor-side query shape, issue coverage, missing-target repost/quote fallback, Home quote materialization policy, and no read marker mutation from repository restore.

Production Home is not wired to the `UICollectionView` `TimelineEngine` yet. The legacy SwiftUI `TimelineFeedView` / `TimelinePostRow` / `TimelineAttachments` path still exists and must not receive new production Timeline behavior.

The v0.2 schema remains the source of truth. `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` and `Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql` are not changed by this decision.

`Packages/AstrenzaCore/Sources/AstrenzaCore/NostrEventStore.swift` still owns the current GRDB store path and still uses `timeline_entries` for the current Home timeline index. `timeline_entries` remains a legacy/current bridge path until a separate feed materialization, backfill, dual-write, or retirement ADR opens that work.

## 3. Decision

Do not promote the current test-private SQLite adapter directly into `Astrenza/Sources/AstrenzaApp/TimelineEngine/Repository/`.

The first production promotion boundary should be a core/store-owned read-only boundary, tentatively named `TimelineRepositoryStore`, owned by `Packages/AstrenzaCore` unless a separate Store package is introduced first. The boundary should expose read-only feed window operations and keep SQL/GRDB access behind a persistence layer, not inside UIKit `TimelineEngine` code.

Because `TimelineEngineTypes.swift` is app-local, a core/store-owned production boundary must not use `TimelineInitialWindowRequest`, `TimelineReadStateDraft`, `FeedID`, `EventID`, or `TimelineEntryID` from the app target as public protocol types. The first implementation should define core/store-owned DTOs and let an app-side repository/coordinator map those DTOs into existing TimelineEngine source-model types. Moving shared contract types into a package is a separate option, but it is not the recommended first slice.

Recommended next step: define the read-only store boundary in production source first, then add a GRDB-backed read-only implementation only after DDL parity and read-only transaction tests are in place. If implementation is included in the next slice, it must remain read-only, fixture-backed, and unwired from production Home.

Rationale:

- `project.yml` does not give the app target a direct `GRDB.swift` dependency. `GRDB` is currently owned by `Packages/AstrenzaCore`.
- The v1 spec says `TimelineEngine` owns collection view, snapshot, anchor, visible range, and prefetch behavior, but does not parse Nostr events or write DB directly.
- The v1 spec assigns GRDB schema, transactions, queries, and migrations to Store/Core responsibilities.
- Direct app-layer SQL would make it easier for UI code to bypass repository contracts and mix `timeline_entries` with v0.2 `feed_items`.

Options considered:

| Option | Decision | Reason |
|---|---|---|
| App-local adapter under `AstrenzaApp/TimelineEngine/Repository/` | Rejected for first slice | Would require direct DB access from TimelineEngine and likely direct GRDB dependency churn. |
| `AstrenzaCore` read-only store boundary | Accepted with DTO boundary | Matches current GRDB ownership and keeps UI -> repository -> store direction explicit, but it must define core/store-owned DTOs instead of depending on app-local TimelineEngine types. |
| New `TimelineRepository` package | Deferred | Could become useful when Store boundaries split, but it is dependency churn before production Home wiring is opened. |
| Keep adapter test-only until production Home wiring | Partially accepted | Keep the SQLite adapter test-only now; the next production change should define only the core/store read boundary, still with no Home wiring. |

## 4. Public Contract

Future production code should expose a narrow read-only interface, with names allowed to change during implementation. The public protocol must use core/store-owned DTOs or primitive persisted identifiers, not app-local `TimelineEngineTypes.swift` types:

```swift
protocol TimelineRepositoryStore: Sendable {
    func fetchInitialWindow(
        feedID: TimelineRepositoryStoreFeedID,
        request: TimelineRepositoryStoreInitialWindowRequest,
        policy: TimelineRepositoryStoreWindowPolicy
    ) async throws -> TimelineRepositoryStoreWindowResult

    func fetchReadState(
        feedID: TimelineRepositoryStoreFeedID
    ) async throws -> TimelineRepositoryStoreReadState?

    func fetchAnchorWindow(
        feedID: TimelineRepositoryStoreFeedID,
        anchor: TimelineRepositoryStoreAnchor,
        policy: TimelineRepositoryStoreWindowPolicy
    ) async throws -> TimelineRepositoryStoreWindowResult
}
```

The first production boundary must not expose write methods.

The app-side repository/coordinator may map `TimelineRepositoryStoreWindowResult` into existing source-model types from `TimelineEngineTypes.swift`. That mapping is app-owned and must remain separate from the core/store SQL implementation.

Return types should be narrow DTOs that map deterministically into TimelineEngine source-model types. The boundary must not return UI cells, SwiftUI views, app-local internal types, GRDB rows, SQLite statements, raw event JSON, or resolver runtime objects.

Required diagnostics defaults:

- `readMarkerChanged == false`
- `requiresNetworkWork == false`
- `requiresDBWork == false` when that field means unexpected external DB work or mutation
- `localDBReadWork == true` if a future diagnostics model adds a dedicated local read flag

All failures must map to typed issues. Raw SQL, raw persisted private material, raw event JSON, `nsec`, secret key material, private relay/account material, and unredacted DB values must not appear in user-visible errors, logs, diagnostics artifacts, or test failure messages.

## 5. Dependency Boundary

The concrete production adapter may import GRDB only inside the core/store-owned implementation. `TimelineEngine` and UIKit surfaces should not import GRDB for this slice.

The adapter should depend on `DatabaseReader` for read-only operations. Factories may accept `DatabasePool` when production composition needs pool ownership, but the query implementation should be written against the narrow read interface so tests can inject a fixture reader.

Fixture tests should inject a file-backed or in-memory GRDB reader created from the official v0.2 DDL or a DDL parity fixture. SQLite C API fixture code in `TimelineRepositoryDBAdapterReadOnlyTests.swift` remains test-only and should not be copied into production source.

SQL ownership belongs to the core/store persistence layer. The app layer owns feed intent and UI consumption, not SQL strings or direct table access.

To avoid UI -> DB bypass:

- `TimelineEngine` asks a repository/coordinator for source-model rows.
- The repository/coordinator calls `TimelineRepositoryStore`.
- `TimelineRepositoryStore` owns SQL and typed issue mapping.
- `TimelineRepositoryStore` returns core/store-owned DTOs.
- The app-side repository/coordinator maps DTOs into `TimelineEngineTypes.swift` source-model rows.
- UIKit snapshot code never sees GRDB, SQLite handles, SQL text, or transaction objects.

## 6. Query Contract

The current test contracts are the required query baseline for production promotion:

- visible query applies `feed_id` equality;
- visible query applies `hidden_reason IS NULL`;
- visible query excludes `pending_new` by default with `pending_new = 0`;
- pending rows are included only through explicit user action or a future explicit top-of-feed policy;
- deterministic ordering is `ORDER BY sort_at DESC, tie_break_id ASC`;
- `collapsed` rows remain represented and are not hidden by the visible predicate;
- anchor lookup starts from `feed_read_state.scroll_anchor_item_key` when available;
- scroll anchor event ID, marker event ID, marker sort key, last visible top/bottom, newest visible row, and empty output remain separate fallback cases;
- newer-side query and older-side query keep strict anchor boundaries;
- missing-target repost and quote rows remain fallback-capable visible rows when policy allows visibility;
- `reason = quote` with `subject_event_id == NULL` remains unresolved/unavailable quote subject, not an invalid row and not a reply row;
- read-only adapter work does not create `resolve_jobs`;
- read-only adapter work does not write diagnostics rows;
- read-only adapter work does not advance read marker.

`timeline_entries` is the current legacy event-centric index owned by `NostrEventStore`. It may be used only as a temporary bridge input for fixture/source-model parity or an explicitly approved temporary adapter. It is not the v1 feed source of truth. No production code may merge `timeline_entries` and `feed_items` inside the same visible-window result unless a separate dual-write/backfill ADR defines source precedence, idempotency, rollback, divergence diagnostics, and retirement criteria. `timeline_entries.event_id -> feed_items.item_key/source_event_id/subject_event_id` is permitted only for simple bridge fixtures, and `timeline_entries.source` is not equivalent to `feed_items.reason`.

## 7. Forbidden Scope For First Production Slice

The first production slice after this ADR must still forbid:

- DB writes from the adapter;
- SQL schema changes;
- DB migration changes;
- production Home Timeline wiring;
- production `TimelineEngine` wiring into Home/root/splash;
- legacy SwiftUI Timeline changes;
- `TimelinePlaceholderRow` changes unless a separate UI scope explicitly opens them;
- real `ResolveCoordinator` actor implementation;
- `resolve_jobs` execution;
- relay, network, URLSession, WebSocket, media resolver, profile resolver, or OGP resolver calls;
- read marker advancement;
- `timeline_entries` retirement, migration, backfill, or dual-write;
- external telemetry;
- production diagnostics upload;
- GitHub Actions changes.

## 8. Required Tests Before Production Promotion

Before a production read-only adapter implementation can be accepted, targeted tests must prove:

- official schema fixture DB or DDL parity against `astrenza_local_db_schema_v0_2.sql`;
- read-only operation through `DatabaseReader` or a read-only `DatabasePool`/reader wrapper;
- no write transaction from the adapter;
- file-backed fixture behavior, not only in-memory DTO behavior;
- thread-safety and correct queue usage for the chosen GRDB reader;
- typed error/issue mapping for invalid reason, item key, sort key, malformed read state, missing feed, hidden anchor, and pending anchor cases;
- initial visible window for `feed_items`;
- `feed_read_state` anchor restore;
- hidden, pending, collapsed, anchor, quote, repost, and missing-target fallback cases;
- `reason = quote` with missing or nil subject survives read-only round trip;
- read marker remains unmutated;
- no `resolve_jobs`, diagnostics rows, or feed rows are created by reads;
- no URLSession, WebSocket, relay, media, profile, or OGP startup logs for app-hosted tests;
- selected `xcodebuild` suites execute non-zero Swift Testing counts;
- performance smoke for 10k rows if feasible before Home wiring;
- schema and migration files stay unchanged unless a later migration ADR explicitly opens them.

Minimum selected app suites for the first production boundary should include:

- `TimelineQuoteMaterializationPolicyTests`
- `TimelineRepositoryDBAdapterReadOnlyTests`
- `TimelineRepositoryPersistenceShapeTests`
- `TimelineDBBridgeRepositoryPipelineTests`

## 9. Open Questions

- Should the first production protocol live directly in `Packages/AstrenzaCore`, or should a new Store/TimelineRepository package be introduced before implementation?
- When should shared contract types move out of app-local `TimelineEngineTypes.swift`, if ever?
- Should the concrete read-only adapter accept `any DatabaseReader`, `DatabasePool`, or an Astrenza-owned protocol that wraps GRDB?
- When should a write adapter be introduced, if ever?
- When should `feed_items` be backfilled or dual-written from `timeline_entries`?
- When can `timeline_entries` be retired?
- Should production diagnostics persistence use `timeline_snapshot_diagnostics`, local artifact export only, or both?
- How should `localDBReadWork` be represented without weakening the existing `requiresDBWork == false` no-mutation/no-external-work contract?
- How should production composition prevent UI code from acquiring the same database handle and bypassing `TimelineRepositoryStore`?

## 10. Next Recommended Implementation

The next goal should be narrow:

1. Add a production-source read-only `TimelineRepositoryStore` boundary under `Packages/AstrenzaCore` or an explicitly approved Store module, using core/store-owned DTOs rather than app-local TimelineEngine types.
2. Add official-schema/DDL-parity fixture tests for `feed_items` and `feed_read_state`.
3. If a concrete adapter is included, implement only a read-only skeleton against injected `DatabaseReader`, with no write methods and no Home wiring.
4. Keep the current SQLite C API adapter in `TimelineRepositoryDBAdapterReadOnlyTests.swift` test-only until GRDB parity is proven.

The next implementation must still have no DB writes, no schema change, no migration, no production Home wiring, no legacy SwiftUI Timeline changes, no real `ResolveCoordinator`, no network/relay/media/OGP startup, and no `timeline_entries` retirement.
