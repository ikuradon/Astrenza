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
- [ ] Root diagnostics sink injection baseline follows `Documents/Plans/timeline_home_limited_wiring_plan.md`: `test: inject TimelineHome route diagnostics sink at root preflight`, default legacy explicit, exactly one local in-memory route decision artifact, collection view decision may be recorded locally but `TimelineCollectionViewController` and collection view `TimelineSurface` construction from Root remain closed, no same-session fallback after visible mutation, and no production replacement of legacy Home.
- [ ] Root diagnostics sink injection baseline passes a local in-memory `TimelineHomeRouteDiagnosticsSink` or narrow protocol into `TimelineHomeRootRouteCallSite`; it does not call `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select` directly from Root.
- [ ] Root diagnostics sink injection baseline keeps launch arguments, debug override, `createdAtMS`, and dependency readiness injected into the preflight path; the Root call site does not read `ProcessInfo.processInfo.arguments` directly unless a tiny adapter reads it and injects it into the preflight input.
- [ ] Root diagnostics sink injection baseline attaches a local route decision artifact for debug review only: `artifactKind == "timeline_home_route_decision"`, `eventName == "timeline_home_route_preflight_decision"`, `source == "rootPreflight"`, `selectedRoute`, fallback reason or none, dependency readiness, side-effect sentinel all false, `requiresNetworkWork == false`, `requiresDBWrite == false`, `readMarkerChanged == false`, and `preventsDualMutation == true` are visible without route construction, relay startup, network work, DB writes, file writes, external upload, telemetry, analytics, remote logging, raw private content, raw event JSON, pubkeys, event IDs, relay URLs, `nsec`, Keychain data, signing payloads, or bearer tokens.
- [ ] Root diagnostics sink injection baseline proves `TimelineHomeRootRouteDiagnosticsSinkInjectionTests` executed non-zero Swift Testing tests, including `root_preflight_records_one_local_route_decision`, `root_preflight_default_legacy_rendering_unchanged`, `root_preflight_sink_is_in_memory_only`, `root_preflight_sink_does_not_construct_collection_view`, `root_preflight_sink_does_not_construct_nostr_store`, `root_preflight_sink_does_not_start_network`, `root_preflight_sink_does_not_write_db`, `root_preflight_sink_does_not_advance_read_marker`, `root_preflight_sink_does_not_call_dataSourceApply`, `root_preflight_sink_artifact_passes_privacy_guard`, and `root_preflight_sink_selected_suites_non_zero`.
- [ ] Flagged collection view route construction remains limited to the reviewed offscreen/non-rendered path: default legacy behavior is unchanged with Root preflight plus sink injection, the route diagnostics artifact proves no network/DB/read-marker side effects, construction readiness / construction plan consumer / offscreen harness / offscreen harness result consumer / artifact chain consumer pass, offscreen controller smoke and snapshot coordinator harness remain green, no startup network logs appear, `networkWaitedBeforeInteractiveScrollMS == 0`, `readMarkerChanged == false`, old/new dual mutation prevention remains true, and production Root body render switching remains separately closed.
- [ ] Collection view route construction means Root/Home may construct a collection view route description or a `TimelineSurface` / `TimelineCollectionViewController` dependency path behind explicit `--timeline-engine=collectionView` and readiness gates; it must remain no-window/offscreen or non-rendered unless separately opened, and it is not default rendering, not route activation, and not a rendering switch.
- [ ] Root body render switching remains explicit-flag-only and clean-gate-only: default/no-flag startup remains legacy, debug override `.collectionView` cannot bypass the launch flag, rollback/manual fallback remain legacy, and collection view Home is not the default.
- [ ] Before route construction opens, required gates are listed and PASS: Root no-op preflight, route diagnostics sink injection, root decision snapshot, snapshot consumer, construction readiness, construction plan consumer, offscreen harness, offscreen harness result consumer, artifact chain consumer, `TimelineCollectionViewControllerSmokeTests`, `TimelineInitialRestoreSnapshotCoordinatorHarnessTests`, selected Swift Testing suites non-zero, startup network grep with no matches, `networkWaitedBeforeInteractiveScrollMS == 0`, `readMarkerChanged == false`, `requiresNetworkWork == false`, `requiresDBWrite == false`, coordinator-only `dataSource.apply`, no extra collectionView-path `NostrHomeTimelineStore` construction, no DB write/read marker mutation, and artifact privacy guard/self-test.
- [ ] Future route construction tests exist before implementation opens construction: `TimelineHomeCollectionViewRouteBehindFlagConstructionTests`, `collectionView_route_requires_explicit_flag`, `collectionView_route_requires_all_readiness_gates`, `default_legacy_route_does_not_construct_collectionView`, `flagged_collectionView_route_constructs_only_non_rendered_or_offscreen_path`, `flagged_collectionView_route_keeps_renderedRoute_legacy`, `flagged_collectionView_route_keeps_activation_false`, `flagged_collectionView_route_records_artifact_chain`, `flagged_collectionView_route_does_not_start_network`, `flagged_collectionView_route_does_not_write_db`, `flagged_collectionView_route_does_not_advance_read_marker`, `flagged_collectionView_route_does_not_call_dataSourceApply_from_Root`, `flagged_collectionView_route_does_not_construct_extra_NostrHomeTimelineStore`, `startup_network_grep_no_matches`, and `selected_swift_testing_suites_non_zero`.
- [ ] First route construction implementation, when explicitly opened, is titled `test: construct TimelineHome collectionView route behind flag`; it may only construct a collection view route description or read-only/offline dependency path plus a no-window/offscreen or non-rendered `TimelineSurface` or `TimelineCollectionViewController` behind explicit flag/readiness while keeping the default rendered route legacy, `renderedRouteAfterConstruction == legacy`, and `routeActivationAllowed == false`.
- [ ] First route construction implementation forbids defaulting to collection view, replacing legacy Home rendering, activation/render switch, removing or bypassing `NostrHomeTimelineStore`, starting relay/network/resolver work, writing DB/read marker/`feed_read_state`/`feed_items.pending_new`/`resolve_jobs`, calling `dataSource.apply` from Root, changing splash/root shell behavior, GitHub Actions/dependency changes, SQL schema/migration changes, legacy SwiftUI Timeline implementation changes, and URLSession/relay/media resolver/OGP resolver/profile resolver/real `ResolveCoordinator` connections.
- [ ] Root body render switching remains later than construction, activation switch helper, Root activation decision chain, and Root body activation wiring gate: if any gate fails, do not render collection view; record the artifact and keep legacy.
- [ ] Root body render switch behavior is covered by `TimelineHomeRootBodyRenderSwitchTests`: explicit flag required, clean wiring gate required, default without the flag legacy, dirty wiring gate renders legacy, clean flagged wiring renders collection view, root shell first paint preserved, Timeline-area-only restore gate, no startup network, no DB write, no read-marker advancement, no Root `dataSource.apply`, no extra `NostrHomeTimelineStore`, same-session double mutation prevented, rollback returns to legacy, and selected suites non-zero.
- [ ] Root body render switch forbidden scope includes defaulting to collection view, removing or bypassing `NostrHomeTimelineStore`, relay/network/resolver startup before first interactive scroll, DB write/read marker/`feed_read_state`/`pending_new` mutation, `dataSource.apply` from Root, splash/root shell behavior changes, GitHub Actions/dependency/schema/migration changes, external telemetry/upload/export paths, opening the `ResolveCoordinator` actor, and media/OGP resolver wiring.
- [ ] TimelineHome startup smoke acceptance includes a fixed result bundle generated for `TimelineHomeFlaggedCollectionViewStartupSmokeTests`; final PR notes include the exact result bundle path.
- [ ] TimelineHome startup smoke acceptance includes startup-network scan output from that fixed result bundle. Required tokens are `LocalDataTask`, `ATS failure`, `nw_`, `WebSocket`, `URLSessionWebSocketTask`, `wss://`, `setDefaultRelays`, and relay connection attempts; plain `URLSession` duplicate-class warnings are distinguished from actual startup attempts.
- [ ] TimelineHome startup smoke acceptance includes privacy encoded JSON checks proving no raw result-bundle lines, raw excerpts, or raw `launchArguments` are encoded.
- [ ] TimelineHome startup smoke privacy schema allows pattern hits to expose only `patternKind`, `tokenID`, `lineNumber` or occurrence index, and a fixed `redactedSummary`; launch arguments are normalized to known flags, `requestedEngineMode`, `unknownArgumentCount`, and `redactedUnknownArguments`.
- [ ] TimelineHome startup smoke forbidden-fragment checks include `nsec`, `secret`, `privateKey`, `private_key`, `raw_json`, `rawEvent`, `raw_event`, `mnemonic`, `keychain`, `nostr secret`, relay URL, pubkey, event id, and private message content phrase.
- [ ] TimelineHome startup smoke selected suite counts are included, and no selected Swift Testing suite executed 0 tests. `Executed 0 tests` from the XCTest wrapper alone is not evidence.
- [ ] TimelineHome startup smoke gate behavior remains fixed: default/no-flag startup remains legacy, flagged startup requires `--timeline-engine=collectionView`, a clean Root body wiring gate is required, dirty bundle scans reject the flagged route, stale restore input rejects the flagged route, rollback/manual fallback remain legacy, and there is no DB write/read-marker/`pending_new`/Root `dataSource.apply` side effect.
- [ ] TimelineHome startup local review packet attaches the fixed startup smoke result bundle path and the selected app suite result bundle path from the current run.
- [ ] TimelineHome startup local review packet pastes startup-network scan output and privacy scan output, including explicit separation of plain `URLSession` duplicate-class warnings from actual startup-network attempts.
- [ ] TimelineHome startup local review packet pastes selected suite counts, zero selected suite count, `AstrenzaCore` total test count when run, and `TimelineRepositoryStore` suite count when run.
- [ ] TimelineHome startup local review packet pastes the encoded diagnostics attachment summary, encoded evidence bundle summary, and encoded local gate report summary.
- [ ] TimelineHome startup local gate report summary includes `reportKind`, `reportVersion`, `source`, `gateStatus`, `fixedResultBundlePathSummary`, `startupNetworkScanStatus`, `privacyScanStatus`, `selectedSuiteCounts`, `totalSelectedTestCount`, `zeroSelectedSuiteCount`, `selectedSwiftTestingSuitesNonZero`, `selectedRoute`, `renderedRoute`, `usedCollectionViewFlag`, `artifactSummary`, `issueKinds`, `blockingIssueKinds`, `nonBlockingIssueKinds`, `releaseGateFailures`, and `noNetworkDBReadMarkerRootApplySideEffects`.
- [ ] TimelineHome startup local gate pass evidence confirms `usedCollectionViewFlag == true`, `selectedRoute == collectionView`, `renderedRoute == collectionView`, clean Root body wiring gate evidence, clean startup-network/privacy scans, non-zero selected Swift Testing suites, zero selected suite count, clean side-effect sentinels, no raw bundle lines, no raw `launchArguments`, and no dirty relay/pubkey/event/secret-like fragments.
- [ ] TimelineHome startup failure evidence is attached for any startup-network token hit, privacy forbidden fragment hit, selected Swift Testing suite with 0 tests, missing fixed result bundle path, missing selected suite counts, missing local gate report summary, non-`collectionView` route evidence, or dirty side-effect sentinel.
- [ ] TimelineHome startup local review packet confirms no selected Swift Testing suite executed 0 tests.
- [ ] TimelineHome startup local review packet confirms no CI or `.github` changes unless a later approved scope explicitly opens them.
- [ ] Root diagnostics sink injection baseline keeps `NostrHomeTimelineStore`, legacy SwiftUI Home, root shell, startup splash, schema, migration, DB write paths, relay/network/resolver startup, real `ResolveCoordinator`, `resolve_jobs`, `TimelinePlaceholderRow`, project/dependency files, and `.github` unchanged unless a later approved scope explicitly opens them.
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
