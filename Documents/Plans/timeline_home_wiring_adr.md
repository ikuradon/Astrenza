# TimelineEngine Home Wiring ADR

## 1. Status

Proposed for later rollout/default decisions. The TimelineHome collectionView flagged startup/restore/scroll local gate is complete.

This ADR is docs-only. It records the staged production Home wiring strategy for the new TimelineEngine restore pipeline. It does not authorize collection view Home as the default route.

## 2. Context

The legacy SwiftUI Home path remains the default production Home surface. `AstrenzaRootView` still owns the root shell/session flow, and `HomeTimelineView` still renders the default timeline through the legacy SwiftUI `TimelineFeedView` path unless the explicit collection view startup/restore/scroll gates are clean.

The new TimelineEngine/Core Store pipeline is ready for offline and source-model acceptance, but it is not yet wired into production Home. The existing offline path covers:

- Core `TimelineRepositoryStore` read-only boundary.
- App `TimelineRepositoryStoreWindowComposer`.
- App `TimelineRepositoryStore` diagnostics mapping.
- `TimelineInitialRestoreUseCase`.
- `TimelineInitialRestoreCoordinatorAdapter`.
- `TimelineHomeEngineMode`.
- `TimelineHomeRouteAdapter`.
- `TimelineHomeRouteIntegrationSkeleton`.
- `TimelineHomeRouteHost`.
- `TimelineHomeRouteDiagnostics`.
- `TimelineHomeRootRouteGuard`.
- `TimelineHomeRootRoutePreflight`.
- `TimelineHomeLaunchRestoreContract`.
- `TimelineSurfaceDependencyContainer`.
- `TimelineHomeRouteConstructionReadiness`.
- `TimelineHomeRouteConstructionPlanConsumer`.
- `TimelineHomeRouteConstructionReadinessConsumer`.
- `TimelineHomeOffscreenConstructionHarnessResultConsumer`.
- `TimelineHomeConstructionArtifactChainConsumer`.
- `TimelineHomeCollectionViewRouteActivationReadiness`.
- `TimelineHomeCollectionViewRouteActivationReadinessConsumer`.
- `TimelineHomeActivationArtifactChainConsumer`.
- `TimelineHomeRootActivationPreflight`.
- `TimelineHomeRootActivationDecisionSnapshotChain`.
- `TimelineHomeRootActivationDecisionSnapshotChainConsumer`.
- `TimelineHomeCollectionViewRouteActivationSwitch`.
- `TimelineHomeRootBodyActivationWiringGate`.
- `TimelineHomeRootBodyActivationWiringGateConsumer`.
- `TimelineHomeRootBodyRenderSwitch`.
- `TimelineHomeCollectionViewRouteRestore`.
- `TimelineHomeCollectionViewStartupSmoke`.
- `TimelineHomeCollectionViewVisibleRestoreRows`.
- `TimelineHomeCollectionViewRestoreScrollPosition`.
- `TimelineCollectionViewController` offscreen smoke coverage.
- `TimelineInitialRestoreSnapshotCoordinatorHarness`.
- TimelineEngine scaffold, `TimelineSnapshotCoordinator`, `TimelinePositionRecorder`, and `TimelineDiagnosticsRecorder`.

Schema v0.2 remains unchanged. DB write paths, resolver execution, relay sync, media/OGP/profile resolver connection, default collection view rollout, and production DB-backed Home write wiring remain out of scope.

The v1 source-of-truth still requires the production Timeline direction to be `UICollectionView` + `UICollectionViewDiffableDataSource` + `UIHostingConfiguration`, with DesignSystem tokens treated as runtime contracts rather than optional styling.

Current production launch behavior also has a known future rollout gap: the root shell and app-wide startup splash are still coupled to Home readiness. A future wiring PR must separate root shell first paint from the Timeline-area restore gate before enabling the collection view Home path by default.

## 3. Decision

Production Home wiring uses an explicit engine mode flag, modeled as `AstrenzaTimelineEngineMode`, with a launch argument such as `--timeline-engine=collectionView`.

The default mode remains legacy SwiftUI Home. The first collection view rollout is Home-only and explicit-flag-only; Mentions, Profile, Thread, List, and Search surfaces remain separate future decisions.

The running session must not automatically fall back from the collection view path to legacy Home after Home has started mutating visible state. Rollback is a restart-time or debug-switch choice that selects the legacy path before route construction, not a same-session dual-render or hidden failover.

`AstrenzaRootView` root shell behavior remains unchanged by this ADR. Future implementation must preserve immediate root shell first paint and must not wait for relay, network, resolver, search, pruning, checkpoint, or EOSE work before the first interactive Timeline scroll.

Collection view route construction is a separate milestone from route activation. It means Root/Home may construct a collection view route description or a `TimelineSurface` / `TimelineCollectionViewController` dependency path behind `--timeline-engine=collectionView` and readiness gates. It is not default rendering, not route activation, and not a rendering switch. The first construction slice must remain no-window/offscreen or non-rendered unless a later task explicitly opens rendered construction. The Root body decision snapshot must continue to report `renderedRoute == legacy`, `renderedRouteAfterConstruction == legacy`, and `routeActivationAllowed == false` until a later activation task explicitly opens rendering.

The activation switch helper is a pure milestone where Root/Home route artifacts can prove the already constructed collection view path would be eligible behind the explicit `--timeline-engine=collectionView` flag and clean readiness gates. It does not by itself authorize `AstrenzaRootView.body` to render collection view Home.

Root body render switch is the milestone where `AstrenzaRootView.body` may choose the collection view Home route. It requires the explicit `--timeline-engine=collectionView` flag, a clean Root body activation wiring gate, all construction and activation artifacts still clean, default launch without the flag remaining legacy, and manual rollback remaining legacy. It must preserve Root shell first paint, keep the Timeline restore gate scoped to the Timeline area only, and must not introduce startup network, DB writes, read-marker mutation, or Root-owned `dataSource.apply`.

Current state remains default-legacy: collection view rendering is allowed only when the explicit flag, clean wiring gate, clean route restore input, clean fixed result bundle scan, and non-zero selected Swift Testing suites all pass. TimelineHome collectionView flagged startup/restore/scroll local gate complete. Debug override `.collectionView` must not bypass the explicit launch flag or readiness gates.

## 4. Dependency Injection Plan

Future Home wiring should construct the new path through a narrow dependency container rather than allowing Home views to directly create DB, network, relay, or resolver objects. The initial dependency set is:

- `TimelineRepositoryStore`.
- `TimelineRepositoryStoreWindowComposer`.
- `TimelineInitialRestoreUseCase`.
- `TimelineInitialRestoreCoordinatorAdapter` or its production runtime equivalent.
- `TimelineCollectionViewController` / `TimelineSurface`.
- Row model projector / `TimelineEntryViewState` projector.
- `TimelineSnapshotCoordinator`.
- Persisted-anchor restore executor.
- `TimelineDiagnosticsRecorder` and diagnostics sink.
- Fake/test runtime dependencies for fixture Home and app-hosted tests.

The Core store dependency should be injected as the read-only `TimelineRepositoryStore` boundary. UIKit and SwiftUI surfaces must not own SQL strings, `GRDB` handles, relay clients, or resolver queues.

Home wiring must not call relay or network work before local initial restore. It must not write the read marker during launch, restore, sync, EOSE, foreground, or resolve. It must not mutate `feed_items.pending_new` during restore. It must not call `dataSource.apply` outside `TimelineSnapshotCoordinator`.

## 5. Legacy Home Boundary

Legacy SwiftUI Home remains frozen except for bug fixes and required compatibility maintenance. No new feature work should be added to `TimelineFeedView`, `TimelinePostRow`, `TimelineAttachments`, or their `ScrollView` / `LazyVStack` production timeline path.

Legacy Home can remain the default and fallback while the collection view path matures. The old and new paths must not both observe and mutate the visible dataset or read marker at the same time.

Any shared store used by the new path remains read-only until a separate write-path ADR explicitly opens DB write scope.

## 6. Feature Flag / Rollout Gates

The collection view Home path can only be enabled behind the engine mode flag after all of these gates pass:

- A local fixture Home launch uses the new path without production relay, network, or resolver startup.
- Restore plan to coordinator expectation tests pass.
- An initial `UICollectionView` surface smoke test passes.
- Startup logs show no network startup before local restore, including no `LocalDataTask`, `ATS`, `nw_`, `WebSocketTask`, `URLSessionWebSocketTask`, `wss://`, or `setDefaultRelays` activity for the selected restore path.
- Restore diagnostics keep `readMarkerChanged == false`.
- Restore diagnostics keep `networkWaitedBeforeInteractiveScrollMS == 0`.
- Visible rows exclude `pending_new` by default.
- Visible rows exclude hidden rows by default.
- Missing-target quote and repost rows remain in the snapshot with fallback render state.
- Selected `xcodebuild` suites execute non-zero Swift Testing tests.
- The manual debug switch and launch argument are documented.
- Root shell first paint is proven independent from Timeline restore readiness.
- Root decision snapshots and consumers prove `renderedRoute == legacy`, `collectionViewRouteConstructed == false`, `readMarkerChanged == false`, `requiresNetworkWork == false`, `requiresDBWrite == false`, `networkWaitedBeforeInteractiveScrollMS == 0`, and no `dataSource.apply` outside `TimelineSnapshotCoordinator`.
- Route diagnostics artifacts pass the privacy guard and contain no fallback, missing dependency, runtime-disabled, rollout-blocked, unknown mode, or release-blocker decision before construction opens.
- The collection view construction path does not construct an extra `NostrHomeTimelineStore` for the same account/feed session.
- Construction readiness, construction plan consumer, offscreen harness, offscreen harness result consumer, construction artifact chain consumer, `TimelineCollectionViewControllerSmokeTests`, and `TimelineInitialRestoreSnapshotCoordinatorHarnessTests` all pass.
- Diagnostics guard self-test passes before claiming privacy guard coverage.
- Activation switch helper, activation readiness, activation readiness consumer, activation artifact chain consumer, Root activation preflight, Root activation decision snapshot chain, Root activation decision snapshot chain consumer, Root body activation wiring gate, and Root body activation wiring gate consumer all pass before `AstrenzaRootView.body` selects collection view.
- The Root body render switch suite proves explicit flag required, clean wiring gate required, default legacy without flag, dirty wiring gate renders legacy, clean flagged wiring renders collection view, root shell first paint preserved, Timeline-area-only restore gate, no startup network, no DB write, no read-marker advancement, no Root `dataSource.apply`, no extra `NostrHomeTimelineStore`, same-session double mutation prevented, rollback to legacy, and non-zero selected Swift Testing suites.

## 7. Startup Smoke Acceptance Baseline

`TimelineHomeFlaggedCollectionViewStartupSmokeTests` defines the acceptance baseline for future TimelineHome startup gates. The baseline is valid only when a fixed `.xcresult` bundle is generated for the selected run, the result bundle path is reported, the fixed bundle is scanned for startup-network evidence, and the selected Swift Testing suites execute non-zero tests. `Executed 0 tests` from the XCTest wrapper is not evidence unless the same run also reports a later non-zero Swift Testing summary and the `.xcresult` tree contains the selected suites.

Startup smoke artifacts must use a privacy-safe schema:

- No raw result-bundle lines.
- No raw excerpts.
- No raw `launchArguments`.
- Pattern hits may expose only `patternKind`, `tokenID`, `lineNumber` or occurrence index, and a fixed `redactedSummary`.
- Launch arguments are normalized to known flags, `requestedEngineMode`, `unknownArgumentCount`, and `redactedUnknownArguments`.
- Unknown argument values are counted and redacted, never copied.

Encoded startup smoke JSON, debug summaries, fixtures, screenshots, logs, and failure artifacts must reject these fragments: `nsec`, `secret`, `privateKey`, `private_key`, `raw_json`, `rawEvent`, `raw_event`, `mnemonic`, `keychain`, `nostr secret`, relay URL, pubkey, event id, and private message content phrase.

The fixed result bundle startup-network scan must check `LocalDataTask`, `ATS failure`, `nw_`, `WebSocket`, `URLSessionWebSocketTask`, `wss://`, `setDefaultRelays`, and relay connection attempts. A plain `URLSession` duplicate-class warning must be separated from an actual startup attempt; it is not by itself a relay/network attempt when the fixed bundle has none of the stronger startup-network tokens.

Startup smoke release review evidence is a local-only packet layered as:

```text
TimelineHomeStartupSmokeDiagnosticsAttachment
  -> TimelineHomeStartupSmokeEvidenceBundle
  -> TimelineHomeStartupSmokeLocalGateReport
  -> TimelineHome startup local review packet
```

The diagnostics attachment, evidence bundle, local gate report, and review packet remain local/offline/debug/failure-artifact evidence only. They do not open file writers, upload/export telemetry, analytics, remote logging, CI artifact upload, DB work, network work, resolver work, Root/Home rendering, splash behavior changes, schema changes, migrations, dependency changes, or `.github` changes.

The local review packet must include the fixed startup smoke result bundle path, selected app suite result bundle path, startup-network scan output, privacy scan output, encoded diagnostics attachment summary, encoded evidence bundle summary, encoded local gate report summary, selected suite counts, zero selected suite count, `AstrenzaCore` total test count when run, `TimelineRepositoryStore` suite count when run, git SHA, `HEAD == origin/main`, and clean worktree confirmation.

The local gate report pass semantics must stay strict. A clean-looking bundle still fails without explicit collection view startup evidence. Pass requires `usedCollectionViewFlag == true`, `selectedRoute == collectionView`, `renderedRoute == collectionView`, clean Root body wiring gate evidence, clean startup-network scan, clean privacy scan, `selectedSwiftTestingSuitesNonZero == true`, zero selected suite count, every side-effect sentinel clean, no raw bundle lines, no raw `launchArguments`, and no dirty relay/pubkey/event/secret-like fragments.

Failure evidence must be preserved for any startup-network token hit, any privacy forbidden fragment hit, any selected Swift Testing suite with 0 tests, missing fixed result bundle path, missing selected suite counts, missing local gate report summary, missing explicit collection view flag, non-`collectionView` selected or rendered route, or any dirty side-effect sentinel.

The flagged route is rejected and legacy remains selected when the fixed result bundle scan is dirty, when restore input is stale, when the explicit `--timeline-engine=collectionView` flag is missing, or when the Root body wiring gate is dirty. Rollback and manual fallback remain legacy. No startup smoke gate may write DB state, mutate read marker, mutate `feed_read_state`, mutate `pending_new`, call `dataSource.apply` from Root, start network/resolver work, or add telemetry/export/upload paths.

## 8. Rollback Criteria

Keep the flag off, or roll back to legacy mode on the next launch, if any of these occur:

- First paint waits for network, relay EOSE, resolver, search, pruning, checkpoint, or optimize work.
- The visible timeline jumps or briefly shows newest/top before restoring the saved anchor.
- Read marker advances during launch, restore, sync, EOSE, foreground, or resolve.
- `pending_new` inserts automatically without user action or an explicit top-of-feed policy.
- `dataSource.apply` is called outside `TimelineSnapshotCoordinator`.
- Old and new Home both observe or mutate the visible dataset/read marker.
- Core Store query results diverge from source-model tests.
- Row projection changes item identity.

## 9. Current Sequence Position

TimelineHome collectionView flagged startup/restore/scroll local gate complete.

Completed checkpoints include route construction, activation switch helper, Root body activation wiring gate, explicit Root body render switch, startup smoke privacy, simulator startup smoke, visible restored rows, and restore scroll position. The completed boundary still requires default/no flag remaining legacy, explicit `--timeline-engine=collectionView`, clean evaluated Root body wiring gate evidence, startup smoke PASS, visible restored rows PASS, restore scroll position PASS, no startup network, no DB write, no read marker mutation, no `pending_new` mutation, no Root-owned `dataSource.apply`, no extra `NostrHomeTimelineStore`, and non-zero selected Swift Testing suites.

Next phase candidates only:

1. actual data display quality
2. scroll interaction behavior
3. local pagination/windowing
4. manual visual smoke
5. release/default decision

## 10. Explicit Forbidden Scope

This ADR does not open:

- SQL schema changes.
- DB migration.
- DB write paths.
- Real `ResolveCoordinator` actor implementation.
- `resolve_jobs` execution.
- Relay, network, media resolver, OGP resolver, or profile resolver connection.
- External telemetry.
- GitHub Actions changes.
- Dependency changes.
- Legacy Home feature work.
- Read marker advancement during launch, restore, sync, EOSE, foreground, or resolve.
- Production root shell, splash, default route behavior, or collection view default rollout changes.
- Root body render switching outside the explicit flag and clean Root body wiring gate.
- Root direct calls to `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select`; Root must enter through `TimelineHomeRootRoutePreflight.invoke(_:)` or a tiny wrapper that preserves `.collectionView` debug-override sanitization.

Diagnostics for this pipeline remain local/debug/failure-artifact only until a separate privacy decision explicitly opens another destination.

## 11. Required Tests For Future Wiring PR

Future wiring PRs should include focused RED-first coverage before production integration:

- `TimelineHomeRootRouteCallSiteTests`.
- `TimelineHomeEngineModeTests`.
- `TimelineSurfaceDependencyContainerTests`.
- `TimelineCollectionViewControllerSmokeTests`.
- `TimelineHomeRouteFlagTests`.
- `TimelineHomeRouteConstructionReadinessTests`.
- `TimelineHomeCollectionViewRouteBehindFlagConstructionTests`.
- `TimelineHomeRouteIntegrationSkeletonTests`.
- `default_root_route_preflight_keeps_legacy_home`.
- `root_route_preflight_does_not_construct_collection_view`.
- `root_route_preflight_does_not_construct_nostr_store`.
- `root_route_preflight_records_local_diagnostics`.
- `collection_view_flag_records_decision_but_does_not_enable_by_default`.
- `unknown_flag_falls_back_to_legacy`.
- `read_marker_not_advanced_by_root_preflight`.
- `no_network_started_by_root_preflight`.
- `no_db_write_by_root_preflight`.
- `launch_does_not_wait_for_network`.
- `launch_restore_cached_anchor_no_visible_jump`.
- `pending_new_not_inserted_until_user_action`.
- `read_marker_not_advanced_by_restore`.
- `dataSourceApply_coordinator_only`.
- `collectionView_route_requires_explicit_flag`.
- `collectionView_route_requires_all_readiness_gates`.
- `default_legacy_route_does_not_construct_collectionView`.
- `flagged_collectionView_route_constructs_only_non_rendered_or_offscreen_path`.
- `flagged_collectionView_route_keeps_renderedRoute_legacy`.
- `flagged_collectionView_route_keeps_activation_false`.
- `flagged_collectionView_route_records_artifact_chain`.
- `flagged_collectionView_route_does_not_start_network`.
- `flagged_collectionView_route_does_not_write_db`.
- `flagged_collectionView_route_does_not_advance_read_marker`.
- `flagged_collectionView_route_does_not_call_dataSourceApply_from_Root`.
- `flagged_collectionView_route_does_not_construct_extra_NostrHomeTimelineStore`.
- `TimelineHomeCollectionViewRouteActivationTests`.
- `activation_requires_explicit_flag`.
- `activation_requires_all_construction_gates`.
- `default_legacy_rendering_remains_default`.
- `activation_does_not_start_network_before_interactive_scroll`.
- `activation_does_not_advance_read_marker`.
- `activation_does_not_write_db`.
- `activation_does_not_call_dataSourceApply_from_Root`.
- `activation_does_not_construct_extra_NostrHomeTimelineStore`.
- `activation_records_route_and_construction_artifacts`.
- `activation_uses_timeline_area_restore_gate_only`.
- `activation_keeps_root_shell_first_paint`.
- `activation_rollback_returns_to_legacy`.
- `TimelineHomeRootBodyRenderSwitchTests`.
- `root_body_render_switch_requires_explicit_flag`.
- `root_body_render_switch_requires_clean_wiring_gate`.
- `default_without_flag_renders_legacy`.
- `dirty_wiring_gate_renders_legacy`.
- `clean_flagged_wiring_renders_collectionView`.
- `render_switch_preserves_root_shell_first_paint`.
- `render_switch_uses_timeline_area_restore_gate_only`.
- `render_switch_does_not_start_network_before_interactive_scroll`.
- `render_switch_does_not_write_db`.
- `render_switch_does_not_advance_read_marker`.
- `render_switch_does_not_call_dataSourceApply_from_Root`.
- `render_switch_does_not_construct_extra_NostrHomeTimelineStore`.
- `render_switch_prevents_same_session_double_mutation`.
- `rollback_returns_to_legacy`.
- `startup_network_grep_no_matches`.
- `selected_swift_testing_suites_non_zero`.

Use Swift type names in `-only-testing` and require every selected app suite to report a non-zero Swift Testing count. An xcodebuild run that exits 0 while selecting 0 Swift Testing tests is not valid evidence.
