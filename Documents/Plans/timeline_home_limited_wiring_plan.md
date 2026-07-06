# TimelineHome Limited Wiring Plan

## 1. Status

Proposed.

This document defines the limited TimelineHome Root/Home wiring ladder through the current explicit-flag Root body render switch and startup smoke checkpoints, then defines the acceptance baseline for future TimelineHome startup gates.

- `test: wire TimelineHome collectionView route into Root body behind flag`
- `test: repair TimelineHome startup smoke privacy`

This is a docs-only planning/checklist document. It does not change production source, tests, CI, project configuration, SQL, or dependencies. It does not render collection view Home by default and does not authorize collection view Home as the default.

## 2. Basis

The Root diagnostics sink injection task started only after the route diagnostics sink checkpoint passed review and selected non-zero test validation. The checkpoint was:

- `63ddf7c test: define TimelineHome route diagnostics sink`

The route decision snapshot consumer checkpoint extended the read-only local/debug path:

- `93252db test: read TimelineHome root route decision snapshots`

The latest construction artifact chain checkpoint links route decision snapshots, construction readiness, and offscreen harness results through a deterministic local/offline consumer:

- `10f328e test: read TimelineHome construction artifact chain`

The first flagged construction implementation checkpoint constructed only the allowed offscreen/non-rendered collection view route descriptor path behind explicit flag and readiness gates:

- `f163ed0 test: construct TimelineHome collectionView route behind flag`

The activation switch helper checkpoint evaluated the already constructed route behind the explicit flag and clean readiness artifacts without changing `AstrenzaRootView.body`:

- `18be791 test: activate TimelineHome collectionView route behind flag`

The Root body activation wiring gate and reader checkpoints proved that a clean activation switch can be consumed while production Root body rendering remains legacy:

- `5611495 test: define TimelineHome root body activation wiring gate`
- `6de53d0 test: read TimelineHome root body activation wiring gate results`

The explicit Root body render switch checkpoint opened only the flagged branch, not the default route:

- `491b7e9 test: wire TimelineHome collectionView route into Root body behind flag`

The startup smoke privacy checkpoint repaired the flagged startup artifact schema so raw result bundle lines and raw launch arguments are not encoded:

- `4b913a3 test: repair TimelineHome startup smoke privacy`

`AstrenzaRootView` already performs a no-op `TimelineHomeRootRouteCallSite` production preflight before constructing the existing `NostrSessionStore` and `NostrHomeTimelineStore`. `TimelineHomeRouteDiagnosticsSink` now exists as a local, offline, in-memory retention sink for route decision artifacts. `TimelineHomeRootRouteDecisionSnapshot`, `TimelineHomeRootRouteDecisionSnapshotConsumer`, `TimelineHomeRouteConstructionReadiness`, `TimelineHomeRouteConstructionPlanConsumer`, `TimelineHomeRouteConstructionReadinessConsumer`, `TimelineHomeOffscreenConstructionHarnessResultConsumer`, and `TimelineHomeConstructionArtifactChainConsumer` can read the Root-visible route/construction artifact chain in local/debug/fixture code.

The current allowed state is default legacy rendering plus a flagged collection view construction result, activation switch helper result, Root activation decision chain, Root body activation wiring gate result, explicit Root body render switch result, collection view route restore decision, and startup smoke artifact. The collection view route remains gated by `--timeline-engine=collectionView`, a clean Root body wiring gate, clean restore input, a clean fixed result bundle scan, and non-zero selected Swift Testing suites.

The existing contracts available to the future construction-readiness slice are:

- `TimelineHomeEngineMode`
- `TimelineHomeRouteAdapter`
- `TimelineHomeRouteIntegrationSkeleton`
- `TimelineHomeRouteHost`
- `TimelineHomeRouteDiagnostics`
- `TimelineHomeRouteDiagnosticsSink`
- `TimelineHomeRootRouteGuard`
- `TimelineHomeRootRoutePreflight`
- `TimelineHomeLaunchRestoreContract`
- `TimelineSurfaceDependencyContainer`
- `TimelineHomeRouteConstructionReadiness`
- `TimelineHomeRouteConstructionPlanConsumer`
- `TimelineHomeRouteConstructionReadinessConsumer`
- `TimelineCollectionViewController` offscreen smoke coverage
- `TimelineHomeOffscreenConstructionHarnessResultConsumer`
- `TimelineHomeConstructionArtifactChainConsumer`
- `TimelineHomeCollectionViewRouteActivationReadiness`
- `TimelineHomeCollectionViewRouteActivationReadinessConsumer`
- `TimelineHomeActivationArtifactChainConsumer`
- `TimelineHomeRootActivationPreflight`
- `TimelineHomeRootActivationDecisionSnapshotChain`
- `TimelineHomeRootActivationDecisionSnapshotChainConsumer`
- `TimelineHomeCollectionViewRouteActivationSwitch`
- `TimelineHomeRootBodyActivationWiringGate`
- `TimelineHomeRootBodyActivationWiringGateConsumer`
- `TimelineInitialRestoreSnapshotCoordinatorHarness`
- `TimelineInitialRestoreUseCase`
- `TimelineRepositoryStoreWindowComposer`
- Core `TimelineRepositoryStore` read-only boundary

## 3. Current Sink-Injection Scope Baseline

The completed sink-injection implementation task was:

- `test: inject TimelineHome route diagnostics sink at root preflight`

Equivalent future maintenance wording is acceptable only if it keeps the same scope: Root may pass a local in-memory `TimelineHomeRouteDiagnosticsSink`, or a narrow protocol for the same behavior, into the existing no-op `TimelineHomeRootRouteCallSite` preflight path. The call must preserve visible Home behavior.

The default route remains legacy SwiftUI Home. The collection view route must not be constructed from Root in this implementation, even when `--timeline-engine=collectionView` records a decision in the local preflight diagnostics. The route decision exists to prove Root can call the pure preflight boundary and record one safe local artifact without changing Home output.

The implementation must preserve these constraints:

- Root preflight records exactly one `TimelineHomeRouteDecisionArtifact`.
- The artifact remains local and in-memory only.
- Any debug summary is exposed only in tests or debug builds.
- Route artifact naming remains stable: `artifactKind == "timeline_home_route_decision"`, `eventName == "timeline_home_route_preflight_decision"`, and `source == "rootPreflight"`.
- Default launch uses legacy Home and renders the existing `HomeTimelineView` path as before.
- Unknown or missing flag falls back to legacy before any route construction.
- `collectionView` flag may record a local preflight decision only when dependency readiness is injected and ready.
- `collectionView` flag must not instantiate `TimelineCollectionViewController`.
- `collectionView` flag must not construct a collection view `TimelineSurface` from Root.
- Root must call `TimelineHomeRootRoutePreflight.invoke(_:)` or a tiny wrapper around it, not `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select` directly.
- Root shell behavior remains unchanged.
- Observable production Home/root/splash behavior remains unchanged; any route decision wrapper must preserve the default legacy path behavior.
- No production replacement of legacy Home.
- No DB writes.
- No relay or network start before local restore.
- No resolver work before first interactive scroll.
- No read marker advancement.
- No `feed_items.pending_new` mutation.
- No same-session dual mutation between legacy Home and collection view Home.
- No file writes from the sink.
- No network, upload, export telemetry, analytics, or remote logging.
- No `dataSource.apply` call.
- No GitHub Actions changes.
- No legacy SwiftUI Timeline implementation changes.

## 4. Allowed Sink-Injection Maintenance Changes

Sink-injection maintenance may make only the minimum code changes needed to preserve Root calling the preflight boundary with a local diagnostics sink without replacing production Home.

Allowed files or classes:

- `AstrenzaRootView`, only for passing a local in-memory sink into the existing narrow no-op preflight call or wrapper call while preserving observable default legacy Home/root/splash behavior.
- A tiny Root-adjacent wrapper, if needed, whose only responsibility is to inject launch arguments, debug override, dependency readiness, and a local diagnostics sink into `TimelineHomeRootRouteCallSite` or `TimelineHomeRootRoutePreflight`.
- A minimal legacy-only child wrapper, if needed, to prove a future `collectionView` decision path does not construct `NostrHomeTimelineStore`; this wrapper must keep the default legacy render path unchanged and must not mount collection view UI.
- `TimelineHomeRootRoutePreflight`, only if the call-site contract needs a small pure input/output refinement.
- `TimelineHomeRootRouteGuard`, only if the guard contract needs a small pure input/output refinement.
- `TimelineHomeRouteDiagnostics`, only for local route diagnostics artifact shape already covered by tests.
- `TimelineHomeRouteDiagnosticsSink`, only for local in-memory retention behavior, a narrow injectable protocol, or test/debug summary access.
- `TimelineHomeEngineModeResolver`, only through injected arguments or a small adapter; the Root call site must not read `ProcessInfo.processInfo.arguments` directly unless that read is isolated in the adapter and injected into the preflight input.
- Safe encoded route artifact fixtures, only when they pass `scripts/guard_timeline_diagnostics_artifact.sh`.
- Test support fakes that prove no network start, no DB write, no read marker mutation, and no double mutation.

Sink-injection maintenance may not:

- Delete or replace legacy Home.
- Remove `NostrHomeTimelineStore`.
- Bypass `NostrHomeTimelineStore` for the current legacy Home render path.
- Mount legacy `HomeTimelineView` hidden or offscreen at the same time as a collection view Home route for the same account/session.
- Instantiate `TimelineCollectionViewController` from Root.
- Construct a collection view `TimelineSurface` from Root.
- Call `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select` directly from Root.
- Write files from the sink.
- Upload, export telemetry, analytics, or remote logging from the sink.
- Start relay sync for the collection view path.
- Construct live `NostrRelayRuntime` for the collection view path before local restore.
- Write `feed_read_state`.
- Mutate read marker.
- Create `resolve_jobs`.
- Call network, relay, media resolver, OGP resolver, profile resolver, or real `ResolveCoordinator`.
- Alter SQL schema.
- Add DB migration.
- Alter root shell, startup splash, or Launch Screen behavior.
- Change legacy SwiftUI Timeline files: `TimelineFeedView`, `TimelinePostRow`, or `TimelineAttachments`.
- Call `dataSource.apply` outside `TimelineSnapshotCoordinator`.
- Touch `.github` or GitHub Actions.

## 5. Sink-Injection Validation Baseline

The sink-injection checkpoint is covered by the focused app test suite:

- `TimelineHomeRootRouteDiagnosticsSinkInjectionTests`

Required test cases:

- `root_preflight_records_one_local_route_decision`
- `root_preflight_default_legacy_rendering_unchanged`
- `root_preflight_sink_is_in_memory_only`
- `root_preflight_sink_does_not_construct_collection_view`
- `root_preflight_sink_does_not_construct_nostr_store`
- `root_preflight_sink_does_not_start_network`
- `root_preflight_sink_does_not_write_db`
- `root_preflight_sink_does_not_advance_read_marker`
- `root_preflight_sink_does_not_call_dataSourceApply`
- `root_preflight_sink_artifact_passes_privacy_guard`
- `root_preflight_sink_selected_suites_non_zero`

The tests must prove behavior, not only source-string absence. Use spies or fakes where needed to prove preflight invocation count, local artifact count, sink storage scope, collection view construction count, legacy store construction count, network start count, DB write count, read marker mutation count, `dataSource.apply` count, and legacy/new visible dataset mutation count.

The required assertions are:

- Root shell remains immediate.
- Existing root/splash coupling remains unchanged and is not claimed as full production root-shell compliance until a separate root-shell separation task tests it.
- Legacy Home remains default.
- Root preflight writes exactly one local route decision artifact.
- The sink is in-memory only and performs no file writes.
- `TimelineHomeRootRoutePreflight` receives injected arguments.
- `ProcessInfo.processInfo.arguments` is not read directly from the Root call site unless it is read by a small adapter and injected into the preflight input.
- Debug override, `createdAtMS`, and every `TimelineHomeRouteDependencyStatus` readiness flag are injected; the preflight boundary must not read global state, service locators, singletons, network state, DB state, or UserDefaults directly.
- Debug override `.collectionView` cannot bypass the launch flag.
- Route diagnostics artifact is generated locally and is not uploaded or sent to telemetry, analytics, remote logging, or external services.
- Unknown launch argument values remain redacted in diagnostics; raw private content, raw event JSON, pubkeys, event IDs, relay URLs, relay/account private material, `nsec`, Keychain data, signing payloads, and bearer tokens do not appear in artifacts.
- Side-effect sentinel remains all false.
- Production Root body render switching remains explicit-flag-only and clean-gate-only.
- `HEAD == origin/main` is verified after push.

Every selected app suite must report a non-zero Swift Testing count. Treat xcodebuild exit 0 with only `Executed 0 tests` and no later Swift Testing count as FAIL.

Minimum selected suites for sink-injection maintenance and construction-readiness validation:

- `AstrenzaTests/TimelineHomeRouteDiagnosticsSinkTests`
- `AstrenzaTests/TimelineHomeRootRouteCallSiteTests`
- `AstrenzaTests/TimelineHomeRootRoutePreflightTests`
- `AstrenzaTests/TimelineHomeRootRouteGuardTests`
- `AstrenzaTests/TimelineHomeRouteDiagnosticsTests`
- `AstrenzaTests/TimelineCollectionViewControllerSmokeTests`
- `AstrenzaTests/TimelineInitialRestoreSnapshotCoordinatorHarnessTests`
- `AstrenzaTests/TimelineEngineScaffoldTests`

Use type names in `-only-testing`, not display names. For example, `TimelineCollectionViewControllerSmokeTests` is the current type name for the offscreen controller smoke suite.

Required acceptance gates:

- `HEAD == origin/main` after push.
- Every selected Swift Testing suite reports a non-zero executed test count.
- Startup network grep has no matches in the new Root preflight/sink path.
- A safe encoded route artifact passes `scripts/guard_timeline_diagnostics_artifact.sh`.
- Root and splash visible behavior are unchanged.
- Default legacy Home rendering is unchanged.
- Production Root body render switching remains explicit-flag-only and clean-gate-only.
- The route artifact contains no forbidden privacy fragments.

## 6. Construction Gates That Must Remain Clean

The `f163ed0` construction checkpoint opened only the flagged offscreen/non-rendered collection view route construction path. Future activation can proceed only if all of these construction gates remain clean:

- Sink injection is reviewed and PASS.
- Default legacy behavior is unchanged with Root preflight plus sink injection.
- Route diagnostics artifact is generated locally, decodable, and free of forbidden privacy fragments.
- Route diagnostics artifact proves no network, DB, read marker, `pending_new`, or `dataSource.apply` side effects.
- Offscreen controller smoke pass.
- Snapshot coordinator harness pass.
- Launch restore contract pass.
- No startup network logs.
- `networkWaitedBeforeInteractiveScrollMS == 0`.
- `readMarkerChanged == false`.
- Old/new dual mutation prevention remains true.
- Selected suites execute non-zero Swift Testing tests.
- Root shell first paint remains independent from Timeline restore readiness.
- No same-session fallback path can double-mutate visible Home state.
- The ADR/checklist explicitly says route construction scope is open.

## 7. Collection View Route Construction Readiness

For this plan, "collection view route construction" means Root/Home is allowed to construct the `TimelineSurface` or `TimelineCollectionViewController` dependency path behind the explicit `--timeline-engine=collectionView` flag and readiness gates.

Construction is not default rendering. Construction is not route activation. Construction does not mean the rendered route switches away from legacy unless the explicit Root body render switch gate is clean. Construction must remain behind the explicit launch flag and all readiness gates below.

Current post-construction state:

- The current allowed state is legacy rendering plus the `f163ed0` flagged collection view construction result, limited to offscreen/non-rendered or descriptor-only behavior from Root/Home's perspective.
- Root body render switching remains explicit-flag-only and clean-gate-only.
- Debug override `.collectionView` cannot bypass the launch flag.
- Default legacy rendering remains required.
- Root must keep entering through `TimelineHomeRootRoutePreflight.invoke(_:)` or a tiny wrapper, not by directly calling `TimelineHomeRouteHost.decide`, `TimelineHomeRouteAdapter.decide`, or `TimelineHomeRouteIntegrationSkeleton.select`.

Required construction gates that must remain clean before future activation:

- Root no-op preflight PASS.
- Route diagnostics sink injection PASS.
- Root decision snapshot PASS.
- Snapshot consumer PASS.
- Construction readiness PASS.
- Construction plan consumer PASS.
- Offscreen construction harness PASS.
- Offscreen harness result consumer PASS.
- Construction artifact chain consumer PASS.
- Selected Swift Testing suites report non-zero executed test counts.
- Startup network grep has no matches for `LocalDataTask`, `ATS`, `nw_`, `WebSocketTask`, `URLSessionWebSocketTask`, `wss://`, or `setDefaultRelays`.
- `networkWaitedBeforeInteractiveScrollMS == 0`.
- `readMarkerChanged == false`.
- `requiresNetworkWork == false`.
- `requiresDBWrite == false`.
- `dataSource.apply` remains coordinator-only.
- No extra `NostrHomeTimelineStore` construction occurs for the collection view route construction path. The existing legacy default path can still construct its baseline store while legacy remains selected.
- No DB write or read marker mutation occurs.
- Generated route diagnostics artifacts pass the privacy guard.
- Diagnostics guard self-test passes.
- Offscreen `TimelineCollectionViewControllerSmokeTests` PASS.
- Initial restore snapshot coordinator harness PASS.
- The local `timeline_home_route_decision` artifact, `TimelineHomeRootRouteDecisionSnapshot`, construction readiness plan, offscreen harness result, and artifact chain decode through `TimelineHomeRouteDiagnosticsConsumer`, `TimelineHomeRootRouteDecisionSnapshotConsumer`, `TimelineHomeRouteConstructionPlanConsumer`, `TimelineHomeRouteConstructionReadinessConsumer`, `TimelineHomeOffscreenConstructionHarnessResultConsumer`, and `TimelineHomeConstructionArtifactChainConsumer`.
- The decoded gate shows `source == rootPreflight`, `legacyFallback == false`, `missingDependencies.isEmpty`, `fallbackIssueKinds.isEmpty`, `releaseBlockerFlags.isEmpty`, `sideEffectSentinel` all false, `dataSourceApplyCalled == false`, and no privacy-forbidden fragments in encoded artifact, export, snapshot, debug summary, logs, fixtures, screenshots, or failure artifacts.
- Any fallback, missing dependency, runtime-disabled, rollout-blocked, unknown mode, or non-empty `releaseBlockerFlags` decision keeps route construction closed.
- Diagnostics consumers remain readers, not privacy sanitizers. Only sanitized route diagnostics artifacts may be consumed or attached.

Release blocker language:

- Collection view Home route construction must not be enabled unless Root shell first paint is proven independent from Timeline restore readiness.
- Route construction is blocked if any launch path waits for relay, network, EOSE, resolver, search, pruning, checkpoint, or optimize work before first interactive Timeline scroll.
- Route construction is blocked if the restore gate covers the Root shell or tab bar, continues an app-wide splash, records `networkWaitedBeforeInteractiveScrollMS > 0`, or changes read marker state during launch, restore, sync, EOSE, foreground, or resolve.

## 8. First Route Construction Implementation Scope

When a later explicit implementation prompt opens construction, the preferred task title is:

- `test: construct TimelineHome collectionView route behind flag`

Allowed for that future task:

- Construct a collection view route description or dependency path only behind the explicit `--timeline-engine=collectionView` flag and readiness gates.
- Construct read-only/offline dependencies for the flagged path.
- Construct `TimelineSurface` or `TimelineCollectionViewController` only in the explicit flagged path.
- Keep construction no-window/offscreen or non-rendered unless a later task explicitly opens rendered construction.
- Keep the default rendered route legacy.
- Keep `routeActivationAllowed == false`.
- Keep `renderedRouteAfterConstruction == legacy`.
- Record the route/construction artifact chain locally.
- Keep existing readiness, plan, harness, harness-result consumer, artifact-chain consumer, smoke, and restore-harness tests green.
- Keep runtime network, relay, resolver, DB-write, read marker, `feed_read_state`, and `feed_items.pending_new` dependencies closed.
- Initial snapshot mutation must flow through `TimelineSnapshotCoordinator.applyPreservingPosition`; direct `dataSource.apply` remains coordinator-only.

Forbidden for that future task:

- Defaulting to collection view.
- Replacing legacy Home rendering.
- Route activation or render switching.
- Removing or bypassing `NostrHomeTimelineStore`.
- Starting relay, network, resolver, media resolver, OGP resolver, profile resolver, or real `ResolveCoordinator` work.
- Writing DB state, read marker state, `feed_read_state`, `feed_items.pending_new`, or `resolve_jobs`.
- Calling `dataSource.apply` from Root.
- Changing splash, Launch Screen, or root shell behavior.
- GitHub Actions changes.
- Dependency changes.
- SQL schema or migration changes.
- Legacy SwiftUI Timeline implementation changes.
- Connecting `URLSession`, relay, media resolver, OGP resolver, profile resolver, or real `ResolveCoordinator`.

## 9. Required Future Route Construction Tests

Before route construction can open, future tests must exist with these suite and case names:

- `TimelineHomeCollectionViewRouteBehindFlagConstructionTests`
- `collectionView_route_requires_explicit_flag`
- `collectionView_route_requires_all_readiness_gates`
- `default_legacy_route_does_not_construct_collectionView`
- `flagged_collectionView_route_constructs_only_non_rendered_or_offscreen_path`
- `flagged_collectionView_route_keeps_renderedRoute_legacy`
- `flagged_collectionView_route_keeps_activation_false`
- `flagged_collectionView_route_records_artifact_chain`
- `flagged_collectionView_route_does_not_start_network`
- `flagged_collectionView_route_does_not_write_db`
- `flagged_collectionView_route_does_not_advance_read_marker`
- `flagged_collectionView_route_does_not_call_dataSourceApply_from_Root`
- `flagged_collectionView_route_does_not_construct_extra_NostrHomeTimelineStore`
- `startup_network_grep_no_matches`
- `selected_swift_testing_suites_non_zero`

Future validation must also include:

- Startup network log grep with zero matches.
- No extra `NostrHomeTimelineStore` construction in the collection view route construction path.
- `xcodegen generate` before targeted `xcodebuild test` whenever new app test files are involved.
- A later Swift Testing line such as `Test run with N tests in 1 suite passed`, with `N > 0`, for every selected app suite.

## 10. Root Body Render Switch Gate Baseline

The implementation title for this milestone was:

- `test: wire TimelineHome collectionView route into Root body behind flag`

Root body render switch means `AstrenzaRootView.body` may choose the collection view Home route only behind the explicit `--timeline-engine=collectionView` flag and a clean Root body activation wiring gate. Default launch without the flag remains legacy. Rollback and manual fallback remain legacy. Root shell first paint must remain unchanged, and the Timeline restore gate must remain scoped to the Timeline area only. Activation/render switch must not introduce startup network, DB writes, read-marker mutation, or Root-owned `dataSource.apply`.

Required preconditions that must remain clean:

- Flagged construction PASS.
- Activation switch helper PASS.
- Activation readiness PASS.
- Activation readiness consumer PASS.
- Activation artifact chain consumer PASS.
- Root activation preflight PASS.
- Root activation decision snapshot chain PASS.
- Root activation decision snapshot chain consumer PASS.
- Root body activation wiring gate PASS.
- Root body activation wiring gate consumer PASS.
- `TimelineCollectionViewControllerSmokeTests` PASS.
- `TimelineInitialRestoreSnapshotCoordinatorHarnessTests` PASS.
- Startup-network grep has no matches.
- `dataSource.apply` remains coordinator-only.
- No extra `NostrHomeTimelineStore` construction.
- No DB write, read marker, `feed_read_state`, or `pending_new` mutation.
- Privacy guard and diagnostics guard self-test PASS.
- Selected Swift Testing suites execute non-zero tests.

Allowed Root body switch scope:

- Touch `AstrenzaRootView.body` only for an explicit flagged route branch.
- Use the injected mode, preflight, and wiring gate output.
- Render the collection view route only when `wiringAllowed == true`.
- Record the local diagnostics/artifact decision.
- Keep legacy route as fallback and rollback.
- Preserve root shell first paint.
- Keep same-session double mutation prevented.

Forbidden Root body switch scope:

- Defaulting to collection view.
- Removing or bypassing `NostrHomeTimelineStore`.
- Starting relay, network, or resolver work before first interactive scroll.
- Writing DB state or mutating read marker, `feed_read_state`, or `pending_new`.
- Calling `dataSource.apply` from Root.
- Changing splash, Launch Screen, or root shell behavior.
- GitHub Actions, dependency, schema, or migration changes.
- Adding an external telemetry, upload, or export path.
- Opening the `ResolveCoordinator` actor or media/OGP resolver wiring.
- Same-session double mutation between legacy and collection view paths.

Required Root body render switch tests:

- `TimelineHomeRootBodyRenderSwitchTests`
- `root_body_render_switch_requires_explicit_flag`
- `root_body_render_switch_requires_clean_wiring_gate`
- `default_without_flag_renders_legacy`
- `dirty_wiring_gate_renders_legacy`
- `clean_flagged_wiring_renders_collectionView`
- `render_switch_preserves_root_shell_first_paint`
- `render_switch_uses_timeline_area_restore_gate_only`
- `render_switch_does_not_start_network_before_interactive_scroll`
- `render_switch_does_not_write_db`
- `render_switch_does_not_advance_read_marker`
- `render_switch_does_not_call_dataSourceApply_from_Root`
- `render_switch_does_not_construct_extra_NostrHomeTimelineStore`
- `render_switch_prevents_same_session_double_mutation`
- `rollback_returns_to_legacy`
- `selected_swift_testing_suites_non_zero`

## 11. TimelineHome Startup Smoke Acceptance Baseline

Future TimelineHome startup gates use `TimelineHomeFlaggedCollectionViewStartupSmokeTests` as the fixed startup smoke acceptance baseline. A valid run must generate a fixed result bundle with `-resultBundlePath`, report the exact result bundle path, and scan that current bundle only. Broad scans of stale `/tmp` or DerivedData logs are not evidence.

Selected Swift Testing suites must execute non-zero tests. The XCTest wrapper line `Executed 0 tests` is expected noise when followed by Swift Testing discovery; by itself it is not evidence. The accepted evidence is a later Swift Testing summary such as `Test run with N tests in M suites passed`, with `N > 0` and every selected suite represented in the `.xcresult` test tree.

The privacy-safe startup smoke schema is:

- Result bundle scan hits must not encode raw result-bundle lines.
- Result bundle scan hits must not encode raw excerpts.
- Result bundle scan hits must not encode raw launch arguments.
- Each pattern hit may include only `patternKind`, `tokenID`, `lineNumber` or occurrence index, and a fixed `redactedSummary`.
- Launch arguments must be normalized to known flags, `requestedEngineMode`, `unknownArgumentCount`, and a `redactedUnknownArguments` marker.
- Unknown launch arguments are counted, not copied.
- Diagnostics consumers remain readers, not privacy sanitizers; only sanitized startup smoke artifacts may be consumed or attached.

Required forbidden-fragment checks for encoded startup smoke JSON, debug summaries, fixtures, screenshots, logs, and failure artifacts:

- `nsec`
- `secret`
- `privateKey`
- `private_key`
- `raw_json`
- `rawEvent`
- `raw_event`
- `mnemonic`
- `keychain`
- `nostr secret`
- relay URL
- pubkey
- event id
- private message content phrase

Required startup-network scan tokens for the fixed result bundle:

- `LocalDataTask`
- `ATS failure`
- `nw_`
- `WebSocket`
- `URLSessionWebSocketTask`
- `wss://`
- `setDefaultRelays`
- relay connection attempts
- Plain `URLSession` duplicate-class warnings must be distinguished from actual startup attempts. A duplicate-class warning is environment noise only when the fixed bundle has no `LocalDataTask`, `WebSocket`, `URLSessionWebSocketTask`, `wss://`, `setDefaultRelays`, or relay connection attempt evidence.

Future gate behavior:

- Default startup with no flag remains legacy.
- Flagged startup requires explicit `--timeline-engine=collectionView`.
- Flagged startup requires a clean Root body wiring gate.
- A dirty fixed result bundle scan rejects the flagged route and keeps legacy.
- Stale restore input rejects the flagged route and keeps legacy.
- Rollback and manual fallback remain legacy.
- The gate must not write DB state, mutate read marker, mutate `feed_read_state`, mutate `pending_new`, or call `dataSource.apply` from Root.
- The gate must not start network, relay, resolver, media resolver, OGP resolver, profile resolver, or real `ResolveCoordinator` work before first interactive scroll.
- The gate must not add telemetry, upload, export, analytics, remote logging, or external artifact destinations.

## 12. Final Acceptance For This Docs Slice

This docs slice is accepted only if:

- Production Home/root/splash behavior remains unchanged.
- Schema remains unchanged.
- Migration is avoided.
- DB write, network, relay, media resolver, OGP resolver, profile resolver, and real `ResolveCoordinator` scope remains closed.
- Production Root body render switching remains explicit-flag-only and clean-gate-only.
- Default/no-flag startup remains legacy.
- The startup smoke acceptance baseline requires a fixed result bundle path, startup-network scan output, privacy encoded JSON checks, and selected suite counts.
- A selected Swift Testing suite with 0 tests is a release blocker.
- Construction, activation switch helper, Root body wiring gate, production Root body render switching, collectionView route restore, and startup smoke are documented as separate milestones.
- Rollback and manual fallback remain legacy.
- If any Root body wiring gate, restore input, or result bundle scan fails, the flagged startup smoke must not render the collection view route; it must record the artifact and keep legacy rendering.

## 13. Rollback Plan

Rollback for the future Root body render switch is a launch-time or restart-time choice.

- Remove the flag or set the mode back to legacy.
- A debug setting change requires restart before Root body route switching.
- Do not silently fall back in the same session after either Home path has started mutating visible state.
- Diagnostics record the route decision and any fallback issue locally.
- Legacy Home remains available until the collection view route passes release gates and a separate decision enables it by default.
- Manual fallback remains legacy.
- If any Root body wiring gate fails, do not render the collection view route; record the blocked artifact chain and keep legacy rendering.

## 14. Open Questions

- Exact SwiftUI insertion point for a future route host.
- Whether the route host is test-only first or production-source behind the flag.
- Whether the first collection view path uses read-only Core Store or fake store in app tests.
- How to expose diagnostics in debug UI.
- Whether existing Root shell startup splash coupling needs separate cleanup before route wiring.
