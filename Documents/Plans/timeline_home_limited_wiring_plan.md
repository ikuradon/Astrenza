# TimelineHome Limited Wiring Plan

## 1. Status

Proposed.

This document defines the first limited, feature-flagged Home wiring task. It is docs-only and does not implement production Home wiring.

## 2. Basis

The first limited wiring task starts only after the latest launch restore contract has passed review and selected non-zero test validation. The contract checkpoint is:

- `4707cf2 test: define TimelineHome launch restore contract`

The existing contracts available to the next implementation slice are:

- `TimelineHomeEngineMode`
- `TimelineHomeRouteAdapter`
- `TimelineHomeLaunchRestoreContract`
- `TimelineSurfaceDependencyContainer`
- `TimelineCollectionViewController` offscreen smoke coverage
- `TimelineInitialRestoreSnapshotCoordinatorHarness`
- `TimelineInitialRestoreUseCase`
- `TimelineRepositoryStoreWindowComposer`
- Core `TimelineRepositoryStore` read-only boundary

## 3. First Limited Wiring Scope

The next implementation task is a feature-flagged route integration skeleton only.

The default route remains legacy SwiftUI Home. The collection view route may be constructed only behind an explicit flag such as `--timeline-engine=collectionView`, and the route decision must happen before visible Home state is constructed.

The first implementation must preserve these constraints:

- Default launch uses legacy Home.
- Unknown or missing flag falls back to legacy before route construction.
- `collectionView` route can be constructed only behind the explicit flag and ready dependency gates.
- Root shell behavior remains unchanged.
- Observable production Home/root/splash behavior remains unchanged; any route decision wrapper must preserve the default legacy path behavior.
- No automatic runtime fallback to legacy in the same session after a collection view route starts mutating visible state.
- No production replacement of legacy Home yet.
- No DB writes.
- No relay or network start before local restore.
- No resolver work before first interactive scroll.
- No read marker advancement.
- No `feed_items.pending_new` mutation.
- No same-session dual mutation between legacy Home and collection view Home.

## 4. Allowed Future Code Changes

The first wiring PR may make only the minimum code changes needed to prove a route decision can be made behind the flag without replacing production Home.

Allowed files or classes:

- A small Home route adapter call site or wrapper, if needed.
- `AstrenzaRootView`, only for a narrow pre-render route decision or wrapper call that preserves observable default legacy Home/root/splash behavior.
- `AstrenzaLaunchMode`, only if it is needed to pass launch arguments into a pure route decision.
- A test-only or debug-only `TimelineHomeRouteHost`, if preferred.
- `TimelineHomeEngineModeResolver`, only for feature flag reading already covered by tests.
- `TimelineHomeRouteAdapter`, only for route decision shape needed by the skeleton.
- A route decision object.
- `TimelineSurfaceDependencyContainer` construction with fakes or a read-only store.
- A local noop diagnostics sink.
- Test support fakes that prove no network start, no DB write, no read marker mutation, and no double mutation.

The first wiring PR may not:

- Delete or replace legacy Home.
- Remove `NostrHomeTimelineStore`.
- Mount legacy `HomeTimelineView` hidden or offscreen at the same time as a collection view Home route for the same account/session.
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

## 5. Required Tests For First Wiring PR

The first wiring PR must add a focused app test suite:

- `TimelineHomeRouteIntegrationSkeletonTests`

Required test cases:

- `default_mode_uses_legacy_home`
- `collectionView_flag_selects_collectionView_route_decision`
- `unknown_flag_falls_back_to_legacy`
- `missing_dependencies_fall_back_to_legacy`
- `root_shell_contract_unchanged`
- `collectionView_route_does_not_start_network`
- `collectionView_route_does_not_advance_read_marker`
- `collectionView_route_does_not_write_db`
- `legacy_and_collectionView_do_not_double_mutate_visible_dataset`
- `dataSourceApply_coordinator_only`

The tests must prove behavior, not only source-string absence. Use spies or fakes where needed to prove route adapter invocation count, network start count, DB write count, read marker mutation count, and legacy/new visible dataset mutation count.

Every selected app suite must report a non-zero Swift Testing count. Treat xcodebuild exit 0 with only `Executed 0 tests` and no later Swift Testing count as FAIL.

Minimum selected suites for the first wiring PR:

- `AstrenzaTests/TimelineHomeEngineModeTests`
- `AstrenzaTests/TimelineHomeRouteAdapterTests`
- `AstrenzaTests/TimelineHomeLaunchRestoreContractTests`
- `AstrenzaTests/TimelineSurfaceDependencyContainerTests`
- `AstrenzaTests/TimelineCollectionViewControllerSmokeTests`
- `AstrenzaTests/TimelineHomeRouteIntegrationSkeletonTests`
- `AstrenzaTests/TimelineInitialRestoreUseCaseTests`
- `AstrenzaTests/TimelineInitialRestoreCoordinatorAcceptanceTests`
- `AstrenzaTests/TimelineInitialRestoreSnapshotCoordinatorHarnessTests`
- `AstrenzaTests/TimelineEngineScaffoldTests`

Use type names in `-only-testing`, not display names. For example, `TimelineCollectionViewControllerSmokeTests` is the current type name for the offscreen controller smoke suite.

## 6. Release Gates Before Enabling Collection View By Default

The collection view route must not become the default until all of these gates pass:

- Offscreen controller smoke pass.
- Snapshot coordinator harness pass.
- Launch restore contract pass.
- Local fixture route integration pass.
- No startup network logs.
- `networkWaitedBeforeInteractiveScrollMS == 0`.
- `readMarkerChanged == false`.
- `pending_new` excluded.
- Hidden rows excluded.
- Missing-target quote/repost retained.
- Selected suites execute non-zero Swift Testing tests.
- Manual debug switch or launch argument documented.
- Root shell first paint remains independent from Timeline restore readiness.
- No same-session fallback path can double-mutate visible Home state.

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
