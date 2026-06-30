# TimelineHome Limited Wiring Plan

## 1. Status

Proposed.

This document defines the next minimal Root call-site diagnostics sink injection task. It is docs-only and does not implement production Home wiring.

## 2. Basis

The next Root diagnostics sink injection task starts only after the latest route diagnostics sink checkpoint has passed review and selected non-zero test validation. The checkpoint is:

- `63ddf7c test: define TimelineHome route diagnostics sink`

`AstrenzaRootView` already performs a no-op `TimelineHomeRootRouteCallSite` production preflight before constructing the existing `NostrSessionStore` and `NostrHomeTimelineStore`. `TimelineHomeRouteDiagnosticsSink` now exists as a local, offline, in-memory retention sink for route decision artifacts.

The existing contracts available to the next implementation slice are:

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
- `TimelineCollectionViewController` offscreen smoke coverage
- `TimelineInitialRestoreSnapshotCoordinatorHarness`
- `TimelineInitialRestoreUseCase`
- `TimelineRepositoryStoreWindowComposer`
- Core `TimelineRepositoryStore` read-only boundary

## 3. Next Implementation Scope

The next implementation task is:

- `test: inject TimelineHome route diagnostics sink at root preflight`

Equivalent wording is acceptable only if it keeps the same scope: Root may pass a local in-memory `TimelineHomeRouteDiagnosticsSink`, or a narrow protocol for the same behavior, into the existing no-op `TimelineHomeRootRouteCallSite` preflight path. The call must preserve visible Home behavior.

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

## 4. Allowed Future Code Changes

The sink-injection PR may make only the minimum code changes needed to prove Root can call the preflight boundary with a local diagnostics sink without replacing production Home.

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

The sink-injection PR may not:

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

## 5. Required Tests For Next Sink-Injection PR

The next sink-injection PR must add a focused app test suite:

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
- CollectionView route construction remains closed.
- `HEAD == origin/main` is verified after push.

Every selected app suite must report a non-zero Swift Testing count. Treat xcodebuild exit 0 with only `Executed 0 tests` and no later Swift Testing count as FAIL.

Minimum selected suites for the next sink-injection PR:

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
- CollectionView route construction remains closed.
- The route artifact contains no forbidden privacy fragments.

## 6. Exit Criteria Before Opening Actual Collection View Route Construction

Actual collection view route construction from Root remains closed. It can only be opened by a later task after all of these gates pass:

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

## 7. Rollback Plan

Rollback is a launch-time or restart-time choice.

- Remove the flag or set the mode back to legacy.
- A debug setting change requires restart before route construction.
- Do not silently fall back in the same session after the collection view route has started mutating visible state.
- Diagnostics record the route decision and any fallback issue locally.
- Legacy Home remains available until the collection view route passes release gates and a separate decision enables it by default.

## 8. Open Questions

- Exact SwiftUI insertion point for a future route host.
- Whether the route host is test-only first or production-source behind the flag.
- Whether the first collection view path uses read-only Core Store or fake store in app tests.
- How to expose diagnostics in debug UI.
- Whether existing Root shell startup splash coupling needs separate cleanup before route wiring.
