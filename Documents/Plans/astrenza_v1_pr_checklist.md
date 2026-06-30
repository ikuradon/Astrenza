# Astrenza v1 PR Checklist

Use this checklist for every Astrenza v1 implementation PR. The canonical source of truth is `Documents/Specifications/astrenza_nostr_client_development_spec.md`.

## PR DoD

- [ ] The PR states which v1 spec section it implements.
- [ ] Archive documents were used only for context, not as implementation authority.
- [ ] The change keeps or deliberately migrates salvage assets: Core, DB, projection, resolver, relay diagnostics, fixtures, and Maestro intent.
- [ ] Unit tests were added or updated for changed logic.
- [ ] Migration-impacting changes include migration tests or an explicit no-schema-change note.
- [ ] DB bridge changes state whether v0.2 schema remains unchanged, reference `Documents/Plans/timeline_repository_db_adapter_adr.md`, `Documents/Plans/timeline_quote_materialization_adr.md`, and `Documents/Plans/timeline_repository_adapter_promotion_adr.md` when future adapter or quote materializer work begins, or include a spec-backed migration/backfill/rollback plan.
- [ ] Secret material, `nsec`, signing keys, bearer tokens, pubkey-sensitive logs, and crash output were audited.
- [ ] UI changes include Dynamic Type and accessibility notes.
- [ ] Feed/order/read-state changes include anchor/read-marker validation and explain whether `feed_items` / `feed_read_state` semantics changed.
- [ ] Delayed resolve changes include projection tests and snapshot or documented best-effort visual validation.
- [ ] Visible row height changes include E2E anchor delta validation or an explicit reason they cannot affect visible Timeline rows.
- [ ] Protocol/relay changes include fixtures, FakeRelay tests, or integration-test notes.
- [ ] New or changed UI controls have stable `accessibilityIdentifier` coverage where E2E needs them.
- [ ] Snapshot baseline changes include a reason.
- [ ] Timeline diagnostics artifact changes follow `Documents/Plans/timeline_diagnostics_artifact_contract.md`.
- [ ] If diagnostics export JSON shape, artifact fixtures, or CI/failure-artifact handling changed, `scripts/guard_timeline_diagnostics_artifact.sh <path-to-json-or-dir>` was run against the generated artifact JSON.
- [ ] Final PR notes list commands/tests run, failures, unrun tests, and follow-up work.

## Timeline / Resolve PR DoD

- [ ] New production Timeline work uses `UICollectionView` + `UICollectionViewDiffableDataSource` + `UIHostingConfiguration`.
- [ ] Legacy `TimelineFeedView`, `TimelinePostRow`, and `TimelineAttachments` are not production-extended.
- [ ] New `TimelineEngine`, `TimelineRows`, or `TimelineV1` code passes `scripts/guard_designsystem.sh`.
- [ ] `ResolveCoordinatorBoundary` changes include a `ResolveCoordinatorBoundaryIssue.Kind.allCases` issue coverage matrix.
- [ ] Real `ResolveCoordinator` or `resolve_jobs` changes prove UI does not directly start network/DB work and first interactive restore does not wait on queue execution.
- [ ] DB bridge changes include either a no-schema-change note or a migration plan, and reference `Documents/Plans/timeline_db_bridge_audit.md`, `Documents/Plans/timeline_repository_db_adapter_adr.md`, and `Documents/Plans/timeline_quote_materialization_adr.md` when future real adapter or quote materializer work begins.
- [ ] Diffable snapshot items are stable `TimelineEntryID` / `feed_items.item_key` values only.
- [ ] Row identity is unchanged across OGP, media, profile, repost, quote, and reply-parent resolve.
- [ ] Delayed resolve uses reconfigure-style updates, not delete/insert, for visible row enrichment.
- [ ] read marker does not advance on launch, root shell display, restore gate, sync, EOSE, foreground, or resolve.
- [ ] scroll anchor capture/restore remains separate from read marker.
- [ ] `pending_new` does not enter the visible snapshot automatically.
- [ ] `feed_items.pending_new` or caller-provided pending IDs are checked against the snapshot mutation reason before visible insertion.
- [ ] User-triggered pending_new insertion captures and restores anchor.
- [ ] Gap fill captures and restores anchor.
- [ ] Failed resolve keeps the note visible through fallback state.
- [ ] Visible mute uses collapsed placeholder before removal/reload.
- [ ] OGP, media, quote, and reply updates respect reserved layout contracts.
- [ ] No raw color, raw spacing, raw font size, or ad-hoc icon size is introduced in new Timeline components.
- [ ] Action buttons preserve 44x44pt minimum hit targets.
- [ ] No splash, relay sync, OGP, media, profile, search, pruning, checkpoint, or optimize step blocks first interactive Timeline restore.

## Required Specific Checks

- [ ] Row identity stability: before/after resolve item IDs are identical.
- [ ] Read marker stability: launch/sync/resolve cannot call marker advancement.
- [ ] `pending_new` stability: new items remain out of visible snapshot until user action or explicit top-of-feed condition.
- [ ] Delayed resolve apply path: update is `reconfigureItems` or equivalent, not delete/insert.
- [ ] Static guard: run `scripts/guard_designsystem.sh`; it scans `Packages/DesignSystem/Sources/DesignSystem` plus existing future Timeline component paths only, and intentionally does not scan legacy SwiftUI Timeline files.
- [ ] Resolve boundary coverage: run `xcodebuild test -project Astrenza.xcodeproj -scheme Astrenza -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:AstrenzaTests/ResolveCoordinatorBoundaryContractTests` when `ResolveCoordinatorBoundary` changes.
- [ ] DB bridge audit: prove `Documents/Specifications/astrenza_local_db_schema_v0_2.sql` and `Documents/Specifications/astrenza_local_db_schema_v0_2_migration.sql` are unchanged, or include the approved migration plan.
- [ ] Future `TimelineRepositoryDBAdapter` work follows `Documents/Plans/timeline_repository_db_adapter_adr.md` and `Documents/Plans/timeline_repository_adapter_promotion_adr.md`: core/store-owned read-only boundary first, fixture DB first, no production Home wiring, no network/resolver startup, and non-zero selected Swift Testing execution counts.
- [ ] Quote materialization: future adapter/materializer work follows `Documents/Plans/timeline_quote_materialization_adr.md`; default Home emits one source note row plus quote render hint, while `reason = quote` remains reserved for notifications, quote search, and specialized quote feeds.
- [ ] Targeted diff check: future DB adapter/materializer PRs prove schema/migration, production Home wiring, legacy SwiftUI Timeline, real `ResolveCoordinator`, network/resolver startup paths, `TimelinePlaceholderRow`, and `.github` are unchanged unless an approved scope explicitly includes them.
- [ ] Future production Home wiring follows `Documents/Plans/timeline_home_wiring_adr.md`: default legacy mode, `AstrenzaTimelineEngineMode` / `--timeline-engine=collectionView` gate, no same-session dual mutation, no network before local restore, and no root shell or app-wide splash regression.
- [ ] Next Root diagnostics sink injection follows `Documents/Plans/timeline_home_limited_wiring_plan.md`: `test: inject TimelineHome route diagnostics sink at root preflight`, default legacy explicit, exactly one local in-memory route decision artifact, collection view decision may be recorded locally but `TimelineCollectionViewController` and collection view `TimelineSurface` construction from Root remain closed, no same-session fallback after visible mutation, and no production replacement of legacy Home.
- [ ] Next Root diagnostics sink injection passes a local in-memory `TimelineHomeRouteDiagnosticsSink` or narrow protocol into `TimelineHomeRootRouteCallSite`; it does not call `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select` directly from Root.
- [ ] Next Root diagnostics sink injection keeps launch arguments, debug override, `createdAtMS`, and dependency readiness injected into the preflight path; the Root call site does not read `ProcessInfo.processInfo.arguments` directly unless a tiny adapter reads it and injects it into the preflight input.
- [ ] Next Root diagnostics sink injection attaches a local route decision artifact for debug review only: `artifactKind == "timeline_home_route_decision"`, `eventName == "timeline_home_route_preflight_decision"`, `source == "rootPreflight"`, `selectedRoute`, fallback reason or none, dependency readiness, side-effect sentinel all false, `requiresNetworkWork == false`, `requiresDBWrite == false`, `readMarkerChanged == false`, and `preventsDualMutation == true` are visible without route construction, relay startup, network work, DB writes, file writes, external upload, telemetry, analytics, remote logging, raw private content, raw event JSON, pubkeys, event IDs, relay URLs, `nsec`, Keychain data, signing payloads, or bearer tokens.
- [ ] Next Root diagnostics sink injection proves `TimelineHomeRootRouteDiagnosticsSinkInjectionTests` executed non-zero Swift Testing tests, including `root_preflight_records_one_local_route_decision`, `root_preflight_default_legacy_rendering_unchanged`, `root_preflight_sink_is_in_memory_only`, `root_preflight_sink_does_not_construct_collection_view`, `root_preflight_sink_does_not_construct_nostr_store`, `root_preflight_sink_does_not_start_network`, `root_preflight_sink_does_not_write_db`, `root_preflight_sink_does_not_advance_read_marker`, `root_preflight_sink_does_not_call_dataSourceApply`, `root_preflight_sink_artifact_passes_privacy_guard`, and `root_preflight_sink_selected_suites_non_zero`.
- [ ] Actual collection view route construction remains closed until sink injection is reviewed and PASS, default legacy behavior is unchanged with Root preflight plus sink injection, the route diagnostics artifact proves no network/DB/read-marker side effects, offscreen controller smoke and snapshot coordinator harness remain green, no startup network logs appear, `networkWaitedBeforeInteractiveScrollMS == 0`, `readMarkerChanged == false`, old/new dual mutation prevention remains true, and an explicit ADR/checklist opens route construction scope.
- [ ] Next Root diagnostics sink injection keeps `NostrHomeTimelineStore`, legacy SwiftUI Home, root shell, startup splash, schema, migration, DB write paths, relay/network/resolver startup, real `ResolveCoordinator`, `resolve_jobs`, `TimelinePlaceholderRow`, project/dependency files, and `.github` unchanged unless a later approved scope explicitly opens them.
- [ ] `feed_items` / `feed_read_state`: validate read marker and anchor separately; launch/sync/EOSE/foreground/resolve cannot advance marker, and visible snapshot queries exclude `pending_new` by default.
- [ ] DesignSystem usage: no raw `Color`, numeric padding, raw `.font(.system(size:))`, or per-component SF Symbol size in new Timeline components.
- [ ] Hit target: reply/repost/reaction/share/more actions are at least 44x44pt.
- [ ] Launch restore: first interactive Timeline does not wait for network or relay EOSE.
- [ ] Diagnostics export: `summary.restoreGateMetrics` is readable offline, and `networkWaitedBeforeInteractiveScrollMS > 0` is treated as release-blocking.
- [ ] Diagnostics export privacy: no `nsec`, secret key material, raw event JSON, raw private content, or private relay/account material appears in JSON, logs, fixtures, screenshots, or failure artifacts; run `scripts/guard_timeline_diagnostics_artifact.sh <path-to-json-or-dir>` for generated diagnostics artifact JSON.
- [ ] Diagnostics guard self-test: run `scripts/guard_timeline_diagnostics_artifact.sh --self-test` when diagnostics artifact shape, fixtures, guard logic, or failure-artifact handling changes.
- [ ] Diagnostics export boundary: reading a JSON artifact does not require production Home/Timeline wiring, DB queries, relay startup, network work, or a debug screen UI.
- [ ] No-network guardrail: for app-hosted Timeline restore/Resolve tests, inspect targeted logs for `LocalDataTask`, `ATS`, `nw_`, `WebSocketTask`, `URLSessionWebSocketTask`, `wss://`, and `setDefaultRelays` before claiming the test stayed offline.
- [ ] Fallback display: failed OGP/media/profile/repost/quote/reply resolve does not remove the note row.
- [ ] Security: no `nsec` or secret material appears in DB, logs, crash output, screenshots, or fixtures.

## Release Blockers From v1 Spec

A PR or release is blocked if any of the following is true:

- Opening the app advances read marker.
- Launch Screen, splash, or restore gate waits for network sync or EOSE.
- `TimelineDiagnosticsExport` records `networkWaitedBeforeInteractiveScrollMS > 0`.
- `TimelineDiagnosticsExport` records `readMarkerChanged == true` for launch, restore, sync, EOSE, foreground, or resolve work.
- Launch briefly shows newest/top before jumping to saved anchor.
- Relay sync or resolve moves visible Timeline by one or more cells.
- `nsec` or secret material appears in DB, logs, crash output, or fixtures.
- Publish success/failure state differs between UI and DB.
- Deletion or mute is treated as physical deletion and cannot be rebuilt or undone.
- Migration failure lacks a recovery path.
- Delayed resolve failure removes the note body.
- Timeline row contains raw color, raw spacing, or ad-hoc icon size.
- Action hit target is below 44x44pt.
- OGP, media, quote, or reply resolve allows unbounded row height growth.
